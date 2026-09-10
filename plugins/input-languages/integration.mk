CXX ?= c++
CPPFLAGS := -Iinclude
CXXFLAGS := -std=c++23 -Wall -Wextra -Wpedantic -Werror
PLUGIN_PACKAGES := hyprland pixman-1 libdrm aquamarine hyprutils hyprgraphics hyprcursor hyprlang libinput libudev
PLUGIN_FLAGS := -shared -fPIC -fno-gnu-unique
HELPER_PACKAGES := libsystemd libcrypto
HELPER_FLAGS := -pthread

.PHONY: integration-artifact

integration-artifact:
	@test -n "$(OUTPUT_DIR)" || { printf 'OUTPUT_DIR is required\n' >&2; exit 2; }
	@for value in "$(BUILD_ID)" "$(SOURCE_ID)"; do \
		printf '%s\n' "$$value" | grep -Eq '^[0-9a-f]{64}$$' || { printf 'BUILD_ID and SOURCE_ID must be lowercase SHA-256 digests\n' >&2; exit 2; }; \
	done
	@for value in "$(COMPILER_ID)" "$(COMPATIBILITY_ID)" "$(INTEGRATION_ID)" "$(PROTOCOL_ID)" "$(CONTROLLER_ID)" "$(HEALTH_ID)" "$(UNIT_ID)"; do \
		test -n "$$value" || { printf 'all integration identities are required\n' >&2; exit 2; }; \
	done
	@test ! -e "$(OUTPUT_DIR)/input-languages.so" && test ! -e "$(OUTPUT_DIR)/input-languages-fcitx-helper"
	@mkdir -p "$(OUTPUT_DIR)/contracts" "$(OUTPUT_DIR)/systemd"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(PLUGIN_FLAGS) \
		-DINPUT_LANGUAGES_BUILD_ID='"$(BUILD_ID)"' \
		-DINPUT_LANGUAGES_SOURCE_ID='"$(SOURCE_ID)"' \
		-DINPUT_LANGUAGES_COMPILER_ID='"$(COMPILER_ID)"' \
		-DINPUT_LANGUAGES_COMPATIBILITY_ID='"$(COMPATIBILITY_ID)"' \
		-DINPUT_LANGUAGES_INTEGRATION_ID='"$(INTEGRATION_ID)"' \
		-DINPUT_LANGUAGES_PROTOCOL_ID='"$(PROTOCOL_ID)"' \
		-DINPUT_LANGUAGES_CONTROLLER_ID='"$(CONTROLLER_ID)"' \
		-DINPUT_LANGUAGES_HEALTH_ID='"$(HEALTH_ID)"' \
		-DINPUT_LANGUAGES_UNIT_ID='"$(UNIT_ID)"' \
		-DINPUT_LANGUAGES_ARTIFACT_ROLE='"plugin"' \
		-DINPUT_LANGUAGES_FCITX_COORDINATION \
		src/plugin.cpp src/input-language-model.cpp src/fcitx-follower.cpp src/fcitx-protocol.cpp src/integration-artifact-identity.cpp \
		-o "$(OUTPUT_DIR)/input-languages.so" $(HELPER_FLAGS) $$(pkg-config --cflags --libs $(PLUGIN_PACKAGES))
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) \
		-DINPUT_LANGUAGES_BUILD_ID='"$(BUILD_ID)"' \
		-DINPUT_LANGUAGES_SOURCE_ID='"$(SOURCE_ID)"' \
		-DINPUT_LANGUAGES_COMPILER_ID='"$(COMPILER_ID)"' \
		-DINPUT_LANGUAGES_COMPATIBILITY_ID='"$(COMPATIBILITY_ID)"' \
		-DINPUT_LANGUAGES_INTEGRATION_ID='"$(INTEGRATION_ID)"' \
		-DINPUT_LANGUAGES_PROTOCOL_ID='"$(PROTOCOL_ID)"' \
		-DINPUT_LANGUAGES_CONTROLLER_ID='"$(CONTROLLER_ID)"' \
		-DINPUT_LANGUAGES_HEALTH_ID='"$(HEALTH_ID)"' \
		-DINPUT_LANGUAGES_UNIT_ID='"$(UNIT_ID)"' \
		-DINPUT_LANGUAGES_ARTIFACT_ROLE='"helper"' \
		src/fcitx-helper-main.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp src/fcitx-controller.cpp src/fcitx-controller-cli.cpp src/fcitx-sd-bus-transport.cpp \
		src/integration-artifact-identity.cpp -o "$(OUTPUT_DIR)/input-languages-fcitx-helper" $(HELPER_FLAGS) \
		$$(pkg-config --cflags --libs $(HELPER_PACKAGES))
	@cp -a -- widget/dotfiles.keyboard-layout "$(OUTPUT_DIR)/dotfiles.keyboard-layout"
	@cp -a -- contracts/. "$(OUTPUT_DIR)/contracts/"
	@cp -- systemd/dotfiles-input-languages-fcitx.socket "$(OUTPUT_DIR)/systemd/"
	@cp -- systemd/dotfiles-input-languages-fcitx.service "$(OUTPUT_DIR)/systemd/"
