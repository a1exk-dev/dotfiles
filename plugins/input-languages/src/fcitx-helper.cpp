#include "fcitx-helper.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <condition_variable>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <limits>
#include <mutex>
#include <optional>
#include <poll.h>
#include <string_view>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>
#include <utility>

namespace InputLanguages::Fcitx {
namespace {
using namespace std::chrono_literals;
using Clock = std::chrono::steady_clock;

bool setDescriptorFlags(int descriptor) {
	const int status = fcntl(descriptor, F_GETFL);
	const int descriptorFlags = fcntl(descriptor, F_GETFD);
	return status >= 0 && descriptorFlags >= 0 &&
		fcntl(descriptor, F_SETFL, status | O_NONBLOCK) == 0 &&
		fcntl(descriptor, F_SETFD, descriptorFlags | FD_CLOEXEC) == 0;
}

struct ReceivedPacket {
	std::optional<Protocol::Frame> frame;
	bool wouldBlock = false;
	bool disconnected = false;
	std::string error;
};

ReceivedPacket receivePacket(int descriptor) {
	std::array<std::byte, Protocol::MAX_PACKET_BYTES> bytes{};
	iovec vector{.iov_base = bytes.data(), .iov_len = bytes.size()};
	msghdr message{};
	message.msg_iov = &vector;
	message.msg_iovlen = 1;
	const auto count = recvmsg(descriptor, &message, MSG_DONTWAIT | MSG_CMSG_CLOEXEC);
	if (count == 0)
		return {.frame = {}, .wouldBlock = false, .disconnected = true, .error = {}};
	if (count < 0) {
		if (errno == EAGAIN || errno == EWOULDBLOCK)
			return {.frame = {}, .wouldBlock = true, .disconnected = false, .error = {}};
		if (errno == EINTR)
			return {.frame = {}, .wouldBlock = true, .disconnected = false, .error = {}};
		return {.frame = {}, .wouldBlock = false, .disconnected = true, .error = std::strerror(errno)};
	}
	const auto decoded = Protocol::decode(
		std::span(bytes.data(), static_cast<std::size_t>(count)),
		(message.msg_flags & MSG_TRUNC) != 0);
	return decoded
		? ReceivedPacket{.frame = std::move(decoded.frame), .wouldBlock = false, .disconnected = false, .error = {}}
		: ReceivedPacket{.frame = {}, .wouldBlock = false, .disconnected = false, .error = decoded.error};
}

bool sendFrame(int descriptor, const Protocol::Frame& frame) {
	const auto packet = Protocol::encode(frame);
	if (!packet)
		return false;
	for (;;) {
		const auto count = send(descriptor, packet->data(), packet->size(), MSG_DONTWAIT | MSG_NOSIGNAL);
		if (count == static_cast<ssize_t>(packet->size()))
			return true;
		if (count < 0 && errno == EINTR)
			continue;
		return false;
	}
}

int acceptPeer(int listener) {
	for (;;) {
		const int peer = accept4(listener, nullptr, nullptr, SOCK_NONBLOCK | SOCK_CLOEXEC);
		if (peer >= 0)
			return peer;
		if (errno == EINTR)
			continue;
		return -1;
	}
}

bool sameUid(int descriptor) {
	ucred credentials{};
	socklen_t size = sizeof(credentials);
	return getsockopt(descriptor, SOL_SOCKET, SO_PEERCRED, &credentials, &size) == 0 && size == sizeof(credentials) &&
		credentials.uid == getuid();
}

Protocol::Outcome protocolOutcome(Fcitx::Outcome outcome) {
	switch (outcome) {
		case Fcitx::Outcome::Pending: return Protocol::Outcome::Pending;
		case Fcitx::Outcome::Converged: return Protocol::Outcome::Converged;
		case Fcitx::Outcome::IdleNoContext: return Protocol::Outcome::IdleNoContext;
		case Fcitx::Outcome::Drift: return Protocol::Outcome::Drift;
		case Fcitx::Outcome::Unavailable: return Protocol::Outcome::Unavailable;
		case Fcitx::Outcome::TimeoutIndeterminate: return Protocol::Outcome::TimeoutIndeterminate;
		case Fcitx::Outcome::MethodError: return Protocol::Outcome::MethodError;
		case Fcitx::Outcome::ConfigurationConflict: return Protocol::Outcome::ConfigurationConflict;
		case Fcitx::Outcome::UnsupportedInterface: return Protocol::Outcome::UnsupportedInterface;
	}
	return Protocol::Outcome::HelperFailed;
}

bool exactManagedGroup(const Group& group) {
	return group.name == MANAGED_GROUP_NAME && group.defaultLayout == "us" &&
		(group.defaultMethod.empty() || group.defaultMethod == US_METHOD || group.defaultMethod == RUSSIAN_METHOD) &&
		group.items.size() == 2 && group.items[0] == GroupItem{US_METHOD, ""} && group.items[1] == GroupItem{RUSSIAN_METHOD, ""};
}

Protocol::ManagedGroupState groupState(const Snapshot& snapshot) {
	if (snapshot.identity.uniqueOwner.empty() || snapshot.identity.controllerShape != ControllerShape::Supported || !snapshot.profile.safe)
		return Protocol::ManagedGroupState::Unknown;
	const auto group = std::ranges::find(snapshot.groups, MANAGED_GROUP_NAME, &Group::name);
	if (group == snapshot.groups.end())
		return Protocol::ManagedGroupState::Missing;
	return exactManagedGroup(*group) ? Protocol::ManagedGroupState::Exact : Protocol::ManagedGroupState::Foreign;
}

bool deterministic(Protocol::Outcome outcome) {
	return outcome == Protocol::Outcome::ConfigurationConflict || outcome == Protocol::Outcome::UnsupportedInterface;
}

std::string boundedText(std::string value) {
	std::size_t cursor = 0;
	std::size_t accepted = 0;
	const auto limit = std::min(value.size(), Protocol::MAX_TEXT_BYTES);
	while (cursor < limit) {
		const auto first = static_cast<unsigned char>(value[cursor]);
		std::size_t length = 1;
		if (first >= 0xc2 && first <= 0xdf)
			length = 2;
		else if (first >= 0xe0 && first <= 0xef)
			length = 3;
		else if (first >= 0xf0 && first <= 0xf4)
			length = 4;
		else if (first > 0x7f)
			return "invalid utf-8";
		if (cursor + length > limit)
			break;
		for (std::size_t index = 1; index < length; ++index) {
			if ((static_cast<unsigned char>(value[cursor + index]) & 0xc0) != 0x80)
				return "invalid utf-8";
		}
		cursor += length;
		accepted = cursor;
	}
	value.resize(accepted);
	return value;
}

struct Job {
	bool converge = false;
	uint64_t generation = 0;
	std::string method;
};

struct Completion {
	Job job;
	AdapterResult result;
};

class ControllerWorker {
  public:
	explicit ControllerWorker(ControllerAdapter& controller) : m_controller(controller), m_event(eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC)), m_thread([this] { run(); }) {}
	~ControllerWorker() { stop(); }

	ControllerWorker(const ControllerWorker&) = delete;
	ControllerWorker& operator=(const ControllerWorker&) = delete;

	[[nodiscard]] bool valid() const { return m_event >= 0; }
	[[nodiscard]] int event() const { return m_event; }

	bool submit(Job job) {
		std::lock_guard lock(m_mutex);
		if (m_stopping || m_job || m_busy)
			return false;
		m_latestGeneration.store(job.generation, std::memory_order_release);
		m_authorityActive.store(true, std::memory_order_release);
		m_job = std::move(job);
		m_condition.notify_one();
		return true;
	}

	std::optional<Completion> take() {
		uint64_t ignored = 0;
		while (read(m_event, &ignored, sizeof(ignored)) < 0 && errno == EINTR) {}
		std::lock_guard lock(m_mutex);
		if (!m_completion)
			return std::nullopt;
		auto result = std::move(m_completion);
		m_completion.reset();
		return result;
	}

	bool idle() {
		std::lock_guard lock(m_mutex);
		return !m_job && !m_busy && !m_completion;
	}

	void supersede(uint64_t generation) noexcept {
		m_latestGeneration.store(generation, std::memory_order_release);
	}

	void cancel() noexcept {
		m_authorityActive.store(false, std::memory_order_release);
	}

	void stop() {
		cancel();
		{
			std::lock_guard lock(m_mutex);
			if (m_stopping)
				return;
			m_stopping = true;
			m_job.reset();
		}
		m_condition.notify_one();
		if (m_thread.joinable())
			m_thread.join();
		if (m_event >= 0)
			close(m_event);
		m_event = -1;
	}

  private:
	void run() noexcept {
		for (;;) {
			Job job;
			{
				std::unique_lock lock(m_mutex);
				m_condition.wait(lock, [this] { return m_stopping || m_job.has_value(); });
				if (m_stopping)
					return;
				job = std::move(*m_job);
				m_job.reset();
				m_busy = true;
			}
			AdapterResult result;
			try {
				result = job.converge
					? m_controller.convergeMethod(job.method, job.generation, [this, generation = job.generation] {
						return m_authorityActive.load(std::memory_order_acquire) &&
							m_latestGeneration.load(std::memory_order_acquire) == generation;
					})
					: m_controller.inspect();
			} catch (...) {
				result = {.outcome = Fcitx::Outcome::Unavailable, .snapshot = {}, .retryAfterSeconds = 0, .diagnostic = "Controller worker failed"};
			}
			{
				std::lock_guard lock(m_mutex);
				m_busy = false;
				if (!m_stopping)
					m_completion = Completion{.job = std::move(job), .result = std::move(result)};
			}
			uint64_t signal = 1;
			while (write(m_event, &signal, sizeof(signal)) < 0 && errno == EINTR) {}
		}
	}

	ControllerAdapter& m_controller;
	int m_event = -1;
	std::mutex m_mutex;
	std::condition_variable m_condition;
	std::optional<Job> m_job;
	std::optional<Completion> m_completion;
	bool m_busy = false;
	bool m_stopping = false;
	std::atomic_uint64_t m_latestGeneration = 0;
	std::atomic_bool m_authorityActive = true;
	std::thread m_thread;
};

struct Transition {
	uint64_t acceptedGeneration = 0;
	std::optional<uint64_t> acknowledgedGeneration;
	uint64_t ownerEpoch = 0;
	Protocol::ManagedGroupState managedGroupState = Protocol::ManagedGroupState::Unknown;
	std::string observedMethod;
	Protocol::Outcome outcome = Protocol::Outcome::Pending;
	Protocol::RetryPhase retryPhase = Protocol::RetryPhase::None;
	std::string diagnostic;
	bool operator==(const Transition&) const = default;
};

std::string transitionLog(const Transition& transition) {
	constexpr std::array OUTCOME_NAMES{
		"pending", "converged", "idle-no-context", "drift", "unavailable", "disconnected",
		"timeout-indeterminate", "method-error", "configuration-conflict", "unsupported-interface",
		"protocol-error", "helper-failed",
	};
	return "fcitx helper state outcome=" + std::string(OUTCOME_NAMES[static_cast<std::size_t>(transition.outcome)]) +
		" generation=" + std::to_string(transition.acceptedGeneration) +
		" owner-epoch=" + std::to_string(transition.ownerEpoch) +
		" diagnostic=" + transition.diagnostic;
}

void journal(std::string_view message) {
	while (!message.empty()) {
		const auto written = write(STDERR_FILENO, message.data(), message.size());
		if (written > 0) {
			message.remove_prefix(static_cast<std::size_t>(written));
			continue;
		}
		if (written < 0 && errno == EINTR)
			continue;
		break;
	}
	static constexpr char NEWLINE = '\n';
	while (write(STDERR_FILENO, &NEWLINE, 1) < 0 && errno == EINTR) {}
}

int timeoutMilliseconds(Clock::time_point now, std::initializer_list<Clock::time_point> deadlines) {
	auto deadline = Clock::time_point::max();
	for (const auto candidate : deadlines)
		deadline = std::min(deadline, candidate);
	if (deadline <= now)
		return 0;
	const auto delay = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
	return static_cast<int>(std::min<int64_t>(delay.count() + 1, std::numeric_limits<int>::max()));
}

}

std::string runtimeSocketPath() {
	const char* runtime = std::getenv("XDG_RUNTIME_DIR");
	return runtime && runtime[0] == '/' ? std::string(runtime) + "/dotfiles-input-languages/fcitx.sock" : std::string{};
}

std::string installedFcitxUpstreamVersion(std::string_view databaseRoot) noexcept {
	try {
		std::string packageVersion;
		for (const auto& entry : std::filesystem::directory_iterator(databaseRoot)) {
			if (!entry.is_directory() || !entry.path().filename().string().starts_with("fcitx5-"))
				continue;
			std::ifstream description(entry.path() / "desc");
			std::string line;
			std::string packageName;
			std::string candidateVersion;
			while (std::getline(description, line)) {
				if (line == "%NAME%")
					std::getline(description, packageName);
				else if (line == "%VERSION%")
					std::getline(description, candidateVersion);
			}
			if (packageName != "fcitx5")
				continue;
			if (!packageVersion.empty())
				return {};
			packageVersion = std::move(candidateVersion);
		}
		const auto release = packageVersion.find_last_of('-');
		if (release == std::string::npos || release == 0 || release + 1 == packageVersion.size())
			return {};
		return packageVersion.substr(0, release);
	} catch (...) {
		return {};
	}
}

bool validateSocketActivatedListener(int listenerFd, std::string& diagnostic, bool* operationalFailure) noexcept {
	try {
		if (operationalFailure)
			*operationalFailure = false;
		const auto path = runtimeSocketPath();
		if (path.empty()) {
			diagnostic = "XDG_RUNTIME_DIR is missing or not absolute";
			return false;
		}
		int type = 0;
		int accepting = 0;
		socklen_t integerSize = sizeof(int);
		sockaddr_un address{};
		socklen_t addressSize = sizeof(address);
		if (getsockopt(listenerFd, SOL_SOCKET, SO_TYPE, &type, &integerSize) != 0 ||
			getsockopt(listenerFd, SOL_SOCKET, SO_ACCEPTCONN, &accepting, &integerSize) != 0 ||
			getsockname(listenerFd, reinterpret_cast<sockaddr*>(&address), &addressSize) != 0) {
			if (operationalFailure)
				*operationalFailure = true;
			diagnostic = "socket activation listener inspection failed";
			return false;
		}
		if (type != SOCK_SEQPACKET || accepting != 1 || address.sun_family != AF_UNIX ||
			address.sun_path[0] == '\0' || path != address.sun_path) {
			diagnostic = "socket activation listener does not match the frozen path and type";
			return false;
		}
		const auto parent = path.substr(0, path.find_last_of('/'));
		struct stat parentStatus {};
		struct stat socketStatus {};
		struct stat listenerStatus {};
		if (lstat(parent.c_str(), &parentStatus) != 0 || lstat(path.c_str(), &socketStatus) != 0) {
			if (operationalFailure && errno != ENOENT && errno != ENOTDIR)
				*operationalFailure = true;
			diagnostic = "socket activation path inspection failed";
			return false;
		}
		if (fstat(listenerFd, &listenerStatus) != 0 || !setDescriptorFlags(listenerFd)) {
			if (operationalFailure)
				*operationalFailure = true;
			diagnostic = "socket activation descriptor inspection failed";
			return false;
		}
		if (!S_ISDIR(parentStatus.st_mode) || parentStatus.st_uid != getuid() || (parentStatus.st_mode & 07777) != 0700 ||
			!S_ISSOCK(socketStatus.st_mode) || socketStatus.st_uid != getuid() || (socketStatus.st_mode & 07777) != 0600 ||
			!S_ISSOCK(listenerStatus.st_mode) || listenerStatus.st_uid != getuid()) {
			diagnostic = "socket activation path ownership, mode, or descriptor flags are unsafe";
			return false;
		}
		return true;
	} catch (...) {
		if (operationalFailure)
			*operationalFailure = true;
		diagnostic = "listener validation failed";
		return false;
	}
}

Helper::Helper(ControllerAdapter& controller, HelperOptions options)
	: m_controller(controller), m_options(std::move(options)) {}

void Helper::requestStop() noexcept {
	m_stop.store(true, std::memory_order_relaxed);
}

int Helper::run(int listenerFd) noexcept {
	std::string listenerError;
	bool listenerFailure = false;
	if (!validateSocketActivatedListener(listenerFd, listenerError, &listenerFailure)) {
		journal(listenerError);
		return listenerFailure ? 1 : 0;
	}
	if (m_options.buildId.size() != 64 || m_options.sourceId.size() != 64 ||
		m_options.pollInterval <= 0ms || m_options.heartbeatInterval <= 0ms || m_options.heartbeatInterval > 1000ms ||
		m_options.retrySecond <= 0ms) {
		journal("helper identities or timing are incompatible");
		return 0;
	}

	int authority = -1;
	std::optional<Protocol::Hello> hello;
	while (!m_stop.load(std::memory_order_relaxed) && !hello) {
		pollfd descriptors[2]{{.fd = listenerFd, .events = POLLIN, .revents = 0}, {.fd = authority, .events = POLLIN, .revents = 0}};
		const int count = poll(descriptors, authority >= 0 ? 2 : 1, 100);
		if (count < 0 && errno != EINTR) {
			journal("authority accept poll failed");
			return 1;
		}
		if (descriptors[0].revents & (POLLHUP | POLLERR | POLLNVAL)) {
			journal("socket activation listener failed before handshake");
			if (authority >= 0)
				close(authority);
			return 1;
		}
		if (descriptors[0].revents & POLLIN) {
			for (;;) {
				const int peer = acceptPeer(listenerFd);
				if (peer < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
					break;
				if (peer < 0) {
					journal("authority accept failed");
					if (authority >= 0)
						close(authority);
					return 1;
				}
				if (!sameUid(peer) || authority >= 0) {
					journal(authority >= 0 ? "rejected second authority" : "rejected unauthenticated authority");
					close(peer);
					continue;
				}
				authority = peer;
				descriptors[1].fd = authority;
			}
		}
		if (authority < 0)
			continue;
		if (descriptors[1].revents & (POLLHUP | POLLERR | POLLNVAL)) {
			close(authority);
			return 0;
		}
		if (!(descriptors[1].revents & POLLIN))
			continue;
		const auto packet = receivePacket(authority);
		if (packet.disconnected) {
			close(authority);
			return 0;
		}
		if (!packet.frame || !std::holds_alternative<Protocol::Hello>(*packet.frame)) {
			journal("rejected malformed HELLO");
			close(authority);
			return 0;
		}
		auto candidate = std::get<Protocol::Hello>(std::move(*packet.frame));
		if (candidate.protocolIdentity != Protocol::IDENTITY || candidate.buildId != m_options.buildId ||
			candidate.sourceId != m_options.sourceId) {
			journal("rejected incompatible HELLO identity");
			close(authority);
			return 0;
		}
		hello = std::move(candidate);
	}
	if (!hello) {
		if (authority >= 0)
			close(authority);
		return 0;
	}

	const Protocol::Ready ready{
		.protocolIdentity = Protocol::IDENTITY,
		.buildId = m_options.buildId,
		.sourceId = m_options.sourceId,
		.authoritySession = hello->authoritySession,
	};
	if (!sendFrame(authority, ready)) {
		close(authority);
		return 0;
	}

	ControllerWorker worker(m_controller);
	if (!worker.valid()) {
		journal("Controller worker initialization failed");
		close(authority);
		return 1;
	}
	Protocol::Target target{.authoritySession = hello->authoritySession, .language = hello->language, .generation = hello->generation};
	uint64_t reportSequence = 0;
	uint64_t lastOwnerEpoch = 0;
	std::optional<Transition> published;
	auto now = Clock::now();
	auto nextHeartbeat = now + m_options.heartbeatInterval;
	auto nextPoll = now + m_options.pollInterval;
	auto nextRepair = now;
	bool stopAfterPublish = false;
	bool runtimeFailed = false;

	auto publish = [&](Transition transition) {
		if (published && *published == transition)
			return true;
		Protocol::State state{
			.protocolIdentity = Protocol::IDENTITY,
			.buildId = m_options.buildId,
			.authoritySession = hello->authoritySession,
			.reportSequence = ++reportSequence,
			.acceptedGeneration = transition.acceptedGeneration,
			.acknowledgedGeneration = transition.acknowledgedGeneration,
			.ownerEpoch = transition.ownerEpoch,
			.managedGroupState = transition.managedGroupState,
			.observedMethod = boundedText(transition.observedMethod),
			.outcome = transition.outcome,
			.retryPhase = transition.retryPhase,
			.diagnostic = boundedText(transition.diagnostic),
		};
		if (!sendFrame(authority, state))
			return false;
		published = std::move(transition);
		journal(transitionLog(*published));
		return true;
	};

	if (!publish({.acceptedGeneration = target.generation, .acknowledgedGeneration = {}, .ownerEpoch = 0,
		.managedGroupState = Protocol::ManagedGroupState::Unknown, .observedMethod = {},
		.outcome = Protocol::Outcome::Pending, .retryPhase = Protocol::RetryPhase::Write, .diagnostic = {}})) {
		close(authority);
		return 0;
	}
	worker.submit({.converge = true, .generation = target.generation, .method = target.language == Protocol::Language::Us ? US_METHOD : RUSSIAN_METHOD});
	nextRepair = Clock::time_point::max();

	while (!m_stop.load(std::memory_order_relaxed) && !stopAfterPublish) {
		now = Clock::now();
		pollfd descriptors[3]{
			{.fd = listenerFd, .events = POLLIN, .revents = 0},
			{.fd = authority, .events = POLLIN, .revents = 0},
			{.fd = worker.event(), .events = POLLIN, .revents = 0},
		};
		const int timeout = timeoutMilliseconds(now, {nextHeartbeat, nextPoll, worker.idle() ? nextRepair : Clock::time_point::max()});
		const int count = poll(descriptors, 3, timeout);
		if (count < 0) {
			if (errno == EINTR)
				continue;
			journal("helper event poll failed");
			runtimeFailed = true;
			break;
		}
		if (descriptors[0].revents & (POLLHUP | POLLERR | POLLNVAL)) {
			journal("socket activation listener failed");
			runtimeFailed = true;
			break;
		}
		if (descriptors[2].revents & (POLLHUP | POLLERR | POLLNVAL)) {
			journal("Controller worker notification failed");
			runtimeFailed = true;
			break;
		}
		if (descriptors[0].revents & POLLIN) {
			for (;;) {
				const int second = acceptPeer(listenerFd);
				if (second < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
					break;
				if (second < 0) {
					journal("second-authority accept failed");
					runtimeFailed = true;
					break;
				}
				journal("rejected second authority");
				close(second);
			}
		}
		if (runtimeFailed)
			break;
		if (descriptors[1].revents & (POLLHUP | POLLERR | POLLNVAL))
			break;
		if (descriptors[1].revents & POLLIN) {
			constexpr unsigned MAX_DRAINED_TARGETS = 64;
			for (unsigned drained = 0; drained < MAX_DRAINED_TARGETS; ++drained) {
				auto packet = receivePacket(authority);
				if (packet.wouldBlock)
					break;
				if (packet.disconnected) {
					stopAfterPublish = true;
					break;
				}
				if (!packet.frame || !std::holds_alternative<Protocol::Target>(*packet.frame)) {
					publish({.acceptedGeneration = target.generation, .acknowledgedGeneration = {}, .ownerEpoch = lastOwnerEpoch,
						.managedGroupState = Protocol::ManagedGroupState::Unknown, .observedMethod = {},
						.outcome = Protocol::Outcome::ProtocolError, .retryPhase = Protocol::RetryPhase::None,
						.diagnostic = "invalid TARGET frame"});
					stopAfterPublish = true;
					break;
				}
				auto offered = std::get<Protocol::Target>(std::move(*packet.frame));
				if (offered.authoritySession != hello->authoritySession || offered.generation < target.generation ||
					(offered.generation == target.generation && offered.language != target.language)) {
					publish({.acceptedGeneration = target.generation, .acknowledgedGeneration = {}, .ownerEpoch = lastOwnerEpoch,
						.managedGroupState = Protocol::ManagedGroupState::Unknown, .observedMethod = {},
						.outcome = Protocol::Outcome::ProtocolError, .retryPhase = Protocol::RetryPhase::None,
						.diagnostic = "stale, conflicting, or foreign-session target"});
					stopAfterPublish = true;
					break;
				}
			if (offered.generation > target.generation) {
				target = offered;
				worker.supersede(target.generation);
					nextRepair = Clock::now();
					if (!publish({.acceptedGeneration = target.generation, .acknowledgedGeneration = {}, .ownerEpoch = lastOwnerEpoch,
						.managedGroupState = Protocol::ManagedGroupState::Unknown, .observedMethod = {},
						.outcome = Protocol::Outcome::Pending, .retryPhase = Protocol::RetryPhase::Write, .diagnostic = {}}))
						stopAfterPublish = true;
				}
			}
		}
		if (stopAfterPublish)
			break;

		if (descriptors[2].revents & POLLIN) {
			auto completion = worker.take();
			if (completion && completion->job.generation == target.generation) {
				auto& result = completion->result;
				auto outcome = protocolOutcome(result.outcome);
				const auto managed = groupState(result.snapshot);
				if (managed == Protocol::ManagedGroupState::Missing || managed == Protocol::ManagedGroupState::Foreign)
					outcome = Protocol::Outcome::ConfigurationConflict;
				const auto desiredMethod = target.language == Protocol::Language::Us ? std::string_view(US_METHOD) : std::string_view(RUSSIAN_METHOD);
				if (!completion->job.converge && managed == Protocol::ManagedGroupState::Exact &&
					result.snapshot.currentGroup == MANAGED_GROUP_NAME) {
					if (result.snapshot.currentMethod.empty())
						outcome = Protocol::Outcome::IdleNoContext;
					else if (result.snapshot.currentMethod == desiredMethod)
						outcome = Protocol::Outcome::Converged;
					else
						outcome = Protocol::Outcome::Drift;
				}
				const bool ownerReplaced = lastOwnerEpoch != 0 && result.snapshot.identity.ownerEpoch != 0 &&
					result.snapshot.identity.ownerEpoch != lastOwnerEpoch;
				if (result.snapshot.identity.ownerEpoch != 0)
					lastOwnerEpoch = result.snapshot.identity.ownerEpoch;
				std::optional<uint64_t> acknowledged;
				if (outcome == Protocol::Outcome::Converged && !result.snapshot.currentMethod.empty() &&
					result.snapshot.currentMethod == desiredMethod && result.snapshot.identity.ownerEpoch == lastOwnerEpoch)
					acknowledged = target.generation;
				const auto phase = result.retryAfterSeconds > 0 ? Protocol::RetryPhase::Backoff : Protocol::RetryPhase::None;
				if (!publish({
						.acceptedGeneration = target.generation,
						.acknowledgedGeneration = acknowledged,
						.ownerEpoch = lastOwnerEpoch,
						.managedGroupState = managed,
						.observedMethod = result.snapshot.currentMethod,
						.outcome = outcome,
						.retryPhase = phase,
						.diagnostic = result.diagnostic,
					}))
					break;
				if (deterministic(outcome)) {
					stopAfterPublish = true;
				} else if (result.retryAfterSeconds > 0) {
					nextRepair = Clock::now() + m_options.retrySecond * result.retryAfterSeconds;
				} else if (ownerReplaced) {
					nextRepair = Clock::now();
				} else if (outcome == Protocol::Outcome::Drift || outcome == Protocol::Outcome::Unavailable ||
					outcome == Protocol::Outcome::MethodError || outcome == Protocol::Outcome::TimeoutIndeterminate) {
					if (completion->job.converge || nextRepair == Clock::time_point::max())
						nextRepair = Clock::now() + m_options.pollInterval;
				} else {
					nextRepair = Clock::time_point::max();
				}
			} else if (completion) {
				nextRepair = Clock::now();
			}
		}
		if (stopAfterPublish)
			break;

		now = Clock::now();
		if (now >= nextHeartbeat) {
			if (!sendFrame(authority, Protocol::Heartbeat{.authoritySession = hello->authoritySession, .reportSequence = ++reportSequence}))
				break;
			nextHeartbeat = now + m_options.heartbeatInterval;
		}
		if (now >= nextPoll) {
			nextPoll = now + m_options.pollInterval;
			if (worker.idle() && nextRepair > now)
				worker.submit({.converge = false, .generation = target.generation, .method = target.language == Protocol::Language::Us ? US_METHOD : RUSSIAN_METHOD});
		}
		if (now >= nextRepair && worker.idle()) {
			nextRepair = Clock::time_point::max();
			worker.submit({.converge = true, .generation = target.generation, .method = target.language == Protocol::Language::Us ? US_METHOD : RUSSIAN_METHOD});
		}
	}

	worker.cancel();
	close(authority);
	return runtimeFailed ? 1 : 0;
}

}
