#include "fcitx-protocol.hpp"

#include <algorithm>
#include <limits>
#include <string_view>
#include <type_traits>

namespace InputLanguages::Fcitx::Protocol {
namespace {

class Writer {
  public:
	template <typename Integer>
	void integer(Integer value) {
		using Unsigned = std::make_unsigned_t<Integer>;
		auto unsignedValue = static_cast<Unsigned>(value);
		for (std::size_t index = 0; index < sizeof(Integer); ++index)
			m_bytes.push_back(static_cast<std::byte>((unsignedValue >> (index * 8)) & 0xff));
	}

	void raw(std::span<const std::byte> value) { m_bytes.insert(m_bytes.end(), value.begin(), value.end()); }

	bool text(std::string_view value) {
		if (value.size() > MAX_TEXT_BYTES || !validUtf8(value))
			return false;
		integer<uint16_t>(static_cast<uint16_t>(value.size()));
		raw(std::as_bytes(std::span(value.data(), value.size())));
		return true;
	}

	bool digest(std::string_view value) {
		if (value.size() != 64 || !std::ranges::all_of(value, [](unsigned char byte) {
			return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
		}))
			return false;
		raw(std::as_bytes(std::span(value.data(), value.size())));
		return true;
	}

	bool optionalText(const std::optional<std::string>& value) {
		integer<uint8_t>(value ? 1 : 0);
		return !value || (!value->empty() && text(*value));
	}

	std::vector<std::byte> take() { return std::move(m_bytes); }

  private:
	static bool validUtf8(std::string_view value) {
		std::size_t index = 0;
		while (index < value.size()) {
			const auto first = static_cast<unsigned char>(value[index++]);
			if (first <= 0x7f)
				continue;
			unsigned continuation = 0;
			uint32_t codepoint = 0;
			if (first >= 0xc2 && first <= 0xdf) {
				continuation = 1;
				codepoint = first & 0x1f;
			} else if (first >= 0xe0 && first <= 0xef) {
				continuation = 2;
				codepoint = first & 0x0f;
			} else if (first >= 0xf0 && first <= 0xf4) {
				continuation = 3;
				codepoint = first & 0x07;
			} else {
				return false;
			}
			if (value.size() - index < continuation)
				return false;
			for (unsigned count = 0; count < continuation; ++count) {
				const auto next = static_cast<unsigned char>(value[index++]);
				if ((next & 0xc0) != 0x80)
					return false;
				codepoint = (codepoint << 6) | (next & 0x3f);
			}
			if ((continuation == 2 && codepoint < 0x800) || (continuation == 3 && codepoint < 0x10000) ||
				(codepoint >= 0xd800 && codepoint <= 0xdfff) || codepoint > 0x10ffff)
				return false;
		}
		return true;
	}

	std::vector<std::byte> m_bytes;
};

class Reader {
  public:
	explicit Reader(std::span<const std::byte> bytes) : m_bytes(bytes) {}

	template <typename Integer>
	bool integer(Integer& value) {
		if (remaining() < sizeof(Integer))
			return false;
		using Unsigned = std::make_unsigned_t<Integer>;
		Unsigned result = 0;
		for (std::size_t index = 0; index < sizeof(Integer); ++index)
			result |= static_cast<Unsigned>(std::to_integer<unsigned char>(m_bytes[m_offset++])) << (index * 8);
		value = static_cast<Integer>(result);
		return true;
	}

	bool raw(std::span<std::byte> destination) {
		if (remaining() < destination.size())
			return false;
		std::ranges::copy(m_bytes.subspan(m_offset, destination.size()), destination.begin());
		m_offset += destination.size();
		return true;
	}

	bool text(std::string& value) {
		uint16_t length = 0;
		if (!integer(length) || length > MAX_TEXT_BYTES || remaining() < length)
			return false;
		value.assign(reinterpret_cast<const char*>(m_bytes.data() + m_offset), length);
		m_offset += length;
		Writer validation;
		return validation.text(value);
	}

	bool digest(std::string& value) {
		if (remaining() < 64)
			return false;
		value.assign(reinterpret_cast<const char*>(m_bytes.data() + m_offset), 64);
		m_offset += 64;
		return value.size() == 64 && std::ranges::all_of(value, [](unsigned char byte) {
			return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
		});
	}

	bool optionalText(std::optional<std::string>& value) {
		uint8_t present = 0;
		std::string textValue;
		if (!integer(present) || present > 1 || (present == 1 && (!text(textValue) || textValue.empty())))
			return false;
		if (present)
			value = std::move(textValue);
		else
			value.reset();
		return true;
	}

	[[nodiscard]] std::size_t remaining() const { return m_bytes.size() - m_offset; }

  private:
	std::span<const std::byte> m_bytes;
	std::size_t m_offset = 0;
};

template <typename Enum>
bool readEnum(Reader& reader, Enum& value, uint8_t maximum) {
	uint8_t raw = 0;
	if (!reader.integer(raw) || raw > maximum)
		return false;
	value = static_cast<Enum>(raw);
	return true;
}

bool validSession(const Session& session) {
	return std::ranges::any_of(session, [](std::byte value) { return value != std::byte{}; });
}

template <typename Enum>
bool validEnum(Enum value, uint8_t maximum) {
	return static_cast<uint8_t>(value) <= maximum;
}

bool writePayload(Writer& writer, const Hello& frame) {
	return !frame.protocolIdentity.empty() && writer.text(frame.protocolIdentity) && writer.digest(frame.buildId) && writer.digest(frame.sourceId) &&
		(writer.raw(frame.authoritySession), writer.integer(frame.language), writer.integer(frame.generation),
			validSession(frame.authoritySession) && validEnum(frame.language, 1) && frame.generation != 0);
}

bool writePayload(Writer& writer, const Ready& frame) {
	return !frame.protocolIdentity.empty() && writer.text(frame.protocolIdentity) && writer.digest(frame.buildId) && writer.digest(frame.sourceId) &&
		(writer.raw(frame.authoritySession), validSession(frame.authoritySession));
}

bool writePayload(Writer& writer, const Target& frame) {
	writer.raw(frame.authoritySession);
	writer.integer(frame.language);
	writer.integer(frame.generation);
	return validSession(frame.authoritySession) && validEnum(frame.language, 1) && frame.generation != 0;
}

bool writePayload(Writer& writer, const State& frame) {
	if (frame.protocolIdentity.empty() || !writer.text(frame.protocolIdentity) || !writer.digest(frame.buildId))
		return false;
	writer.raw(frame.authoritySession);
	writer.integer(frame.reportSequence);
	writer.integer(frame.acceptedGeneration);
	writer.integer<uint8_t>(frame.acknowledgedGeneration ? 1 : 0);
	if (frame.acknowledgedGeneration)
		writer.integer(*frame.acknowledgedGeneration);
	writer.integer(frame.ownerState);
	if (!writer.optionalText(frame.uniqueOwner))
		return false;
	writer.integer(frame.ownerEpoch);
	writer.integer(frame.managedGroupState);
	if (!writer.optionalText(frame.currentGroup) || !writer.text(frame.observedMethod))
		return false;
	writer.integer(frame.outcome);
	writer.integer(frame.retryPhase);
	const bool ownerValid = (frame.ownerState == OwnerState::Absent && !frame.uniqueOwner) ||
		((frame.ownerState == OwnerState::Present || frame.ownerState == OwnerState::Competing) &&
			frame.uniqueOwner && frame.ownerEpoch != 0);
	const bool acknowledgementValid = !frame.acknowledgedGeneration ||
		(frame.ownerState == OwnerState::Present && frame.managedGroupState == ManagedGroupState::Exact &&
			frame.currentGroup && !frame.observedMethod.empty() && frame.outcome == Outcome::Converged);
	return writer.text(frame.diagnostic) && validSession(frame.authoritySession) && frame.reportSequence != 0 && frame.acceptedGeneration != 0 &&
		(!frame.acknowledgedGeneration || *frame.acknowledgedGeneration == frame.acceptedGeneration) &&
		validEnum(frame.ownerState, 2) && ownerValid && acknowledgementValid && validEnum(frame.managedGroupState, 3) &&
		validEnum(frame.outcome, 11) && validEnum(frame.retryPhase, 5);
}

bool writePayload(Writer& writer, const Heartbeat& frame) {
	writer.raw(frame.authoritySession);
	writer.integer(frame.reportSequence);
	return validSession(frame.authoritySession) && frame.reportSequence != 0;
}

template <typename FrameValue>
constexpr FrameType frameType();
template <> constexpr FrameType frameType<Hello>() { return FrameType::Hello; }
template <> constexpr FrameType frameType<Ready>() { return FrameType::Ready; }
template <> constexpr FrameType frameType<Target>() { return FrameType::Target; }
template <> constexpr FrameType frameType<State>() { return FrameType::State; }
template <> constexpr FrameType frameType<Heartbeat>() { return FrameType::Heartbeat; }

bool readPayload(Reader& reader, Hello& frame) {
	return reader.text(frame.protocolIdentity) && reader.digest(frame.buildId) && reader.digest(frame.sourceId) &&
		!frame.protocolIdentity.empty() && reader.raw(frame.authoritySession) && validSession(frame.authoritySession) && readEnum(reader, frame.language, 1) &&
		reader.integer(frame.generation) && frame.generation != 0;
}

bool readPayload(Reader& reader, Ready& frame) {
	return reader.text(frame.protocolIdentity) && reader.digest(frame.buildId) && reader.digest(frame.sourceId) &&
		!frame.protocolIdentity.empty() && reader.raw(frame.authoritySession) && validSession(frame.authoritySession);
}

bool readPayload(Reader& reader, Target& frame) {
	return reader.raw(frame.authoritySession) && validSession(frame.authoritySession) && readEnum(reader, frame.language, 1) &&
		reader.integer(frame.generation) && frame.generation != 0;
}

bool readPayload(Reader& reader, State& frame) {
	uint8_t present = 0;
	uint64_t acknowledged = 0;
	if (!reader.text(frame.protocolIdentity) || frame.protocolIdentity.empty() || !reader.digest(frame.buildId) || !reader.raw(frame.authoritySession) || !validSession(frame.authoritySession) ||
		!reader.integer(frame.reportSequence) || frame.reportSequence == 0 || !reader.integer(frame.acceptedGeneration) ||
		frame.acceptedGeneration == 0 || !reader.integer(present) || present > 1 ||
		(present == 1 && (!reader.integer(acknowledged) || acknowledged == 0)) || !readEnum(reader, frame.ownerState, 2) ||
		!reader.optionalText(frame.uniqueOwner) || !reader.integer(frame.ownerEpoch) ||
		!readEnum(reader, frame.managedGroupState, 3) || !reader.optionalText(frame.currentGroup) || !reader.text(frame.observedMethod) ||
		!readEnum(reader, frame.outcome, 11) || !readEnum(reader, frame.retryPhase, 5) || !reader.text(frame.diagnostic))
		return false;
	if (present)
		frame.acknowledgedGeneration = acknowledged;
	const bool ownerValid = (frame.ownerState == OwnerState::Absent && !frame.uniqueOwner) ||
		((frame.ownerState == OwnerState::Present || frame.ownerState == OwnerState::Competing) &&
			frame.uniqueOwner && frame.ownerEpoch != 0);
	const bool acknowledgementValid = !frame.acknowledgedGeneration ||
		(frame.ownerState == OwnerState::Present && frame.managedGroupState == ManagedGroupState::Exact &&
			frame.currentGroup && !frame.observedMethod.empty() && frame.outcome == Outcome::Converged);
	return ownerValid && acknowledgementValid &&
		(!frame.acknowledgedGeneration || *frame.acknowledgedGeneration == frame.acceptedGeneration);
}

bool readPayload(Reader& reader, Heartbeat& frame) {
	return reader.raw(frame.authoritySession) && validSession(frame.authoritySession) && reader.integer(frame.reportSequence) && frame.reportSequence != 0;
}

}

std::optional<std::vector<std::byte>> encode(const Frame& frame) noexcept {
	try {
		Writer payload;
		FrameType type{};
		const bool valid = std::visit([&](const auto& value) {
			type = frameType<std::decay_t<decltype(value)>>();
			return writePayload(payload, value);
		}, frame);
		if (!valid)
			return std::nullopt;
		auto payloadBytes = payload.take();
		if (payloadBytes.size() > MAX_PAYLOAD_BYTES)
			return std::nullopt;
		Writer packet;
		packet.integer(MAGIC);
		packet.integer(VERSION);
		packet.integer(type);
		packet.integer<uint16_t>(static_cast<uint16_t>(payloadBytes.size()));
		packet.integer<uint16_t>(0);
		packet.raw(payloadBytes);
		return packet.take();
	} catch (...) {
		return std::nullopt;
	}
}

DecodeResult decode(std::span<const std::byte> packet, bool truncated) noexcept {
	try {
		if (truncated || packet.size() > MAX_PACKET_BYTES)
			return {.frame = {}, .error = "oversized or truncated packet"};
		if (packet.size() < HEADER_BYTES)
			return {.frame = {}, .error = "truncated header"};
		Reader reader(packet);
		uint32_t magic = 0;
		uint16_t version = 0;
		uint16_t rawType = 0;
		uint16_t payloadBytes = 0;
		uint16_t reserved = 0;
		if (!reader.integer(magic) || !reader.integer(version) || !reader.integer(rawType) || !reader.integer(payloadBytes) ||
			!reader.integer(reserved) || magic != MAGIC || version != VERSION || reserved != 0 ||
			payloadBytes > MAX_PAYLOAD_BYTES || payloadBytes != reader.remaining())
			return {.frame = {}, .error = "invalid header or payload length"};
		Reader payload(packet.subspan(HEADER_BYTES));
		Frame frame;
		bool valid = false;
		switch (static_cast<FrameType>(rawType)) {
			case FrameType::Hello: frame = Hello{}; valid = readPayload(payload, std::get<Hello>(frame)); break;
			case FrameType::Ready: frame = Ready{}; valid = readPayload(payload, std::get<Ready>(frame)); break;
			case FrameType::Target: frame = Target{}; valid = readPayload(payload, std::get<Target>(frame)); break;
			case FrameType::State: frame = State{}; valid = readPayload(payload, std::get<State>(frame)); break;
			case FrameType::Heartbeat: frame = Heartbeat{}; valid = readPayload(payload, std::get<Heartbeat>(frame)); break;
			default: return {.frame = {}, .error = "unknown frame type"};
		}
		if (!valid || payload.remaining() != 0)
			return {.frame = {}, .error = "invalid frame payload"};
		return {.frame = std::move(frame), .error = {}};
	} catch (...) {
		return {.frame = {}, .error = "frame decoding failed"};
	}
}

}
