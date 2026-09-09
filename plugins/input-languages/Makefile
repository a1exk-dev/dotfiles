CXX ?= c++
COMPILER_ID ?= $(shell $(CXX) -dumpfullversion -dumpversion)
CPPFLAGS := -Iinclude
CXXFLAGS := -std=c++23 -Wall -Wextra -Wpedantic -Werror
BUILD_DIR ?= $(or $(XDG_CACHE_HOME),$(HOME)/.cache)/dotfiles/input-languages-build
PLUGIN_PACKAGES := hyprland pixman-1 libdrm aquamarine hyprutils hyprgraphics hyprcursor hyprlang libinput libudev
PLUGIN_FLAGS := -shared -fPIC -fno-gnu-unique
WIDGET_ID := dotfiles.keyboard-layout
WIDGET_SOURCE := widget/$(WIDGET_ID)

.PHONY: test check artifact clean

test: $(BUILD_DIR)/input-language-model-test $(BUILD_DIR)/fcitx-controller-test
	@$(BUILD_DIR)/input-language-model-test
	@$(BUILD_DIR)/fcitx-controller-test

$(BUILD_DIR)/input-language-model-test: tests/input-language-model-test.cpp src/input-language-model.cpp include/input-language-model.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/input-language-model-test.cpp src/input-language-model.cpp -o "$@"

$(BUILD_DIR)/fcitx-controller-test: tests/fcitx-controller-test.cpp src/fcitx-controller.cpp src/fcitx-sd-bus-transport.cpp include/fcitx-controller.hpp
	@mkdir -p "$(BUILD_DIR)"
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) tests/fcitx-controller-test.cpp src/fcitx-controller.cpp src/fcitx-sd-bus-transport.cpp -o "$@" \
		$$(pkg-config --cflags --libs libsystemd libcrypto)

check:
	@tmp=$$(mktemp -d "$${TMPDIR:-/tmp}/input-languages-check.XXXXXX"); \
	trap 'rm -rf -- "$$tmp"' EXIT; \
	$(MAKE) --no-print-directory artifact OUTPUT_DIR="$$tmp" BUILD_ID=static-check SOURCE_ID=static-check COMPILER_ID="$(COMPILER_ID)"; \
	file "$$tmp/input-languages.so" | grep -F 'shared object' >/dev/null; \
	for symbol in pluginAPIVersion pluginInit pluginExit; do \
		nm -D --defined-only "$$tmp/input-languages.so" | grep -Eq "[[:space:]]$$symbol$$" || exit 1; \
	done; \
	for symbol in g_pInputManager g_pKeybindManager; do \
		nm -D --defined-only "$$tmp/input-languages.so" | grep -Eq "[[:space:]][uV][[:space:]]$$symbol$$" || exit 1; \
	done; \
	identity=$$(readelf -p .input_languages "$$tmp/input-languages.so"); \
	printf '%s\n' "$$identity" | grep -F 'build_id=static-check' >/dev/null; \
	printf '%s\n' "$$identity" | grep -F 'source_id=static-check' >/dev/null; \
	printf '%s\n' "$$identity" | grep -F 'compiler=$(COMPILER_ID)' >/dev/null; \
	test "$$(find "$$tmp/$(WIDGET_ID)" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)" = "$$(printf '%s\n' KeyboardLayout.qml KeyboardLayoutModel.js manifest.json | LC_ALL=C sort)"

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
