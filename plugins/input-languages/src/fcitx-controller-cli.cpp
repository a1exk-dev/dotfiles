#include "fcitx-controller-cli.hpp"

#include <string>
#include <string_view>

namespace InputLanguages::Fcitx {
namespace {

std::string jsonString(std::string_view value) {
	std::string result = "\"";
	for (const char character : value) {
		switch (character) {
			case '\\': result += "\\\\"; break;
			case '"': result += "\\\""; break;
			case '\n': result += "\\n"; break;
			case '\r': result += "\\r"; break;
			case '\t': result += "\\t"; break;
			default: result += character; break;
		}
	}
	return result + '"';
}

std::string_view outcomeName(Outcome outcome) {
	switch (outcome) {
		case Outcome::Pending: return "pending";
		case Outcome::Converged: return "converged";
		case Outcome::IdleNoContext: return "idle-no-context";
		case Outcome::Drift: return "drift";
		case Outcome::Unavailable: return "unavailable";
		case Outcome::TimeoutIndeterminate: return "timeout-indeterminate";
		case Outcome::MethodError: return "method-error";
		case Outcome::ConfigurationConflict: return "configuration-conflict";
		case Outcome::UnsupportedInterface: return "unsupported-interface";
	}
	return "unsupported-interface";
}

void writeResult(std::ostream& output, const AdapterResult& result) {
	output << "{\"outcome\":" << jsonString(outcomeName(result.outcome))
		   << ",\"snapshot\":" << snapshotJson(result.snapshot)
		   << ",\"snapshot_digest\":" << jsonString(snapshotDigest(result.snapshot))
		   << ",\"diagnostic\":" << jsonString(result.diagnostic) << "}\n";
}

}

int runControllerCommand(int argc, char** argv, ControllerTransport& transport, std::ostream& output, std::ostream& error) {
	if (argc < 3 || std::string_view(argv[1]) != "controller") {
		error << "expected controller inspect or controller execute\n";
		return 2;
	}
	const bool restoration = std::string_view(argv[2]) == "restore-inspect" || std::string_view(argv[2]) == "restore-execute";
	ControllerAdapter adapter(transport, restoration);
	const auto initial = adapter.inspect();
	if (std::string_view(argv[2]) == "inspect" || std::string_view(argv[2]) == "restore-inspect") {
		if (argc != 3) {
			error << "controller inspect takes no arguments\n";
			return 2;
		}
		writeResult(output, initial);
		return initial.outcome == Outcome::UnsupportedInterface || initial.outcome == Outcome::Unavailable ? 1 : 0;
	}
	if ((std::string_view(argv[2]) != "execute" && std::string_view(argv[2]) != "restore-execute") || argc < 5) {
		error << "controller execute requires an expected digest and action\n";
		return 2;
	}
	if (snapshotDigest(initial.snapshot) != argv[3]) {
		writeResult(output, {.outcome = Outcome::ConfigurationConflict, .snapshot = initial.snapshot, .diagnostic = "Controller state changed before command"});
		return 1;
	}
	const std::string_view action = argv[4];
	Command command;
	if (action == "add-managed" && argc == 5)
		command = AddGroupCommand{MANAGED_GROUP_NAME};
	else if (action == "populate-managed" && argc == 5)
		command = SetGroupCommand{MANAGED_GROUP_NAME, "us", {{US_METHOD, ""}, {RUSSIAN_METHOD, ""}}};
	else if (action == "switch-group" && argc == 6)
		command = SwitchGroupCommand{argv[5]};
	else if (action == "set-method" && argc == 6)
		command = SetCurrentMethodCommand{argv[5]};
	else if (action == "remove-managed" && argc == 5)
		command = RemoveGroupCommand{MANAGED_GROUP_NAME};
	else if (action == "save" && argc == 5)
		command = SaveCommand{};
	else {
		error << "unsupported controller action\n";
		return 2;
	}
	const auto result = adapter.executeOne(initial.snapshot, command);
	writeResult(output, result);
	return result.outcome == Outcome::Pending || result.outcome == Outcome::Converged || result.outcome == Outcome::IdleNoContext ? 0 : 1;
}

}
