#include "fcitx-helper.hpp"
#include "fcitx-protocol.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fcntl.h>
#include <functional>
#include <fstream>
#include <iostream>
#include <mutex>
#include <optional>
#include <poll.h>
#include <string>
#include <string_view>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <utility>
#include <vector>

namespace {
using namespace InputLanguages::Fcitx;
using namespace InputLanguages::Fcitx::Protocol;
using namespace std::chrono_literals;

const std::string BUILD(64, 'b');
const std::string SOURCE(64, 'c');

void require(bool condition, std::string_view message) {
	if (!condition) {
		std::cerr << "not ok - " << message << '\n';
		std::exit(1);
	}
}

Session session(unsigned seed = 1) {
	Session result{};
	for (std::size_t index = 0; index < result.size(); ++index)
		result[index] = static_cast<std::byte>(seed + index);
	return result;
}

Snapshot exactSnapshot(std::string method = US_METHOD) {
	return {
		.identity = {.uniqueOwner = ":1.42", .ownerEpoch = 1, .supervised = true,
			.upstreamVersion = SUPPORTED_UPSTREAM_VERSION, .controllerShape = ControllerShape::Supported},
		.profile = {.safe = true, .device = 1, .inode = 2, .mode = 0600, .ownerUid = static_cast<uint32_t>(getuid()), .sha256 = std::string(64, 'a')},
		.groups = {{.name = MANAGED_GROUP_NAME, .defaultMethod = US_METHOD, .defaultLayout = "us",
			.items = {{US_METHOD, ""}, {RUSSIAN_METHOD, ""}}}},
		.availableMethods = {US_METHOD, RUSSIAN_METHOD},
		.enabledAddons = {"keyboard", "dbus", "dbusfrontend"},
		.currentGroup = MANAGED_GROUP_NAME,
		.currentMethod = std::move(method),
	};
}

class ScriptedTransport final : public ControllerTransport {
  public:
	Inspection inspect() noexcept override {
		std::this_thread::sleep_for(inspectDelay);
		std::lock_guard lock(mutex);
		++inspectionCount;
		if (unavailableInspections > 0) {
			--unavailableInspections;
			return {.status = TransportStatus::Unavailable, .snapshot = {}, .diagnostic = "scripted unavailable"};
		}
		if (replaceOwnerAtInspection > 0 && inspectionCount == replaceOwnerAtInspection) {
			++snapshot.identity.ownerEpoch;
			snapshot.identity.uniqueOwner = ":1.43";
			snapshot.currentMethod = replacementMethod;
		}
		return {.status = TransportStatus::Ok, .snapshot = snapshot, .diagnostic = {}};
	}

	CommandResult execute(const Snapshot&, const Command& command) noexcept override {
		std::lock_guard lock(mutex);
		commands.push_back(command);
		const auto status = commandStatuses.empty() ? TransportStatus::Ok : commandStatuses.front();
		if (!commandStatuses.empty())
			commandStatuses.pop_front();
		const bool apply = status == TransportStatus::Ok || (status == TransportStatus::Timeout && applyTimedOutCommands);
		if (apply) {
			switch (commandKind(command)) {
				case CommandKind::AddGroup: break;
				case CommandKind::SetGroup: break;
				case CommandKind::SwitchGroup: {
					const auto& value = std::get<SwitchGroupCommand>(command);
					snapshot.currentGroup = value.groupName;
					const auto group = std::ranges::find(snapshot.groups, value.groupName, &Group::name);
					if (group != snapshot.groups.end()) {
						snapshot.currentMethod = group->defaultMethod;
						std::rotate(snapshot.groups.begin(), group, group + 1);
					}
					break;
				}
				case CommandKind::SetCurrentMethod:
					if (!ignoreMethodSet)
						snapshot.currentMethod = std::get<SetCurrentMethodCommand>(command).method;
					break;
				case CommandKind::RemoveGroup: break;
				case CommandKind::Save: break;
			}
		}
		return {.status = status, .diagnostic = status == TransportStatus::Ok ? std::string{} : "scripted timeout"};
	}

	std::vector<std::string> writtenMethods() {
		std::lock_guard lock(mutex);
		std::vector<std::string> methods;
		for (const auto& command : commands) {
			if (const auto* set = std::get_if<SetCurrentMethodCommand>(&command))
				methods.push_back(set->method);
		}
		return methods;
	}

	int inspections() {
		std::lock_guard lock(mutex);
		return inspectionCount;
	}

	void allowMethodSet() {
		std::lock_guard lock(mutex);
		ignoreMethodSet = false;
	}

	std::mutex mutex;
	Snapshot snapshot = exactSnapshot();
	std::chrono::milliseconds inspectDelay{0};
	std::deque<TransportStatus> commandStatuses;
	std::vector<Command> commands;
	int inspectionCount = 0;
	int unavailableInspections = 0;
	int replaceOwnerAtInspection = 0;
	std::string replacementMethod = RUSSIAN_METHOD;
	bool applyTimedOutCommands = false;
	bool ignoreMethodSet = false;
};

class SocketFixture {
  public:
	SocketFixture() {
		std::array<char, 64> pattern{};
		std::strcpy(pattern.data(), "/tmp/fcitx-helper-test.XXXXXX");
		const char* created = mkdtemp(pattern.data());
		require(created != nullptr, "temporary runtime directory is created");
		root = created;
		setenv("XDG_RUNTIME_DIR", root.c_str(), 1);
		parent = root + "/dotfiles-input-languages";
		require(mkdir(parent.c_str(), 0700) == 0, "private runtime parent is created");
		path = parent + "/fcitx.sock";
		listener = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
		require(listener >= 0, "seqpacket listener is created");
		sockaddr_un address{};
		address.sun_family = AF_UNIX;
		require(path.size() < sizeof(address.sun_path), "test socket path is bounded");
		std::strcpy(address.sun_path, path.c_str());
		const auto oldMask = umask(0177);
		const int bound = bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address));
		umask(oldMask);
		require(bound == 0 && chmod(path.c_str(), 0600) == 0 && listen(listener, 8) == 0, "frozen listener path and modes are established");
	}

	~SocketFixture() {
		if (client >= 0)
			close(client);
		if (listener >= 0)
			close(listener);
		std::filesystem::remove_all(root);
	}

	int connectClient() {
		const int descriptor = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
		require(descriptor >= 0, "seqpacket client is created");
		sockaddr_un address{};
		address.sun_family = AF_UNIX;
		std::strcpy(address.sun_path, path.c_str());
		require(connect(descriptor, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0, "seqpacket client connects");
		return descriptor;
	}

	void start(ScriptedTransport& transport, bool captureJournal = true,
		std::chrono::milliseconds pollInterval = 20ms, std::chrono::milliseconds retrySecond = 60ms) {
		if (captureJournal) {
			int descriptors[2]{};
			require(pipe2(descriptors, O_CLOEXEC | O_NONBLOCK) == 0, "journal capture pipe is created");
			journalRead = descriptors[0];
			savedStderr = dup(STDERR_FILENO);
			require(savedStderr >= 0 && dup2(descriptors[1], STDERR_FILENO) == STDERR_FILENO, "production journal boundary is captured");
			close(descriptors[1]);
		}
		controller = std::make_unique<ControllerAdapter>(transport);
		helper = std::make_unique<Helper>(*controller, HelperOptions{
			.buildId = std::string(BUILD), .sourceId = std::string(SOURCE), .pollInterval = pollInterval,
			.heartbeatInterval = 25ms, .retrySecond = retrySecond,
		});
		thread = std::thread([this] { result = helper->run(listener); });
	}

	void stop() {
		if (helper)
			helper->requestStop();
		if (thread.joinable())
			thread.join();
		if (savedStderr >= 0) {
			require(dup2(savedStderr, STDERR_FILENO) == STDERR_FILENO, "stderr journal boundary is restored");
			close(savedStderr);
			savedStderr = -1;
			std::array<char, 4096> bytes{};
			for (;;) {
				const auto count = read(journalRead, bytes.data(), bytes.size());
				if (count > 0) {
					journal.append(bytes.data(), static_cast<std::size_t>(count));
					continue;
				}
				break;
			}
			close(journalRead);
			journalRead = -1;
		}
	}

	std::size_t journalCount(std::string_view needle) const {
		std::size_t count = 0;
		for (std::size_t offset = 0; (offset = journal.find(needle, offset)) != std::string::npos; offset += needle.size())
			++count;
		return count;
	}

	void connectAndHello(Language language = Language::Us, uint64_t generation = 1, Session authority = session()) {
		client = connectClient();
		sendFrame(client, Hello{.protocolIdentity = IDENTITY, .buildId = std::string(BUILD), .sourceId = std::string(SOURCE),
			.authoritySession = authority, .language = language, .generation = generation});
		const auto ready = receive(500ms);
		require(ready && std::holds_alternative<Ready>(*ready), "matching HELLO receives READY");
		require(std::get<Ready>(*ready).authoritySession == authority, "READY preserves authority identity");
	}

	void sendFrame(int descriptor, const Frame& frame) {
		const auto encoded = encode(frame);
		require(encoded.has_value(), "test frame encodes");
		require(send(descriptor, encoded->data(), encoded->size(), MSG_NOSIGNAL) == static_cast<ssize_t>(encoded->size()), "complete seqpacket frame sends");
	}

	std::optional<Frame> receive(std::chrono::milliseconds timeout) {
		pollfd descriptor{.fd = client, .events = POLLIN, .revents = 0};
		if (poll(&descriptor, 1, static_cast<int>(timeout.count())) <= 0)
			return std::nullopt;
		std::array<std::byte, MAX_PACKET_BYTES> bytes{};
		const auto count = recv(client, bytes.data(), bytes.size(), 0);
		if (count <= 0)
			return std::nullopt;
		const auto decoded = decode(std::span(bytes.data(), static_cast<std::size_t>(count)));
		require(decoded.frame.has_value(), "helper emits valid protocol frames");
		return decoded.frame;
	}

	State waitState(const std::function<bool(const State&)>& predicate, std::chrono::milliseconds timeout = 700ms) {
		const auto deadline = std::chrono::steady_clock::now() + timeout;
		while (std::chrono::steady_clock::now() < deadline) {
			auto frame = receive(40ms);
			if (frame && std::holds_alternative<State>(*frame) && predicate(std::get<State>(*frame)))
				return std::get<State>(std::move(*frame));
		}
	require(false, "expected helper state arrives before deadline");
		return {};
	}

	std::string root;
	std::string parent;
	std::string path;
	int listener = -1;
	int client = -1;
	int result = -1;
	int savedStderr = -1;
	int journalRead = -1;
	std::string journal;
	std::unique_ptr<ControllerAdapter> controller;
	std::unique_ptr<Helper> helper;
	std::thread thread;
};

void codecTests() {
	const auto authority = session();
	const std::vector<Frame> frames{
		Hello{.protocolIdentity = IDENTITY, .buildId = std::string(BUILD), .sourceId = std::string(SOURCE), .authoritySession = authority, .language = Language::Russian, .generation = 9},
		Ready{.protocolIdentity = IDENTITY, .buildId = std::string(BUILD), .sourceId = std::string(SOURCE), .authoritySession = authority},
		Target{.authoritySession = authority, .language = Language::Us, .generation = 10},
		State{.protocolIdentity = IDENTITY, .buildId = std::string(BUILD), .authoritySession = authority, .reportSequence = 4,
			.acceptedGeneration = 10, .acknowledgedGeneration = 10, .ownerEpoch = 2, .managedGroupState = ManagedGroupState::Exact,
			.observedMethod = RUSSIAN_METHOD, .outcome = Protocol::Outcome::Converged, .retryPhase = RetryPhase::None, .diagnostic = "ok"},
		Heartbeat{.authoritySession = authority, .reportSequence = 5},
	};
	for (const auto& frame : frames) {
		const auto packet = encode(frame);
		require(packet && packet->size() <= MAX_PACKET_BYTES, "every frozen frame encodes within the packet bound");
		const auto decoded = decode(*packet);
		require(decoded.frame && *decoded.frame == frame, "every frozen frame round trips exactly");
	}

	auto packet = *encode(frames.front());
	require(!decode(std::span(packet).first(11)), "truncated headers are rejected");
	require(!decode(packet, true), "kernel-reported packet truncation is rejected");
	std::vector<std::byte> oversized(MAX_PACKET_BYTES + 1);
	require(!decode(oversized), "oversized packets are rejected");
	packet[8] = std::byte{0};
	packet[9] = std::byte{0};
	require(!decode(packet), "type-length disagreement is rejected");
	packet = *encode(frames.front());
	packet[6] = std::byte{99};
	require(!decode(packet), "unknown frame types are rejected");
	packet = *encode(frames.front());
	packet[10] = std::byte{1};
	require(!decode(packet), "nonzero reserved fields are rejected");
	require(!encode(Hello{.protocolIdentity = IDENTITY, .buildId = std::string(64, 'G'), .sourceId = std::string(SOURCE),
		.authoritySession = authority, .language = Language::Us, .generation = 1}), "non-lowercase digests are rejected");
	require(!encode(Hello{.protocolIdentity = std::string(97, 'x'), .buildId = std::string(BUILD), .sourceId = std::string(SOURCE),
		.authoritySession = authority, .language = Language::Us, .generation = 1}), "overlong identities are rejected");
	require(!encode(Target{.authoritySession = {}, .language = Language::Us, .generation = 1}), "an empty authority nonce is rejected");
	require(!encode(Target{.authoritySession = authority, .language = static_cast<Language>(2), .generation = 1}), "out-of-range enums are rejected");
	std::cout << "ok - bounded codec accepts only exact frozen frames\n";
}

void listenerValidation() {
	SocketFixture fixture;
	std::string diagnostic;
	require(validateSocketActivatedListener(fixture.listener, diagnostic), "the exact socket-activated listener is accepted");
	bool operationalFailure = false;
	require(!validateSocketActivatedListener(-1, diagnostic, &operationalFailure) && operationalFailure,
		"listener inspection syscall failures are operational rather than deterministic incompatibility");
	require(chmod(fixture.parent.c_str(), 0755) == 0, "test parent mode changes");
	require(!validateSocketActivatedListener(fixture.listener, diagnostic), "a non-private runtime parent is rejected");
	require(chmod(fixture.parent.c_str(), 0700) == 0 && chmod(fixture.path.c_str(), 0660) == 0, "test socket mode changes");
	require(!validateSocketActivatedListener(fixture.listener, diagnostic), "a non-private socket mode is rejected");
	ScriptedTransport transport;
	fixture.start(transport);
	fixture.thread.join();
	fixture.stop();
	require(fixture.result == 0, "deterministic listener incompatibility exits cleanly");
	std::cout << "ok - socket activation path, type, ownership, and modes are validated\n";
}

void installedVersionEvidence() {
	std::array<char, 64> pattern{};
	std::strcpy(pattern.data(), "/tmp/fcitx-version-test.XXXXXX");
	const char* created = mkdtemp(pattern.data());
	require(created != nullptr, "temporary package database is created");
	const std::filesystem::path root(created);
	std::filesystem::create_directory(root / "fcitx5-configtool-5.1.21-1");
	std::ofstream(root / "fcitx5-configtool-5.1.21-1" / "desc") << "%NAME%\nfcitx5-configtool\n\n%VERSION%\n5.1.21-1\n";
	std::filesystem::create_directory(root / "fcitx5-5.1.21-3");
	std::ofstream(root / "fcitx5-5.1.21-3" / "desc") << "%NAME%\nfcitx5\n\n%VERSION%\n5.1.21-3\n";
	require(installedFcitxUpstreamVersion(root.string()) == SUPPORTED_UPSTREAM_VERSION,
		"installed upstream version is derived from exact package metadata without confusing sibling packages");
	std::filesystem::remove_all(root);
	require(installedFcitxUpstreamVersion(root.string()).empty(), "missing package evidence cannot assert a supported version");
	std::cout << "ok - installed Fcitx version evidence is observed rather than asserted\n";
}

void handshakeHeartbeatAndSecondAuthority() {
	ScriptedTransport transport;
	SocketFixture fixture;
	fixture.start(transport, true);
	fixture.connectAndHello();
	const auto converged = fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::Converged; });
	require(converged.acknowledgedGeneration == 1 && converged.observedMethod == US_METHOD, "matching nonempty readback acknowledges the HELLO target");
	uint64_t sequence = converged.reportSequence;
	bool sawHeartbeat = false;
	for (int attempt = 0; attempt < 5; ++attempt) {
		const auto frame = fixture.receive(80ms);
		if (frame && std::holds_alternative<Heartbeat>(*frame)) {
			const auto heartbeat = std::get<Heartbeat>(*frame);
			require(heartbeat.reportSequence > sequence, "heartbeats advance the monotonic report sequence");
			sequence = heartbeat.reportSequence;
			sawHeartbeat = true;
			break;
		}
	}
	require(sawHeartbeat, "heartbeats are published within the configured one-second maximum");
	std::this_thread::sleep_for(70ms);
	require(transport.inspections() >= 2, "Controller state is polled at the configured production seam");
	const int second = fixture.connectClient();
	pollfd rejected{.fd = second, .events = POLLIN | POLLHUP, .revents = 0};
	char byte = 0;
	require(poll(&rejected, 1, 300) > 0 && recv(second, &byte, sizeof(byte), 0) == 0, "a second authority is rejected without replacing the first");
	close(second);
	fixture.stop();
	require(fixture.result == 0, "explicit helper shutdown is clean");
	require(fixture.journalCount("fcitx helper state outcome=") == 2,
		"the production journal records state transitions, but not polls or heartbeats");
	require(fixture.journal.find("rejected second authority") != std::string::npos,
		"the production journal records an actionable second-authority rejection");
	std::cout << "ok - handshake, polling, heartbeat, logging, and single authority are enforced\n";
}

void startupRecoveryNoContextAndDrift() {
	{
		ScriptedTransport transport;
		transport.unavailableInspections = 2;
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello();
		require(fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::Unavailable; }).acknowledgedGeneration == std::nullopt,
			"an authority can start before Fcitx without false acknowledgement");
		require(fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::Converged; }).acknowledgedGeneration == 1,
			"polling recovers when Fcitx becomes available");
		fixture.stop();
	}
	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod.clear();
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello(Language::Russian);
		const auto idle = fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::IdleNoContext; });
		require(!idle.acknowledgedGeneration && idle.observedMethod.empty(), "empty context remains pending idle-no-context");
		fixture.stop();
	}
	{
		ScriptedTransport transport;
		transport.snapshot.groups.push_back({.name = "Default", .defaultMethod = US_METHOD, .defaultLayout = "us", .items = {{US_METHOD, ""}}});
		transport.snapshot.currentGroup = "Default";
		transport.snapshot.currentMethod = US_METHOD;
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello(Language::Russian);
		const auto repaired = fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::Converged; });
		require(repaired.observedMethod == RUSSIAN_METHOD && repaired.acknowledgedGeneration == 1,
			"current group and method drift are repaired toward authority");
		fixture.stop();
	}
	{
		ScriptedTransport transport;
		transport.snapshot.groups.clear();
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello();
		const auto conflict = fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::ConfigurationConflict; });
		require(conflict.managedGroupState == ManagedGroupState::Missing, "a missing lifecycle-owned group is a deterministic conflict");
		fixture.stop();
	}
	std::cout << "ok - both startup orders, unavailable recovery, no context, and drift converge correctly\n";
}

void coalescingStaleAndOwnerReplacement() {
	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = RUSSIAN_METHOD;
		transport.inspectDelay = 80ms;
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello(Language::Us, 1);
		fixture.sendFrame(fixture.client, Target{.authoritySession = session(), .language = Language::Us, .generation = 2});
		fixture.sendFrame(fixture.client, Target{.authoritySession = session(), .language = Language::Russian, .generation = 3});
		const auto newest = fixture.waitState([](const State& state) { return state.acknowledgedGeneration == 3; }, 1200ms);
		require(newest.acceptedGeneration == 3 && transport.writtenMethods().empty(),
			"superseded work cannot write an older target before the newest target is acknowledged");
		fixture.sendFrame(fixture.client, Target{.authoritySession = session(), .language = Language::Russian, .generation = 2});
		require(fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::ProtocolError; }).acceptedGeneration == 3,
			"a stale generation is rejected as a typed protocol error");
		fixture.stop();
	}
	{
		ScriptedTransport transport;
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello();
		fixture.waitState([](const State& state) { return state.acknowledgedGeneration == 1; });
		fixture.sendFrame(fixture.client, Target{.authoritySession = session(9), .language = Language::Russian, .generation = 2});
		require(fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::ProtocolError; }).acceptedGeneration == 1,
			"a foreign authority session cannot replace the current target");
		fixture.stop();
	}
	{
		ScriptedTransport transport;
		transport.replaceOwnerAtInspection = 4;
		transport.replacementMethod = RUSSIAN_METHOD;
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello(Language::Us);
		fixture.waitState([](const State& state) { return state.acknowledgedGeneration == 1 && state.ownerEpoch == 1; });
		const auto refreshed = fixture.waitState([](const State& state) { return state.acknowledgedGeneration == 1 && state.ownerEpoch == 2; }, 1000ms);
		require(refreshed.observedMethod == US_METHOD, "owner replacement invalidates old evidence and reconverges the current target");
		fixture.stop();
	}
	std::cout << "ok - newest generation wins, stale generations fail, and owner replacement refreshes\n";
}

void timeoutBackoffAndDisconnect() {
	{
		ScriptedTransport transport;
		transport.snapshot.currentMethod = US_METHOD;
		transport.commandStatuses = {TransportStatus::Timeout, TransportStatus::Ok, TransportStatus::Ok};
		transport.ignoreMethodSet = true;
		SocketFixture fixture;
		fixture.start(transport, true, 15ms, 100ms);
		fixture.connectAndHello(Language::Russian);
		const auto timeout = fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::TimeoutIndeterminate; });
		require(timeout.retryPhase == RetryPhase::Backoff && !timeout.acknowledgedGeneration,
			"timed-out write is reported as indeterminate backoff without acknowledgement");
		const auto before = transport.writtenMethods().size();
		const auto inspectionsBefore = transport.inspections();
		std::this_thread::sleep_for(45ms);
		require(transport.writtenMethods().size() == before, "poll reads do not bypass adapter repair backoff");
		require(transport.inspections() > inspectionsBefore, "read-only polling continues during repair backoff");
		transport.allowMethodSet();
		require(fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::Converged; }, 900ms).acknowledgedGeneration == 1,
			"retry performs read-before-write and eventually converges");
		fixture.stop();
	}
	{
		ScriptedTransport transport;
		transport.inspectDelay = 100ms;
		SocketFixture fixture;
		fixture.start(transport, true);
		fixture.connectAndHello(Language::Russian);
		close(fixture.client);
		fixture.client = -1;
		fixture.thread.join();
		fixture.stop();
		require(fixture.result == 0 && transport.writtenMethods().empty(),
			"authority disconnect cancels outstanding work before any later Controller write and exits cleanly");
	}
	std::cout << "ok - timeout readback, bounded retry, and authority disconnect are safe\n";
}

void unexpectedRuntimeFailure() {
	ScriptedTransport transport;
	SocketFixture fixture;
	fixture.start(transport, true);
	fixture.connectAndHello();
	fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::Converged; });
	close(fixture.listener);
	fixture.listener = -1;
	fixture.thread.join();
	fixture.stop();
	require(fixture.result == 1, "unexpected listener loss exits nonzero for Restart=on-failure");
	require(fixture.journal.find("socket activation listener failed") != std::string::npos,
		"unexpected listener loss records an actionable journal diagnostic");
	std::cout << "ok - unexpected runtime failure requests service restart\n";
}

void malformedIdentityAndConflict() {
	auto runRejected = [](const std::function<void(SocketFixture&)>& sendInvalid) {
		ScriptedTransport transport;
		SocketFixture fixture;
		fixture.start(transport, true);
		fixture.client = fixture.connectClient();
		sendInvalid(fixture);
		pollfd closed{.fd = fixture.client, .events = POLLIN | POLLHUP, .revents = 0};
		char byte = 0;
		require(poll(&closed, 1, 500) > 0 && recv(fixture.client, &byte, sizeof(byte), 0) == 0,
			"invalid handshake input closes the authority connection");
		fixture.stop();
		require(fixture.result == 0 && transport.inspections() == 0, "invalid authority input exits cleanly before Controller work");
		require(!fixture.journal.empty(), "invalid authority input records an actionable journal diagnostic");
	};
	runRejected([](SocketFixture& fixture) {
		fixture.sendFrame(fixture.client, Hello{.protocolIdentity = IDENTITY, .buildId = std::string(64, 'd'), .sourceId = std::string(SOURCE),
			.authoritySession = session(), .language = Language::Us, .generation = 1});
	});
	runRejected([](SocketFixture& fixture) {
		std::array<std::byte, 4> malformed{};
		require(send(fixture.client, malformed.data(), malformed.size(), MSG_NOSIGNAL) == static_cast<ssize_t>(malformed.size()), "malformed packet sends");
	});
	runRejected([](SocketFixture& fixture) {
		std::vector<std::byte> oversized(MAX_PACKET_BYTES + 1);
		require(send(fixture.client, oversized.data(), oversized.size(), MSG_NOSIGNAL) == static_cast<ssize_t>(oversized.size()), "oversized packet sends atomically");
	});
	{
		ScriptedTransport transport;
		transport.snapshot.groups.front().items.pop_back();
		SocketFixture fixture;
		fixture.start(transport);
		fixture.connectAndHello();
		const auto conflict = fixture.waitState([](const State& state) { return state.outcome == Protocol::Outcome::ConfigurationConflict; });
		require(conflict.managedGroupState == ManagedGroupState::Foreign && !conflict.acknowledgedGeneration,
			"deterministic group incompatibility is typed and never acknowledged");
		fixture.stop();
		require(fixture.result == 0, "deterministic incompatibility exits cleanly without restart failure");
	}
	std::cout << "ok - malformed, oversized, wrong-identity, and deterministic conflict inputs fail closed\n";
}

}

int main() {
	codecTests();
	listenerValidation();
	installedVersionEvidence();
	handshakeHeartbeatAndSecondAuthority();
	startupRecoveryNoContextAndDrift();
	coalescingStaleAndOwnerReplacement();
	timeoutBackoffAndDisconnect();
	unexpectedRuntimeFailure();
	malformedIdentityAndConflict();
	std::cout << "ok - socket-activated helper integration suite passed\n";
}
