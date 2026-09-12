#include "fcitx-controller.hpp"

#include <openssl/evp.h>

#include <algorithm>
#include <array>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string_view>

namespace InputLanguages::Fcitx {
namespace {

bool contains(const std::vector<std::string>& values, std::string_view expected) {
	return std::ranges::find(values, expected) != values.end();
}

Outcome transportOutcome(TransportStatus status) {
	switch (status) {
		case TransportStatus::Ok:
			return Outcome::Pending;
		case TransportStatus::Unavailable:
		case TransportStatus::Disconnected:
			return Outcome::Unavailable;
		case TransportStatus::Timeout:
			return Outcome::TimeoutIndeterminate;
		case TransportStatus::MethodError:
			return Outcome::MethodError;
		case TransportStatus::MalformedReply:
			return Outcome::UnsupportedInterface;
		case TransportStatus::Conflict:
			return Outcome::ConfigurationConflict;
	}
	return Outcome::UnsupportedInterface;
}

bool repairable(TransportStatus status) {
	return status == TransportStatus::Unavailable || status == TransportStatus::Disconnected ||
		status == TransportStatus::Timeout || status == TransportStatus::MethodError;
}

bool runtimeSupported(const Snapshot& snapshot) {
	if (snapshot.identity.uniqueOwner.empty() || snapshot.identity.ownerEpoch == 0 || !snapshot.identity.supervised ||
		!snapshot.profile.safe ||
		snapshot.identity.upstreamVersion != SUPPORTED_UPSTREAM_VERSION || snapshot.identity.controllerShape != ControllerShape::Supported ||
		!contains(snapshot.availableMethods, US_METHOD) || !contains(snapshot.availableMethods, RUSSIAN_METHOD) ||
		!contains(snapshot.enabledAddons, "keyboard") || !contains(snapshot.enabledAddons, "dbus") ||
		!contains(snapshot.enabledAddons, "dbusfrontend"))
		return false;
	if (snapshot.currentGroup.empty() || std::ranges::none_of(snapshot.groups, [&snapshot](const Group& group) { return group.name == snapshot.currentGroup; }))
		return false;
	for (std::size_t index = 0; index < snapshot.groups.size(); ++index) {
		if (snapshot.groups[index].name.empty())
			return false;
		for (std::size_t other = index + 1; other < snapshot.groups.size(); ++other) {
			if (snapshot.groups[index].name == snapshot.groups[other].name)
				return false;
		}
	}
	return true;
}

bool restorationRuntimeSupported(const Snapshot& snapshot) {
	if (snapshot.identity.uniqueOwner.empty() || snapshot.identity.ownerEpoch == 0 || !snapshot.identity.supervised || !snapshot.profile.safe ||
		snapshot.identity.controllerShape != ControllerShape::Supported || snapshot.currentGroup.empty() ||
		std::ranges::none_of(snapshot.groups, [&snapshot](const Group& group) { return group.name == snapshot.currentGroup; }))
		return false;
	for (std::size_t index = 0; index < snapshot.groups.size(); ++index) {
		if (snapshot.groups[index].name.empty())
			return false;
		for (std::size_t other = index + 1; other < snapshot.groups.size(); ++other) {
			if (snapshot.groups[index].name == snapshot.groups[other].name)
				return false;
		}
	}
	return true;
}

bool defaultMethodAllowed(std::string_view method) {
	return method.empty() || method == US_METHOD || method == RUSSIAN_METHOD;
}

bool exactManagedGroup(const Group& group) {
	return group.name == MANAGED_GROUP_NAME && group.defaultLayout == "us" && defaultMethodAllowed(group.defaultMethod) &&
		group.items.size() == 2 && group.items[0].method == US_METHOD && group.items[0].layoutOverride.empty() &&
		group.items[1].method == RUSSIAN_METHOD && group.items[1].layoutOverride.empty();
}

bool methodBelongsToGroup(const Group& group, std::string_view method) {
	return method.empty() || std::ranges::any_of(group.items, [method](const GroupItem& item) { return item.method == method; });
}

const Group* findGroup(const Snapshot& snapshot, std::string_view name) {
	const auto found = std::ranges::find(snapshot.groups, name, &Group::name);
	return found == snapshot.groups.end() ? nullptr : &*found;
}

AdapterResult inspectionFailure(Inspection inspection) {
	if (inspection.status != TransportStatus::Ok) {
		return {
			.outcome = transportOutcome(inspection.status),
			.snapshot = std::move(inspection.snapshot),
			.retryAfterSeconds = 0,
			.diagnostic = std::move(inspection.diagnostic),
		};
	}
	return {
		.outcome = Outcome::UnsupportedInterface,
		.snapshot = std::move(inspection.snapshot),
		.retryAfterSeconds = 0,
		.diagnostic = "unsupported Controller1 runtime",
	};
}

bool unrelatedGroupsPreserved(const Snapshot& before, const Snapshot& after) {
	std::vector<std::string> beforeOrder;
	std::vector<std::string> afterOrder;
	for (const auto& group : before.groups) {
		if (group.name == MANAGED_GROUP_NAME)
			continue;
		beforeOrder.push_back(group.name);
		const auto* current = findGroup(after, group.name);
		if (!current || *current != group)
			return false;
	}
	for (const auto& group : after.groups) {
		if (std::ranges::find(beforeOrder, group.name) != beforeOrder.end())
			afterOrder.push_back(group.name);
	}
	return beforeOrder == afterOrder;
}

bool inventoriesPreserved(const Snapshot& before, const Snapshot& after) {
	return before.availableMethods == after.availableMethods && before.enabledAddons == after.enabledAddons && before.addons == after.addons;
}

bool semanticsEqual(const Snapshot& before, const Snapshot& after) {
	return before.identity == after.identity && before.groups == after.groups && before.availableMethods == after.availableMethods &&
		before.enabledAddons == after.enabledAddons && before.addons == after.addons && before.currentGroup == after.currentGroup && before.currentMethod == after.currentMethod;
}

std::string jsonString(std::string_view value) {
	std::string result = "\"";
	for (const unsigned char character : value) {
		switch (character) {
			case '\\': result += "\\\\"; break;
			case '"': result += "\\\""; break;
			case '\b': result += "\\b"; break;
			case '\f': result += "\\f"; break;
			case '\n': result += "\\n"; break;
			case '\r': result += "\\r"; break;
			case '\t': result += "\\t"; break;
			default:
				if (character < 0x20) {
					std::ostringstream escaped;
					escaped << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<unsigned>(character);
					result += escaped.str();
				} else {
					result += static_cast<char>(character);
				}
		}
	}
	return result + '"';
}

}

ControllerAdapter::ControllerAdapter(ControllerTransport& transport, bool restorationMode)
	: m_transport(transport), m_restorationMode(restorationMode) {
	m_transport.setRestorationMode(restorationMode);
}

CommandKind commandKind(const Command& command) noexcept {
	if (std::holds_alternative<AddGroupCommand>(command))
		return CommandKind::AddGroup;
	if (std::holds_alternative<SetGroupCommand>(command))
		return CommandKind::SetGroup;
	if (std::holds_alternative<SwitchGroupCommand>(command))
		return CommandKind::SwitchGroup;
	if (std::holds_alternative<SetCurrentMethodCommand>(command))
		return CommandKind::SetCurrentMethod;
	if (std::holds_alternative<RemoveGroupCommand>(command))
		return CommandKind::RemoveGroup;
	return CommandKind::Save;
}

AdapterResult ControllerAdapter::inspect() noexcept {
	auto inspection = m_transport.inspect();
	if (inspection.status != TransportStatus::Ok || !(m_restorationMode ? restorationRuntimeSupported(inspection.snapshot) : runtimeSupported(inspection.snapshot)))
		return inspectionFailure(std::move(inspection));

	const auto& snapshot = inspection.snapshot;
	const auto* managed = findGroup(snapshot, MANAGED_GROUP_NAME);
	if (!managed)
		return {.outcome = Outcome::Pending, .snapshot = std::move(inspection.snapshot), .retryAfterSeconds = 0, .diagnostic = {}};
	if (!exactManagedGroup(*managed))
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(inspection.snapshot), .retryAfterSeconds = 0, .diagnostic = "managed group is foreign"};
	if (snapshot.currentGroup != MANAGED_GROUP_NAME)
		return {.outcome = Outcome::Drift, .snapshot = std::move(inspection.snapshot), .retryAfterSeconds = 0, .diagnostic = "managed group is not current"};

	if (snapshot.currentMethod.empty())
		return {.outcome = Outcome::IdleNoContext, .snapshot = std::move(inspection.snapshot), .retryAfterSeconds = 0, .diagnostic = {}};
	if (snapshot.currentMethod != US_METHOD && snapshot.currentMethod != RUSSIAN_METHOD)
		return {.outcome = Outcome::Drift, .snapshot = std::move(inspection.snapshot), .retryAfterSeconds = 0, .diagnostic = "current method is outside the managed group"};
	return {.outcome = Outcome::Converged, .snapshot = std::move(inspection.snapshot), .retryAfterSeconds = 0, .diagnostic = {}};
}

AdapterResult ControllerAdapter::executeOne(const Snapshot& expected, const Command& command) noexcept {
	auto last = expected;
	auto verify = [&command](const Snapshot& before, const Snapshot& after) {
		switch (commandKind(command)) {
			case CommandKind::AddGroup: {
				const auto& add = std::get<AddGroupCommand>(command);
				const auto* managed = findGroup(after, add.groupName);
				const auto* current = findGroup(before, before.currentGroup);
				return !findGroup(before, add.groupName) && managed && current && managed->items.empty() &&
					managed->defaultMethod.empty() && managed->defaultLayout == current->defaultLayout &&
					after.currentGroup == before.currentGroup && after.currentMethod == before.currentMethod;
			}
			case CommandKind::SetGroup: {
				const auto& set = std::get<SetGroupCommand>(command);
				const auto* group = findGroup(after, set.groupName);
				return group && set.groupName == MANAGED_GROUP_NAME && exactManagedGroup(*group) &&
					after.currentGroup == before.currentGroup && after.currentMethod == before.currentMethod;
			}
			case CommandKind::SwitchGroup: {
				const auto& selected = std::get<SwitchGroupCommand>(command);
				const auto* group = findGroup(after, selected.groupName);
				return group && !after.groups.empty() && after.groups.front().name == selected.groupName &&
					after.currentGroup == selected.groupName && methodBelongsToGroup(*group, after.currentMethod);
			}
			case CommandKind::SetCurrentMethod: {
				const auto& selected = std::get<SetCurrentMethodCommand>(command);
				const auto* group = findGroup(after, after.currentGroup);
				return group && methodBelongsToGroup(*group, selected.method) &&
					(after.currentMethod.empty() || after.currentMethod == selected.method);
			}
			case CommandKind::RemoveGroup: {
				const auto& removed = std::get<RemoveGroupCommand>(command);
				return !findGroup(after, removed.groupName) && after.currentGroup == before.currentGroup &&
					after.currentMethod == before.currentMethod;
			}
			case CommandKind::Save:
				return semanticsEqual(before, after);
		}
		return false;
	};
	if (auto failure = runVerifiedMutation(last, command, verify))
		return std::move(*failure);
	return {
		.outcome = last.currentMethod.empty() ? Outcome::IdleNoContext : Outcome::Pending,
		.snapshot = std::move(last),
		.retryAfterSeconds = 0,
		.diagnostic = {},
	};
}

std::optional<AdapterResult> ControllerAdapter::runVerifiedMutation(
	Snapshot& last,
	const Command& command,
	const std::function<bool(const Snapshot&, const Snapshot&)>& verify,
	const std::function<bool()>& stillCurrent) noexcept {
	auto preflight = m_transport.inspect();
	if (preflight.status != TransportStatus::Ok || !(m_restorationMode ? restorationRuntimeSupported(preflight.snapshot) : runtimeSupported(preflight.snapshot)))
		return inspectionFailure(std::move(preflight));
	if (preflight.snapshot.identity != last.identity)
		return AdapterResult{.outcome = Outcome::Unavailable, .snapshot = std::move(preflight.snapshot), .retryAfterSeconds = 0, .diagnostic = "Controller owner changed"};
	if (preflight.snapshot != last)
		return AdapterResult{.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(preflight.snapshot), .retryAfterSeconds = 0, .diagnostic = "Controller state changed before mutation"};
	if (stillCurrent && !stillCurrent())
		return AdapterResult{.outcome = Outcome::Pending, .snapshot = std::move(preflight.snapshot), .retryAfterSeconds = 0, .diagnostic = "target superseded"};

	const Snapshot before = std::move(preflight.snapshot);
	auto commandResult = m_transport.execute(before, command);
	if (commandResult.status != TransportStatus::Ok && commandResult.status != TransportStatus::Timeout) {
		if (commandKind(command) == CommandKind::Save && commandResult.status == TransportStatus::MethodError)
			m_pendingSave = PendingSave{.snapshot = before, .purpose = m_savePurpose, .target = m_retryTarget};
		return AdapterResult{
			.outcome = transportOutcome(commandResult.status),
			.snapshot = before,
			.retryAfterSeconds = repairable(commandResult.status) ? nextRetry() : 0,
			.diagnostic = std::move(commandResult.diagnostic),
		};
	}

	auto readback = m_transport.inspect();
	if (readback.status != TransportStatus::Ok || !(m_restorationMode ? restorationRuntimeSupported(readback.snapshot) : runtimeSupported(readback.snapshot)))
		return inspectionFailure(std::move(readback));
	if (readback.snapshot.identity != before.identity)
		return AdapterResult{.outcome = Outcome::Unavailable, .snapshot = std::move(readback.snapshot), .retryAfterSeconds = 0, .diagnostic = "Controller owner changed"};
	const bool profileMayChange = commandKind(command) == CommandKind::SetGroup || commandKind(command) == CommandKind::Save;
	if (!profileMayChange && readback.snapshot.profile != before.profile)
		return AdapterResult{.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(readback.snapshot), .retryAfterSeconds = 0, .diagnostic = "Fcitx profile changed during a non-persisting Controller command"};
	if (commandResult.status == TransportStatus::Timeout && commandKind(command) == CommandKind::Save) {
		m_pendingSave = PendingSave{.snapshot = readback.snapshot, .purpose = m_savePurpose, .target = m_retryTarget};
		return AdapterResult{.outcome = Outcome::TimeoutIndeterminate, .snapshot = std::move(readback.snapshot), .retryAfterSeconds = nextRetry(), .diagnostic = std::move(commandResult.diagnostic)};
	}
	if (commandResult.status == TransportStatus::Timeout && semanticsEqual(readback.snapshot, before))
		return AdapterResult{.outcome = Outcome::TimeoutIndeterminate, .snapshot = std::move(readback.snapshot), .retryAfterSeconds = nextRetry(), .diagnostic = std::move(commandResult.diagnostic)};
	if (!inventoriesPreserved(before, readback.snapshot) || !unrelatedGroupsPreserved(before, readback.snapshot) || !verify(before, readback.snapshot))
		return AdapterResult{.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(readback.snapshot), .retryAfterSeconds = 0, .diagnostic = "Controller mutation produced an unexpected semantic delta"};
	last = std::move(readback.snapshot);
	return std::nullopt;
}

AdapterResult ControllerAdapter::installManagedGroup(std::string desiredMethod) noexcept {
	if (desiredMethod != US_METHOD && desiredMethod != RUSSIAN_METHOD)
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = {}, .retryAfterSeconds = 0, .diagnostic = "unsupported desired method"};

	m_savePurpose = SavePurpose::Install;
	auto initial = m_transport.inspect();
	if (initial.status != TransportStatus::Ok || !runtimeSupported(initial.snapshot))
		return inspectionFailure(std::move(initial));
	resetRetry(desiredMethod, initial.snapshot.identity.ownerEpoch);
	if (m_pendingSave) {
		if (m_pendingSave->purpose != SavePurpose::Install || m_pendingSave->target != desiredMethod)
			return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(initial.snapshot), .retryAfterSeconds = 0, .diagnostic = "indeterminate Save belongs to another operation"};
		if (initial.snapshot != m_pendingSave->snapshot)
			return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(initial.snapshot), .retryAfterSeconds = 0, .diagnostic = "Controller state changed after indeterminate Save"};
		return saveSnapshot(std::move(initial.snapshot));
	}
	if (findGroup(initial.snapshot, MANAGED_GROUP_NAME))
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(initial.snapshot), .retryAfterSeconds = 0, .diagnostic = "managed group name collision"};

	Snapshot last = std::move(initial.snapshot);

	if (auto failure = runVerifiedMutation(last,
			AddGroupCommand{MANAGED_GROUP_NAME},
			[](const Snapshot& before, const Snapshot& after) {
				const auto* managed = findGroup(after, MANAGED_GROUP_NAME);
				const auto* current = findGroup(before, before.currentGroup);
				return managed && current && managed->items.empty() && managed->defaultMethod.empty() &&
					managed->defaultLayout == current->defaultLayout && after.currentGroup == before.currentGroup &&
					after.currentMethod == before.currentMethod;
			}))
		return std::move(*failure);

	const std::vector<GroupItem> items{{US_METHOD, ""}, {RUSSIAN_METHOD, ""}};
	if (auto failure = runVerifiedMutation(last,
			SetGroupCommand{MANAGED_GROUP_NAME, "us", items},
			[](const Snapshot& before, const Snapshot& after) {
				const auto* managed = findGroup(after, MANAGED_GROUP_NAME);
				return managed && exactManagedGroup(*managed) && after.currentGroup == before.currentGroup &&
					after.currentMethod == before.currentMethod;
			}))
		return std::move(*failure);

	if (auto failure = runVerifiedMutation(last,
			SwitchGroupCommand{MANAGED_GROUP_NAME},
			[](const Snapshot&, const Snapshot& after) {
				const auto* managed = findGroup(after, MANAGED_GROUP_NAME);
				return !after.groups.empty() && after.groups.front().name == MANAGED_GROUP_NAME &&
					after.currentGroup == MANAGED_GROUP_NAME && managed && methodBelongsToGroup(*managed, after.currentMethod);
			}))
		return std::move(*failure);

	if (auto failure = runVerifiedMutation(last,
			SetCurrentMethodCommand{desiredMethod},
			[&desiredMethod](const Snapshot&, const Snapshot& after) {
				return after.currentGroup == MANAGED_GROUP_NAME && (after.currentMethod.empty() || after.currentMethod == desiredMethod);
			}))
		return std::move(*failure);

	if (auto failure = runVerifiedMutation(last,
			SaveCommand{},
			[](const Snapshot& before, const Snapshot& after) { return semanticsEqual(before, after); }))
		return std::move(*failure);

	return {
		.outcome = last.currentMethod.empty() ? Outcome::IdleNoContext : Outcome::Converged,
		.snapshot = std::move(last),
		.retryAfterSeconds = 0,
		.diagnostic = {},
	};
}

unsigned ControllerAdapter::nextRetry() noexcept {
	constexpr unsigned DELAYS[] = {1, 2, 4, 8};
	const auto index = std::min<unsigned>(m_retryIndex, std::size(DELAYS) - 1);
	++m_retryIndex;
	return DELAYS[index];
}

void ControllerAdapter::resetRetry(std::string_view desiredMethod, uint64_t ownerEpoch, uint64_t deliveryGeneration) noexcept {
	if (m_retryTarget == desiredMethod && m_retryOwnerEpoch == ownerEpoch && m_retryGeneration == deliveryGeneration)
		return;
	m_retryTarget = desiredMethod;
	m_retryOwnerEpoch = ownerEpoch;
	m_retryGeneration = deliveryGeneration;
	m_retryIndex = 0;
}

AdapterResult ControllerAdapter::saveSnapshot(Snapshot snapshot, const std::function<bool()>& stillCurrent) noexcept {
	if (auto failure = runVerifiedMutation(
			snapshot,
			SaveCommand{},
			[](const Snapshot& before, const Snapshot& after) { return semanticsEqual(before, after); },
			stillCurrent))
		return std::move(*failure);
	m_pendingSave.reset();
	m_retryIndex = 0;
	return {
		.outcome = snapshot.currentMethod.empty() ? Outcome::IdleNoContext : Outcome::Converged,
		.snapshot = std::move(snapshot),
		.retryAfterSeconds = 0,
		.diagnostic = {},
	};
}

AdapterResult ControllerAdapter::convergeMethod(
	std::string desiredMethod,
	uint64_t deliveryGeneration,
	const std::function<bool()>& stillCurrent) noexcept {
	if (desiredMethod != US_METHOD && desiredMethod != RUSSIAN_METHOD)
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = {}, .retryAfterSeconds = 0, .diagnostic = "unsupported desired method"};

	auto beforeInspection = m_transport.inspect();
	if (beforeInspection.status != TransportStatus::Ok || !runtimeSupported(beforeInspection.snapshot))
		return inspectionFailure(std::move(beforeInspection));
	Snapshot before = std::move(beforeInspection.snapshot);
	resetRetry(desiredMethod, before.identity.ownerEpoch, deliveryGeneration);
	m_savePurpose = SavePurpose::Converge;
	if (m_pendingSave) {
		if (m_pendingSave->purpose != SavePurpose::Converge)
			return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(before), .retryAfterSeconds = 0, .diagnostic = "indeterminate Save belongs to another operation"};
		if (m_pendingSave->target == desiredMethod && before.currentMethod == desiredMethod && before == m_pendingSave->snapshot)
			return saveSnapshot(std::move(before), stillCurrent);
		m_pendingSave.reset();
	}
	const auto* managed = findGroup(before, MANAGED_GROUP_NAME);
	if (!managed || !exactManagedGroup(*managed))
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(before), .retryAfterSeconds = 0, .diagnostic = "managed group is absent or foreign"};
	if (stillCurrent && !stillCurrent())
		return {.outcome = Outcome::Pending, .snapshot = std::move(before), .retryAfterSeconds = 0, .diagnostic = "target superseded"};
	bool groupChanged = false;
	if (before.currentGroup != MANAGED_GROUP_NAME) {
		auto switchResult = m_transport.execute(
			before,
			SwitchGroupCommand{MANAGED_GROUP_NAME});
		if (switchResult.status != TransportStatus::Ok && switchResult.status != TransportStatus::Timeout)
			return {.outcome = transportOutcome(switchResult.status), .snapshot = std::move(before), .retryAfterSeconds = repairable(switchResult.status) ? nextRetry() : 0, .diagnostic = std::move(switchResult.diagnostic)};
		auto switchReadback = m_transport.inspect();
		if (switchReadback.status != TransportStatus::Ok || !runtimeSupported(switchReadback.snapshot))
			return inspectionFailure(std::move(switchReadback));
		if (switchReadback.snapshot.identity != before.identity) {
			resetRetry(desiredMethod, switchReadback.snapshot.identity.ownerEpoch, deliveryGeneration);
			return {.outcome = Outcome::Unavailable, .snapshot = std::move(switchReadback.snapshot), .retryAfterSeconds = 0, .diagnostic = "Controller owner changed"};
		}
		if (switchReadback.snapshot.profile != before.profile)
			return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(switchReadback.snapshot), .retryAfterSeconds = 0, .diagnostic = "Fcitx profile changed during group drift repair"};
		const auto* switchedManaged = findGroup(switchReadback.snapshot, MANAGED_GROUP_NAME);
		if (!switchedManaged || !exactManagedGroup(*switchedManaged) || !inventoriesPreserved(before, switchReadback.snapshot) ||
			!unrelatedGroupsPreserved(before, switchReadback.snapshot) || switchReadback.snapshot.groups.empty() ||
			switchReadback.snapshot.groups.front().name != MANAGED_GROUP_NAME || !methodBelongsToGroup(*switchedManaged, switchReadback.snapshot.currentMethod))
			return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(switchReadback.snapshot), .retryAfterSeconds = 0, .diagnostic = "group switch changed Controller semantics"};
		if (switchReadback.snapshot.currentGroup != MANAGED_GROUP_NAME) {
			const auto outcome = switchResult.status == TransportStatus::Timeout ? Outcome::TimeoutIndeterminate : Outcome::Drift;
			return {.outcome = outcome, .snapshot = std::move(switchReadback.snapshot), .retryAfterSeconds = nextRetry(), .diagnostic = std::move(switchResult.diagnostic)};
		}
		before = std::move(switchReadback.snapshot);
		groupChanged = true;
	}
	if (before.currentMethod.empty())
		return groupChanged ? saveSnapshot(std::move(before), stillCurrent) : AdapterResult{.outcome = Outcome::IdleNoContext, .snapshot = std::move(before), .retryAfterSeconds = 0, .diagnostic = {}};
	if (before.currentMethod == desiredMethod) {
		m_retryIndex = 0;
		return groupChanged ? saveSnapshot(std::move(before), stillCurrent) : AdapterResult{.outcome = Outcome::Converged, .snapshot = std::move(before), .retryAfterSeconds = 0, .diagnostic = {}};
	}
	if (before.currentMethod != US_METHOD && before.currentMethod != RUSSIAN_METHOD)
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(before), .retryAfterSeconds = 0, .diagnostic = "current method is outside the managed group"};

	const Command setMethod = SetCurrentMethodCommand{desiredMethod};
	if (stillCurrent && !stillCurrent())
		return {.outcome = Outcome::Pending, .snapshot = std::move(before), .retryAfterSeconds = 0, .diagnostic = "target superseded"};
	auto setResult = m_transport.execute(before, setMethod);
	if (setResult.status != TransportStatus::Ok && setResult.status != TransportStatus::Timeout) {
		const auto retry = repairable(setResult.status) ? nextRetry() : 0;
		return {
			.outcome = transportOutcome(setResult.status),
			.snapshot = std::move(before),
			.retryAfterSeconds = retry,
			.diagnostic = std::move(setResult.diagnostic),
		};
	}

	// A write reply never proves delivery, and a timeout is indeterminate until this readback.
	auto afterInspection = m_transport.inspect();
	if (afterInspection.status != TransportStatus::Ok || !runtimeSupported(afterInspection.snapshot))
		return inspectionFailure(std::move(afterInspection));
	Snapshot after = std::move(afterInspection.snapshot);
	if (after.identity != before.identity) {
		resetRetry(desiredMethod, after.identity.ownerEpoch, deliveryGeneration);
		return {.outcome = Outcome::Unavailable, .snapshot = std::move(after), .retryAfterSeconds = 0, .diagnostic = "Controller owner changed"};
	}
	if (after.profile != before.profile)
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(after), .retryAfterSeconds = 0, .diagnostic = "Fcitx profile changed during method delivery"};
	if (!inventoriesPreserved(before, after) || !unrelatedGroupsPreserved(before, after) || !findGroup(after, MANAGED_GROUP_NAME) ||
		!exactManagedGroup(*findGroup(after, MANAGED_GROUP_NAME)))
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(after), .retryAfterSeconds = 0, .diagnostic = "Controller state changed outside method delivery"};
	if (after.currentGroup != MANAGED_GROUP_NAME)
		return {.outcome = Outcome::Drift, .snapshot = std::move(after), .retryAfterSeconds = nextRetry(), .diagnostic = "managed group drifted during method delivery"};
	if (after.currentMethod.empty())
		return {.outcome = Outcome::IdleNoContext, .snapshot = std::move(after), .retryAfterSeconds = 0, .diagnostic = {}};
	if (after.currentMethod != desiredMethod) {
		const auto outcome = setResult.status == TransportStatus::Timeout ? Outcome::TimeoutIndeterminate : Outcome::Drift;
		return {.outcome = outcome, .snapshot = std::move(after), .retryAfterSeconds = nextRetry(), .diagnostic = std::move(setResult.diagnostic)};
	}

	return saveSnapshot(std::move(after), stillCurrent);
}

AdapterResult ControllerAdapter::restore(const Snapshot& prior) noexcept {
	if (prior.currentGroup.empty() || prior.currentGroup == MANAGED_GROUP_NAME)
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = {}, .retryAfterSeconds = 0, .diagnostic = "invalid restoration group"};
	const auto* priorGroup = findGroup(prior, prior.currentGroup);
	if (!priorGroup)
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = {}, .retryAfterSeconds = 0, .diagnostic = "restoration group is absent from prior semantics"};
	if (!prior.currentMethod.empty() && std::ranges::none_of(priorGroup->items, [&prior](const GroupItem& item) { return item.method == prior.currentMethod; }))
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = {}, .retryAfterSeconds = 0, .diagnostic = "restoration method is not in the prior group"};

	m_savePurpose = SavePurpose::Restore;
	auto initial = m_transport.inspect();
	if (initial.status != TransportStatus::Ok || !(m_restorationMode ? restorationRuntimeSupported(initial.snapshot) : runtimeSupported(initial.snapshot)))
		return inspectionFailure(std::move(initial));
	resetRetry(prior.currentMethod, initial.snapshot.identity.ownerEpoch);
	if (m_pendingSave) {
		if (m_pendingSave->purpose != SavePurpose::Restore)
			return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(initial.snapshot), .retryAfterSeconds = 0, .diagnostic = "indeterminate Save belongs to another operation"};
		if (initial.snapshot != m_pendingSave->snapshot)
			return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(initial.snapshot), .retryAfterSeconds = 0, .diagnostic = "Controller state changed after indeterminate Save"};
		return saveSnapshot(std::move(initial.snapshot));
	}
	const auto* managed = findGroup(initial.snapshot, MANAGED_GROUP_NAME);
	const auto* currentPriorGroup = findGroup(initial.snapshot, prior.currentGroup);
	if (!managed || !exactManagedGroup(*managed) || !currentPriorGroup || *currentPriorGroup != *priorGroup)
		return {.outcome = Outcome::ConfigurationConflict, .snapshot = std::move(initial.snapshot), .retryAfterSeconds = 0, .diagnostic = "restoration anchor or managed group is foreign"};

	Snapshot last = std::move(initial.snapshot);

	if (last.currentGroup != prior.currentGroup) {
		if (auto failure = runVerifiedMutation(last,
				SwitchGroupCommand{prior.currentGroup},
				[&prior](const Snapshot&, const Snapshot& after) {
					const auto* destination = findGroup(after, prior.currentGroup);
					return !after.groups.empty() && after.groups.front().name == prior.currentGroup &&
						after.currentGroup == prior.currentGroup && destination && methodBelongsToGroup(*destination, after.currentMethod);
				}))
			return std::move(*failure);
	}

	if (!prior.currentMethod.empty() && last.currentMethod != prior.currentMethod) {
		if (auto failure = runVerifiedMutation(last,
				SetCurrentMethodCommand{prior.currentMethod},
				[&prior](const Snapshot&, const Snapshot& after) { return after.currentGroup == prior.currentGroup && after.currentMethod == prior.currentMethod; }))
			return std::move(*failure);
	}

	if (auto failure = runVerifiedMutation(last,
			RemoveGroupCommand{MANAGED_GROUP_NAME},
			[&prior](const Snapshot& before, const Snapshot& after) {
				return after.currentGroup == prior.currentGroup && after.currentMethod == before.currentMethod &&
					!findGroup(after, MANAGED_GROUP_NAME);
			}))
		return std::move(*failure);

	if (auto failure = runVerifiedMutation(last,
			SaveCommand{},
			[](const Snapshot& before, const Snapshot& after) { return semanticsEqual(before, after); }))
		return std::move(*failure);

	return {
		.outcome = last.currentMethod.empty() ? Outcome::IdleNoContext : Outcome::Converged,
		.snapshot = std::move(last),
		.retryAfterSeconds = 0,
		.diagnostic = {},
	};
}

std::string snapshotJson(const Snapshot& snapshot) {
	std::ostringstream output;
	output << "{\"identity\":{\"unique_owner\":" << jsonString(snapshot.identity.uniqueOwner)
		   << ",\"owner_epoch\":" << snapshot.identity.ownerEpoch
		   << ",\"supervised\":" << (snapshot.identity.supervised ? "true" : "false")
		   << ",\"upstream_version\":" << jsonString(snapshot.identity.upstreamVersion)
		   << ",\"controller_shape\":" << jsonString(snapshot.identity.controllerShape == ControllerShape::Supported ? "supported" : "unsupported")
		   << "},\"profile\":{\"path\":" << jsonString(snapshot.profile.path)
		   << ",\"safe\":" << (snapshot.profile.safe ? "true" : "false")
		   << ",\"device\":" << snapshot.profile.device << ",\"inode\":" << snapshot.profile.inode
		   << ",\"mode\":" << snapshot.profile.mode << ",\"uid\":" << snapshot.profile.ownerUid
		   << ",\"digest\":" << jsonString(snapshot.profile.sha256) << "},\"groups\":[";
	for (std::size_t groupIndex = 0; groupIndex < snapshot.groups.size(); ++groupIndex) {
		if (groupIndex)
			output << ',';
		const auto& group = snapshot.groups[groupIndex];
		output << "{\"name\":" << jsonString(group.name) << ",\"default_layout\":" << jsonString(group.defaultLayout)
			   << ",\"default_im\":" << jsonString(group.defaultMethod) << ",\"properties\":" << group.propertiesJson << ",\"items\":[";
		for (std::size_t itemIndex = 0; itemIndex < group.items.size(); ++itemIndex) {
			if (itemIndex)
				output << ',';
			const auto& item = group.items[itemIndex];
			output << "{\"method\":" << jsonString(item.method) << ",\"layout_override\":" << jsonString(item.layoutOverride)
				   << ",\"display_name\":" << jsonString(item.displayName) << ",\"native_name\":" << jsonString(item.nativeName)
				   << ",\"language_code\":" << jsonString(item.languageCode) << ",\"addon\":" << jsonString(item.addon)
				   << ",\"configurable\":" << (item.configurable ? "true" : "false") << ",\"variant\":";
			if (item.variant)
				output << jsonString(*item.variant);
			else
				output << "null";
			output << ",\"properties\":" << item.propertiesJson << '}';
		}
		output << "]}";
	}
	output << "],\"available_methods\":[";
	for (std::size_t index = 0; index < snapshot.availableMethods.size(); ++index) {
		if (index)
			output << ',';
		output << jsonString(snapshot.availableMethods[index]);
	}
	output << "],\"addons\":[";
	for (std::size_t index = 0; index < snapshot.addons.size(); ++index) {
		if (index)
			output << ',';
		const auto& addon = snapshot.addons[index];
		output << "{\"name\":" << jsonString(addon.name) << ",\"enabled\":" << (addon.enabled ? "true" : "false")
			   << ",\"available\":" << (addon.available ? "true" : "false") << '}';
	}
	output << "],\"current_group\":" << jsonString(snapshot.currentGroup)
		   << ",\"observed_method\":" << jsonString(snapshot.currentMethod) << '}';
	return output.str();
}

std::string snapshotDigest(const Snapshot& snapshot) noexcept {
	try {
		const auto serialized = snapshotJson(snapshot);
		std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
		unsigned length = 0;
		EVP_MD_CTX* context = EVP_MD_CTX_new();
		const bool valid = context && EVP_DigestInit_ex(context, EVP_sha256(), nullptr) == 1 &&
			EVP_DigestUpdate(context, serialized.data(), serialized.size()) == 1 &&
			EVP_DigestFinal_ex(context, digest.data(), &length) == 1 && length == 32;
		EVP_MD_CTX_free(context);
		if (!valid)
			return {};
		static constexpr char HEX[] = "0123456789abcdef";
		std::string result;
		result.reserve(length * 2);
		for (unsigned index = 0; index < length; ++index) {
			result += HEX[digest[index] >> 4];
			result += HEX[digest[index] & 0x0f];
		}
		return result;
	} catch (...) {
		return {};
	}
}

}
