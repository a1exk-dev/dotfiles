#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace InputLanguages::Fcitx {

inline constexpr auto SUPPORTED_UPSTREAM_VERSION = "5.1.21";
inline constexpr auto MANAGED_GROUP_NAME = "Dotfiles Input Languages";
inline constexpr auto US_METHOD = "keyboard-us";
inline constexpr auto RUSSIAN_METHOD = "keyboard-ru";

enum class ControllerShape { Supported, Unsupported };
enum class ControllerShapeRequirement { ChangedApply, Restoration };
[[nodiscard]] ControllerShape controllerShapeFromIntrospection(
	std::string_view xml,
	ControllerShapeRequirement requirement = ControllerShapeRequirement::ChangedApply) noexcept;
enum class TransportStatus { Ok, Unavailable, Disconnected, Timeout, MethodError, MalformedReply, Conflict };
enum class Outcome {
	Pending,
	Converged,
	IdleNoContext,
	Drift,
	Unavailable,
	TimeoutIndeterminate,
	MethodError,
	ConfigurationConflict,
	UnsupportedInterface,
};

struct RuntimeIdentity {
	std::string uniqueOwner;
	uint64_t ownerEpoch = 0;
	bool supervised = false;
	std::string upstreamVersion;
	ControllerShape controllerShape = ControllerShape::Unsupported;

	bool operator==(const RuntimeIdentity&) const = default;
};

struct GroupItem {
	std::string method;
	std::string layoutOverride;
	std::string displayName{};
	std::string nativeName{};
	std::string languageCode{};
	std::string addon{};
	bool configurable = false;
	std::optional<std::string> variant{};
	std::string propertiesJson = "{}";

	bool operator==(const GroupItem&) const = default;
};

struct Group {
	std::string name;
	std::string defaultMethod;
	std::string defaultLayout;
	std::vector<GroupItem> items;
	std::string propertiesJson = "{}";

	bool operator==(const Group&) const = default;
};

struct ProfileIdentity {
	std::string path{};
	bool safe = false;
	uint64_t device = 0;
	uint64_t inode = 0;
	uint32_t mode = 0;
	uint32_t ownerUid = 0;
	std::string sha256;

	bool operator==(const ProfileIdentity&) const = default;
};

struct AddonState {
	std::string name;
	bool enabled = false;
	bool available = false;

	bool operator==(const AddonState&) const = default;
};

struct Snapshot {
	RuntimeIdentity identity;
	ProfileIdentity profile;
	std::vector<Group> groups;
	std::vector<std::string> availableMethods;
	std::vector<std::string> enabledAddons;
	std::vector<AddonState> addons{};
	std::string currentGroup;
	std::string currentMethod;

	bool operator==(const Snapshot&) const = default;
};

struct Inspection {
	TransportStatus status = TransportStatus::Unavailable;
	Snapshot snapshot;
	std::string diagnostic;
};

enum class CommandKind { AddGroup, SetGroup, SwitchGroup, SetCurrentMethod, RemoveGroup, Save };

struct AddGroupCommand {
	std::string groupName;
	bool operator==(const AddGroupCommand&) const = default;
};

struct SetGroupCommand {
	std::string groupName;
	std::string defaultLayout;
	std::vector<GroupItem> items;
	bool operator==(const SetGroupCommand&) const = default;
};

struct SwitchGroupCommand {
	std::string groupName;
	bool operator==(const SwitchGroupCommand&) const = default;
};

struct SetCurrentMethodCommand {
	std::string method;
	bool operator==(const SetCurrentMethodCommand&) const = default;
};

struct RemoveGroupCommand {
	std::string groupName;
	bool operator==(const RemoveGroupCommand&) const = default;
};

struct SaveCommand {
	bool operator==(const SaveCommand&) const = default;
};

using Command = std::variant<AddGroupCommand, SetGroupCommand, SwitchGroupCommand, SetCurrentMethodCommand, RemoveGroupCommand, SaveCommand>;
[[nodiscard]] CommandKind commandKind(const Command& command) noexcept;

struct CommandResult {
	TransportStatus status = TransportStatus::Unavailable;
	std::string diagnostic;
};

class ControllerTransport {
  public:
	virtual ~ControllerTransport() = default;
	virtual void setRestorationMode(bool) noexcept {}
	virtual Inspection inspect() noexcept = 0;
	virtual CommandResult execute(const Snapshot& expected, const Command& command) noexcept = 0;
};

struct RuntimeEvidence {
	std::string uniqueOwner;
	std::string upstreamVersion;
	bool supervised = false;
	std::string profilePath;
};

class SdBusControllerTransport final : public ControllerTransport {
  public:
	explicit SdBusControllerTransport(RuntimeEvidence evidence) noexcept;
	~SdBusControllerTransport() override;
	SdBusControllerTransport(const SdBusControllerTransport&) = delete;
	SdBusControllerTransport& operator=(const SdBusControllerTransport&) = delete;

	void updateEvidence(RuntimeEvidence evidence) noexcept;
	void setRestorationMode(bool enabled) noexcept override;
	Inspection inspect() noexcept override;
	CommandResult execute(const Snapshot& expected, const Command& command) noexcept override;

  private:
	class Impl;
	std::unique_ptr<Impl> m_impl;
};

struct AdapterResult {
	Outcome outcome = Outcome::Unavailable;
	Snapshot snapshot;
	unsigned retryAfterSeconds = 0;
	std::string diagnostic;
};

class ControllerAdapter {
  public:
	explicit ControllerAdapter(ControllerTransport& transport, bool restorationMode = false);
	[[nodiscard]] AdapterResult inspect() noexcept;
	[[nodiscard]] AdapterResult executeOne(const Snapshot& expected, const Command& command) noexcept;
	[[nodiscard]] AdapterResult installManagedGroup(std::string desiredMethod) noexcept;
	[[nodiscard]] AdapterResult convergeMethod(
		std::string desiredMethod,
		uint64_t deliveryGeneration = 0,
		const std::function<bool()>& stillCurrent = {}) noexcept;
	[[nodiscard]] AdapterResult restore(const Snapshot& prior) noexcept;

  private:
	enum class SavePurpose { None, Install, Converge, Restore };
	struct PendingSave {
		Snapshot snapshot;
		SavePurpose purpose = SavePurpose::None;
		std::string target;
	};

	[[nodiscard]] unsigned nextRetry() noexcept;
	void resetRetry(std::string_view desiredMethod, uint64_t ownerEpoch, uint64_t deliveryGeneration = 0) noexcept;
	[[nodiscard]] AdapterResult saveSnapshot(Snapshot snapshot, const std::function<bool()>& stillCurrent = {}) noexcept;
	[[nodiscard]] std::optional<AdapterResult> runVerifiedMutation(
		Snapshot& last,
		const Command& command,
		const std::function<bool(const Snapshot&, const Snapshot&)>& verify,
		const std::function<bool()>& stillCurrent = {}) noexcept;

	ControllerTransport& m_transport;
	bool m_restorationMode = false;
	std::optional<PendingSave> m_pendingSave;
	SavePurpose m_savePurpose = SavePurpose::None;
	std::string m_retryTarget;
	uint64_t m_retryOwnerEpoch = 0;
	uint64_t m_retryGeneration = 0;
	unsigned m_retryIndex = 0;
};

[[nodiscard]] std::string snapshotJson(const Snapshot& snapshot);
[[nodiscard]] std::string snapshotDigest(const Snapshot& snapshot) noexcept;

}
