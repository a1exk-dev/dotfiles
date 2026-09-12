#include "input-language-health.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <string_view>

namespace {
using namespace InputLanguages;

void require(bool condition, std::string_view message) {
	if (!condition) {
		std::cerr << "not ok - " << message << '\n';
		std::exit(1);
	}
}
}

int main() {
	Fcitx::FollowerSnapshot follower{
		.authoritySession = {std::byte{1}},
		.target = {.language = Language::Russian, .generation = 8},
		.connection = Fcitx::FollowerConnection::Connected,
		.acceptedGeneration = 8,
		.acknowledgedGeneration = 8,
		.reportSequence = 12,
		.reportAge = std::chrono::milliseconds(25),
		.coalescedTargets = 2,
		.ownerState = Fcitx::Protocol::OwnerState::Present,
		.uniqueOwner = ":1.42",
		.ownerEpoch = 3,
		.managedGroupState = Fcitx::Protocol::ManagedGroupState::Exact,
		.currentGroup = "Dotfiles Input Languages",
		.observedMethod = "keyboard-ru",
		.outcome = Fcitx::Protocol::Outcome::Converged,
		.retryPhase = Fcitx::Protocol::RetryPhase::None,
		.diagnostic = "line\n\x01",
		.stale = false,
	};
	const auto health = coordinatedHealthJson({
		.buildId = std::string(64, 'b'),
		.sourceId = std::string(64, 'c'),
		.compatibilityHash = "stack",
		.canonicalGroup = 1,
		.physicalGroups = {{"keyboard-b", 1}, {"keyboard-a", 1}},
		.excludedKeyboards = {"virtual-b", "virtual-a"},
		.target = {.language = Language::Russian, .generation = 8},
		.synchronized = true,
	}, follower);
	const std::string expected =
		"{\"healthy\":true,\"direct_xkb_health\":\"healthy\","
		"\"build_id\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\","
		"\"source_id\":\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\","
		"\"compatibility_hash\":\"stack\",\"canonical_group\":1,"
		"\"physical_keyboards\":[\"keyboard-a\",\"keyboard-b\"],\"excluded_keyboards\":[\"virtual-a\",\"virtual-b\"],"
		"\"authority_session\":\"01000000000000000000000000000000\",\"canonical_language\":\"Russian\",\"canonical_generation\":8,"
		"\"physical_groups\":[{\"device\":\"keyboard-a\",\"group\":1},{\"device\":\"keyboard-b\",\"group\":1}],"
		"\"physical_synchronized\":true,\"helper_connection\":\"connected\","
		"\"helper_build_id\":\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\","
		"\"protocol_identity\":\"dotfiles-input-languages-fcitx-seqpacket-v1\",\"offered_generation\":8,"
		"\"accepted_generation\":8,\"acknowledged_generation\":8,\"report_sequence\":12,\"report_age_milliseconds\":25,"
		"\"coalesced_targets\":2,\"fcitx_owner_state\":\"present\",\"fcitx_unique_owner\":\":1.42\",\"fcitx_owner_epoch\":3,"
		"\"managed_group_state\":\"exact\",\"current_group\":\"Dotfiles Input Languages\",\"observed_method\":\"keyboard-ru\","
		"\"retry_phase\":\"none\",\"outcome\":\"converged\",\"diagnostic\":\"line\\n\\u0001\",\"report_stale\":false}";
	require(health == expected, "production health emits every frozen field exactly once with the expected type and value");
	require(health.find("\"indicator_state\"") == std::string::npos, "production health excludes indicator state");
	require(health.find("\"physical_groups\":[{\"device\":\"keyboard-a\",\"group\":1},{\"device\":\"keyboard-b\",\"group\":1}]") != std::string::npos,
		"production health uses deterministic evidence-schema device groups");
	require(health.find("\"fcitx_owner_state\":\"present\",\"fcitx_unique_owner\":\":1.42\",\"fcitx_owner_epoch\":3") != std::string::npos,
		"production health includes the acknowledged owner identity");
	require(health.find("\"current_group\":\"Dotfiles Input Languages\"") != std::string::npos &&
		health.find("\"report_stale\":false") != std::string::npos,
		"production health includes current group and explicit freshness");
	require(health.find("line\\n\\u0001") != std::string::npos, "production health escapes every JSON control byte");
	std::cout << "ok - coordinated production health uses the frozen field contract\n";
}
