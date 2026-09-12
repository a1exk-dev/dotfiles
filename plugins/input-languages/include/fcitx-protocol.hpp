#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <variant>
#include <vector>

namespace InputLanguages::Fcitx::Protocol {

inline constexpr uint32_t MAGIC = 0x44494c46;
inline constexpr uint16_t VERSION = 1;
inline constexpr std::size_t HEADER_BYTES = 12;
inline constexpr std::size_t MAX_PACKET_BYTES = 1024;
inline constexpr std::size_t MAX_PAYLOAD_BYTES = MAX_PACKET_BYTES - HEADER_BYTES;
inline constexpr std::size_t MAX_TEXT_BYTES = 96;
inline constexpr auto IDENTITY = "dotfiles-input-languages-fcitx-seqpacket-v1";

using Session = std::array<std::byte, 16>;

enum class FrameType : uint16_t { Hello = 1, Ready = 2, Target = 3, State = 4, Heartbeat = 5 };
enum class Language : uint8_t { Us = 0, Russian = 1 };
enum class OwnerState : uint8_t { Absent = 0, Present = 1, Competing = 2 };
enum class ManagedGroupState : uint8_t { Unknown = 0, Exact = 1, Missing = 2, Foreign = 3 };
enum class Outcome : uint8_t {
	Pending = 0,
	Converged = 1,
	IdleNoContext = 2,
	Drift = 3,
	Unavailable = 4,
	Disconnected = 5,
	TimeoutIndeterminate = 6,
	MethodError = 7,
	ConfigurationConflict = 8,
	UnsupportedInterface = 9,
	ProtocolError = 10,
	HelperFailed = 11,
};
enum class RetryPhase : uint8_t { None = 0, Poll = 1, Read = 2, Write = 3, ReadBeforeRetry = 4, Backoff = 5 };

struct Hello {
	std::string protocolIdentity;
	std::string buildId;
	std::string sourceId;
	Session authoritySession{};
	Language language = Language::Us;
	uint64_t generation = 0;
	bool operator==(const Hello&) const = default;
};

struct Ready {
	std::string protocolIdentity;
	std::string buildId;
	std::string sourceId;
	Session authoritySession{};
	bool operator==(const Ready&) const = default;
};

struct Target {
	Session authoritySession{};
	Language language = Language::Us;
	uint64_t generation = 0;
	bool operator==(const Target&) const = default;
};

struct State {
	std::string protocolIdentity;
	std::string buildId;
	Session authoritySession{};
	uint64_t reportSequence = 0;
	uint64_t acceptedGeneration = 0;
	std::optional<uint64_t> acknowledgedGeneration;
	OwnerState ownerState = OwnerState::Absent;
	std::optional<std::string> uniqueOwner;
	uint64_t ownerEpoch = 0;
	ManagedGroupState managedGroupState = ManagedGroupState::Unknown;
	std::optional<std::string> currentGroup;
	std::string observedMethod;
	Outcome outcome = Outcome::Pending;
	RetryPhase retryPhase = RetryPhase::None;
	std::string diagnostic;
	bool operator==(const State&) const = default;
};

struct Heartbeat {
	Session authoritySession{};
	uint64_t reportSequence = 0;
	bool operator==(const Heartbeat&) const = default;
};

using Frame = std::variant<Hello, Ready, Target, State, Heartbeat>;

struct DecodeResult {
	std::optional<Frame> frame;
	std::string error;
	explicit operator bool() const noexcept { return frame.has_value(); }
};

[[nodiscard]] std::optional<std::vector<std::byte>> encode(const Frame& frame) noexcept;
[[nodiscard]] DecodeResult decode(std::span<const std::byte> packet, bool truncated = false) noexcept;

}
