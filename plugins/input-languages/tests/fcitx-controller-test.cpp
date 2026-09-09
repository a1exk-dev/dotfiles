#include "fcitx-controller.hpp"

#include <algorithm>
#include <cstdlib>
#include <deque>
#include <iostream>
#include <functional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {
using namespace InputLanguages::Fcitx;

void require(bool condition, const std::string& message) {
	if (!condition) {
		std::cerr << "not ok - " << message << '\n';
		std::exit(1);
	}
}

Snapshot exactSnapshot() {
	return {
		.identity = {
			.uniqueOwner = ":1.42",
			.ownerEpoch = 1,
			.supervised = true,
			.upstreamVersion = "5.1.21",
			.controllerShape = ControllerShape::Supported,
		},
		.profile = {.safe = true, .device = 1, .inode = 2, .mode = 0600, .ownerUid = 1000, .sha256 = std::string(64, 'a')},
		.groups = {
			{
				.name = "Dotfiles Input Languages",
				.defaultMethod = "keyboard-us",
				.defaultLayout = "us",
				.items = {{"keyboard-us", ""}, {"keyboard-ru", ""}},
			},
		},
		.availableMethods = {"keyboard-us", "keyboard-ru"},
		.enabledAddons = {"keyboard", "dbus", "dbusfrontend"},
		.currentGroup = "Dotfiles Input Languages",
		.currentMethod = "keyboard-us",
	};
}

class ScriptedTransport final : public ControllerTransport {
  public:
	Inspection inspect() noexcept override {
		++inspectionCount;
		if (onInspect)
			onInspect(inspectionCount, snapshot);
		return {.status = TransportStatus::Ok, .snapshot = snapshot, .diagnostic = {}};
	}

	CommandResult execute(const Snapshot& expected, const Command& command) noexcept override {
		if (profileChangesBeforeExecute) {
			profileChangesBeforeExecute = false;
			snapshot.profile.sha256[0] = 'b';
			if (snapshot.profile != expected.profile)
				return {.status = TransportStatus::Conflict, .diagnostic = "scripted profile conflict"};
		}
		commands.push_back(command);
		const auto status = commandStatuses.empty() ? TransportStatus::Ok : commandStatuses.front();
		if (!commandStatuses.empty())
			commandStatuses.pop_front();
		if (status != TransportStatus::Ok && !(status == TransportStatus::Timeout && applyTimedOutCommands))
			return {.status = status, .diagnostic = "scripted failure"};
		switch (commandKind(command)) {
			case CommandKind::AddGroup: {
				const auto& add = std::get<AddGroupCommand>(command);
				snapshot.groups.push_back({.name = add.groupName, .defaultMethod = {}, .defaultLayout = "us", .items = {}});
				break;
			}
			case CommandKind::SetGroup: {
				const auto& set = std::get<SetGroupCommand>(command);
				for (auto& group : snapshot.groups) {
					if (group.name == set.groupName) {
						group.defaultLayout = set.defaultLayout;
						group.defaultMethod = RUSSIAN_METHOD;
						group.items = set.items;
					}
				}
				break;
			}
			case CommandKind::SwitchGroup: {
				const auto& switchGroup = std::get<SwitchGroupCommand>(command);
				snapshot.currentGroup = switchGroup.groupName;
				if (const auto group = std::ranges::find(snapshot.groups, switchGroup.groupName, &Group::name); group != snapshot.groups.end()) {
					snapshot.currentMethod = group->defaultMethod;
					std::rotate(snapshot.groups.begin(), group, group + 1);
				}
				break;
			}
			case CommandKind::SetCurrentMethod: {
				const auto& setMethod = std::get<SetCurrentMethodCommand>(command);
				if (!ignoreMethodSet)
					snapshot.currentMethod = setMethod.method;
				break;
			}
			case CommandKind::RemoveGroup: {
				const auto& remove = std::get<RemoveGroupCommand>(command);
				std::erase_if(snapshot.groups, [&remove](const Group& group) { return group.name == remove.groupName; });
				break;
			}
			case CommandKind::Save:
				break;
		}
		if (afterCommand)
			afterCommand(command, snapshot);
		return {.status = status, .diagnostic = status == TransportStatus::Ok ? std::string{} : "scripted failure"};
	}

	Snapshot snapshot = exactSnapshot();
	int inspectionCount = 0;
	std::vector<Command> commands;
	std::function<void(const Command&, Snapshot&)> afterCommand;
	std::function<void(int, Snapshot&)> onInspect;
	std::deque<TransportStatus> commandStatuses;
	bool applyTimedOutCommands = false;
	bool ignoreMethodSet = false;
	bool profileChangesBeforeExecute = false;
};
}

int main(int argc, char** argv) {
	if (argc == 2 && std::string_view(argv[1]) == "--live-read-only") {
		const char* home = std::getenv("HOME");
		require(home != nullptr, "HOME is available for live profile inspection");
		const std::string profile = std::string(home) + "/.config/fcitx5/profile";
		const char* currentAddress = std::getenv("DBUS_SESSION_BUS_ADDRESS");
		const std::string savedAddress = currentAddress ? currentAddress : "";
		setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=/tmp/dotfiles-missing-session-bus", 1);
		SdBusControllerTransport recoveryTransport({.uniqueOwner = {}, .upstreamVersion = SUPPORTED_UPSTREAM_VERSION, .supervised = true, .profilePath = profile});
		require(recoveryTransport.inspect().status != TransportStatus::Ok, "initial session-bus setup failure is reported");
		if (currentAddress)
			setenv("DBUS_SESSION_BUS_ADDRESS", savedAddress.c_str(), 1);
		else
			unsetenv("DBUS_SESSION_BUS_ADDRESS");
		require(recoveryTransport.inspect().status == TransportStatus::Ok, "the same transport recovers after session-bus setup is restored");

		SdBusControllerTransport transport({.uniqueOwner = {}, .upstreamVersion = SUPPORTED_UPSTREAM_VERSION, .supervised = false, .profilePath = profile});
		auto result = transport.inspect();
		require(result.status == TransportStatus::Ok, "live Controller inspection succeeds");
		transport.updateEvidence({
			.uniqueOwner = result.snapshot.identity.uniqueOwner,
			.upstreamVersion = SUPPORTED_UPSTREAM_VERSION,
			.supervised = true,
			.profilePath = profile,
		});
		result = transport.inspect();
		require(result.status == TransportStatus::Ok && result.snapshot.identity.controllerShape == ControllerShape::Supported,
			"live Controller exposes the approved shape");
		require(!result.snapshot.groups.empty() && !result.snapshot.currentGroup.empty(), "live Controller semantics are readable");
		std::cout << "ok - live Controller transport inspection is read-only and supported\n";
		return 0;
	}

	{
		const std::string xml = R"XML(
<node><interface name="org.fcitx.Fcitx.Controller1">
<method name="AddInputMethodGroup"><arg type="s" direction="in"/></method>
<method name="AvailableInputMethods"><arg type="a(ssssssb)" direction="out"/></method>
<method name="CurrentInputMethod"><arg type="s" direction="out"/></method>
<method name="CurrentInputMethodGroup"><arg type="s" direction="out"/></method>
<method name="DebugInfo"><arg type="s" direction="out"/></method>
<method name="FullInputMethodGroupInfo"><arg type="s" direction="in"/><arg type="sssa{sv}a(sssssssbsa{sv})" direction="out"/></method>
<method name="GetAddonsV2"><arg type="a(sssibbbasas)" direction="out"/></method>
<method name="InputMethodGroupInfo"><arg type="s" direction="in"/><arg type="sa(ss)" direction="out"/></method>
<method name="InputMethodGroups"><arg type="as" direction="out"/></method>
<signal name="InputMethodGroupsChanged"/>
<method name="RemoveInputMethodGroup"><arg type="s" direction="in"/></method>
<method name="Save"/>
<method name="SetCurrentIM"><arg type="s" direction="in"/></method>
<method name="SetInputMethodGroupInfo"><arg type="ssa(ss)" direction="in"/></method>
<method name="SwitchInputMethodGroup"><arg type="s" direction="in"/></method>
<method name="AdditionalSupportedMember"/>
</interface></node>)XML";
		require(controllerShapeFromIntrospection(xml) == ControllerShape::Supported, "the exact manifest tolerates additional Controller members");
		auto changed = xml;
		changed.replace(changed.find("ssa(ss)"), 7, "ssa(sss)");
		require(controllerShapeFromIntrospection(changed) == ControllerShape::Unsupported, "a changed Controller signature is rejected");
	}
	std::cout << "ok - Controller introspection requires exact listed signatures\n";

	{
		ScriptedTransport transport;
		ControllerAdapter adapter(transport);
		const auto result = adapter.inspect();
		require(result.outcome == Outcome::Converged, "exact Controller state is accepted");
		require(result.snapshot == transport.snapshot, "inspection returns the complete semantic snapshot");
		require(transport.inspectionCount == 1 && transport.commands.empty(), "inspection performs no mutation");
	}
	std::cout << "ok - exact Controller state is inspected without mutation\n";

	{
		for (const auto& mutate : std::vector<std::function<void(Snapshot&)>>{
				[](Snapshot& snapshot) { snapshot.identity.supervised = false; },
				[](Snapshot& snapshot) { snapshot.identity.upstreamVersion = "5.1.22"; },
				[](Snapshot& snapshot) { snapshot.identity.controllerShape = ControllerShape::Unsupported; },
				[](Snapshot& snapshot) { snapshot.profile.safe = false; },
				[](Snapshot& snapshot) { snapshot.availableMethods.pop_back(); },
				[](Snapshot& snapshot) { snapshot.enabledAddons.pop_back(); },
			}) {
			ScriptedTransport transport;
			mutate(transport.snapshot);
			ControllerAdapter adapter(transport);
			const auto result = adapter.inspect();
			require(result.outcome == Outcome::UnsupportedInterface, "unsupported Controller prerequisite is rejected");
			require(transport.commands.empty(), "unsupported Controller prerequisite cannot write");
		}
	}
	std::cout << "ok - unsupported Controller prerequisites fail closed\n";

	{
		ScriptedTransport transport;
		transport.snapshot.groups = {{
			.name = "Default",
			.defaultMethod = US_METHOD,
			.defaultLayout = "us",
			.items = {{US_METHOD, ""}},
		}};
		transport.snapshot.currentGroup = "Default";
		ControllerAdapter adapter(transport);
		const auto result = adapter.installManagedGroup(RUSSIAN_METHOD);
		require(result.outcome == Outcome::Converged, "the managed group is created and selected");
		require(result.snapshot.groups.size() == 2 &&
			std::ranges::any_of(result.snapshot.groups, [](const Group& group) { return group.name == "Default"; }),
			"the unrelated group is preserved");
		require(result.snapshot.currentGroup == MANAGED_GROUP_NAME && result.snapshot.currentMethod == RUSSIAN_METHOD, "the requested method is selected");
		require(transport.commands.size() == 5, "installation uses four semantic writes and Save");
		require(commandKind(transport.commands.back()) == CommandKind::Save, "installation ends with Save");
		require(transport.inspectionCount >= static_cast<int>(transport.commands.size() * 2), "every mutation has preflight and readback inspection");
	}
	std::cout << "ok - managed group installation verifies each delta and saves\n";

	{
		ScriptedTransport transport;
		transport.snapshot.groups = {{.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}}};
		transport.snapshot.currentGroup = "Default";
		transport.commandStatuses = {TransportStatus::Timeout};
		ControllerAdapter adapter(transport);
		const auto indeterminate = adapter.installManagedGroup(US_METHOD);
		require(indeterminate.outcome == Outcome::TimeoutIndeterminate && transport.inspectionCount >= 3,
			"a timed-out structural write reads semantics before returning indeterminate");

		ScriptedTransport appliedTransport;
		appliedTransport.snapshot.groups = {{.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}}};
		appliedTransport.snapshot.currentGroup = "Default";
		appliedTransport.snapshot.currentMethod = US_METHOD;
		appliedTransport.commandStatuses = {TransportStatus::Timeout};
		appliedTransport.applyTimedOutCommands = true;
		ControllerAdapter appliedAdapter(appliedTransport);
		require(appliedAdapter.installManagedGroup(US_METHOD).outcome == Outcome::Converged,
			"readback accepts a timed-out structural write that produced the exact delta");
	}
	std::cout << "ok - structural timeouts read before continuation or retry\n";

	{
		ScriptedTransport transport;
		ControllerAdapter adapter(transport);
		const auto result = adapter.installManagedGroup(US_METHOD);
		require(result.outcome == Outcome::ConfigurationConflict, "a pre-existing managed name is a collision");
		require(transport.commands.empty(), "a managed-name collision performs no mutation");
	}
	std::cout << "ok - managed group collisions fail before mutation\n";

	{
		ScriptedTransport transport;
		transport.snapshot.groups = {{.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}}};
		transport.snapshot.currentGroup = "Default";
		transport.onInspect = [](int count, Snapshot& snapshot) {
			if (count == 4)
				snapshot.profile.sha256[0] = 'b';
		};
		ControllerAdapter adapter(transport);
		const auto result = adapter.installManagedGroup(US_METHOD);
		require(result.outcome == Outcome::ConfigurationConflict && transport.commands.size() == 1,
			"a profile identity change blocks the next Controller mutation");
	}
	std::cout << "ok - profile no-follow identity is rechecked before every mutation\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.profileChangesBeforeExecute = true;
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::ConfigurationConflict && result.retryAfterSeconds == 0 && transport.commands.empty(),
			"a final pre-call profile race fails closed without a write or retry");
	}
	std::cout << "ok - final pre-call profile drift is a deterministic conflict\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::Converged && result.snapshot.currentMethod == RUSSIAN_METHOD, "set requires matching readback");
		require(transport.commands.size() == 2 && commandKind(transport.commands[0]) == CommandKind::SetCurrentMethod &&
			commandKind(transport.commands[1]) == CommandKind::Save, "a verified method delta is saved");
	}
	std::cout << "ok - method delivery converges through set, readback, and Save\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.snapshot.groups.push_back({.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}});
		Snapshot prior = transport.snapshot;
		prior.groups.erase(prior.groups.begin());
		prior.currentGroup = "Default";
		transport.commandStatuses = {TransportStatus::Ok, TransportStatus::Timeout};
		ControllerAdapter adapter(transport);
		const auto indeterminate = adapter.convergeMethod(RUSSIAN_METHOD);
		require(indeterminate.outcome == Outcome::TimeoutIndeterminate && indeterminate.retryAfterSeconds == 1,
			"a timed-out Save remains indeterminate after semantic readback");
		const auto wrongOperation = adapter.restore(prior);
		require(wrongOperation.outcome == Outcome::ConfigurationConflict && transport.commands.size() == 2,
			"an indeterminate convergence Save cannot be resumed as restoration");
		const auto cancelled = adapter.convergeMethod(RUSSIAN_METHOD, 1, [] { return false; });
		require(cancelled.outcome == Outcome::Pending && transport.commands.size() == 2,
			"a superseded or disconnected authority cannot retry an indeterminate Save");
		const auto retried = adapter.convergeMethod(RUSSIAN_METHOD);
		require(retried.outcome == Outcome::Converged && transport.commands.size() == 3 &&
			commandKind(transport.commands[2]) == CommandKind::Save, "matching state retries an indeterminate Save before convergence");
	}
	std::cout << "ok - indeterminate Save is read and retried before convergence\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod.clear();
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::IdleNoContext && transport.commands.empty(), "empty method remains idle without an invented acknowledgement");
	}
	std::cout << "ok - empty current method remains idle-no-context\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.commandStatuses = {TransportStatus::Timeout};
		ControllerAdapter adapter(transport);
		const auto first = adapter.convergeMethod(RUSSIAN_METHOD);
		require(first.outcome == Outcome::TimeoutIndeterminate && first.retryAfterSeconds == 1, "an unapplied timeout schedules the first bounded retry");
		require(transport.inspectionCount >= 2, "a timed-out write is followed by semantic readback");

		transport.commandStatuses = {TransportStatus::Timeout};
		const auto second = adapter.convergeMethod(RUSSIAN_METHOD);
		require(second.retryAfterSeconds == 2, "repairable retries use increasing backoff");
	}
	std::cout << "ok - write timeout reads before bounded retry\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		ControllerAdapter adapter(transport);
		const std::vector<unsigned> expected{1, 2, 4, 8, 8, 8};
		for (const auto delay : expected) {
			transport.commandStatuses = {TransportStatus::Timeout};
			require(adapter.convergeMethod(RUSSIAN_METHOD).retryAfterSeconds == delay, "repair backoff follows the fixed capped sequence");
		}
		transport.commandStatuses = {TransportStatus::Timeout};
		require(adapter.convergeMethod(US_METHOD).outcome == Outcome::Converged, "a new target resets retry state before observing convergence");
		transport.commandStatuses = {TransportStatus::Timeout};
		require(adapter.convergeMethod(RUSSIAN_METHOD).retryAfterSeconds == 1, "retry starts at one second after a new target");
	}
	std::cout << "ok - repair backoff follows 1, 2, 4, 8 with an eight-second cap\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.commandStatuses = {TransportStatus::Timeout};
		transport.applyTimedOutCommands = true;
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::Converged && result.retryAfterSeconds == 0, "readback accepts a timed-out write that took effect");
	}
	std::cout << "ok - indeterminate writes are resolved by readback\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.ignoreMethodSet = true;
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::Drift && result.retryAfterSeconds == 1, "a successful no-effect method call is repairable drift");
		require(transport.commands.size() == 1, "a no-effect method call is not saved as convergence");
	}
	std::cout << "ok - successful no-effect writes never acknowledge convergence\n";

	{
		ScriptedTransport transport;
		transport.snapshot.groups.push_back({.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}});
		transport.snapshot.currentGroup = "Default";
		transport.snapshot.currentMethod = US_METHOD;
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::Converged, "current-group drift is repaired toward the managed group");
		require(transport.commands.size() == 3 && commandKind(transport.commands[0]) == CommandKind::SwitchGroup &&
			commandKind(transport.commands[1]) == CommandKind::SetCurrentMethod && commandKind(transport.commands[2]) == CommandKind::Save,
			"group drift is repaired before method delivery and Save");
	}
	std::cout << "ok - current-group drift is repaired before method convergence\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.afterCommand = [](const Command& command, Snapshot& snapshot) {
			if (commandKind(command) == CommandKind::SetCurrentMethod)
				++snapshot.identity.ownerEpoch;
		};
		ControllerAdapter adapter(transport);
		const auto replaced = adapter.convergeMethod(RUSSIAN_METHOD);
		require(replaced.outcome == Outcome::Unavailable && transport.commands.size() == 1, "owner replacement invalidates method delivery");

		transport.afterCommand = {};
		transport.snapshot.currentMethod = US_METHOD;
		transport.commandStatuses = {TransportStatus::Timeout};
		const auto retry = adapter.convergeMethod(RUSSIAN_METHOD);
		require(retry.retryAfterSeconds == 1, "a new owner resets repair backoff");
	}
	std::cout << "ok - owner epochs invalidate stale work and reset backoff\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		ControllerAdapter adapter(transport);
		transport.commandStatuses = {TransportStatus::Timeout};
		require(adapter.convergeMethod(RUSSIAN_METHOD, 1).retryAfterSeconds == 1,
			"the first delivery generation starts at one-second retry");
		transport.commandStatuses = {TransportStatus::Timeout};
		require(adapter.convergeMethod(RUSSIAN_METHOD, 2).retryAfterSeconds == 1,
			"a newer same-language generation resets repair backoff");
	}
	std::cout << "ok - every new delivery generation resets repair backoff\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.afterCommand = [](const Command& command, Snapshot& snapshot) {
			if (commandKind(command) == CommandKind::SetCurrentMethod)
				snapshot.groups.push_back({.name = "Concurrent", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}});
		};
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::Converged && result.snapshot.groups.back().name == "Concurrent", "unrelated concurrent groups survive method convergence");
	}
	std::cout << "ok - unrelated concurrent group changes are preserved\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.afterCommand = [](const Command& command, Snapshot& snapshot) {
			if (commandKind(command) == CommandKind::SetCurrentMethod)
				snapshot.profile.sha256[0] = 'b';
		};
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::ConfigurationConflict && transport.commands.size() == 1,
			"a concurrent profile edit is not adopted after method delivery");
	}
	std::cout << "ok - non-persisting commands reject concurrent profile edits\n";

	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.afterCommand = [](const Command& command, Snapshot& snapshot) {
			if (commandKind(command) == CommandKind::SetCurrentMethod)
				snapshot.enabledAddons.pop_back();
		};
		ControllerAdapter adapter(transport);
		const auto result = adapter.convergeMethod(RUSSIAN_METHOD);
		require(result.outcome == Outcome::UnsupportedInterface && transport.commands.size() == 1,
			"unexpected compatibility inventory drift stops before Save");
	}
	std::cout << "ok - unexpected compatibility drift fails closed\n";

	{
		ScriptedTransport transport;
		const Snapshot prior{
			.identity = transport.snapshot.identity,
			.profile = transport.snapshot.profile,
			.groups = {{.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}}},
			.availableMethods = transport.snapshot.availableMethods,
			.enabledAddons = transport.snapshot.enabledAddons,
			.currentGroup = "Default",
			.currentMethod = US_METHOD,
		};
		transport.snapshot.groups.push_back(prior.groups.front());
		transport.snapshot.currentMethod = RUSSIAN_METHOD;
		transport.afterCommand = [](const Command& command, Snapshot& snapshot) {
			if (commandKind(command) == CommandKind::SwitchGroup)
				snapshot.groups.push_back({.name = "Concurrent", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}});
		};
		ControllerAdapter adapter(transport);
		const auto result = adapter.restore(prior);
		require(result.outcome == Outcome::Converged, "semantic restoration converges to the prior method");
		require(result.snapshot.currentGroup == "Default" && result.snapshot.currentMethod == US_METHOD, "prior current semantics are restored");
		require(result.snapshot.groups.size() == 2 && result.snapshot.groups.back().name == "Concurrent", "unrelated later groups survive restoration");
		require(transport.commands.size() == 3 && commandKind(transport.commands[0]) == CommandKind::SwitchGroup &&
			commandKind(transport.commands[1]) == CommandKind::RemoveGroup && commandKind(transport.commands[2]) == CommandKind::Save,
			"restoration avoids a redundant method write after group switching restored it");
	}
	std::cout << "ok - semantic restoration preserves unrelated later groups\n";

	{
		ScriptedTransport transport;
		Snapshot prior = transport.snapshot;
		prior.groups = {{.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}}};
		prior.currentGroup = "Default";
		prior.currentMethod.clear();
		transport.snapshot.groups.push_back(prior.groups.front());
		ControllerAdapter adapter(transport);
		const auto result = adapter.restore(prior);
		require(result.outcome == Outcome::Converged || result.outcome == Outcome::IdleNoContext, "restoration accepts the current observation without inventing prior method intent");
		require(std::ranges::none_of(transport.commands, [](const Command& command) { return commandKind(command) == CommandKind::SetCurrentMethod; }),
			"an empty prior method is not restored as a concrete method");
	}
	std::cout << "ok - empty prior method remains non-authoritative during restoration\n";
}
