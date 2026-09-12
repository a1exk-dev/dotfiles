#pragma once

#include "fcitx-protocol.hpp"
#include "input-language-model.hpp"

#include <array>
#include <chrono>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>

namespace InputLanguages::Fcitx {

enum class FollowerConnection { Connected, Disconnected, Failed, Incompatible };

struct FollowerOptions {
	std::string buildId;
	std::string sourceId;
	std::string socketPath;
	std::array<std::chrono::milliseconds, 6> reconnectDelays{
		std::chrono::milliseconds(100), std::chrono::milliseconds(200), std::chrono::milliseconds(400),
		std::chrono::milliseconds(800), std::chrono::milliseconds(1600), std::chrono::milliseconds(2000)};
	std::chrono::milliseconds staleAfter{3000};
	std::chrono::milliseconds pollSlice{25};
};

struct FollowerSnapshot {
	Protocol::Session authoritySession{};
	LanguageTarget target{};
	FollowerConnection connection = FollowerConnection::Disconnected;
	std::optional<uint64_t> acceptedGeneration;
	std::optional<uint64_t> acknowledgedGeneration;
	std::optional<uint64_t> reportSequence;
	std::optional<std::chrono::milliseconds> reportAge;
	uint64_t coalescedTargets = 0;
	Protocol::OwnerState ownerState = Protocol::OwnerState::Absent;
	std::optional<std::string> uniqueOwner;
	uint64_t ownerEpoch = 0;
	Protocol::ManagedGroupState managedGroupState = Protocol::ManagedGroupState::Unknown;
	std::optional<std::string> currentGroup;
	std::string observedMethod;
	Protocol::Outcome outcome = Protocol::Outcome::Disconnected;
	Protocol::RetryPhase retryPhase = Protocol::RetryPhase::None;
	std::string diagnostic;
	bool stale = true;
};

class FcitxFollower final : public TargetSink {
  public:
	FcitxFollower(FollowerOptions options, LanguageTarget initialTarget);
	~FcitxFollower() override;

	FcitxFollower(const FcitxFollower&) = delete;
	FcitxFollower& operator=(const FcitxFollower&) = delete;

	void offer(LanguageTarget target) noexcept override;
	[[nodiscard]] FollowerSnapshot snapshot() const noexcept;

	[[nodiscard]] static std::string defaultSocketPath();
	[[nodiscard]] static std::string authoritySessionHex(const Protocol::Session& session);

  private:
	class Impl;
	std::unique_ptr<Impl> m_impl;
};

}
