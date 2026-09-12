#pragma once

#include "fcitx-follower.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace InputLanguages {

struct PhysicalGroup {
	std::string device;
	uint32_t group = 0;
	bool operator==(const PhysicalGroup&) const = default;
};

struct HealthInput {
	std::string buildId;
	std::string sourceId;
	std::string compatibilityHash;
	uint32_t canonicalGroup = 0;
	std::vector<PhysicalGroup> physicalGroups;
	std::vector<std::string> excludedKeyboards;
	LanguageTarget target;
	bool synchronized = false;
};

[[nodiscard]] std::string coordinatedHealthJson(HealthInput input, Fcitx::FollowerSnapshot follower);

}
