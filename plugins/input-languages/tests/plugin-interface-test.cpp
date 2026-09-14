#include "fcitx-integration-fixture.hpp"

#include <aquamarine/input/Input.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <dlfcn.h>
#include <libinput.h>
#include <libudev.h>
#include <regex>

// The host supplies only the compositor/device boundary. The unmodified plugin,
// installed signal implementation, coordinator, follower, and helper run normally.
namespace {
std::string serverHash;
unsigned hostCalls = 0;
std::unordered_map<std::string, SP<SHyprCtlCommand>> commands;
UP<Event::CEventBus> eventBus;
std::vector<std::pair<std::string, uint32_t>> seatUpdates;

class BackendKeyboard final : public Aquamarine::IKeyboard {
  public:
	libinput_device* getLibinputHandle() override { return reinterpret_cast<libinput_device*>(this); }
	const std::string& getName() override { return name; }
	std::string name = "fixture";
};
class Keyboard final : public IKeyboard {
  public:
	explicit Keyboard(std::string name, bool isVirtual = false) : virtualDevice(isVirtual) {
		m_hlName = name;
		m_currentRules.layout = "us,ru";
		m_xkbKeymapString = "fixture-keymap";
	}
	bool isVirtual() override { return virtualDevice; }
	SP<Aquamarine::IKeyboard> aq() override { return backend; }
	bool virtualDevice;
	SP<BackendKeyboard> backend = makeShared<BackendKeyboard>();
};

std::string compatibilityHash() {
	auto versionMinor = [](std::string version) { return version.substr(0, version.find_last_of('.')); };
	return std::string(GIT_COMMIT_HASH) + "_aq_" + versionMinor(AQUAMARINE_VERSION) + "_hu_" + versionMinor(HYPRUTILS_VERSION) +
		"_hg_" + versionMinor(HYPRGRAPHICS_VERSION) + "_hc_" + versionMinor(HYPRCURSOR_VERSION) + "_hlg_" + versionMinor(HYPRLANG_VERSION);
}
}

// Header-defined compositor globals initialize these unrelated display services.
CHyprColor::CHyprColor(float red, float green, float blue, float alpha) : r(red), g(green), b(blue), a(alpha) {}
Log::CLogger::CLogger() = default;
const NColorManagement::SPCPRimaries& NColorManagement::getPrimaries(ePrimaries) {
 static const SPCPRimaries value;
 return value;
}
WP<const NColorManagement::CImageDescription> NColorManagement::CImageDescription::from(const SImageDescription&) { return {}; }

// Exact installed declarations prevent a permissive mock header hiding API drift.
CInputManager::CInputManager() = default;
CInputManager::~CInputManager() = default;
CKeybindManager::CKeybindManager() = default;
CKeybindManager::~CKeybindManager() = default;
CInputMethodRelay::CInputMethodRelay() = default;
IKeyboard::~IKeyboard() = default;
eHIDType IHID::getType() { return HID_TYPE_UNKNOWN; }
uint32_t IKeyboard::getCapabilities() { return HID_INPUT_CAPABILITY_KEYBOARD; }
eHIDType IKeyboard::getType() { return HID_TYPE_KEYBOARD; }
std::optional<xkb_layout_index_t> IKeyboard::getActiveLayoutIndex() { return m_activeLayout; }
void IKeyboard::updateModifiers(uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {
	m_modifiersState = {.depressed = depressed, .latched = latched, .locked = locked, .group = group};
	m_activeLayout = group;
}
void CInputManager::onKeyboardMod(SP<IKeyboard> keyboard) {
	seatUpdates.emplace_back(keyboard->m_hlName, keyboard->m_activeLayout);
	Event::bus()->m_events.input.keyboard.layout.emit(keyboard, "layout");
}
uint32_t CKeybindManager::keycodeToModifier(xkb_keycode_t key) {
	return key == KEY_LEFTCTRL + 8 || key == KEY_LEFTSHIFT + 8 || key == KEY_RIGHTCTRL + 8 || key == KEY_RIGHTSHIFT + 8;
}
UP<Event::CEventBus>& Event::bus() { ++hostCalls; return eventBus; }
extern "C" udev_device* libinput_device_get_udev_device(libinput_device* device) { return reinterpret_cast<udev_device*>(device); }
extern "C" const char* udev_device_get_property_value(udev_device*, const char* key) { return std::strcmp(key, "ID_INPUT_KEYBOARD") == 0 ? "1" : nullptr; }
extern "C" udev_device* udev_device_unref(udev_device*) { return nullptr; }
APICALL EXPORT const char* __hyprland_api_get_hash() { return serverHash.c_str(); }
APICALL SP<SHyprCtlCommand> HyprlandAPI::registerHyprCtlCommand(HANDLE, SHyprCtlCommand command) {
	++hostCalls;
	auto result = makeShared<SHyprCtlCommand>(std::move(command));
	commands[result->name] = result;
	return result;
}
APICALL bool HyprlandAPI::addDispatcherV2(HANDLE, const std::string& name, std::function<SDispatchResult(std::string)> handler) {
	++hostCalls;
	g_pKeybindManager->m_dispatchers[name] = std::move(handler);
	return true;
}

namespace {
// Assert fixed scalar fields from the production snapshot. Complete JSON shape
// validation belongs to input-language-health-test and the lifecycle parser tests.
std::string health() { return commands.at("inputlanguages")->fn(eHyprCtlOutputFormat::FORMAT_JSON, "inputlanguages"); }
std::string field(const std::string& object, const char* name) {
 const std::regex pattern(std::string("\"") + name + "\":(\"[^\"]*\"|[0-9]+|true|false|null)");
 std::smatch match;
 require(std::regex_search(object, match, pattern), "production health contains the required scalar field");
 const std::string value = match[1];
 return value.starts_with('"') ? value.substr(1, value.size() - 2) : value;
}
bool twoPhysicalKeyboards() {
 return health().find("\"physical_keyboards\":[\"first\",\"second\"]") != std::string::npos;
}
void key(const SP<Keyboard>& keyboard, uint32_t code, bool pressed) {
	keyboard->m_keyboardEvents.key.emit({.keycode = code, .state = pressed ? WL_KEYBOARD_KEY_STATE_PRESSED : WL_KEYBOARD_KEY_STATE_RELEASED});
}
void chord(const SP<Keyboard>& keyboard, bool shiftFirst = false) {
	const auto first = shiftFirst ? KEY_LEFTSHIFT : KEY_LEFTCTRL;
	const auto second = shiftFirst ? KEY_LEFTCTRL : KEY_LEFTSHIFT;
	key(keyboard, first, true); key(keyboard, second, true);
	key(keyboard, first, false); key(keyboard, second, false);
}
}

int main(int argc, char** argv) {
	require(argc == 2, "compiled plugin path is provided");
	SocketFixture socket;
	void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if (!library) { std::cerr << dlerror() << '\n'; return 1; }
	auto init = reinterpret_cast<PLUGIN_DESCRIPTION_INFO (*)(HANDLE)>(dlsym(library, "pluginInit"));
	auto exit = reinterpret_cast<void (*)()>(dlsym(library, "pluginExit"));
	require(init && exit, "real plugin entry points resolve");
	serverHash = "incompatible-installed-stack";
	bool rejected = false;
	try { init(library); } catch (const std::runtime_error&) { rejected = true; }
	require(rejected && hostCalls == 0, "compatibility mismatch rejects before touching compositor internals");

	serverHash = compatibilityHash();
	eventBus = makeUnique<Event::CEventBus>();
	g_pInputManager = makeUnique<CInputManager>();
	g_pKeybindManager = makeUnique<CKeybindManager>();
	auto first = makeShared<Keyboard>("first");
	auto second = makeShared<Keyboard>("second");
	auto excluded = makeShared<Keyboard>("virtual", true);
	g_pInputManager->m_keyboards = {first, second, excluded};
	unsigned passed = 0;
	auto consumer = first->m_keyboardEvents.key.listen([&](IKeyboard::SKeyEvent) { ++passed; });
	std::filesystem::rename(socket.path, socket.path + ".unpublished");
	init(library);
	require(twoPhysicalKeyboards(), "loaded plugin accepts both physical keyboards and excludes virtual input");
	seatUpdates.clear();
	const auto absentStart = std::chrono::steady_clock::now();
	chord(first);
	require(std::chrono::steady_clock::now() - absentStart < 100ms, "absent socket cannot block loaded input callbacks");
	require(passed == 4 && first->m_activeLayout == 1 && second->m_activeLayout == 1 && excluded->m_activeLayout == 0,
		"actual non-consuming callbacks synchronize physical keyboards with an absent socket");
	require(seatUpdates.size() == 2, "one target fans out through the compositor seat boundary once per device");
	const auto generation = field(health(), "canonical_generation");
	key(first, KEY_LEFTCTRL, true); key(first, KEY_LEFTSHIFT, true); key(first, KEY_C, true);
	key(first, KEY_C, false); key(first, KEY_LEFTCTRL, false); key(first, KEY_LEFTSHIFT, false);
	require(field(health(), "canonical_generation") == generation, "third-key shortcuts remain non-consuming and cancel switching");
	std::filesystem::rename(socket.path + ".unpublished", socket.path);
	const auto silentStart = std::chrono::steady_clock::now();
	chord(second, true);
	require(std::chrono::steady_clock::now() - silentStart < 100ms, "silent helper cannot block loaded input callbacks");
	require(first->m_activeLayout == 0 && second->m_activeLayout == 0, "reverse-order chord works on the other keyboard");
	chord(first);
	auto hotplug = makeShared<Keyboard>("hotplug");
	g_pInputManager->m_keyboards.push_back(hotplug);
	Event::bus()->m_events.input.keyboard.layout.emit(hotplug, "layout");
	require(hotplug->m_activeLayout == 1, "hotplug joins the authoritative target through the layout callback");
	hotplug->m_events.destroy.emit();
	std::erase(g_pInputManager->m_keyboards, hotplug);
	require(twoPhysicalKeyboards(), "unplug removes the physical device");
	Event::bus()->m_events.config.preReload.emit();
	Event::bus()->m_events.config.props_refreshed.emit(false);
	require(std::stoull(field(health(), "canonical_generation")) == std::stoull(generation) + 2 && first->m_activeLayout == 1,
		"unchanged reload preserves language and generation");
	excluded->m_activeLayout = 1;
	Event::bus()->m_events.input.keyboard.layout.emit(excluded, "layout");
	require(excluded->m_activeLayout == 0, "excluded widget request preserves its device baseline");
	first->m_activeLayout = 0;
	Event::bus()->m_events.input.keyboard.layout.emit(first, "layout");
	require(first->m_activeLayout == 0 && second->m_activeLayout == 0, "stock widget layout requests still reach the authority");
	const auto reset = commands.at("inputlanguagesreset")->fn(eHyprCtlOutputFormat::FORMAT_JSON, "inputlanguagesreset 1");
	require((field(reset, "ok") == "true") && first->m_activeLayout == 1, "registered reset command invokes the production dispatcher");

	ExactTransport transport;
	ControllerAdapter controller(transport);
	Helper helper(controller, HelperOptions{.buildId = BUILD, .sourceId = SOURCE, .pollInterval = 20ms, .heartbeatInterval = 20ms, .retrySecond = 20ms});
	int helperResult = -1;
	std::thread helperThread([&] { helperResult = helper.run(socket.listener); });
	require(waitUntil([&] { return field(health(), "outcome") == "converged"; }, 3000ms), "loaded plugin converges through the real follower and helper protocol");
	require(transport.currentMethod() == RUSSIAN_METHOD && field(health(), "acknowledged_generation") == field(health(), "canonical_generation"),
		"cached production health acknowledges the current generation");
	const auto begin = std::chrono::steady_clock::now();
	for (unsigned i = 0; i < 100; ++i) health();
	require(std::chrono::steady_clock::now() - begin < 500ms, "registered health command reads the cache without Controller round trips");
	chord(first);
	require(first->m_activeLayout == 0 && second->m_activeLayout == 0, "loaded input callbacks complete direct fan-out synchronously");
	require(waitUntil([&] { return field(health(), "outcome") == "converged" && transport.currentMethod() == US_METHOD; }), "newest target reaches the helper");
	helper.requestStop(); helperThread.join();
	require(helperResult == 0, "helper exits normally");
	const auto finalGeneration = field(health(), "canonical_generation");
	require(waitUntil([&] { return field(health(), "report_stale") == "true" && field(health(), "acknowledged_generation") == "null"; }, 4000ms),
		"registered health rejects stale acknowledgement after helper loss");
	require(field(health(), "canonical_generation") == finalGeneration && first->m_activeLayout == 0 && second->m_activeLayout == 0,
		"stale delivery preserves canonical authority and direct input");
	const auto stop = std::chrono::steady_clock::now();
	exit();
	// Hyprland removes plugin-owned registrations after pluginExit.
	commands.clear(); g_pKeybindManager->m_dispatchers.clear();
	require(dlclose(library) == 0 && std::chrono::steady_clock::now() - stop < 500ms, "plugin unload is bounded with an unavailable helper");
	const auto before = first->m_activeLayout;
	chord(first);
	require(first->m_activeLayout == before, "unload detaches callbacks");
	std::cout << "ok - loaded exact-stack plugin interfaces, device callbacks, delivery, health, and unload\n";
}
