#include "fcitx-follower.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <thread>
#include <unistd.h>

namespace InputLanguages::Fcitx {
namespace {
using Clock = std::chrono::steady_clock;

Protocol::Language protocolLanguage(Language language) {
	return language == Language::Us ? Protocol::Language::Us : Protocol::Language::Russian;
}

Protocol::Session newAuthoritySession() {
	Protocol::Session session{};
	ssize_t offset = 0;
	while (offset < static_cast<ssize_t>(session.size())) {
		const auto count = getrandom(session.data() + offset, session.size() - static_cast<std::size_t>(offset), 0);
		if (count < 0 && errno == EINTR)
			continue;
		if (count <= 0)
			throw std::runtime_error("could not create the Input Languages authority session");
		offset += count;
	}
	if (std::ranges::all_of(session, [](std::byte value) { return value == std::byte{}; }))
		throw std::runtime_error("could not create a nonzero Input Languages authority session");
	return session;
}

bool sendFrame(int socket, const Protocol::Frame& frame) {
	const auto packet = Protocol::encode(frame);
	if (!packet)
		return false;
	ssize_t count;
	do {
		count = send(socket, packet->data(), packet->size(), MSG_DONTWAIT | MSG_NOSIGNAL);
	} while (count < 0 && errno == EINTR);
	return count == static_cast<ssize_t>(packet->size());
}

struct ReceivedFrame {
	std::optional<Protocol::Frame> frame;
	bool wouldBlock = false;
	bool disconnected = false;
};

ReceivedFrame receiveFrame(int socket) {
	std::array<std::byte, Protocol::MAX_PACKET_BYTES> bytes{};
	iovec vector{.iov_base = bytes.data(), .iov_len = bytes.size()};
	msghdr message{};
	message.msg_iov = &vector;
	message.msg_iovlen = 1;
	ssize_t count;
	do {
		count = recvmsg(socket, &message, MSG_DONTWAIT | MSG_TRUNC);
	} while (count < 0 && errno == EINTR);
	if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
		return {.frame = {}, .wouldBlock = true, .disconnected = false};
	if (count <= 0)
		return {.frame = {}, .wouldBlock = false, .disconnected = true};
	const bool truncated = (message.msg_flags & MSG_TRUNC) != 0 || count > static_cast<ssize_t>(bytes.size());
	const auto visible = std::min<std::size_t>(static_cast<std::size_t>(count), bytes.size());
	auto decoded = Protocol::decode(std::span(bytes).first(visible), truncated);
	return {.frame = std::move(decoded.frame)};
}
}

class FcitxFollower::Impl {
  public:
	Impl(FollowerOptions options, LanguageTarget initialTarget) :
		m_options(std::move(options)), m_session(newAuthoritySession()),
		m_language(initialTarget.language), m_generation(initialTarget.generation) {
		const Protocol::Hello identityProbe{
			.protocolIdentity = Protocol::IDENTITY,
			.buildId = m_options.buildId,
			.sourceId = m_options.sourceId,
			.authoritySession = m_session,
			.language = protocolLanguage(initialTarget.language),
			.generation = initialTarget.generation,
		};
		if (!Protocol::encode(identityProbe) || m_options.staleAfter <= std::chrono::milliseconds::zero() ||
			m_options.pollSlice <= std::chrono::milliseconds::zero() ||
			std::ranges::any_of(m_options.reconnectDelays, [](auto delay) { return delay <= std::chrono::milliseconds::zero(); }))
			throw std::invalid_argument("invalid Fcitx follower identity, target, path, or timing");
		m_worker = std::thread([this] { run(); });
	}

	~Impl() {
		m_stop.store(true, std::memory_order_release);
		m_wake.notify_all();
		if (m_worker.joinable())
			m_worker.join();
	}

	void offer(LanguageTarget target) noexcept {
		if (target.generation == 0 || target.generation <= m_generation.load(std::memory_order_acquire))
			return;
		if (m_generation.load(std::memory_order_relaxed) > m_sentGeneration.load(std::memory_order_relaxed))
			m_coalesced.fetch_add(1, std::memory_order_relaxed);
		m_revision.fetch_add(1, std::memory_order_acq_rel);
		m_language.store(target.language, std::memory_order_relaxed);
		m_generation.store(target.generation, std::memory_order_relaxed);
		m_revision.fetch_add(1, std::memory_order_release);
		m_wake.notify_one();
	}

	FollowerSnapshot snapshot() const noexcept {
		try {
			FollowerSnapshot result;
			std::optional<Clock::time_point> lastReport;
			{
				const std::scoped_lock lock(m_snapshotMutex);
				result = m_snapshot;
				lastReport = m_lastReport;
			}
			result.authoritySession = m_session;
			result.target = currentTarget();
			result.coalescedTargets = m_coalesced.load(std::memory_order_relaxed);
			if (result.connection == FollowerConnection::Connected && result.acceptedGeneration != result.target.generation)
				result.outcome = Protocol::Outcome::Pending;
			if (lastReport) {
				result.reportAge = std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - *lastReport);
				result.stale = *result.reportAge > m_options.staleAfter;
			}
			return result;
		} catch (...) {
			FollowerSnapshot failed;
			failed.authoritySession = m_session;
			failed.target = currentTarget();
			failed.connection = FollowerConnection::Failed;
			failed.outcome = Protocol::Outcome::HelperFailed;
			return failed;
		}
	}

  private:
	LanguageTarget currentTarget() const noexcept {
		for (;;) {
			const auto before = m_revision.load(std::memory_order_acquire);
			if ((before & 1U) != 0)
				continue;
			const LanguageTarget target{
				.language = m_language.load(std::memory_order_relaxed),
				.generation = m_generation.load(std::memory_order_relaxed),
			};
			if (before == m_revision.load(std::memory_order_acquire))
				return target;
		}
	}

	void setConnection(FollowerConnection connection, Protocol::Outcome outcome, std::string diagnostic = {}) {
		const std::scoped_lock lock(m_snapshotMutex);
		m_snapshot.connection = connection;
		m_snapshot.outcome = outcome;
		m_snapshot.diagnostic = std::move(diagnostic);
	}

	void sleepInterruptibly(std::chrono::milliseconds duration) const {
		std::unique_lock lock(m_wakeMutex);
		m_wake.wait_for(lock, duration, [this] { return m_stop.load(std::memory_order_acquire); });
	}

	ReceivedFrame waitForFrame(int socketFd, bool wakeForTarget) const {
		auto revision = m_revision.load(std::memory_order_acquire);
		while (!m_stop.load(std::memory_order_acquire)) {
			auto received = receiveFrame(socketFd);
			if (!received.wouldBlock)
				return received;
			std::unique_lock lock(m_wakeMutex);
			m_wake.wait_for(lock, m_options.pollSlice, [this, revision] {
				return m_stop.load(std::memory_order_acquire) || m_revision.load(std::memory_order_acquire) != revision;
			});
			const auto currentRevision = m_revision.load(std::memory_order_acquire);
			if (wakeForTarget && currentRevision != revision)
				return {.frame = {}, .wouldBlock = true, .disconnected = false};
			revision = currentRevision;
		}
		return {.frame = {}, .wouldBlock = false, .disconnected = true};
	}

	int connectSocket() const {
		const int socketFd = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
		if (socketFd < 0)
			return -1;
		sockaddr_un address{};
		address.sun_family = AF_UNIX;
		if (m_options.socketPath.size() >= sizeof(address.sun_path)) {
			close(socketFd);
			return -1;
		}
		std::copy(m_options.socketPath.begin(), m_options.socketPath.end(), address.sun_path);
		int result;
		do {
			result = connect(socketFd, reinterpret_cast<const sockaddr*>(&address), sizeof(address));
		} while (result < 0 && errno == EINTR);
		if (result != 0) {
			close(socketFd);
			return -1;
		}
		ucred credentials{};
		socklen_t credentialsSize = sizeof(credentials);
		if (getsockopt(socketFd, SOL_SOCKET, SO_PEERCRED, &credentials, &credentialsSize) != 0 ||
			credentialsSize != sizeof(credentials) || credentials.uid != geteuid()) {
			close(socketFd);
			return -1;
		}
		return socketFd;
	}

	void waitToReconnect(std::size_t& retry) {
		setConnection(FollowerConnection::Disconnected, Protocol::Outcome::Disconnected);
		sleepInterruptibly(m_options.reconnectDelays[std::min(retry, m_options.reconnectDelays.size() - 1)]);
		retry = std::min(retry + 1, m_options.reconnectDelays.size() - 1);
	}

	bool awaitReady(int socketFd, LanguageTarget helloTarget) {
		while (!m_stop.load(std::memory_order_acquire)) {
			auto received = waitForFrame(socketFd, false);
			if (received.disconnected)
				return false;
			if (!received.frame || !std::holds_alternative<Protocol::Ready>(*received.frame)) {
				setConnection(FollowerConnection::Incompatible, Protocol::Outcome::ProtocolError, "invalid READY frame");
				m_incompatible = true;
				return false;
			}
			const auto& ready = std::get<Protocol::Ready>(*received.frame);
			if (ready.protocolIdentity != Protocol::IDENTITY || ready.buildId != m_options.buildId ||
				ready.sourceId != m_options.sourceId || ready.authoritySession != m_session) {
				setConnection(FollowerConnection::Incompatible, Protocol::Outcome::ProtocolError, "incompatible READY identity");
				m_incompatible = true;
				return false;
			}
			{
				const std::scoped_lock lock(m_snapshotMutex);
				m_snapshot = {};
				m_snapshot.connection = FollowerConnection::Connected;
				m_snapshot.outcome = Protocol::Outcome::Pending;
				m_lastReport.reset();
			}
			const auto current = currentTarget();
			if (current.generation != helloTarget.generation && !sendTarget(socketFd, current))
				return false;
			return true;
		}
		return false;
	}

	bool sendTarget(int socketFd, LanguageTarget target) {
		if (!sendFrame(socketFd, Protocol::Target{
			.authoritySession = m_session,
			.language = protocolLanguage(target.language),
			.generation = target.generation,
		}))
			return false;
		m_sentGeneration.store(target.generation, std::memory_order_relaxed);
		return true;
	}

	void acceptState(const Protocol::State& state, LanguageTarget current) {
		const auto expectedMethod = current.language == Language::Us ? "keyboard-us" : "keyboard-ru";
		const std::scoped_lock lock(m_snapshotMutex);
		if (state.protocolIdentity != Protocol::IDENTITY || state.buildId != m_options.buildId || state.authoritySession != m_session ||
			state.acceptedGeneration != current.generation || (m_snapshot.reportSequence && state.reportSequence <= *m_snapshot.reportSequence) ||
			state.ownerEpoch < m_snapshot.ownerEpoch ||
			(state.acknowledgedGeneration && (state.observedMethod.empty() || state.observedMethod != expectedMethod)))
			return;
		m_snapshot.acceptedGeneration = state.acceptedGeneration;
		m_snapshot.acknowledgedGeneration = state.acknowledgedGeneration;
		m_snapshot.reportSequence = state.reportSequence;
		m_snapshot.ownerEpoch = state.ownerEpoch;
		m_snapshot.managedGroupState = state.managedGroupState;
		m_snapshot.observedMethod = state.observedMethod;
		m_snapshot.outcome = state.outcome;
		m_snapshot.retryPhase = state.retryPhase;
		m_snapshot.diagnostic = state.diagnostic;
		m_lastReport = Clock::now();
	}

	void acceptHeartbeat(const Protocol::Heartbeat& heartbeat) {
		const std::scoped_lock lock(m_snapshotMutex);
		if (heartbeat.authoritySession != m_session || (m_snapshot.reportSequence && heartbeat.reportSequence <= *m_snapshot.reportSequence))
			return;
		m_snapshot.reportSequence = heartbeat.reportSequence;
		m_lastReport = Clock::now();
	}

	void connectedLoop(int socketFd) {
		while (!m_stop.load(std::memory_order_acquire)) {
			const auto target = currentTarget();
			if (target.generation > m_sentGeneration.load(std::memory_order_relaxed)) {
				if (!sendTarget(socketFd, target))
					return;
			}
			auto received = waitForFrame(socketFd, true);
			if (received.wouldBlock)
				continue;
			if (received.disconnected)
				return;
			if (!received.frame) {
				setConnection(FollowerConnection::Incompatible, Protocol::Outcome::ProtocolError, "invalid helper frame");
				m_incompatible = true;
				return;
			}
			if (const auto* state = std::get_if<Protocol::State>(&*received.frame))
				acceptState(*state, currentTarget());
			else if (const auto* heartbeat = std::get_if<Protocol::Heartbeat>(&*received.frame))
				acceptHeartbeat(*heartbeat);
			else {
				setConnection(FollowerConnection::Incompatible, Protocol::Outcome::ProtocolError, "unexpected helper frame");
				m_incompatible = true;
				return;
			}
		}
	}

	void run() noexcept {
		try {
			if (m_options.socketPath.empty()) {
				setConnection(FollowerConnection::Failed, Protocol::Outcome::Unavailable, "XDG_RUNTIME_DIR is missing or not absolute");
				return;
			}
			std::size_t retry = 0;
			while (!m_stop.load(std::memory_order_acquire) && !m_incompatible) {
				const int socketFd = connectSocket();
				if (socketFd < 0) {
					waitToReconnect(retry);
					continue;
				}
				const auto target = currentTarget();
				const Protocol::Hello hello{
					.protocolIdentity = Protocol::IDENTITY,
					.buildId = m_options.buildId,
					.sourceId = m_options.sourceId,
					.authoritySession = m_session,
					.language = protocolLanguage(target.language),
					.generation = target.generation,
				};
				if (!sendFrame(socketFd, hello)) {
					close(socketFd);
					waitToReconnect(retry);
					continue;
				}
				m_sentGeneration.store(target.generation, std::memory_order_relaxed);
				if (awaitReady(socketFd, target)) {
					retry = 0;
					connectedLoop(socketFd);
				}
				close(socketFd);
				if (!m_incompatible && !m_stop.load(std::memory_order_acquire))
					waitToReconnect(retry);
			}
		} catch (...) {
			try {
				setConnection(FollowerConnection::Failed, Protocol::Outcome::HelperFailed);
			} catch (...) {}
		}
	}

	FollowerOptions m_options;
	Protocol::Session m_session;
	std::atomic<Language> m_language;
	std::atomic<uint64_t> m_generation;
	std::atomic<uint64_t> m_revision = 0;
	std::atomic<uint64_t> m_sentGeneration = 0;
	std::atomic<uint64_t> m_coalesced = 0;
	std::atomic_bool m_stop = false;
	bool m_incompatible = false;
	mutable std::mutex m_wakeMutex;
	mutable std::condition_variable m_wake;
	mutable std::mutex m_snapshotMutex;
	FollowerSnapshot m_snapshot;
	std::optional<Clock::time_point> m_lastReport;
	std::thread m_worker;
};

FcitxFollower::FcitxFollower(FollowerOptions options, LanguageTarget initialTarget) :
	m_impl(std::make_unique<Impl>(std::move(options), initialTarget)) {}

FcitxFollower::~FcitxFollower() = default;

void FcitxFollower::offer(LanguageTarget target) noexcept {
	m_impl->offer(target);
}

FollowerSnapshot FcitxFollower::snapshot() const noexcept {
	return m_impl->snapshot();
}

std::string FcitxFollower::defaultSocketPath() {
	const char* runtime = std::getenv("XDG_RUNTIME_DIR");
	return runtime && runtime[0] == '/' ? std::string(runtime) + "/dotfiles-input-languages/fcitx.sock" : std::string{};
}

std::string FcitxFollower::authoritySessionHex(const Protocol::Session& session) {
	constexpr char HEX[] = "0123456789abcdef";
	std::string result;
	result.reserve(session.size() * 2);
	for (const auto byte : session) {
		const auto value = std::to_integer<unsigned char>(byte);
		result += HEX[value >> 4];
		result += HEX[value & 0x0f];
	}
	return result;
}

}
