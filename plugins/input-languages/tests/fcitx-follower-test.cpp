#include "fcitx-follower.hpp"
#include "fcitx-protocol.hpp"

#include <array>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace {
using namespace std::chrono_literals;
using namespace InputLanguages;
using namespace InputLanguages::Fcitx;
using namespace InputLanguages::Fcitx::Protocol;

constexpr auto BUILD = "0000000000000000000000000000000000000000000000000000000000000000";
constexpr auto SOURCE = "1111111111111111111111111111111111111111111111111111111111111111";

void require(bool condition, const std::string& message) {
	if (!condition) {
		std::cerr << "not ok - " << message << '\n';
		std::exit(1);
	}
}

template <typename Predicate>
bool waitUntil(Predicate predicate, std::chrono::milliseconds timeout = 1000ms) {
	const auto deadline = std::chrono::steady_clock::now() + timeout;
	do {
		if (predicate())
			return true;
		std::this_thread::sleep_for(2ms);
	} while (std::chrono::steady_clock::now() < deadline);
	return predicate();
}

struct Listener {
	std::filesystem::path directory;
	std::string path;
	int fd = -1;

	Listener() {
		std::array<char, 64> pattern{};
		const std::string base = "/tmp/input-languages-follower.XXXXXX";
		std::copy(base.begin(), base.end(), pattern.begin());
		const char* created = mkdtemp(pattern.data());
		require(created != nullptr, "a temporary socket directory is created");
		directory = created;
		path = (directory / "fcitx.sock").string();
		fd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
		require(fd >= 0, "a sequenced-packet listener is created");
		sockaddr_un address{};
		address.sun_family = AF_UNIX;
		require(path.size() < sizeof(address.sun_path), "the fixture socket path fits sockaddr_un");
		std::copy(path.begin(), path.end(), address.sun_path);
		require(bind(fd, reinterpret_cast<const sockaddr*>(&address), sizeof(address)) == 0 && listen(fd, 1) == 0,
			"the follower fixture listener starts");
	}

	~Listener() {
		if (fd >= 0)
			close(fd);
		unlink(path.c_str());
		std::filesystem::remove(directory);
	}

	int acceptPeer() const {
		int peer = -1;
		require(waitUntil([&] {
			peer = accept4(fd, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
			return peer >= 0;
		}), "the follower connects to the helper socket");
		return peer;
	}
};

Frame receiveFrame(int peer) {
	std::array<std::byte, MAX_PACKET_BYTES> bytes{};
	ssize_t count = -1;
	require(waitUntil([&] {
		count = recv(peer, bytes.data(), bytes.size(), MSG_DONTWAIT);
		return count > 0;
	}), "the expected protocol frame arrives");
	auto decoded = decode(std::span(bytes).first(static_cast<std::size_t>(count)));
	require(static_cast<bool>(decoded), "the received protocol frame decodes");
	return std::move(*decoded.frame);
}

void sendFrame(int peer, const Frame& frame) {
	const auto encoded = encode(frame);
	require(encoded.has_value(), "the fixture frame encodes");
	ssize_t count = -1;
	require(waitUntil([&] {
		count = send(peer, encoded->data(), encoded->size(), MSG_DONTWAIT | MSG_NOSIGNAL);
		return count >= 0;
	}), "the fixture frame is sent");
	require(static_cast<std::size_t>(count) == encoded->size(), "the complete fixture packet is sent");
}

FollowerOptions options(const std::string& path) {
	return {
		.buildId = BUILD,
		.sourceId = SOURCE,
		.socketPath = path,
		.reconnectDelays = {10ms, 10ms, 10ms, 10ms, 10ms, 10ms},
		.staleAfter = 50ms,
		.pollSlice = 10ms,
	};
}
}

int main() {
	Listener listener;
	auto follower = std::make_unique<FcitxFollower>(options(listener.path), LanguageTarget{.language = InputLanguages::Language::Us, .generation = 1});

	const auto offerStart = std::chrono::steady_clock::now();
	follower->offer({.language = InputLanguages::Language::Russian, .generation = 2});
	follower->offer({.language = InputLanguages::Language::Us, .generation = 3});
	require(std::chrono::steady_clock::now() - offerStart < 100ms, "offers remain bounded before helper acceptance");

	int peer = listener.acceptPeer();
	auto hello = std::get<Hello>(receiveFrame(peer));
	require(hello.language == Protocol::Language::Us && hello.generation == 3,
		"the first handshake coalesces to the complete newest target");
	sendFrame(peer, Ready{.protocolIdentity = IDENTITY, .buildId = BUILD, .sourceId = SOURCE, .authoritySession = hello.authoritySession});
	require(waitUntil([&] { return follower->snapshot().connection == FollowerConnection::Connected; }),
		"a matching READY marks the cached follower connected");

	follower->offer({.language = InputLanguages::Language::Russian, .generation = 4});
	auto target = std::get<Target>(receiveFrame(peer));
	require(target.authoritySession == hello.authoritySession && target.language == Protocol::Language::Russian && target.generation == 4,
		"a connected canonical change sends one explicit TARGET");
	sendFrame(peer, State{
		.protocolIdentity = IDENTITY,
		.buildId = BUILD,
		.authoritySession = hello.authoritySession,
		.reportSequence = 2,
		.acceptedGeneration = 4,
		.acknowledgedGeneration = 4,
		.ownerEpoch = 7,
		.managedGroupState = ManagedGroupState::Exact,
		.observedMethod = "keyboard-ru",
		.outcome = Outcome::Converged,
		.retryPhase = RetryPhase::None,
		.diagnostic = {},
	});
	require(waitUntil([&] { return follower->snapshot().acknowledgedGeneration == 4; }),
		"matching current-session STATE updates cached acknowledgement");
	const auto converged = follower->snapshot();
	require(converged.target == LanguageTarget{.language = InputLanguages::Language::Russian, .generation = 4} &&
		converged.reportSequence == 2 && converged.ownerEpoch == 7 && converged.observedMethod == "keyboard-ru" &&
		converged.outcome == Outcome::Converged && !converged.stale && converged.coalescedTargets >= 1,
		"cached health describes the current target and helper report");
	follower->offer({.language = InputLanguages::Language::Us, .generation = 5});
	target = std::get<Target>(receiveFrame(peer));
	require(target.generation == 5 && follower->snapshot().outcome == Outcome::Pending,
		"a newer offer cannot retain an older generation's converged outcome");

	sendFrame(peer, State{
		.protocolIdentity = IDENTITY,
		.buildId = BUILD,
		.authoritySession = hello.authoritySession,
		.reportSequence = 1,
		.acceptedGeneration = 4,
		.acknowledgedGeneration = {},
		.ownerEpoch = 6,
		.managedGroupState = ManagedGroupState::Foreign,
		.observedMethod = "keyboard-us",
		.outcome = Outcome::ConfigurationConflict,
		.retryPhase = RetryPhase::None,
		.diagnostic = "stale",
	});
	std::this_thread::sleep_for(20ms);
	require(follower->snapshot().acknowledgedGeneration == 4 && follower->snapshot().reportSequence == 2,
		"reordered old-owner health cannot replace the current report");
	require(waitUntil([&] { return follower->snapshot().stale; }), "cached health becomes stale after the frozen age bound");

	close(peer);
	require(waitUntil([&] { return follower->snapshot().connection == FollowerConnection::Disconnected; }),
		"authority disconnect is visible without changing the canonical target");
	peer = listener.acceptPeer();
	hello = std::get<Hello>(receiveFrame(peer));
	require(hello.language == Protocol::Language::Us && hello.generation == 5,
		"reconnect starts from the complete current canonical target");
	sendFrame(peer, Ready{.protocolIdentity = IDENTITY, .buildId = BUILD, .sourceId = SOURCE, .authoritySession = hello.authoritySession});
	sendFrame(peer, State{
		.protocolIdentity = IDENTITY,
		.buildId = BUILD,
		.authoritySession = hello.authoritySession,
		.reportSequence = 1,
		.acceptedGeneration = 5,
		.acknowledgedGeneration = 5,
		.ownerEpoch = 1,
		.managedGroupState = ManagedGroupState::Exact,
		.observedMethod = "keyboard-us",
		.outcome = Outcome::Converged,
		.retryPhase = RetryPhase::None,
		.diagnostic = {},
	});
	require(waitUntil([&] { return follower->snapshot().reportSequence == 1; }),
		"a replacement helper starts a fresh report and owner epoch sequence");

	const auto destroyStart = std::chrono::steady_clock::now();
	follower.reset();
	require(std::chrono::steady_clock::now() - destroyStart < 250ms,
		"follower unload stays bounded while the helper peer is silent");
	close(peer);

	{
		const std::string absentPath = "/tmp/input-languages-follower-absent-" + std::to_string(getpid()) + ".sock";
		const auto start = std::chrono::steady_clock::now();
		FcitxFollower absent(options(absentPath), LanguageTarget{.language = InputLanguages::Language::Us, .generation = 1});
		absent.offer({.language = InputLanguages::Language::Russian, .generation = 2});
		require(std::chrono::steady_clock::now() - start < 100ms,
			"an absent helper socket does not delay canonical publication");
	}

	{
		Listener silentListener;
		FcitxFollower silent(options(silentListener.path), LanguageTarget{.language = InputLanguages::Language::Us, .generation = 1});
		std::vector<std::pair<DeviceId, uint32_t>> updates;
		Coordinator coordinator([&updates](DeviceId id, uint32_t group) { updates.emplace_back(id, group); }, &silent);
		coordinator.addPhysical(1, 0);
		coordinator.addPhysical(2, 0);
		const int silentPeer = silentListener.acceptPeer();
		std::get<Hello>(receiveFrame(silentPeer));
		const auto start = std::chrono::steady_clock::now();
		coordinator.key(1, 29, KeyState::Pressed, true);
		coordinator.key(1, 42, KeyState::Pressed, true);
		coordinator.key(1, 29, KeyState::Released, true);
		require(std::chrono::steady_clock::now() - start < 100ms && updates.size() == 2 && coordinator.group() == 1,
			"a silent helper cannot delay chord handling or physical fan-out");
		close(silentPeer);
	}

	std::cout << "ok - follower coalescing, reconnect, cached health, stale suppression, and bounded shutdown\n";
}
