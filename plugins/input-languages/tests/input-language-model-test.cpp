#include "input-language-model.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {
using InputLanguages::KeyState;
using InputLanguages::Model;
using InputLanguages::Coordinator;

constexpr uint32_t LEFT_CTRL = 29;
constexpr uint32_t LEFT_SHIFT = 42;

void require(bool condition, const std::string& message) {
	if (!condition) {
		std::cerr << "not ok - " << message << '\n';
		std::exit(1);
	}
}
}

int main() {
	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		model.key(LEFT_CTRL, KeyState::Pressed, true);
		model.key(LEFT_SHIFT, KeyState::Pressed, true);
		model.key(LEFT_CTRL, KeyState::Released, true);
		model.key(LEFT_SHIFT, KeyState::Released, true);
		require(groups == std::vector<uint32_t>{1}, "Ctrl then Shift switches once on first release");
	}
	std::cout << "ok - Ctrl then Shift switches once on first release\n";

	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		model.key(LEFT_SHIFT, KeyState::Pressed, true);
		model.key(LEFT_CTRL, KeyState::Pressed, true);
		model.key(LEFT_SHIFT, KeyState::Released, true);
		model.key(LEFT_CTRL, KeyState::Released, true);
		require(groups == std::vector<uint32_t>{1}, "Shift then Ctrl switches once on first release");
	}
	std::cout << "ok - Shift then Ctrl switches once on first release\n";

	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		model.key(LEFT_CTRL, KeyState::Pressed, true);
		model.key(LEFT_SHIFT, KeyState::Pressed, true);
		model.key(30, KeyState::Pressed);
		model.key(30, KeyState::Released);
		model.key(LEFT_CTRL, KeyState::Released, true);
		model.key(LEFT_SHIFT, KeyState::Released, true);
		require(groups.empty(), "a third non-modifier key cancels switching");
	}
	std::cout << "ok - a third non-modifier key cancels switching\n";

	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		model.key(30, KeyState::Pressed);
		model.key(LEFT_CTRL, KeyState::Pressed, true);
		model.key(LEFT_SHIFT, KeyState::Pressed, true);
		model.key(30, KeyState::Released);
		model.key(LEFT_CTRL, KeyState::Released, true);
		model.key(LEFT_SHIFT, KeyState::Released, true);
		require(groups == std::vector<uint32_t>{1}, "a pre-existing key release does not cancel switching");
	}
	std::cout << "ok - a pre-existing key release does not cancel switching\n";

	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		model.key(30, KeyState::Pressed);
		model.key(LEFT_CTRL, KeyState::Pressed, true);
		model.key(LEFT_SHIFT, KeyState::Pressed, true);
		model.key(30, KeyState::Pressed);
		model.key(LEFT_CTRL, KeyState::Pressed, true);
		model.key(LEFT_CTRL, KeyState::Released, true);
		model.key(LEFT_SHIFT, KeyState::Released, true);
		require(groups == std::vector<uint32_t>{1}, "repeat events do not cancel or switch twice");
	}
	std::cout << "ok - repeat events do not cancel or switch twice\n";

	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		for (int occurrence = 0; occurrence < 2; ++occurrence) {
			model.key(LEFT_CTRL, KeyState::Pressed, true);
			model.key(LEFT_SHIFT, KeyState::Pressed, true);
			model.key(LEFT_CTRL, KeyState::Released, true);
			model.key(LEFT_SHIFT, KeyState::Released, true);
		}
		require(groups == std::vector<uint32_t>({1, 0}), "repeated chords alternate the canonical group");
	}
	std::cout << "ok - repeated chords alternate the canonical group\n";

	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		model.key(LEFT_CTRL, KeyState::Pressed, true);
		model.key(LEFT_SHIFT, KeyState::Pressed, true);
		model.key(56, KeyState::Pressed, true);
		model.key(LEFT_CTRL, KeyState::Released, true);
		model.key(LEFT_SHIFT, KeyState::Released, true);
		require(groups == std::vector<uint32_t>{1}, "a third modifier does not cancel switching");
	}
	std::cout << "ok - a third modifier does not cancel switching\n";

	{
		std::vector<uint32_t> groups;
		Model model([&groups](uint32_t group) { groups.push_back(group); });
		model.adoptGroup(1);
		require(model.group() == 1 && groups.empty(), "adopting a physical layout does not echo a change");
		model.reset();
		require(model.group() == 0 && groups == std::vector<uint32_t>{0}, "reset selects US through the normal callback");
		model.reset(1);
		require(model.group() == 1 && groups == std::vector<uint32_t>({0, 1}), "rollback can restore Russian through the same callback");
	}
	std::cout << "ok - canonical group adoption and reset are explicit\n";

	{
		require(InputLanguages::isPhysicalTypingKeyboard(false, true, true), "a non-virtual libinput typing keyboard is accepted");
		require(!InputLanguages::isPhysicalTypingKeyboard(true, true, true), "a virtual keyboard is excluded");
		require(!InputLanguages::isPhysicalTypingKeyboard(false, false, true), "a non-libinput keyboard is excluded");
		require(!InputLanguages::isPhysicalTypingKeyboard(false, true, false), "a button-only libinput device is excluded");
	}
	std::cout << "ok - device classification requires every physical typing signal\n";

	{
		require(InputLanguages::compatibilityMatches("exact-stack", "exact-stack"), "the exact compatibility hash is accepted");
		require(!InputLanguages::compatibilityMatches("exact-stack", "other-stack"), "a different compatibility hash is rejected");
		require(!InputLanguages::compatibilityMatches("exact-stack", nullptr), "a missing running hash is rejected");
	}
	std::cout << "ok - compatibility requires the complete exact running hash\n";

	{
		const auto before = InputLanguages::keymapSetIdentity({"keyboard-a", "keyboard-b", "keyboard-a"});
		const auto reordered = InputLanguages::keymapSetIdentity({"keyboard-b", "keyboard-a"});
		const auto changedSecond = InputLanguages::keymapSetIdentity({"keyboard-a", "keyboard-c"});
		require(before == reordered, "keymap identity ignores keyboard order and duplicate maps");
		require(before != changedSecond, "keymap identity includes every distinct physical-keyboard map");
	}
	std::cout << "ok - reload identity covers the complete physical-keyboard keymap set\n";

	{
		require(InputLanguages::groupAfterKeymapReload("same-keymap", "same-keymap", 1) == 1, "an unchanged keymap preserves Russian");
		require(InputLanguages::groupAfterKeymapReload("old-keymap", "new-keymap", 1) == 0, "a changed keymap resets to US");
	}
	std::cout << "ok - reload policy preserves unchanged keymaps and resets changed keymaps\n";

	{
		std::vector<std::pair<InputLanguages::DeviceId, uint32_t>> updates;
		Coordinator coordinator([&updates](InputLanguages::DeviceId id, uint32_t group) { updates.emplace_back(id, group); });
		coordinator.addPhysical(1, 0);
		coordinator.addPhysical(2, 0);
		coordinator.key(1, LEFT_CTRL, KeyState::Pressed, true);
		coordinator.key(1, LEFT_SHIFT, KeyState::Pressed, true);
		coordinator.key(1, LEFT_CTRL, KeyState::Released, true);
		coordinator.key(1, LEFT_SHIFT, KeyState::Released, true);
		std::sort(updates.begin(), updates.end());
		require(updates == std::vector<std::pair<InputLanguages::DeviceId, uint32_t>>({{1, 1}, {2, 1}}), "a chord fans out to two physical keyboards");
		require(coordinator.group() == 1 && coordinator.synchronized(), "the physical keyboard group is canonical");

		updates.clear();
		coordinator.layout(2, 0);
		std::sort(updates.begin(), updates.end());
		require(updates == std::vector<std::pair<InputLanguages::DeviceId, uint32_t>>({{1, 0}}), "an external physical layout change becomes canonical");
		coordinator.layout(2, 1);

		updates.clear();
		coordinator.addPhysical(3, 0);
		require(updates == std::vector<std::pair<InputLanguages::DeviceId, uint32_t>>({{3, 1}}), "a hotplugged physical keyboard joins the canonical group");
		coordinator.remove(2);
		coordinator.reset();
		std::sort(updates.begin(), updates.end());
		require(updates == std::vector<std::pair<InputLanguages::DeviceId, uint32_t>>({{1, 0}, {3, 0}, {3, 1}}), "unplugged keyboards leave synchronization cleanly");
	}
	std::cout << "ok - two keyboards synchronize across chord, hotplug, and unplug\n";

	{
		std::vector<std::pair<InputLanguages::DeviceId, uint32_t>> updates;
		Coordinator coordinator([&updates](InputLanguages::DeviceId id, uint32_t group) { updates.emplace_back(id, group); });
		coordinator.addPhysical(1, 0);
		coordinator.addExcluded(9, 0, true);
		coordinator.layout(9, 1);
		std::sort(updates.begin(), updates.end());
		require(updates == std::vector<std::pair<InputLanguages::DeviceId, uint32_t>>({{1, 1}, {9, 0}}), "an excluded widget target is restored while physical keyboards adopt its request");
		updates.clear();
		coordinator.key(9, LEFT_CTRL, KeyState::Pressed, true);
		coordinator.key(9, LEFT_SHIFT, KeyState::Pressed, true);
		coordinator.key(9, LEFT_CTRL, KeyState::Released, true);
		require(updates.empty(), "an excluded keyboard cannot recognize the chord");
	}
	std::cout << "ok - excluded devices bridge widget requests without joining the chord group\n";

	{
		std::vector<std::pair<InputLanguages::DeviceId, uint32_t>> updates;
		Coordinator coordinator([&updates](InputLanguages::DeviceId id, uint32_t group) { updates.emplace_back(id, group); });
		coordinator.addPhysical(1, 1);
		coordinator.addExcluded(9, 0, false);
		coordinator.layout(9, 0);
		require(updates == std::vector<std::pair<InputLanguages::DeviceId, uint32_t>>{{1, 0}}, "setup-time excluded layout is not a request");
		updates.clear();
		coordinator.layout(9, 1);
		std::sort(updates.begin(), updates.end());
		require(updates == std::vector<std::pair<InputLanguages::DeviceId, uint32_t>>({{1, 1}, {9, 0}}), "the first explicit excluded-device change is bridged");
	}
	std::cout << "ok - hotplug setup and the first later excluded request remain distinct\n";
}
