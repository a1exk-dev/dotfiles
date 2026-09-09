#include "input-language-model.hpp"

#include <aquamarine/input/Input.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <libinput.h>
#include <libudev.h>

#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>

#ifndef INPUT_LANGUAGES_BUILD_ID
#error INPUT_LANGUAGES_BUILD_ID must be defined
#endif

#ifndef INPUT_LANGUAGES_SOURCE_ID
#error INPUT_LANGUAGES_SOURCE_ID must be defined
#endif

#ifndef INPUT_LANGUAGES_COMPILER_ID
#error INPUT_LANGUAGES_COMPILER_ID must be defined
#endif

namespace {
constexpr std::string_view RESET_DISPATCHER = "input-language-reset";

[[gnu::used, gnu::section(".input_languages")]] const char ARTIFACT_IDENTITY[] =
	"version=1\n"
	"build_id=" INPUT_LANGUAGES_BUILD_ID "\n"
	"source_id=" INPUT_LANGUAGES_SOURCE_ID "\n"
	"compiler=" INPUT_LANGUAGES_COMPILER_ID "\n";

std::string stripPatch(const char* version) {
	const std::string_view value = version;
	const auto separator = value.find_last_of('.');
	return separator == std::string_view::npos ? std::string(value) : std::string(value.substr(0, separator));
}

std::string clientCompatibilityHash() {
	return std::string(GIT_COMMIT_HASH) + "_aq_" + stripPatch(AQUAMARINE_VERSION) + "_hu_" + stripPatch(HYPRUTILS_VERSION) + "_hg_" +
		stripPatch(HYPRGRAPHICS_VERSION) + "_hc_" + stripPatch(HYPRCURSOR_VERSION) + "_hlg_" + stripPatch(HYPRLANG_VERSION);
}

std::string jsonString(std::string_view value) {
	std::string result = "\"";
	for (const char character : value) {
		switch (character) {
			case '\\': result += "\\\\"; break;
			case '"': result += "\\\""; break;
			case '\n': result += "\\n"; break;
			case '\r': result += "\\r"; break;
			case '\t': result += "\\t"; break;
			default: result += character;
		}
	}
	result += '"';
	return result;
}

bool isPhysicalTypingKeyboard(const SP<IKeyboard>& keyboard) {
	if (!keyboard || !keyboard->aq())
		return false;
	auto* const libinputDevice = keyboard->aq()->getLibinputHandle();
	if (!libinputDevice)
		return false;
	auto* const udevDevice = libinput_device_get_udev_device(libinputDevice);
	if (!udevDevice)
		return false;
	const char* const property = udev_device_get_property_value(udevDevice, "ID_INPUT_KEYBOARD");
	const bool accepted = InputLanguages::isPhysicalTypingKeyboard(keyboard->isVirtual(), true, property && std::string_view(property) == "1");
	udev_device_unref(udevDevice);
	return accepted;
}

std::string keymapIdentity(const SP<IKeyboard>& keyboard) {
	if (!keyboard)
		return {};
	const auto& rules = keyboard->m_currentRules;
	return rules.rules + '\0' + rules.model + '\0' + rules.layout + '\0' + rules.variant + '\0' + rules.options + '\0' + keyboard->m_xkbKeymapString;
}

class InputLanguagePlugin {
  public:
	explicit InputLanguagePlugin(HANDLE handle) : m_handle(handle), m_coordinator([this](InputLanguages::DeviceId id, uint32_t group) { applyGroup(id, group); }) {
		scanKeyboards(true, currentPhysicalGroup());
		// Hyprland emits layout while setupKeyboard applies a hotplugged device's keymap.
		m_layoutListener = Event::bus()->m_events.input.keyboard.layout.listen(
			[this](SP<IKeyboard> keyboard, const std::string&) { onKeyboardLayout(std::move(keyboard)); });
		m_preReloadListener = Event::bus()->m_events.config.preReload.listen([this]() { onPreReload(); });
		m_propsRefreshedListener = Event::bus()->m_events.config.props_refreshed.listen([this](bool) { onPropsRefreshed(); });
		m_healthCommand = HyprlandAPI::registerHyprCtlCommand(m_handle, SHyprCtlCommand{
			.name = "inputlanguages",
			.exact = true,
			.fn = [this](eHyprCtlOutputFormat, std::string) { return healthJson(); },
		});
		m_resetCommand = HyprlandAPI::registerHyprCtlCommand(m_handle, SHyprCtlCommand{
			.name = "inputlanguagesreset",
			.exact = false,
			.fn = [this](eHyprCtlOutputFormat, std::string request) { return resetJson(request); },
		});
		if (!m_healthCommand || !m_resetCommand || !HyprlandAPI::addDispatcherV2(m_handle, std::string(RESET_DISPATCHER), [this](std::string group) { return reset(group); }))
			throw std::runtime_error("could not register the Input Languages control interface");
	}

  private:
	struct PhysicalDevice {
		SP<IKeyboard>       keyboard;
		CHyprSignalListener keyListener;
		CHyprSignalListener destroyListener;
	};

	struct ExcludedDevice {
		SP<IKeyboard> keyboard;
		CHyprSignalListener destroyListener;
	};

	void scanKeyboards(bool existing, uint32_t canonicalGroup) {
		m_physical.clear();
		m_excluded.clear();
		m_coordinator.clear(canonicalGroup);
		if (!g_pInputManager)
			return;
		for (const auto& keyboard : g_pInputManager->m_keyboards)
			addKeyboard(keyboard, existing);
	}

	void addKeyboard(const SP<IKeyboard>& keyboard, bool existing) {
		if (!keyboard || m_physical.contains(keyboard.get()) || m_excluded.contains(keyboard.get()))
			return;
		if (isPhysicalTypingKeyboard(keyboard)) {
			auto device = std::make_unique<PhysicalDevice>();
			device->keyboard = keyboard;
			device->keyListener = keyboard->m_keyboardEvents.key.listen([this, raw = keyboard.get()](IKeyboard::SKeyEvent event) {
				const bool pressed = event.state == WL_KEYBOARD_KEY_STATE_PRESSED;
				const bool modifier = g_pKeybindManager && g_pKeybindManager->keycodeToModifier(event.keycode + 8) != 0;
				m_coordinator.key(reinterpret_cast<InputLanguages::DeviceId>(raw), event.keycode,
					pressed ? InputLanguages::KeyState::Pressed : InputLanguages::KeyState::Released, modifier);
			});
			device->destroyListener = keyboard->m_events.destroy.listen([this, raw = keyboard.get()]() {
				m_coordinator.remove(reinterpret_cast<InputLanguages::DeviceId>(raw));
				m_physical.erase(raw);
			});
			m_physical.emplace(keyboard.get(), std::move(device));
			m_coordinator.addPhysical(reinterpret_cast<InputLanguages::DeviceId>(keyboard.get()), keyboard->getActiveLayoutIndex().value_or(0));
			return;
		}

		const auto group = keyboard->getActiveLayoutIndex().value_or(0);
		ExcludedDevice device{.keyboard = keyboard, .destroyListener = {}};
		device.destroyListener = keyboard->m_events.destroy.listen([this, raw = keyboard.get()]() {
			m_coordinator.remove(reinterpret_cast<InputLanguages::DeviceId>(raw));
			m_excluded.erase(raw);
		});
		m_excluded.emplace(keyboard.get(), std::move(device));
		m_coordinator.addExcluded(reinterpret_cast<InputLanguages::DeviceId>(keyboard.get()), group, existing);
	}

	void onKeyboardLayout(SP<IKeyboard> keyboard) {
		if (!keyboard || m_applyingGroup || m_reloading)
			return;
		if (!m_physical.contains(keyboard.get()) && !m_excluded.contains(keyboard.get())) {
			addKeyboard(keyboard, false);
			if (m_excluded.contains(keyboard.get())) {
				const auto group = keyboard->getActiveLayoutIndex();
				if (group)
					m_coordinator.layout(reinterpret_cast<InputLanguages::DeviceId>(keyboard.get()), *group);
			}
			return;
		}

		const auto group = keyboard->getActiveLayoutIndex();
		if (group)
			m_coordinator.layout(reinterpret_cast<InputLanguages::DeviceId>(keyboard.get()), *group);
	}

	void updateGroup(const SP<IKeyboard>& keyboard, uint32_t group) {
		const bool wasApplyingGroup = m_applyingGroup;
		m_applyingGroup = true;
		keyboard->updateModifiers(keyboard->m_modifiersState.depressed, keyboard->m_modifiersState.latched, keyboard->m_modifiersState.locked, group);
		if (g_pInputManager)
			g_pInputManager->onKeyboardMod(keyboard);
		m_applyingGroup = wasApplyingGroup;
	}

	void applyGroup(InputLanguages::DeviceId id, uint32_t group) {
		auto* const raw = reinterpret_cast<IKeyboard*>(id);
		if (const auto physical = m_physical.find(raw); physical != m_physical.end()) {
			updateGroup(physical->second->keyboard, group);
			return;
		}
		if (const auto excluded = m_excluded.find(raw); excluded != m_excluded.end())
			updateGroup(excluded->second.keyboard, group);
	}

	std::string currentKeymapIdentity() const {
		if (!g_pInputManager)
			return {};
		std::vector<std::string> keymaps;
		for (const auto& keyboard : g_pInputManager->m_keyboards) {
			if (isPhysicalTypingKeyboard(keyboard))
				keymaps.push_back(keymapIdentity(keyboard));
		}
		return InputLanguages::keymapSetIdentity(std::move(keymaps));
	}

	uint32_t currentPhysicalGroup() const {
		if (!g_pInputManager)
			return 0;
		for (const auto& keyboard : g_pInputManager->m_keyboards) {
			if (isPhysicalTypingKeyboard(keyboard))
				return keyboard->getActiveLayoutIndex().value_or(0) % 2;
		}
		return 0;
	}

	void onPreReload() {
		m_reloading = true;
		m_groupBeforeReload = m_coordinator.group();
		m_keymapBeforeReload = currentKeymapIdentity();
	}

	void onPropsRefreshed() {
		const auto currentIdentity = currentKeymapIdentity();
		scanKeyboards(true, InputLanguages::groupAfterKeymapReload(m_keymapBeforeReload, currentIdentity, m_groupBeforeReload));
		m_reloading = false;
	}

	SDispatchResult reset(const std::string& requestedGroup) {
		if (!requestedGroup.empty() && requestedGroup != "0" && requestedGroup != "1")
			return {.success = false, .error = "input-language-reset accepts only group 0 or 1"};
		m_coordinator.reset(requestedGroup == "1" ? 1 : 0);
		return {};
	}

	std::string resetJson(const std::string& request) {
		constexpr std::string_view prefix = "inputlanguagesreset ";
		if (!request.starts_with(prefix))
			return R"({"ok":false,"error":"inputlanguagesreset requires group 0 or 1"})";
		if (!g_pKeybindManager)
			return R"({"ok":false,"error":"input-language-reset dispatcher is unavailable"})";
		const auto dispatcher = g_pKeybindManager->m_dispatchers.find(std::string(RESET_DISPATCHER));
		if (dispatcher == g_pKeybindManager->m_dispatchers.end())
			return R"({"ok":false,"error":"input-language-reset dispatcher is unavailable"})";
		const auto result = dispatcher->second(request.substr(prefix.size()));
		if (!result.success)
			return "{\"ok\":false,\"error\":" + jsonString(result.error) + '}';
		return "{\"ok\":true,\"canonical_group\":" + std::to_string(m_coordinator.group()) + '}';
	}

	std::string healthJson() const {
		std::ostringstream output;
		output << "{\"healthy\":" << (m_coordinator.synchronized() ? "true" : "false")
			   << ",\"build_id\":" << jsonString(INPUT_LANGUAGES_BUILD_ID)
			   << ",\"source_id\":" << jsonString(INPUT_LANGUAGES_SOURCE_ID)
			   << ",\"compatibility_hash\":" << jsonString(clientCompatibilityHash())
			   << ",\"canonical_group\":" << m_coordinator.group()
			   << ",\"physical_keyboards\":[";
		bool first = true;
		for (const auto& [_, device] : m_physical) {
			if (!first)
				output << ',';
			first = false;
			output << jsonString(device->keyboard->m_hlName);
		}
		output << "],\"excluded_keyboards\":[";
		first = true;
		for (const auto& [_, device] : m_excluded) {
			if (!first)
				output << ',';
			first = false;
			output << jsonString(device.keyboard->m_hlName);
		}
		output << "]}";
		return output.str();
	}

	HANDLE m_handle;
	uint32_t m_groupBeforeReload = 0;
	bool m_applyingGroup = false;
	bool m_reloading = false;
	std::string m_keymapBeforeReload;
	InputLanguages::Coordinator m_coordinator;
	std::unordered_map<IKeyboard*, std::unique_ptr<PhysicalDevice>> m_physical;
	std::unordered_map<IKeyboard*, ExcludedDevice> m_excluded;
	CHyprSignalListener m_layoutListener;
	CHyprSignalListener m_preReloadListener;
	CHyprSignalListener m_propsRefreshedListener;
	SP<SHyprCtlCommand> m_healthCommand;
	SP<SHyprCtlCommand> m_resetCommand;
};

std::unique_ptr<InputLanguagePlugin> plugin;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
	return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
	const std::string clientHash = clientCompatibilityHash();
	const char* const serverHash = __hyprland_api_get_hash();
	if (!InputLanguages::compatibilityMatches(clientHash, serverHash))
		throw std::runtime_error("Input Languages compatibility mismatch: built for " + clientHash + ", running " + (serverHash ? serverHash : "unknown"));

	plugin = std::make_unique<InputLanguagePlugin>(handle);
	return {"Input Languages", "Cancellable Ctrl+Shift language switching for synchronized physical keyboards", "dotfiles", INPUT_LANGUAGES_BUILD_ID};
}

APICALL EXPORT void PLUGIN_EXIT() {
	plugin.reset();
}
