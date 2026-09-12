CXX ?= c++
COMPILER_ID ?= $(shell $(CXX) -dumpfullversion -dumpversion)
CPPFLAGS := -Iinclude
CXXFLAGS := -std=c++23 -Wall -Wextra -Wpedantic -Werror
BUILD_DIR ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/dotfiles/input-languages-build
PLUGIN_PACKAGES := hyprland pixman-1 libdrm aquamarine hyprutils hyprgraphics hyprcursor hyprlang libinput libudev
PLUGIN_FLAGS := -shared -fPIC -fno-gnu-unique
WIDGET_ID := dotfiles.keyboard-layout
WIDGET_SOURCE := widget/$(WIDGET_ID)
COORDINATED_SOURCE_FILES := Makefile include/input-language-model.hpp include/input-language-health.hpp include/fcitx-follower.hpp include/fcitx-protocol.hpp src/input-language-model.cpp src/input-language-health.cpp src/plugin.cpp src/fcitx-follower.cpp src/fcitx-protocol.cpp
COORDINATED_SOURCE_ID := $(shell sha256sum -- $(COORDINATED_SOURCE_FILES) | sha256sum | cut -d' ' -f1)

.PHONY: test check helper coordinated-plugin artifact clean

test: $(BUILD_DIR)/input-language-model-test $(BUILD_DIR)/input-language-health-test $(BUILD_DIR)/fcitx-controller-test $(BUILD_DIR)/fcitx-helper-test $(BUILD_DIR)/fcitx-follower-test $(BUILD_DIR)/input-language-integration-test
	@$(BUILD_DIR)/input-language-model-test
	@$(BUILD_DIR)/input-language-health-test
	@$(BUILD_DIR)/fcitx-controller-test
	@$(BUILD_DIR)/fcitx-helper-test
	@$(BUILD_DIR)/fcitx-follower-test
	@$(BUILD_DIR)/input-language-integration-test

$(BUILD_DIR)/input-language-model-test: tests/input-language-model-test.cpp src/input-language-model.cpp include/input-language-model.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/input-language-model-test.cpp src/input-language-model.cpp -o "$@"

$(BUILD_DIR)/input-language-health-test: tests/input-language-health-test.cpp src/input-language-health.cpp src/fcitx-follower.cpp src/fcitx-protocol.cpp src/input-language-model.cpp include/input-language-health.hpp include/fcitx-follower.hpp include/fcitx-protocol.hpp include/input-language-model.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/input-language-health-test.cpp src/input-language-health.cpp src/fcitx-follower.cpp src/fcitx-protocol.cpp src/input-language-model.cpp -o "$@" -pthread

$(BUILD_DIR)/fcitx-controller-test: tests/fcitx-controller-test.cpp src/fcitx-controller.cpp src/fcitx-controller-cli.cpp src/fcitx-sd-bus-transport.cpp include/fcitx-controller.hpp include/fcitx-controller-cli.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/fcitx-controller-test.cpp src/fcitx-controller.cpp src/fcitx-controller-cli.cpp src/fcitx-sd-bus-transport.cpp -o "$@" \
		$$(pkg-config --cflags --libs libsystemd libcrypto)

$(BUILD_DIR)/fcitx-helper-test: tests/fcitx-helper-test.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp src/fcitx-controller.cpp include/fcitx-helper.hpp include/fcitx-protocol.hpp include/fcitx-controller.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/fcitx-helper-test.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp src/fcitx-controller.cpp -o "$@" -pthread \
		$$(pkg-config --cflags --libs libcrypto)

$(BUILD_DIR)/fcitx-follower-test: tests/fcitx-follower-test.cpp src/fcitx-follower.cpp src/fcitx-protocol.cpp src/input-language-model.cpp include/fcitx-follower.hpp include/fcitx-protocol.hpp include/input-language-model.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/fcitx-follower-test.cpp src/fcitx-follower.cpp src/fcitx-protocol.cpp src/input-language-model.cpp -o "$@" -pthread

$(BUILD_DIR)/input-language-integration-test: tests/input-language-integration-test.cpp src/input-language-model.cpp src/fcitx-follower.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp src/fcitx-controller.cpp include/input-language-model.hpp include/fcitx-follower.hpp include/fcitx-helper.hpp include/fcitx-protocol.hpp include/fcitx-controller.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/input-language-integration-test.cpp src/input-language-model.cpp src/fcitx-follower.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp src/fcitx-controller.cpp -o "$@" -pthread \
		$$(pkg-config --cflags --libs libcrypto)

check:
	@tmp=$$(mktemp -d "$${TMPDIR:-/tmp}/input-languages-check.XXXXXX"); \
	trap 'rm -rf -- "$$tmp"' EXIT; \
	$(MAKE) --no-print-directory artifact OUTPUT_DIR="$$tmp" BUILD_ID=static-check SOURCE_ID=static-check COMPILER_ID="$(COMPILER_ID)"; \
	$(MAKE) --no-print-directory coordinated-plugin OUTPUT_FILE="$$tmp/input-languages-coordinated.so" \
		BUILD_ID=0000000000000000000000000000000000000000000000000000000000000000 \
		COMPILER_ID="$(COMPILER_ID)"; \
	$(MAKE) --no-print-directory helper OUTPUT_FILE="$$tmp/input-languages-fcitx-helper" \
		BUILD_ID=0000000000000000000000000000000000000000000000000000000000000000 \
		SOURCE_ID=1111111111111111111111111111111111111111111111111111111111111111; \
	file "$$tmp/input-languages.so" | grep -F 'shared object' >/dev/null; \
	file "$$tmp/input-languages-coordinated.so" | grep -F 'shared object' >/dev/null; \
	file "$$tmp/input-languages-fcitx-helper" | grep -F 'ELF' | grep -F 'executable' >/dev/null; \
	test -x "$$tmp/input-languages-fcitx-helper"; \
	for symbol in pluginAPIVersion pluginInit pluginExit; do \
		nm -D --defined-only "$$tmp/input-languages.so" | grep -Eq "[[:space:]]$$symbol$$" || exit 1; \
	done; \
	for symbol in pluginAPIVersion pluginInit pluginExit; do \
		nm -D --defined-only "$$tmp/input-languages-coordinated.so" | grep -Eq "[[:space:]]$$symbol$$" || exit 1; \
	done; \
	! nm -D -C "$$tmp/input-languages.so" | grep -F 'InputLanguages::Fcitx::FcitxFollower' >/dev/null; \
	nm -D -C "$$tmp/input-languages-coordinated.so" | grep -F 'InputLanguages::Fcitx::FcitxFollower' >/dev/null; \
	for symbol in g_pInputManager g_pKeybindManager; do \
		nm -D --defined-only "$$tmp/input-languages.so" | grep -Eq "[[:space:]][uV][[:space:]]$$symbol$$" || exit 1; \
	done; \
	identity=$$(readelf -p .input_languages "$$tmp/input-languages.so"); \
	printf '%s\n' "$$identity" | grep -F 'build_id=static-check' >/dev/null; \
	printf '%s\n' "$$identity" | grep -F 'source_id=static-check' >/dev/null; \
	printf '%s\n' "$$identity" | grep -F 'compiler=$(COMPILER_ID)' >/dev/null; \
	coordinated_identity=$$(readelf -p .input_languages "$$tmp/input-languages-coordinated.so"); \
	printf '%s\n' "$$coordinated_identity" | grep -F 'source_id=$(COORDINATED_SOURCE_ID)' >/dev/null; \
	test "$$(find "$$tmp/$(WIDGET_ID)" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)" = "$$(printf '%s\n' KeyboardLayout.qml KeyboardLayoutModel.js manifest.json | LC_ALL=C sort)"; \
	cp systemd/dotfiles-input-languages-fcitx.socket "$$tmp/dotfiles-input-languages-fcitx.socket"; \
	sed "s|@ARTIFACT_DIR@|$$tmp|" systemd/dotfiles-input-languages-fcitx.service >"$$tmp/dotfiles-input-languages-fcitx.service"; \
	systemd-analyze verify "$$tmp/dotfiles-input-languages-fcitx.socket" "$$tmp/dotfiles-input-languages-fcitx.service"

coordinated-plugin:
	@test -n "$(OUTPUT_FILE)" || { printf 'OUTPUT_FILE is required\n' >&2; exit 2; }
	@printf '%s\n' "$(COORDINATED_SOURCE_ID)" | grep -Eq '^[0-9a-f]{64}$$' || { printf 'COORDINATED_SOURCE_ID must be a lowercase SHA-256 digest\n' >&2; exit 2; }
	@mkdir -p "$$(dirname -- "$(OUTPUT_FILE)")"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(PLUGIN_FLAGS) \
		-DINPUT_LANGUAGES_BUILD_ID='"$(BUILD_ID)"' \
		-DINPUT_LANGUAGES_SOURCE_ID='"$(COORDINATED_SOURCE_ID)"' \
		-DINPUT_LANGUAGES_COMPILER_ID='"$(COMPILER_ID)"' \
		-DINPUT_LANGUAGES_FCITX_COORDINATION \
		src/plugin.cpp src/input-language-model.cpp src/input-language-health.cpp src/fcitx-follower.cpp src/fcitx-protocol.cpp -o "$(OUTPUT_FILE)" \
		-pthread $$(pkg-config --cflags --libs $(PLUGIN_PACKAGES))

helper:
	@test -n "$(OUTPUT_FILE)" || { printf 'OUTPUT_FILE is required\n' >&2; exit 2; }
	@printf '%s\n' "$(BUILD_ID)" | grep -Eq '^[0-9a-f]{64}$$' || { printf 'BUILD_ID must be a lowercase SHA-256 digest\n' >&2; exit 2; }
	@printf '%s\n' "$(SOURCE_ID)" | grep -Eq '^[0-9a-f]{64}$$' || { printf 'SOURCE_ID must be a lowercase SHA-256 digest\n' >&2; exit 2; }
	@mkdir -p "$$(dirname -- "$(OUTPUT_FILE)")"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) \
		-DINPUT_LANGUAGES_BUILD_ID='"$(BUILD_ID)"' \
		-DINPUT_LANGUAGES_SOURCE_ID='"$(SOURCE_ID)"' \
		src/fcitx-helper-main.cpp src/fcitx-helper.cpp src/fcitx-protocol.cpp src/fcitx-controller.cpp src/fcitx-controller-cli.cpp src/fcitx-sd-bus-transport.cpp \
		-o "$(OUTPUT_FILE)" -pthread $$(pkg-config --cflags --libs libsystemd libcrypto)

artifact:
	@test -n "$(OUTPUT_DIR)" || { printf 'OUTPUT_DIR is required\n' >&2; exit 2; }
	@test -n "$(BUILD_ID)" || { printf 'BUILD_ID is required\n' >&2; exit 2; }
	@test -n "$(SOURCE_ID)" || { printf 'SOURCE_ID is required\n' >&2; exit 2; }
	@test -n "$(COMPILER_ID)" || { printf 'COMPILER_ID is required\n' >&2; exit 2; }
	@mkdir -p "$(OUTPUT_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(PLUGIN_FLAGS) \
		-DINPUT_LANGUAGES_BUILD_ID='"$(BUILD_ID)"' \
		-DINPUT_LANGUAGES_SOURCE_ID='"$(SOURCE_ID)"' \
		-DINPUT_LANGUAGES_COMPILER_ID='"$(COMPILER_ID)"' \
		src/plugin.cpp src/input-language-model.cpp -o "$(OUTPUT_DIR)/input-languages.so" \
		$$(pkg-config --cflags --libs $(PLUGIN_PACKAGES))
	@test ! -e "$(OUTPUT_DIR)/$(WIDGET_ID)"
	@cp -a -- "$(WIDGET_SOURCE)" "$(OUTPUT_DIR)/$(WIDGET_ID)"

clean:
	rm -rf -- "$(BUILD_DIR)"
