#include "fcitx-controller.hpp"
#include "fcitx-follower.hpp"
#include "fcitx-helper.hpp"
#include "input-language-model.hpp"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <iostream>
#include <mutex>
#include <string>
#include <string_view>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {
using namespace std::chrono_literals;
using namespace InputLanguages;
using namespace InputLanguages::Fcitx;

const std::string BUILD(64, 'b');
const std::string SOURCE(64, 'c');

void require(bool condition, std::string_view message) {
	if (!condition) {
		std::cout << "not ok - " << message << '\n';
		std::exit(1);
	}
}

template <typename Predicate>
bool waitUntil(Predicate predicate, std::chrono::milliseconds timeout = 1500ms) {
	const auto deadline = std::chrono::steady_clock::now() + timeout;
	do {
		if (predicate())
			return true;
		std::this_thread::sleep_for(2ms);
	} while (std::chrono::steady_clock::now() < deadline);
	return predicate();
}

Snapshot exactSnapshot() {
	return {
		.identity = {.uniqueOwner = ":1.42", .ownerEpoch = 1, .supervised = true,
			.upstreamVersion = SUPPORTED_UPSTREAM_VERSION, .controllerShape = ControllerShape::Supported},
		.profile = {.safe = true, .device = 1, .inode = 2, .mode = 0600,
			.ownerUid = static_cast<uint32_t>(getuid()), .sha256 = std::string(64, 'a')},
		.groups = {{.name = MANAGED_GROUP_NAME, .defaultMethod = US_METHOD, .defaultLayout = "us",
			.items = {{US_METHOD, ""}, {RUSSIAN_METHOD, ""}}}},
		.availableMethods = {US_METHOD, RUSSIAN_METHOD},
		.enabledAddons = {"keyboard", "dbus", "dbusfrontend"},
		.currentGroup = MANAGED_GROUP_NAME,
		.currentMethod = US_METHOD,
	};
}

class ExactTransport final : public ControllerTransport {
  public:
	Inspection inspect() noexcept override {
		const std::scoped_lock lock(m_mutex);
		return {.status = TransportStatus::Ok, .snapshot = m_snapshot, .diagnostic = {}};
	}

	CommandResult execute(const Snapshot&, const Command& command) noexcept override {
		const std::scoped_lock lock(m_mutex);
		if (const auto* set = std::get_if<SetCurrentMethodCommand>(&command))
			m_snapshot.currentMethod = set->method;
		return {.status = TransportStatus::Ok, .diagnostic = {}};
	}

	std::string currentMethod() const {
		const std::scoped_lock lock(m_mutex);
		return m_snapshot.currentMethod;
	}

  private:
	mutable std::mutex m_mutex;
	Snapshot m_snapshot = exactSnapshot();
};

struct SocketFixture {
	std::string root;
	std::string path;
	int listener = -1;

	SocketFixture() {
		std::array<char, 64> pattern{};
		std::strcpy(pattern.data(), "/tmp/input-languages-integration.XXXXXX");
		const char* created = mkdtemp(pattern.data());
		require(created != nullptr, "a temporary integration runtime is created");
		root = created;
		require(setenv("XDG_RUNTIME_DIR", root.c_str(), 1) == 0, "the integration runtime is exported");
		const auto parent = root + "/dotfiles-input-languages";
		require(mkdir(parent.c_str(), 0700) == 0, "the private runtime parent is created");
		path = parent + "/fcitx.sock";
		listener = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
		require(listener >= 0, "the production socket type is created");
		sockaddr_un address{};
		address.sun_family = AF_UNIX;
		require(path.size() < sizeof(address.sun_path), "the production socket path is bounded");
		std::strcpy(address.sun_path, path.c_str());
		const auto oldMask = umask(0177);
		const int bound = bind(listener, reinterpret_cast<const sockaddr*>(&address), sizeof(address));
		umask(oldMask);
		require(bound == 0 && chmod(path.c_str(), 0600) == 0 && listen(listener, 1) == 0,
			"the production socket path and permissions are established");
	}

	~SocketFixture() {
		if (listener >= 0)
			close(listener);
		std::filesystem::remove_all(root);
	}
};
}

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
