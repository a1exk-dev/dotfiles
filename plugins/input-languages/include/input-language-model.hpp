#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace InputLanguages {

enum class KeyState { Pressed, Released };
enum class Language { Us, Russian };

struct LanguageTarget {
	Language language = Language::Us;
	uint64_t generation = 1;
	bool operator==(const LanguageTarget&) const = default;
};

class TargetSink {
  public:
	virtual ~TargetSink() = default;
	virtual void offer(LanguageTarget target) noexcept = 0;
};

class Model {
  public:
	explicit Model(std::function<void(uint32_t)> onGroupChanged);

	void key(uint32_t keycode, KeyState state, bool isModifier = false);
	void adoptGroup(uint32_t group);
	void reset(uint32_t group = 0);
	[[nodiscard]] uint32_t group() const;

  private:
	void clearOccurrenceIfReleased();

	std::function<void(uint32_t)> m_onGroupChanged;
	std::unordered_set<uint32_t>  m_pressed;
	uint32_t                      m_group        = 0;
	bool                          m_leftCtrlDown = false;
	bool                          m_leftShiftDown = false;
	bool                          m_candidate    = false;
	bool                          m_contaminated = false;
	bool                          m_switched     = false;
};

using DeviceId = uintptr_t;

[[nodiscard]] bool isPhysicalTypingKeyboard(bool isVirtual, bool hasLibinput, bool hasTypingProperty);
[[nodiscard]] bool compatibilityMatches(std::string_view client, const char* server);
[[nodiscard]] std::string keymapSetIdentity(std::vector<std::string> keymaps);
[[nodiscard]] uint32_t groupAfterKeymapReload(std::string_view previousKeymap, std::string_view currentKeymap, uint32_t previousGroup);

class Coordinator {
  public:
	explicit Coordinator(std::function<void(DeviceId, uint32_t)> updateGroup, TargetSink* targetSink = nullptr);
	void setTargetSink(TargetSink* targetSink);

	void clear(uint32_t canonicalGroup);
	void addPhysical(DeviceId id, uint32_t currentGroup);
	void addExcluded(DeviceId id, uint32_t currentGroup, bool observesRequests);
	void remove(DeviceId id);
	void key(DeviceId id, uint32_t keycode, KeyState state, bool isModifier);
	void layout(DeviceId id, uint32_t group);
	void reset(uint32_t group = 0);
	void keymapChanged();

	[[nodiscard]] uint32_t group() const;
	[[nodiscard]] LanguageTarget target() const;
	[[nodiscard]] bool synchronized() const;
	[[nodiscard]] std::vector<DeviceId> physicalDevices() const;
	[[nodiscard]] std::vector<DeviceId> excludedDevices() const;

  private:
	struct PhysicalDevice {
		PhysicalDevice(Coordinator& owner, DeviceId id, uint32_t group);

		uint32_t group;
		Model    chord;
	};

	struct ExcludedDevice {
		uint32_t group;
		bool     observesRequests;
	};

	void setCanonical(uint32_t group);
	void publishTarget();

	std::function<void(DeviceId, uint32_t)> m_updateGroup;
	TargetSink* m_targetSink = nullptr;
	std::unordered_map<DeviceId, std::unique_ptr<PhysicalDevice>> m_physical;
	std::unordered_map<DeviceId, ExcludedDevice> m_excluded;
	uint32_t m_group = 0;
	uint64_t m_generation = 1;
};

}
