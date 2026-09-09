#pragma once

#include "fcitx-controller.hpp"
#include "fcitx-protocol.hpp"

#include <atomic>
#include <chrono>
#include <string>

namespace InputLanguages::Fcitx {

struct HelperOptions {
	std::string buildId;
	std::string sourceId;
	std::chrono::milliseconds pollInterval{1000};
	std::chrono::milliseconds heartbeatInterval{1000};
	std::chrono::milliseconds retrySecond{1000};
};

class Helper {
  public:
	Helper(ControllerAdapter& controller, HelperOptions options);
	[[nodiscard]] int run(int listenerFd) noexcept;
	void requestStop() noexcept;

  private:
	ControllerAdapter& m_controller;
	HelperOptions m_options;
	std::atomic_bool m_stop = false;
};

[[nodiscard]] bool validateSocketActivatedListener(
	int listenerFd,
	std::string& diagnostic,
	bool* operationalFailure = nullptr) noexcept;
[[nodiscard]] std::string runtimeSocketPath();
[[nodiscard]] std::string installedFcitxUpstreamVersion(std::string_view databaseRoot = "/var/lib/pacman/local") noexcept;

}
