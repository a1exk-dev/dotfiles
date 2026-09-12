#include "input-language-health.hpp"

#include <algorithm>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string_view>

namespace InputLanguages {
namespace {

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
					output << character;
		}
	}
	output << '"';
	return output.str();
}

template <typename Value>
void appendOptional(std::ostringstream& output, const std::optional<Value>& value) {
	if (value)
		output << *value;
	else
		output << "null";
}

void appendOptionalString(std::ostringstream& output, const std::optional<std::string>& value) {
	if (value)
		output << jsonString(*value);
	else
		output << "null";
}

std::string_view connectionName(Fcitx::FollowerConnection connection) {
	switch (connection) {
		case Fcitx::FollowerConnection::Connected: return "connected";
		case Fcitx::FollowerConnection::Disconnected: return "disconnected";
		case Fcitx::FollowerConnection::Failed: return "failed";
		case Fcitx::FollowerConnection::Incompatible: return "incompatible";
	}
	return "failed";
}

std::string_view ownerStateName(Fcitx::Protocol::OwnerState state) {
	switch (state) {
		case Fcitx::Protocol::OwnerState::Absent: return "absent";
		case Fcitx::Protocol::OwnerState::Present: return "present";
		case Fcitx::Protocol::OwnerState::Competing: return "competing";
	}
	return "absent";
}

std::string_view managedGroupName(Fcitx::Protocol::ManagedGroupState state) {
	switch (state) {
		case Fcitx::Protocol::ManagedGroupState::Unknown: return "unknown";
		case Fcitx::Protocol::ManagedGroupState::Exact: return "exact";
		case Fcitx::Protocol::ManagedGroupState::Missing: return "missing";
		case Fcitx::Protocol::ManagedGroupState::Foreign: return "foreign";
	}
	return "unknown";
}

std::string_view outcomeName(Fcitx::Protocol::Outcome outcome) {
	switch (outcome) {
		case Fcitx::Protocol::Outcome::Pending: return "pending";
		case Fcitx::Protocol::Outcome::Converged: return "converged";
		case Fcitx::Protocol::Outcome::IdleNoContext: return "idle-no-context";
		case Fcitx::Protocol::Outcome::Drift: return "drift";
		case Fcitx::Protocol::Outcome::Unavailable: return "unavailable";
		case Fcitx::Protocol::Outcome::Disconnected: return "disconnected";
		case Fcitx::Protocol::Outcome::TimeoutIndeterminate: return "timeout-indeterminate";
		case Fcitx::Protocol::Outcome::MethodError: return "method-error";
		case Fcitx::Protocol::Outcome::ConfigurationConflict: return "configuration-conflict";
		case Fcitx::Protocol::Outcome::UnsupportedInterface: return "unsupported-interface";
		case Fcitx::Protocol::Outcome::ProtocolError: return "protocol-error";
		case Fcitx::Protocol::Outcome::HelperFailed: return "helper-failed";
	}
	return "helper-failed";
}

std::string_view retryPhaseName(Fcitx::Protocol::RetryPhase phase) {
	switch (phase) {
		case Fcitx::Protocol::RetryPhase::None: return "none";
		case Fcitx::Protocol::RetryPhase::Poll: return "poll";
		case Fcitx::Protocol::RetryPhase::Read: return "read";
		case Fcitx::Protocol::RetryPhase::Write: return "write";
		case Fcitx::Protocol::RetryPhase::ReadBeforeRetry: return "read-before-retry";
		case Fcitx::Protocol::RetryPhase::Backoff: return "backoff";
	}
	return "none";
}

}

std::string coordinatedHealthJson(HealthInput input, Fcitx::FollowerSnapshot follower) {
	std::ranges::sort(input.physicalGroups, {}, &PhysicalGroup::device);
	std::ranges::sort(input.excludedKeyboards);
	const bool synchronized = input.synchronized && !input.physicalGroups.empty() &&
		std::ranges::all_of(input.physicalGroups, [&input](const PhysicalGroup& group) { return group.group == input.canonicalGroup; });
	std::ostringstream output;
	output << "{\"healthy\":" << (synchronized ? "true" : "false")
		   << ",\"direct_xkb_health\":" << jsonString(synchronized ? "healthy" : "unhealthy")
		   << ",\"build_id\":" << jsonString(input.buildId)
		   << ",\"source_id\":" << jsonString(input.sourceId)
		   << ",\"compatibility_hash\":" << jsonString(input.compatibilityHash)
		   << ",\"canonical_group\":" << input.canonicalGroup
		   << ",\"physical_keyboards\":[";
	for (std::size_t index = 0; index < input.physicalGroups.size(); ++index) {
		if (index != 0)
			output << ',';
		output << jsonString(input.physicalGroups[index].device);
	}
	output << "],\"excluded_keyboards\":[";
	for (std::size_t index = 0; index < input.excludedKeyboards.size(); ++index) {
		if (index != 0)
			output << ',';
		output << jsonString(input.excludedKeyboards[index]);
	}
	output << "],\"authority_session\":" << jsonString(Fcitx::FcitxFollower::authoritySessionHex(follower.authoritySession))
		   << ",\"canonical_language\":" << jsonString(input.target.language == Language::Us ? "US" : "Russian")
		   << ",\"canonical_generation\":" << input.target.generation
		   << ",\"physical_groups\":[";
	for (std::size_t index = 0; index < input.physicalGroups.size(); ++index) {
		if (index != 0)
			output << ',';
		output << "{\"device\":" << jsonString(input.physicalGroups[index].device) << ",\"group\":" << input.physicalGroups[index].group << '}';
	}
	output << "],\"physical_synchronized\":" << (synchronized ? "true" : "false")
		   << ",\"helper_connection\":" << jsonString(connectionName(follower.connection))
		   << ",\"helper_build_id\":";
	if (follower.connection == Fcitx::FollowerConnection::Connected)
		output << jsonString(input.buildId);
	else
		output << "null";
	output << ",\"protocol_identity\":" << jsonString(Fcitx::Protocol::IDENTITY)
		   << ",\"offered_generation\":" << follower.target.generation
		   << ",\"accepted_generation\":";
	appendOptional(output, follower.acceptedGeneration);
	output << ",\"acknowledged_generation\":";
	appendOptional(output, follower.acknowledgedGeneration);
	output << ",\"report_sequence\":";
	appendOptional(output, follower.reportSequence);
	output << ",\"report_age_milliseconds\":";
	if (follower.reportAge)
		output << follower.reportAge->count();
	else
		output << "null";
	output << ",\"coalesced_targets\":" << follower.coalescedTargets
		   << ",\"fcitx_owner_state\":" << jsonString(ownerStateName(follower.ownerState))
		   << ",\"fcitx_unique_owner\":";
	appendOptionalString(output, follower.uniqueOwner);
	output << ",\"fcitx_owner_epoch\":" << follower.ownerEpoch
		   << ",\"managed_group_state\":" << jsonString(managedGroupName(follower.managedGroupState))
		   << ",\"current_group\":";
	appendOptionalString(output, follower.currentGroup);
	output << ",\"observed_method\":" << jsonString(follower.observedMethod)
		   << ",\"retry_phase\":" << jsonString(retryPhaseName(follower.retryPhase))
		   << ",\"outcome\":" << jsonString(outcomeName(follower.outcome))
		   << ",\"diagnostic\":" << jsonString(follower.diagnostic)
		   << ",\"report_stale\":" << (follower.stale ? "true" : "false") << '}';
	return output.str();
}

}
