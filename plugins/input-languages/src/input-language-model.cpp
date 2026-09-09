#include "input-language-model.hpp"

#include <algorithm>
#include <utility>

namespace InputLanguages {
namespace {
constexpr uint32_t LEFT_CTRL = 29;
constexpr uint32_t LEFT_SHIFT = 42;
}

Model::Model(std::function<void(uint32_t)> onGroupChanged) : m_onGroupChanged(std::move(onGroupChanged)) {}

void Model::key(uint32_t keycode, KeyState state, bool isModifier) {
	const bool target = keycode == LEFT_CTRL || keycode == LEFT_SHIFT;

	if (state == KeyState::Pressed) {
		if (!m_pressed.insert(keycode).second)
			return;

		if (keycode == LEFT_CTRL)
			m_leftCtrlDown = true;
		else if (keycode == LEFT_SHIFT)
			m_leftShiftDown = true;
		else if (!isModifier && (m_leftCtrlDown || m_leftShiftDown)) {
			m_contaminated = true;
			m_candidate    = false;
		}

		if (target && m_leftCtrlDown && m_leftShiftDown && !m_contaminated && !m_switched)
			m_candidate = true;
		return;
	}

	if (!m_pressed.erase(keycode))
		return;

	const bool shouldSwitch = target && m_candidate && !m_contaminated && !m_switched;
	if (keycode == LEFT_CTRL)
		m_leftCtrlDown = false;
	else if (keycode == LEFT_SHIFT)
		m_leftShiftDown = false;

	if (shouldSwitch) {
		m_group = m_group == 0 ? 1 : 0;
		m_switched = true;
		m_candidate = false;
		m_onGroupChanged(m_group);
	}
	clearOccurrenceIfReleased();
}

void Model::adoptGroup(uint32_t group) {
	m_group = group % 2;
}

void Model::reset(uint32_t group) {
	m_group = group % 2;
	m_onGroupChanged(m_group);
}

uint32_t Model::group() const {
	return m_group;
}

void Model::clearOccurrenceIfReleased() {
	if (m_leftCtrlDown || m_leftShiftDown)
		return;
	m_candidate = false;
	m_contaminated = false;
	m_switched = false;
}

bool isPhysicalTypingKeyboard(bool isVirtual, bool hasLibinput, bool hasTypingProperty) {
	return !isVirtual && hasLibinput && hasTypingProperty;
}

bool compatibilityMatches(std::string_view client, const char* server) {
	return server && client == server;
}

std::string keymapSetIdentity(std::vector<std::string> keymaps) {
	std::ranges::sort(keymaps);
	auto uniqueEnd = std::ranges::unique(keymaps).begin();
	keymaps.erase(uniqueEnd, keymaps.end());

	std::string identity;
	for (const auto& keymap : keymaps) {
		identity += std::to_string(keymap.size());
		identity += ':';
		identity += keymap;
	}
	return identity;
}

uint32_t groupAfterKeymapReload(std::string_view previousKeymap, std::string_view currentKeymap, uint32_t previousGroup) {
	return previousKeymap == currentKeymap ? previousGroup % 2 : 0;
}

Coordinator::PhysicalDevice::PhysicalDevice(Coordinator& owner, DeviceId id, uint32_t initialGroup) :
	group(initialGroup), chord([&owner, id](uint32_t nextGroup) { owner.setCanonical(nextGroup); }) {
	chord.adoptGroup(initialGroup);
}

Coordinator::Coordinator(std::function<void(DeviceId, uint32_t)> updateGroup) : m_updateGroup(std::move(updateGroup)) {}

void Coordinator::clear(uint32_t canonicalGroup) {
	m_physical.clear();
	m_excluded.clear();
	m_group = canonicalGroup % 2;
}

void Coordinator::addPhysical(DeviceId id, uint32_t currentGroup) {
	if (m_physical.contains(id) || m_excluded.contains(id))
		return;
	auto device = std::make_unique<PhysicalDevice>(*this, id, currentGroup % 2);
	m_physical.emplace(id, std::move(device));
	if (currentGroup != m_group) {
		m_physical.at(id)->group = m_group;
		m_physical.at(id)->chord.adoptGroup(m_group);
		m_updateGroup(id, m_group);
	}
}

void Coordinator::addExcluded(DeviceId id, uint32_t currentGroup, bool observesRequests) {
	if (m_physical.contains(id) || m_excluded.contains(id))
		return;
	m_excluded.emplace(id, ExcludedDevice{.group = currentGroup, .observesRequests = observesRequests});
}

void Coordinator::remove(DeviceId id) {
	m_physical.erase(id);
	m_excluded.erase(id);
}

void Coordinator::key(DeviceId id, uint32_t keycode, KeyState state, bool isModifier) {
	const auto found = m_physical.find(id);
	if (found != m_physical.end())
		found->second->chord.key(keycode, state, isModifier);
}

void Coordinator::layout(DeviceId id, uint32_t nextGroup) {
	if (nextGroup > 1)
		return;
	if (const auto physical = m_physical.find(id); physical != m_physical.end()) {
		physical->second->group = nextGroup;
		physical->second->chord.adoptGroup(nextGroup);
		setCanonical(nextGroup);
		return;
	}
	const auto excluded = m_excluded.find(id);
	if (excluded == m_excluded.end())
		return;
	if (!excluded->second.observesRequests) {
		excluded->second.group = nextGroup;
		excluded->second.observesRequests = true;
		return;
	}
	if (excluded->second.group == nextGroup)
		return;
	m_updateGroup(id, excluded->second.group);
	setCanonical(nextGroup);
}

void Coordinator::reset(uint32_t group) {
	setCanonical(group);
}

uint32_t Coordinator::group() const {
	return m_group;
}

bool Coordinator::synchronized() const {
	if (m_physical.empty())
		return false;
	for (const auto& [_, device] : m_physical) {
		if (device->group != m_group)
			return false;
	}
	return true;
}

std::vector<DeviceId> Coordinator::physicalDevices() const {
	std::vector<DeviceId> ids;
	ids.reserve(m_physical.size());
	for (const auto& [id, _] : m_physical)
		ids.push_back(id);
	return ids;
}

std::vector<DeviceId> Coordinator::excludedDevices() const {
	std::vector<DeviceId> ids;
	ids.reserve(m_excluded.size());
	for (const auto& [id, _] : m_excluded)
		ids.push_back(id);
	return ids;
}

void Coordinator::setCanonical(uint32_t nextGroup) {
	m_group = nextGroup % 2;
	for (auto& [id, device] : m_physical) {
		device->chord.adoptGroup(m_group);
		if (device->group == m_group)
			continue;
		device->group = m_group;
		m_updateGroup(id, m_group);
	}
}

}
