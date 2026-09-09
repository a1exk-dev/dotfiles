#include "fcitx-controller.hpp"
#include "fcitx-helper.hpp"

#include <atomic>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <string>
#include <systemd/sd-daemon.h>
#include <thread>
#include <unistd.h>

#ifndef INPUT_LANGUAGES_BUILD_ID
#define INPUT_LANGUAGES_BUILD_ID ""
#endif
#ifndef INPUT_LANGUAGES_SOURCE_ID
#define INPUT_LANGUAGES_SOURCE_ID ""
#endif

namespace {
static_assert(std::atomic_bool::is_always_lock_free);
std::atomic_bool terminated = false;

void terminate(int) {
	terminated.store(true, std::memory_order_relaxed);
}
}

int main() {
	if (sd_listen_fds(0) != 1) {
		std::cerr << "socket activation requires exactly one listener\n";
		return 0;
	}
	const char* home = std::getenv("HOME");
	if (!home || home[0] != '/') {
		std::cerr << "HOME must be absolute\n";
		return 0;
	}

	std::signal(SIGTERM, terminate);
	std::signal(SIGINT, terminate);
	InputLanguages::Fcitx::SdBusControllerTransport transport({
		.uniqueOwner = {},
		.upstreamVersion = InputLanguages::Fcitx::installedFcitxUpstreamVersion(),
		.supervised = true,
		.profilePath = std::string(home) + "/.config/fcitx5/profile",
	});
	InputLanguages::Fcitx::ControllerAdapter controller(transport);
	InputLanguages::Fcitx::Helper helper(controller, {
		.buildId = INPUT_LANGUAGES_BUILD_ID,
		.sourceId = INPUT_LANGUAGES_SOURCE_ID,
	});
	std::thread signalWatcher([&helper] {
		while (!terminated.load(std::memory_order_relaxed))
			usleep(50'000);
		helper.requestStop();
	});
	const int result = helper.run(SD_LISTEN_FDS_START);
	terminated.store(true, std::memory_order_relaxed);
	signalWatcher.join();
	return result;
}
