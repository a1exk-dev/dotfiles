#include "fcitx-controller.hpp"

#include <systemd/sd-bus.h>
#include <systemd/sd-event.h>

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <fcntl.h>
#include <fstream>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace InputLanguages::Fcitx {
namespace {

constexpr auto FCITX_NAME = "org.fcitx.Fcitx5";
constexpr auto CONTROLLER_PATH = "/controller";
constexpr auto CONTROLLER_INTERFACE = "org.fcitx.Fcitx.Controller1";
constexpr uint64_t CALL_TIMEOUT_USEC = 1'000'000;

struct ExpectedMember {
	std::string_view name;
	std::string_view type;
	std::string_view input;
	std::string_view output;
};

constexpr std::array EXPECTED_MEMBERS{
	ExpectedMember{"AddInputMethodGroup", "method", "s", ""},
	ExpectedMember{"AvailableInputMethods", "method", "", "a(ssssssb)"},
	ExpectedMember{"CurrentInputMethod", "method", "", "s"},
	ExpectedMember{"CurrentInputMethodGroup", "method", "", "s"},
	ExpectedMember{"DebugInfo", "method", "", "s"},
	ExpectedMember{"FullInputMethodGroupInfo", "method", "s", "sssa{sv}a(sssssssbsa{sv})"},
	ExpectedMember{"GetAddonsV2", "method", "", "a(sssibbbasas)"},
	ExpectedMember{"InputMethodGroupInfo", "method", "s", "sa(ss)"},
	ExpectedMember{"InputMethodGroups", "method", "", "as"},
	ExpectedMember{"InputMethodGroupsChanged", "signal", "", ""},
	ExpectedMember{"RemoveInputMethodGroup", "method", "s", ""},
	ExpectedMember{"Save", "method", "", ""},
	ExpectedMember{"SetCurrentIM", "method", "s", ""},
	ExpectedMember{"SetInputMethodGroupInfo", "method", "ssa(ss)", ""},
	ExpectedMember{"SwitchInputMethodGroup", "method", "s", ""},
};

std::optional<std::string_view> attribute(std::string_view tag, std::string_view name) {
	for (const char quote : {'"', '\''}) {
		std::string prefix(name);
		prefix += '=';
		prefix += quote;
		const auto start = tag.find(prefix);
		if (start == std::string_view::npos)
			continue;
		const auto valueStart = start + prefix.size();
		const auto end = tag.find(quote, valueStart);
		if (end != std::string_view::npos)
			return tag.substr(valueStart, end - valueStart);
	}
	return std::nullopt;
}

std::optional<std::string_view> interfaceBody(std::string_view xml) {
	std::size_t cursor = 0;
	while ((cursor = xml.find("<interface", cursor)) != std::string_view::npos) {
		const auto tagEnd = xml.find('>', cursor);
		if (tagEnd == std::string_view::npos)
			return std::nullopt;
		const auto tag = xml.substr(cursor, tagEnd - cursor + 1);
		if (attribute(tag, "name") == CONTROLLER_INTERFACE) {
			const auto end = xml.find("</interface>", tagEnd + 1);
			if (end == std::string_view::npos)
				return std::nullopt;
			return xml.substr(tagEnd + 1, end - tagEnd - 1);
		}
		cursor = tagEnd + 1;
	}
	return std::nullopt;
}

bool memberMatches(std::string_view body, const ExpectedMember& expected) {
	const std::string opening = "<" + std::string(expected.type);
	std::size_t cursor = 0;
	while ((cursor = body.find(opening, cursor)) != std::string_view::npos) {
		const auto tagEnd = body.find('>', cursor);
		if (tagEnd == std::string_view::npos)
			return false;
		const auto tag = body.substr(cursor, tagEnd - cursor + 1);
		if (attribute(tag, "name") != expected.name) {
			cursor = tagEnd + 1;
			continue;
		}

		const bool selfClosing = tag.size() >= 2 && tag[tag.size() - 2] == '/';
		std::string_view memberBody;
		if (!selfClosing) {
			const std::string closing = "</" + std::string(expected.type) + '>';
			const auto end = body.find(closing, tagEnd + 1);
			if (end == std::string_view::npos)
				return false;
			memberBody = body.substr(tagEnd + 1, end - tagEnd - 1);
		}

		std::string input;
		std::string output;
		std::size_t argCursor = 0;
		while ((argCursor = memberBody.find("<arg", argCursor)) != std::string_view::npos) {
			const auto argEnd = memberBody.find('>', argCursor);
			if (argEnd == std::string_view::npos)
				return false;
			const auto arg = memberBody.substr(argCursor, argEnd - argCursor + 1);
			const auto signature = attribute(arg, "type");
			if (!signature)
				return false;
			const auto direction = attribute(arg, "direction");
			if (expected.type == "signal" || direction == "out")
				output += *signature;
			else
				input += *signature;
			argCursor = argEnd + 1;
		}
		return input == expected.input && output == expected.output;
	}
	return false;
}

TransportStatus statusFromError(int error) {
	const int value = error < 0 ? -error : error;
	if (value == EBADMSG)
		return TransportStatus::MalformedReply;
	if (value == ETIMEDOUT)
		return TransportStatus::Timeout;
	if (value == ECONNRESET || value == ENOTCONN || value == EPIPE)
		return TransportStatus::Disconnected;
	if (value == ENXIO || value == ENOENT || value == ESRCH)
		return TransportStatus::Unavailable;
	return TransportStatus::MethodError;
}

ProfileIdentity inspectProfile(std::string_view path) {
	ProfileIdentity identity;
	const std::string profilePath(path);
	identity.path = profilePath;
	const int descriptor = open(profilePath.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
	if (descriptor < 0)
		return identity;
	struct stat before {};
	struct stat after {};
	struct stat pathIdentity {};
	EVP_MD_CTX* context = nullptr;
	std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
	unsigned digestLength = 0;
	bool valid = fstat(descriptor, &before) == 0 && S_ISREG(before.st_mode) && before.st_uid == getuid() &&
		(before.st_mode & 07777) == 0600;
	if (valid) {
		context = EVP_MD_CTX_new();
		valid = context && EVP_DigestInit_ex(context, EVP_sha256(), nullptr) == 1;
	}
	std::array<unsigned char, 8192> buffer{};
	while (valid) {
		const auto count = read(descriptor, buffer.data(), buffer.size());
		if (count == 0)
			break;
		if (count < 0) {
			if (errno == EINTR)
				continue;
			valid = false;
			break;
		}
		valid = EVP_DigestUpdate(context, buffer.data(), static_cast<std::size_t>(count)) == 1;
	}
	if (valid)
		valid = EVP_DigestFinal_ex(context, digest.data(), &digestLength) == 1 && digestLength == 32;
	EVP_MD_CTX_free(context);
	if (valid)
		valid = fstat(descriptor, &after) == 0 && before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
			before.st_size == after.st_size && before.st_mtim.tv_sec == after.st_mtim.tv_sec &&
			before.st_mtim.tv_nsec == after.st_mtim.tv_nsec && before.st_ctim.tv_sec == after.st_ctim.tv_sec &&
			before.st_ctim.tv_nsec == after.st_ctim.tv_nsec;
	if (valid)
		valid = fstatat(AT_FDCWD, profilePath.c_str(), &pathIdentity, AT_SYMLINK_NOFOLLOW) == 0 &&
			S_ISREG(pathIdentity.st_mode) && pathIdentity.st_dev == before.st_dev && pathIdentity.st_ino == before.st_ino;
	close(descriptor);
	if (!valid)
		return identity;

	static constexpr char HEX[] = "0123456789abcdef";
	identity = {
		.path = profilePath,
		.safe = true,
		.device = static_cast<uint64_t>(before.st_dev),
		.inode = static_cast<uint64_t>(before.st_ino),
		.mode = static_cast<uint32_t>(before.st_mode & 07777),
		.ownerUid = static_cast<uint32_t>(before.st_uid),
		.sha256 = {},
	};
	identity.sha256.reserve(digestLength * 2);
	for (unsigned index = 0; index < digestLength; ++index) {
		identity.sha256 += HEX[digest[index] >> 4];
		identity.sha256 += HEX[digest[index] & 0x0f];
	}
	return identity;
}

struct PendingCall {
	sd_bus_message* reply = nullptr;
	bool complete = false;
};

int completeCall(sd_bus_message* message, void* userdata, sd_bus_error*) {
	auto& pending = *static_cast<PendingCall*>(userdata);
	pending.reply = sd_bus_message_ref(message);
	pending.complete = true;
	return 1;
}

bool readString(sd_bus_message* message, std::string& value) {
	const char* raw = nullptr;
	if (sd_bus_message_read(message, "s", &raw) < 0 || !raw)
		return false;
	value = raw;
	return true;
}

bool readStringArray(sd_bus_message* message, std::vector<std::string>& values) {
	if (sd_bus_message_enter_container(message, SD_BUS_TYPE_ARRAY, "s") < 0)
		return false;
	for (;;) {
		const char* value = nullptr;
		const int result = sd_bus_message_read(message, "s", &value);
		if (result < 0)
			return false;
		if (result == 0)
			break;
		values.emplace_back(value ? value : "");
	}
	return sd_bus_message_exit_container(message) >= 0;
}

std::string jsonString(std::string_view value) {
	std::ostringstream output;
	output << '"';
	for (const unsigned char character : value) {
		switch (character) {
			case '\\': output << "\\\\"; break;
			case '"': output << "\\\""; break;
			case '\b': output << "\\b"; break;
			case '\f': output << "\\f"; break;
			case '\n': output << "\\n"; break;
			case '\r': output << "\\r"; break;
			case '\t': output << "\\t"; break;
			default:
				if (character < 0x20)
					output << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<unsigned>(character) << std::dec;
				else
					output << static_cast<char>(character);
		}
	}
	output << '"';
	return output.str();
}

bool readJsonValue(sd_bus_message* message, std::string& json, std::optional<std::string>* stringValue = nullptr);

bool readPropertyDictionary(sd_bus_message* message, std::string& json, std::optional<std::string>* variant = nullptr) {
	int result = sd_bus_message_enter_container(message, SD_BUS_TYPE_ARRAY, "{sv}");
	if (result < 0)
		return false;
	std::vector<std::pair<std::string, std::string>> properties;
	while ((result = sd_bus_message_enter_container(message, SD_BUS_TYPE_DICT_ENTRY, "sv")) > 0) {
		std::string key;
		std::string value;
		std::optional<std::string> scalar;
		if (!readString(message, key) || !readJsonValue(message, value, &scalar) || sd_bus_message_exit_container(message) < 0)
			return false;
		if (variant && (key == "variant" || key == "Variant") && scalar)
			*variant = std::move(scalar);
		properties.emplace_back(std::move(key), std::move(value));
	}
	if (result < 0 || sd_bus_message_exit_container(message) < 0)
		return false;
	std::ranges::sort(properties, {}, &std::pair<std::string, std::string>::first);
	json = "{";
	for (std::size_t index = 0; index < properties.size(); ++index) {
		if (index)
			json += ',';
		json += jsonString(properties[index].first) + ':' + properties[index].second;
	}
	json += '}';
	return true;
}

bool readJsonSequence(sd_bus_message* message, char type, const char* contents, std::string& json) {
	if (sd_bus_message_enter_container(message, type, contents) < 0)
		return false;
	json = "[";
	bool first = true;
	for (;;) {
		const int atEnd = sd_bus_message_at_end(message, 0);
		if (atEnd < 0)
			return false;
		if (atEnd > 0)
			break;
		std::string value;
		if (!readJsonValue(message, value))
			return false;
		if (!first)
			json += ',';
		first = false;
		json += value;
	}
	json += ']';
	return sd_bus_message_exit_container(message) >= 0;
}

bool readJsonValue(sd_bus_message* message, std::string& json, std::optional<std::string>* stringValue) {
	char type = 0;
	const char* contents = nullptr;
	if (stringValue)
		stringValue->reset();
	if (sd_bus_message_peek_type(message, &type, &contents) <= 0)
		return false;
	if (type == SD_BUS_TYPE_VARIANT) {
		if (!contents || sd_bus_message_enter_container(message, type, contents) < 0 || !readJsonValue(message, json, stringValue))
			return false;
		return sd_bus_message_at_end(message, 0) > 0 && sd_bus_message_exit_container(message) >= 0;
	}
	if (type == SD_BUS_TYPE_ARRAY) {
		if (contents && std::string_view(contents) == "{sv}")
			return readPropertyDictionary(message, json);
		return contents && readJsonSequence(message, type, contents, json);
	}
	if (type == SD_BUS_TYPE_STRUCT)
		return contents && readJsonSequence(message, type, contents, json);

	switch (type) {
		case SD_BUS_TYPE_STRING:
		case SD_BUS_TYPE_OBJECT_PATH:
		case SD_BUS_TYPE_SIGNATURE: {
			const char* value = nullptr;
			if (sd_bus_message_read_basic(message, type, &value) < 0 || !value)
				return false;
			if (stringValue)
				*stringValue = value;
			json = jsonString(value);
			return true;
		}
		case SD_BUS_TYPE_BOOLEAN: {
			int value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = value ? "true" : "false";
			return true;
		}
		case SD_BUS_TYPE_BYTE: {
			uint8_t value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = std::to_string(value);
			return true;
		}
		case SD_BUS_TYPE_INT16: {
			int16_t value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = std::to_string(value);
			return true;
		}
		case SD_BUS_TYPE_UINT16: {
			uint16_t value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = std::to_string(value);
			return true;
		}
		case SD_BUS_TYPE_INT32:
		case SD_BUS_TYPE_UNIX_FD: {
			int32_t value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = std::to_string(value);
			return true;
		}
		case SD_BUS_TYPE_UINT32: {
			uint32_t value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = std::to_string(value);
			return true;
		}
		case SD_BUS_TYPE_INT64: {
			int64_t value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = std::to_string(value);
			return true;
		}
		case SD_BUS_TYPE_UINT64: {
			uint64_t value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0)
				return false;
			json = std::to_string(value);
			return true;
		}
		case SD_BUS_TYPE_DOUBLE: {
			double value = 0;
			if (sd_bus_message_read_basic(message, type, &value) < 0 || !std::isfinite(value))
				return false;
			std::ostringstream output;
			output << std::setprecision(17) << value;
			json = output.str();
			return true;
		}
		default: return false;
	}
}

}

ControllerShape controllerShapeFromIntrospection(std::string_view xml) noexcept {
	const auto body = interfaceBody(xml);
	if (!body)
		return ControllerShape::Unsupported;
	return std::ranges::all_of(EXPECTED_MEMBERS, [&body](const ExpectedMember& member) { return memberMatches(*body, member); })
		? ControllerShape::Supported
		: ControllerShape::Unsupported;
}

class SdBusControllerTransport::Impl {
  public:
	explicit Impl(RuntimeEvidence initialEvidence) : evidence(std::move(initialEvidence)) {}

	~Impl() {
		if (bus)
			sd_bus_detach_event(bus);
		event = sd_event_unref(event);
		bus = sd_bus_unref(bus);
	}

	int initialize() {
		if (bus && event)
			return 0;
		if (bus || event) {
			if (bus)
				sd_bus_detach_event(bus);
			event = sd_event_unref(event);
			bus = sd_bus_unref(bus);
		}
		int result = sd_event_new(&event);
		if (result < 0)
			return result;
		result = sd_bus_open_user(&bus);
		if (result < 0) {
			event = sd_event_unref(event);
			return result;
		}
		result = sd_bus_attach_event(bus, event, 0);
		if (result < 0) {
			event = sd_event_unref(event);
			bus = sd_bus_unref(bus);
		}
		return result;
	}

	int call(sd_bus_message* request, sd_bus_message** reply) {
		if (inFlight)
			return -EBUSY;
		inFlight = true;
		PendingCall pending;
		sd_bus_slot* slot = nullptr;
		int result = sd_bus_call_async(bus, &slot, request, completeCall, &pending, CALL_TIMEOUT_USEC);
		while (result >= 0 && !pending.complete)
			result = sd_event_run(event, UINT64_MAX);
		slot = sd_bus_slot_unref(slot);
		inFlight = false;
		if (result < 0) {
			pending.reply = sd_bus_message_unref(pending.reply);
			return result;
		}
		if (!pending.reply)
			return -EIO;
		if (sd_bus_message_is_method_error(pending.reply, nullptr)) {
			result = -sd_bus_message_get_errno(pending.reply);
			pending.reply = sd_bus_message_unref(pending.reply);
			return result == 0 ? -EIO : result;
		}
		*reply = pending.reply;
		return 0;
	}

	int newMethodCall(sd_bus_message** message, const char* destination, const char* interface, const char* member) {
		int result = sd_bus_message_new_method_call(bus, message, destination, CONTROLLER_PATH, interface, member);
		if (result >= 0)
			result = sd_bus_message_set_auto_start(*message, 0);
		return result;
	}

	int callController(const std::string& destination, const char* member, sd_bus_message** reply) {
		sd_bus_message* request = nullptr;
		int result = newMethodCall(&request, destination.c_str(), CONTROLLER_INTERFACE, member);
		if (result >= 0)
			result = call(request, reply);
		request = sd_bus_message_unref(request);
		return result;
	}

	int callControllerString(const std::string& destination, const char* member, const std::string& argument, sd_bus_message** reply) {
		sd_bus_message* request = nullptr;
		int result = newMethodCall(&request, destination.c_str(), CONTROLLER_INTERFACE, member);
		if (result >= 0)
			result = sd_bus_message_append(request, "s", argument.c_str());
		if (result >= 0)
			result = call(request, reply);
		request = sd_bus_message_unref(request);
		return result;
	}

	int resolveOwner(std::string& resolved) {
		int result = initialize();
		if (result < 0)
			return result;
		sd_bus_message* request = nullptr;
		sd_bus_message* reply = nullptr;
		result = sd_bus_message_new_method_call(
			bus,
			&request,
			"org.freedesktop.DBus",
			"/org/freedesktop/DBus",
			"org.freedesktop.DBus",
			"GetNameOwner");
		if (result >= 0)
			result = sd_bus_message_set_auto_start(request, 0);
		if (result >= 0)
			result = sd_bus_message_append(request, "s", FCITX_NAME);
		if (result >= 0)
			result = call(request, &reply);
		request = sd_bus_message_unref(request);
		if (result >= 0 && !readString(reply, resolved))
			result = -EBADMSG;
		reply = sd_bus_message_unref(reply);
		if (result < 0) {
			if (!owner.empty()) {
				owner.clear();
				++ownerEpoch;
			}
			return result;
		}
		if (resolved != owner) {
			owner = resolved;
			++ownerEpoch;
		}
		return 0;
	}

	int connectionCredential(const std::string& ownerName, const char* member, uint32_t& value) {
		sd_bus_message* request = nullptr;
		sd_bus_message* reply = nullptr;
		int result = sd_bus_message_new_method_call(
			bus,
			&request,
			"org.freedesktop.DBus",
			"/org/freedesktop/DBus",
			"org.freedesktop.DBus",
			member);
		if (result >= 0)
			result = sd_bus_message_set_auto_start(request, 0);
		if (result >= 0)
			result = sd_bus_message_append(request, "s", ownerName.c_str());
		if (result >= 0)
			result = call(request, &reply);
		request = sd_bus_message_unref(request);
		if (result >= 0)
			result = sd_bus_message_read(reply, "u", &value);
		reply = sd_bus_message_unref(reply);
		return result < 0 ? result : 0;
	}

	bool ownerIsSupervised(const std::string& ownerName) {
		uint32_t ownerUid = 0;
		uint32_t ownerPid = 0;
		if (connectionCredential(ownerName, "GetConnectionUnixUser", ownerUid) < 0 ||
			connectionCredential(ownerName, "GetConnectionUnixProcessID", ownerPid) < 0 || ownerUid != getuid() || ownerPid == 0)
			return false;

		std::array<char, 4096> executable{};
		const std::string executableLink = "/proc/" + std::to_string(ownerPid) + "/exe";
		const auto length = readlink(executableLink.c_str(), executable.data(), executable.size() - 1);
		if (length <= 0 || std::string_view(executable.data(), static_cast<std::size_t>(length)) != "/usr/bin/fcitx5")
			return false;

		std::ifstream cgroup("/proc/" + std::to_string(ownerPid) + "/cgroup");
		std::string line;
		while (std::getline(cgroup, line)) {
			if (line.ends_with("/omarchy-fcitx5.service"))
				return true;
		}
		return false;
	}

	int readFullGroup(const std::string& ownerName, const std::string& requestedName, Group& group) {
		sd_bus_message* reply = nullptr;
		int result = callControllerString(ownerName, "FullInputMethodGroupInfo", requestedName, &reply);
		const char* name = nullptr;
		const char* defaultMethod = nullptr;
		const char* defaultLayout = nullptr;
		if (result >= 0)
			result = sd_bus_message_read(reply, "sss", &name, &defaultMethod, &defaultLayout);
		if (result >= 0 && !readPropertyDictionary(reply, group.propertiesJson))
			result = -EBADMSG;
		if (result >= 0)
			result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_ARRAY, "(sssssssbsa{sv})");
		while (result > 0) {
			result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_STRUCT, "sssssssbsa{sv}");
			if (result <= 0)
				break;
			const char* method = nullptr;
			const char* display = nullptr;
			const char* nativeName = nullptr;
			const char* icon = nullptr;
			const char* label = nullptr;
			const char* language = nullptr;
			const char* addon = nullptr;
			const char* layout = nullptr;
			int configurable = 0;
			result = sd_bus_message_read(reply, "sssssssb", &method, &display, &nativeName, &icon, &label, &language, &addon, &configurable);
			if (result >= 0)
				result = sd_bus_message_read(reply, "s", &layout);
			std::string properties;
			std::optional<std::string> variant;
			if (result >= 0 && !readPropertyDictionary(reply, properties, &variant))
				result = -EBADMSG;
			if (result >= 0)
				result = sd_bus_message_exit_container(reply);
			if (result >= 0) {
				group.items.push_back({
					.method = method ? method : "",
					.layoutOverride = layout ? layout : "",
					.displayName = display ? display : "",
					.nativeName = nativeName ? nativeName : "",
					.languageCode = language ? language : "",
					.addon = addon ? addon : "",
					.configurable = configurable != 0,
					.variant = std::move(variant),
					.propertiesJson = std::move(properties),
				});
			}
		}
		if (result == 0)
			result = sd_bus_message_exit_container(reply);
		if (result >= 0 && name && requestedName == name) {
			group.name = name;
			group.defaultMethod = defaultMethod ? defaultMethod : "";
			group.defaultLayout = defaultLayout ? defaultLayout : "";
		} else if (result >= 0) {
			result = -EBADMSG;
		}
		reply = sd_bus_message_unref(reply);
		return result;
	}

	int crossCheckGroup(const std::string& ownerName, const Group& group) {
		sd_bus_message* reply = nullptr;
		int result = callControllerString(ownerName, "InputMethodGroupInfo", group.name, &reply);
		std::string layout;
		if (result >= 0 && !readString(reply, layout))
			result = -EBADMSG;
		if (result >= 0)
			result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_ARRAY, "(ss)");
		std::vector<GroupItem> items;
		while (result > 0) {
			result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_STRUCT, "ss");
			if (result <= 0)
				break;
			const char* method = nullptr;
			const char* override = nullptr;
			result = sd_bus_message_read(reply, "ss", &method, &override);
			if (result >= 0)
				result = sd_bus_message_exit_container(reply);
			if (result >= 0)
				items.push_back({method ? method : "", override ? override : ""});
		}
		if (result == 0)
			result = sd_bus_message_exit_container(reply);
		reply = sd_bus_message_unref(reply);
		if (result >= 0) {
			if (layout != group.defaultLayout || items.size() != group.items.size())
				result = -EBADMSG;
			for (std::size_t index = 0; result >= 0 && index < items.size(); ++index) {
				if (items[index].method != group.items[index].method || items[index].layoutOverride != group.items[index].layoutOverride)
					result = -EBADMSG;
			}
		}
		return result;
	}

	RuntimeEvidence evidence;
	sd_bus* bus = nullptr;
	sd_event* event = nullptr;
	std::string owner;
	uint64_t ownerEpoch = 0;
	bool inFlight = false;
	bool restorationMode = false;
};

SdBusControllerTransport::SdBusControllerTransport(RuntimeEvidence evidence) noexcept : m_impl(std::make_unique<Impl>(std::move(evidence))) {}

SdBusControllerTransport::~SdBusControllerTransport() = default;

void SdBusControllerTransport::updateEvidence(RuntimeEvidence evidence) noexcept {
	m_impl->evidence = std::move(evidence);
}

void SdBusControllerTransport::setRestorationMode(bool enabled) noexcept {
	m_impl->restorationMode = enabled;
}

Inspection SdBusControllerTransport::inspect() noexcept {
	Snapshot snapshot;
	std::string owner;
	int result = m_impl->resolveOwner(owner);
	if (result < 0)
		return {.status = statusFromError(result), .snapshot = {}, .diagnostic = "Fcitx has no available unique owner"};
	snapshot.identity = {
		.uniqueOwner = owner,
		.ownerEpoch = m_impl->ownerEpoch,
		.supervised = m_impl->evidence.supervised && m_impl->ownerIsSupervised(owner),
		.upstreamVersion = m_impl->evidence.upstreamVersion,
		.controllerShape = ControllerShape::Unsupported,
	};
	if (!m_impl->evidence.profilePath.empty())
		snapshot.profile = inspectProfile(m_impl->evidence.profilePath);

	sd_bus_message* reply = nullptr;
	sd_bus_message* introspectionRequest = nullptr;
	result = m_impl->newMethodCall(&introspectionRequest, owner.c_str(), "org.freedesktop.DBus.Introspectable", "Introspect");
	if (result >= 0)
		result = m_impl->call(introspectionRequest, &reply);
	introspectionRequest = sd_bus_message_unref(introspectionRequest);
	if (result < 0) {
		reply = sd_bus_message_unref(reply);
		return {.status = statusFromError(result), .snapshot = std::move(snapshot), .diagnostic = "Controller introspection failed"};
	}
	std::string xml;
	if (!readString(reply, xml)) {
		reply = sd_bus_message_unref(reply);
		return {.status = TransportStatus::MalformedReply, .snapshot = std::move(snapshot), .diagnostic = "Controller introspection reply is malformed"};
	}
	reply = sd_bus_message_unref(reply);
	snapshot.identity.controllerShape = controllerShapeFromIntrospection(xml);
	if (snapshot.identity.controllerShape != ControllerShape::Supported)
		return {.status = TransportStatus::Ok, .snapshot = std::move(snapshot), .diagnostic = "Controller shape is unsupported"};

	result = m_impl->callController(owner, "InputMethodGroups", &reply);
	std::vector<std::string> groupNames;
	if (result >= 0 && !readStringArray(reply, groupNames))
		result = -EBADMSG;
	reply = sd_bus_message_unref(reply);
	if (result < 0)
		return {.status = statusFromError(result), .snapshot = std::move(snapshot), .diagnostic = "group inventory failed"};
	for (const auto& groupName : groupNames) {
		Group group;
		result = m_impl->readFullGroup(owner, groupName, group);
		if (result >= 0)
			result = m_impl->crossCheckGroup(owner, group);
		if (result < 0)
			return {.status = statusFromError(result), .snapshot = std::move(snapshot), .diagnostic = "group semantic inspection failed"};
		snapshot.groups.push_back(std::move(group));
	}

	result = m_impl->callController(owner, "AvailableInputMethods", &reply);
	if (result >= 0)
		result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_ARRAY, "(ssssssb)");
	while (result > 0) {
		result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_STRUCT, "ssssssb");
		if (result <= 0)
			break;
		const char* name = nullptr;
		const char* display = nullptr;
		const char* nativeName = nullptr;
		const char* icon = nullptr;
		const char* label = nullptr;
		const char* language = nullptr;
		int configurable = 0;
		result = sd_bus_message_read(reply, "ssssssb", &name, &display, &nativeName, &icon, &label, &language, &configurable);
		if (result >= 0)
			result = sd_bus_message_exit_container(reply);
		if (result >= 0)
			snapshot.availableMethods.emplace_back(name ? name : "");
	}
	if (result == 0)
		result = sd_bus_message_exit_container(reply);
	reply = sd_bus_message_unref(reply);
	if (result < 0)
		return {.status = statusFromError(result), .snapshot = std::move(snapshot), .diagnostic = "available-method inspection failed"};

	result = m_impl->callController(owner, "GetAddonsV2", &reply);
	if (result >= 0)
		result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_ARRAY, "(sssibbbasas)");
	while (result > 0) {
		result = sd_bus_message_enter_container(reply, SD_BUS_TYPE_STRUCT, "sssibbbasas");
		if (result <= 0)
			break;
		const char* name = nullptr;
		const char* display = nullptr;
		const char* comment = nullptr;
		int category = 0;
		int configurable = 0;
		int enabled = 0;
		int onDemand = 0;
		result = sd_bus_message_read(reply, "sssibbb", &name, &display, &comment, &category, &configurable, &enabled, &onDemand);
		if (result >= 0)
			result = sd_bus_message_skip(reply, "as");
		if (result >= 0)
			result = sd_bus_message_skip(reply, "as");
		if (result >= 0)
			result = sd_bus_message_exit_container(reply);
		if (result >= 0) {
			snapshot.addons.push_back({.name = name ? name : "", .enabled = enabled != 0, .available = true});
			if (enabled)
				snapshot.enabledAddons.emplace_back(name ? name : "");
		}
	}
	if (result == 0)
		result = sd_bus_message_exit_container(reply);
	reply = sd_bus_message_unref(reply);
	if (result < 0)
		return {.status = statusFromError(result), .snapshot = std::move(snapshot), .diagnostic = "addon inspection failed"};

	result = m_impl->callController(owner, "CurrentInputMethodGroup", &reply);
	if (result >= 0 && !readString(reply, snapshot.currentGroup))
		result = -EBADMSG;
	reply = sd_bus_message_unref(reply);
	if (result >= 0)
		result = m_impl->callController(owner, "CurrentInputMethod", &reply);
	if (result >= 0 && !readString(reply, snapshot.currentMethod))
		result = -EBADMSG;
	reply = sd_bus_message_unref(reply);
	if (result < 0)
		return {.status = statusFromError(result), .snapshot = std::move(snapshot), .diagnostic = "current Controller state inspection failed"};

	// A complete inspection is the evidence boundary used by the immediately following mutation.
	m_impl->evidence.uniqueOwner = owner;
	return {.status = TransportStatus::Ok, .snapshot = std::move(snapshot), .diagnostic = {}};
}

CommandResult SdBusControllerTransport::execute(const Snapshot& expected, const Command& command) noexcept {
	const auto& expectedIdentity = expected.identity;
	if (!expectedIdentity.supervised || (!m_impl->restorationMode && expectedIdentity.upstreamVersion != SUPPORTED_UPSTREAM_VERSION) ||
		expectedIdentity.controllerShape != ControllerShape::Supported || !m_impl->evidence.supervised ||
		m_impl->evidence.uniqueOwner != expectedIdentity.uniqueOwner || m_impl->evidence.upstreamVersion != expectedIdentity.upstreamVersion)
		return {.status = TransportStatus::MethodError, .diagnostic = "Controller runtime evidence is unsupported"};
	std::string owner;
	int result = m_impl->resolveOwner(owner);
	if (result < 0)
		return {.status = statusFromError(result), .diagnostic = "Fcitx owner is unavailable"};
	if (owner != expectedIdentity.uniqueOwner || m_impl->ownerEpoch != expectedIdentity.ownerEpoch)
		return {.status = TransportStatus::Disconnected, .diagnostic = "Fcitx owner changed"};
	if (m_impl->evidence.profilePath.empty() || inspectProfile(m_impl->evidence.profilePath) != expected.profile)
		return {.status = TransportStatus::Conflict, .diagnostic = "Fcitx profile identity changed before Controller command"};

	sd_bus_message* request = nullptr;
	sd_bus_message* reply = nullptr;
	const char* member = nullptr;
	switch (commandKind(command)) {
		case CommandKind::AddGroup:
			member = "AddInputMethodGroup";
			break;
		case CommandKind::SetGroup:
			member = "SetInputMethodGroupInfo";
			break;
		case CommandKind::SwitchGroup:
			member = "SwitchInputMethodGroup";
			break;
		case CommandKind::SetCurrentMethod:
			member = "SetCurrentIM";
			break;
		case CommandKind::RemoveGroup:
			member = "RemoveInputMethodGroup";
			break;
		case CommandKind::Save:
			member = "Save";
			break;
	}
	result = m_impl->newMethodCall(&request, owner.c_str(), CONTROLLER_INTERFACE, member);
	if (result >= 0 && commandKind(command) == CommandKind::SetGroup) {
		const auto& set = std::get<SetGroupCommand>(command);
		result = sd_bus_message_append(request, "ss", set.groupName.c_str(), set.defaultLayout.c_str());
		if (result >= 0)
			result = sd_bus_message_open_container(request, SD_BUS_TYPE_ARRAY, "(ss)");
		for (const auto& item : set.items) {
			if (result >= 0)
				result = sd_bus_message_append(request, "(ss)", item.method.c_str(), item.layoutOverride.c_str());
		}
		if (result >= 0)
			result = sd_bus_message_close_container(request);
	} else if (result >= 0 && commandKind(command) != CommandKind::Save) {
		const std::string* target = nullptr;
		if (const auto* add = std::get_if<AddGroupCommand>(&command))
			target = &add->groupName;
		else if (const auto* switchGroup = std::get_if<SwitchGroupCommand>(&command))
			target = &switchGroup->groupName;
		else if (const auto* setMethod = std::get_if<SetCurrentMethodCommand>(&command))
			target = &setMethod->method;
		else if (const auto* remove = std::get_if<RemoveGroupCommand>(&command))
			target = &remove->groupName;
		result = target ? sd_bus_message_append(request, "s", target->c_str()) : -EINVAL;
	}
	if (result >= 0)
		result = m_impl->call(request, &reply);
	request = sd_bus_message_unref(request);
	reply = sd_bus_message_unref(reply);
	return result < 0
		? CommandResult{.status = statusFromError(result), .diagnostic = "Controller command failed"}
		: CommandResult{.status = TransportStatus::Ok, .diagnostic = {}};
}

}
