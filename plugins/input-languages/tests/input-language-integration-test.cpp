#include "fcitx-integration-fixture.hpp"

int main() {
	SocketFixture socket;
	ExactTransport transport;
	ControllerAdapter controller(transport);
	Helper helper(controller, HelperOptions{
		.buildId = BUILD,
		.sourceId = SOURCE,
		.pollInterval = 20ms,
		.heartbeatInterval = 20ms,
		.retrySecond = 20ms,
	});
	const int savedStderr = dup(STDERR_FILENO);
	const int nullStderr = open("/dev/null", O_WRONLY | O_CLOEXEC);
	require(savedStderr >= 0 && nullStderr >= 0 && dup2(nullStderr, STDERR_FILENO) == STDERR_FILENO,
		"the integration helper journal is isolated");
	close(nullStderr);
	int helperResult = -1;
	std::thread helperThread([&] { helperResult = helper.run(socket.listener); });

	{
		FcitxFollower follower(FollowerOptions{
			.buildId = BUILD,
			.sourceId = SOURCE,
			.socketPath = socket.path,
			.reconnectDelays = {10ms, 10ms, 10ms, 10ms, 10ms, 10ms},
			.staleAfter = 100ms,
			.pollSlice = 10ms,
		}, LanguageTarget{.language = InputLanguages::Language::Us, .generation = 1});
		std::vector<std::pair<DeviceId, uint32_t>> updates;
		Coordinator coordinator([&updates](DeviceId id, uint32_t group) { updates.emplace_back(id, group); }, &follower);
		coordinator.addPhysical(1, 0);
		coordinator.addPhysical(2, 0);
		require(waitUntil([&] { return follower.snapshot().acknowledgedGeneration == 1; }),
			"the real follower and helper acknowledge the initial target");

		coordinator.key(1, 29, KeyState::Pressed, true);
		coordinator.key(1, 42, KeyState::Pressed, true);
		coordinator.key(1, 29, KeyState::Released, true);
		require(waitUntil([&] { return follower.snapshot().acknowledgedGeneration == 2; }),
			"the real helper acknowledges the post-fan-out canonical generation");
		const auto health = follower.snapshot();
		std::ranges::sort(updates);
		require(updates == std::vector<std::pair<DeviceId, uint32_t>>{{1, 1}, {2, 1}} &&
			coordinator.target() == LanguageTarget{.language = InputLanguages::Language::Russian, .generation = 2} &&
			transport.currentMethod() == RUSSIAN_METHOD && health.outcome == Protocol::Outcome::Converged &&
			health.ownerState == Protocol::OwnerState::Present && health.uniqueOwner == ":1.42" && health.ownerEpoch == 1 &&
			health.managedGroupState == Protocol::ManagedGroupState::Exact && health.currentGroup == MANAGED_GROUP_NAME &&
			health.observedMethod == RUSSIAN_METHOD && !health.stale,
			"the production coordinator-follower-helper path converges after physical fan-out");
	}

	helper.requestStop();
	helperThread.join();
	require(dup2(savedStderr, STDERR_FILENO) == STDERR_FILENO, "the integration helper journal is restored");
	close(savedStderr);
	require(helperResult == 0, "the real helper exits cleanly after authority shutdown");
	std::cout << "ok - exact-stack coordinator, follower, helper, and Controller seams converge\n";
}
