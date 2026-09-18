#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

readonly OBS_SETS=$SOURCE_REPO/obs/sets
readonly GENERATOR=$SOURCE_REPO/config/obs-scene/.local/libexec/dotfiles/obs-scene/generate.ts
readonly COLLECTION_FILE=Omarchy_Scene.json
readonly HOST_BUN=$(command -v bun)
readonly -a SCENE_NAMES=(Stream 'Stream no cam' Full 'Full cam' Starting Intro BRB Ending Privacy)
readonly -a AVATAR_ITEMS=('Avatar back' 'Avatar head1' 'Avatar head2' 'Avatar head3' 'Avatar eyes' 'Avatar glow')

# ---------------------------------------------------------------------------
# Static rules over every tracked set.

# Prints one line per portability violation in a set directory.
set_portability_violations() {
	local set=$1 profile name
	local -A names=()
	find "$set" -name service.json -printf 'service.json: %p\n'
	for profile in "$set"/profiles/*/; do
		[[ $(cd -- "$profile" && find . -mindepth 1 -printf '%P\n' | sort | paste -sd' ') == 'basic.ini recordEncoder.json streamEncoder.json' ]] ||
			printf 'profile files: %s\n' "$profile"
		name=$(sed -n '/^\[General\]/,/^\[/s/^Name=//p' "$profile/basic.ini")
		[[ -z ${names[$name]+seen} ]] || printf 'duplicate profile name: %s\n' "$name"
		names[$name]=1
	done
	grep -rHn -e '^CookieId=' -e '^\[Auth\]' -e '^\[SimpleOutput\]' -e 'vaapi_device' "$set" | sed 's/^/forbidden key: /'
	grep -rHn -E '^[A-Za-z]*DeviceId=' "$set" --include=basic.ini | grep -v '=default$' | sed 's/^/audio device: /'
	grep -rHn -E '/home/|/root/|~/|/dev/video' "$set" | sed 's/^/machine path: /'
	find "$set/scene" -name '*.json' ! -name geometry.json -exec \
		jq -r '[.. | objects | select(has("device_id")) | .device_id | select(. != "default")] | .[] | "device id: \(.)"' {} +
}

test_every_tracked_set_is_portable() {
	local set
	for set in "$OBS_SETS"/*/; do
		assert_eq '' "$(set_portability_violations "$set")" "$set should pass the portability rules" || return 1
	done
}

test_portability_rules_catch_each_forbidden_addition() {
	new_fixture || return 1
	local case set violation
	for case in service cookie auth vaapi simple audio camera home duplicate; do
		set=$FIXTURE_ROOT/$case
		rm -rf "$set"
		cp -a "$OBS_SETS/laptop" "$set"
		case $case in
			service) printf '{}\n' >"$set/profiles/Twitch/service.json" ;;
			cookie) printf '[Panels]\nCookieId=ABC\n' >>"$set/profiles/Twitch/basic.ini" ;;
			auth) printf '[Auth]\nType=Twitch\n' >>"$set/profiles/Twitch/basic.ini" ;;
			vaapi) jq -c '.vaapi_device = "/dev/dri/renderD128"' "$OBS_SETS/laptop/profiles/Twitch/streamEncoder.json" >"$set/profiles/Twitch/streamEncoder.json" ;;
			simple) printf '[SimpleOutput]\nStreamEncoder=x264\n' >>"$set/profiles/Twitch/basic.ini" ;;
			audio) sed -i 's/^MonitoringDeviceId=default$/MonitoringDeviceId=alsa_output.usb/' "$set/profiles/Twitch/basic.ini" ;;
			camera) jq '(.sources[] | select(.name == "Camera") | .settings.device_id) = "/dev/video0"' \
				"$OBS_SETS/laptop/scene/$COLLECTION_FILE" >"$set/scene/$COLLECTION_FILE" ;;
			home) sed -i 's|\$HOME/Videos|/home/someone/Videos|' "$set/profiles/Twitch/basic.ini" ;;
			duplicate) cp -a "$set/profiles/Twitch" "$set/profiles/Twitch copy" ;;
		esac
		violation=$(set_portability_violations "$set")
		[[ -n $violation ]] || {
			printf '  the portability rules should catch the %s case\n' "$case" >&2
			return 1
		}
	done
}

test_sets_carry_the_approved_profile_values() {
	local set ini stream record
	for set in laptop pc; do
		ini=$OBS_SETS/$set/profiles/Twitch/basic.ini
		stream=$OBS_SETS/$set/profiles/Twitch/streamEncoder.json
		record=$OBS_SETS/$set/profiles/Twitch/recordEncoder.json
		assert_eq 'Twitch' "$(sed -n 's/^Name=//p' "$ini")" "$set: profile name" || return 1
		assert_contains "$(<"$ini")" $'[Output]\nMode=Advanced' "$set: Advanced output mode" || return 1
		assert_contains "$(<"$ini")" $'Encoder=ffmpeg_vaapi_tex\n' "$set: stream encoder" || return 1
		assert_contains "$(<"$ini")" 'RecEncoder=ffmpeg_vaapi_tex' "$set: record encoder" || return 1
		assert_contains "$(<"$ini")" 'RecFormat2=hybrid_mp4' "$set: hybrid MP4 recordings" || return 1
		assert_contains "$(<"$ini")" 'RecFilePath=$HOME/Videos/Recordings' "$set: recording path" || return 1
		assert_contains "$(<"$ini")" $'FPSType=0\nFPSCommon=60' "$set: 60 fps" || return 1
		assert_eq '{"rate_control":"CBR","bitrate":6000,"keyint_sec":2,"profile":100}' \
			"$(jq -c '{rate_control, bitrate, keyint_sec, profile}' "$stream")" "$set: stream encoder settings" || return 1
		assert_eq '{"rate_control":"CQP","qp":14,"keyint_sec":0,"profile":100}' \
			"$(jq -c '{rate_control, qp, keyint_sec, profile}' "$record")" "$set: record encoder settings" || return 1
	done
	assert_contains "$(<"$OBS_SETS/laptop/profiles/Twitch/basic.ini")" $'BaseCX=1920\nBaseCY=1080\nOutputCX=1920\nOutputCY=1080' 'laptop canvas' || return 1
	assert_contains "$(<"$OBS_SETS/pc/profiles/Twitch/basic.ini")" $'BaseCX=2560\nBaseCY=1440\nOutputCX=1920\nOutputCY=1080' 'pc canvas' || return 1
	assert_contains "$(<"$OBS_SETS/pc/profiles/Twitch/basic.ini")" 'ScaleType=lanczos' 'pc downscale filter' || return 1
	assert_eq '{"canvas":{"width":1920,"height":1080},"bar_crop":52,"strip_width":70,"band_height":0}' \
		"$(jq -c . "$OBS_SETS/laptop/scene/geometry.json")" 'laptop geometry' || return 1
	assert_eq '{"canvas":{"width":2560,"height":1440},"strip_width":0,"band_height":16}' \
		"$(jq -c '{canvas, strip_width, band_height}' "$OBS_SETS/pc/scene/geometry.json")" 'pc geometry'
}

test_committed_collections_equal_a_fresh_generation() {
	new_fixture || return 1
	local set
	for set in "$OBS_SETS"/*/; do
		set=${set%/}
		"$HOST_BUN" "$GENERATOR" collection --geometry "$set/scene/geometry.json" --output "$FIXTURE_ROOT/${set##*/}.json" || return 1
		cmp -s "$FIXTURE_ROOT/${set##*/}.json" "$set/scene/$COLLECTION_FILE" || {
			printf '  %s/scene/%s differs from a fresh generation; regenerate it\n' "$set" "$COLLECTION_FILE" >&2
			return 1
		}
	done
}

scene_items() {
	jq -r --arg scene "$2" '.sources[] | select(.name == $scene) | .settings.items[].name' "$1"
}

source_field() {
	jq -r --arg name "$2" ".sources[] | select(.name == \$name) | $3" "$1"
}

scene_item_field() {
	jq -r --arg scene "$2" --arg item "$3" ".sources[] | select(.name == \$scene) | .settings.items[] | select(.name == \$item) | $4" "$1"
}

test_collections_hold_the_nine_scenes_and_their_sources() {
	local set collection scene tall cropped
	for set in laptop pc; do
		collection=$OBS_SETS/$set/scene/$COLLECTION_FILE
		assert_eq 'Omarchy Scene' "$(jq -r .name "$collection")" "$set: collection name" || return 1
		assert_eq "$(printf '%s\n' "${SCENE_NAMES[@]}")" "$(jq -r '.scene_order[].name' "$collection")" "$set: scene order" || return 1
		assert_eq '$HOME/.local/libexec/dotfiles/obs-scene/omarchy-scene.lua' "$(jq -r '.modules["scripts-tool"][0].path' "$collection")" \
			"$set: the Lua script is registered" || return 1
		assert_eq 'pipewire-screen-capture-source lanczos' \
			"$(source_field "$collection" Screen .id) $(jq -r '.sources[] | select(.name == "Full") | .settings.items[] | select(.name == "Screen") | .scale_filter' "$collection")" \
			"$set: the screen is a lanczos-scaled screen capture" || return 1
		assert_eq 'v4l2_input {} background_removal 4' \
			"$(source_field "$collection" Camera '"\(.id) \(.settings | tojson) \(.filters[0].id) \(.filters[0].settings.blur_background)"')" \
			"$set: the camera has no device and a strength-4 blur" || return 1
		assert_eq 'browser_source about:blank' "$(source_field "$collection" Chat '"\(.id) \(.settings.url)"')" "$set: blank chat" || return 1
		# One Chat browser serves both stream scenes: it renders at the no-camera
		# height, and Stream crops away the top of it.
		tall=$(source_field "$collection" Chat .settings.height)
		assert_eq 0 "$(scene_item_field "$collection" 'Stream no cam' Chat .crop_top)" "$set: the no-camera chat is uncropped" || return 1
		cropped=$(scene_item_field "$collection" Stream Chat .crop_top)
		[[ $cropped -gt 0 && $cropped -lt $tall ]] || {
			printf '  %s: Stream should crop the top of the %s px chat, got %s\n' "$set" "$tall" "$cropped" >&2
			return 1
		}
		for scene in Clock Date Countdown Title; do
			assert_eq text_ft2_source "$(source_field "$collection" "$scene" .id)" "$set: $scene is a FreeType text source" || return 1
		done
		assert_eq '$HOME/.config/obs-studio/omarchy-scene/title.txt' "$(source_field "$collection" Title .settings.text_file)" "$set: title file" || return 1
		assert_eq 'image_source glow' "$(source_field "$collection" 'Avatar glow' '"\(.id) \(.filters[0].name)"')" "$set: glow filter" || return 1
		for scene in Stream 'Full cam'; do
			assert_eq "$(printf '%s\n' Camera "${AVATAR_ITEMS[@]}")" "$(scene_items "$collection" "$scene" | grep -Ex 'Camera|Avatar .*')" \
				"$set: $scene holds the six avatar items above the camera" || return 1
			assert_eq point "$(jq -r --arg scene "$scene" '[.sources[] | select(.name == $scene) | .settings.items[] | select(.name | startswith("Avatar ")) | .scale_filter] | unique | join(",")' "$collection")" \
				"$set: $scene avatar items use point scaling" || return 1
		done
		assert_eq $'Card starting\nCard pulse 0\nCard pulse 1\nCard pulse 2\nCard pulse 3\nCard pulse 4\nCard pulse 5\nCountdown' \
			"$(scene_items "$collection" Starting)" "$set: the Starting card" || return 1
		assert_contains "$(scene_items "$collection" Stream)" $'Chat\nClock\nDate' "$set: the Stream stack" || return 1
	done
	# Both sets leave canvas around the screen, so every screen scene carries the
	# chrome and its pulse layers: side strips on the laptop, bands on the pc.
	for set in laptop pc; do
		for scene in Stream 'Stream no cam' Full 'Full cam'; do
			assert_contains "$(scene_items "$OBS_SETS/$set/scene/$COLLECTION_FILE" "$scene")" $'Screen chrome\nStrip pulse 0' \
				"$set $scene carries the chrome and its pulses" || return 1
		done
	done
	for set in laptop pc; do
		if scene_items "$OBS_SETS/$set/scene/$COLLECTION_FILE" 'Stream no cam' | grep -Eq '^(Camera|Avatar )'; then
			printf '  %s Stream no cam should hold no camera or avatar items\n' "$set" >&2
			return 1
		fi
	done
}

# ---------------------------------------------------------------------------
# Install OBS set

set_obs_version() {
	make_fake obs "[[ \${1-} == --version ]] && printf 'OBS Studio - %s\n' '$1'"
}

set_obs_running() {
	if [[ $1 == true ]]; then
		make_fake pgrep '[[ $* == "-x obs" ]]'
	else
		make_fake pgrep 'exit 1'
	fi
}

# A fake ffmpeg that logs the encoder and fails for the encoders listed in $1.
make_trial_ffmpeg() {
	make_fake ffmpeg "encoder=''
previous=''
for argument in \"\$@\"; do
	[[ \$previous != -c:v ]] || encoder=\$argument
	previous=\$argument
done
printf 'ffmpeg %s\n' \"\$encoder\" >>\"\$DOTFILES_TEST_CALL_LOG\"
[[ ' ${1-} ' != *\" \$encoder \"* ]]"
}

setup_set_fixture() {
	new_fixture || return 1
	set_obs_version 32.2.2
	set_obs_running false
	make_trial_ffmpeg ''
	make_fake bun 'printf "bun %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"'
	OBS_DIR=$FIXTURE_CONFIG/obs-studio
	PROFILES=$OBS_DIR/basic/profiles
	SCENES=$OBS_DIR/basic/scenes
	mkdir -p "$PROFILES/Untitled" "$SCENES" || return 1
	printf '[General]\nName=Untitled\n' >"$PROFILES/Untitled/basic.ini"
	printf '{"name":"Untitled"}\n' >"$SCENES/Untitled.json"
	printf '%s\n' '[General]' 'FirstRun=true' '' '[Basic]' 'Profile=Untitled' 'ProfileDir=Untitled' \
		'SceneCollection=Untitled' 'SceneCollectionFile=Untitled' '' '[Appearance]' 'Theme=com.obsproject.Yami' >"$OBS_DIR/user.ini"
	mkdir -p "$FIXTURE_HOME/.local/state/omarchy/current/theme" || return 1
	printf 'catppuccin\n' >"$FIXTURE_HOME/.local/state/omarchy/current/theme.name"
	cp /usr/share/omarchy/themes/catppuccin/colors.toml "$FIXTURE_HOME/.local/state/omarchy/current/theme/colors.toml"
}

# Links obs-scene the way Stow does, without running the package apply.
link_obs_scene() {
	local source
	while IFS= read -r -d '' source; do
		mkdir -p "$(dirname -- "$FIXTURE_HOME/${source#"$FIXTURE_REPO/config/obs-scene/"}")"
		ln -s "$source" "$FIXTURE_HOME/${source#"$FIXTURE_REPO/config/obs-scene/"}"
	done < <(find "$FIXTURE_REPO/config/obs-scene" \( -type f -o -type l \) -print0)
	make_fake omarchy-font-current "printf 'JetBrainsMono Nerd Font\n'"
	make_fake omarchy "[[ \${1-} == version ]] && printf '4.0.3-1\n'"
}

install_set() {
	local input=$1
	shift
	DOTFILES_TEST_INPUT=$input run_dotfiles "$FIXTURE_ROOT" --action obs-set "$@"
}

ini_value() {
	sed -n "/^\[$2\]/,/^\[/s/^$3=//p" "$1"
}

obs_tree() {
	(cd -- "$OBS_DIR" && find . -printf '%p %s %T@\n' | sort)
}

assert_no_changes() {
	assert_eq "$1" "$(obs_tree)" "$2: OBS state must stay unchanged" || return 1
	assert_eq '' "$(grep '^bun ' "$CALL_LOG")" "$2: the generator must not run"
}

test_install_copies_profiles_and_scene_and_selects_them() {
	setup_set_fixture && link_obs_scene || return 1

	install_set 'y\n' laptop
	assert_eq 0 "$COMMAND_STATUS" "install should succeed: $COMMAND_OUTPUT" || return 1
	assert_eq 'Twitch' "$(ini_value "$PROFILES/Twitch/basic.ini" General Name)" 'the profile is copied' || return 1
	assert_eq "$FIXTURE_HOME/Videos/Recordings" "$(ini_value "$PROFILES/Twitch/basic.ini" AdvOut RecFilePath)" '$HOME is expanded in record paths' || return 1
	assert_eq 'basic.ini recordEncoder.json streamEncoder.json' "$(ls "$PROFILES/Twitch" | paste -sd' ')" 'only the three profile files are copied' || return 1
	assert_eq 755 "$(stat -c %a "$PROFILES/Twitch")" 'the profile folder is readable like one OBS creates' || return 1
	assert_path_absent "$PROFILES/Twitch/service.json" 'service.json is never written' || return 1
	assert_eq "$FIXTURE_HOME/.local/libexec/dotfiles/obs-scene/omarchy-scene.lua" "$(jq -r '.modules["scripts-tool"][0].path' "$SCENES/$COLLECTION_FILE")" \
		'$HOME is expanded in the script path' || return 1
	assert_eq "$FIXTURE_HOME/.config/obs-studio/omarchy-scene/title.txt" "$(source_field "$SCENES/$COLLECTION_FILE" Title .settings.text_file)" \
		'$HOME is expanded in asset paths' || return 1
	assert_eq "$(jq -c . "$FIXTURE_REPO/obs/sets/laptop/scene/geometry.json")" "$(jq -c . "$OBS_DIR/omarchy-scene/geometry.json")" 'the geometry file is written' || return 1
	assert_eq 1 "$(grep -c '^bun .* render ' "$CALL_LOG")" 'the generator runs once' || return 1
	assert_eq "$(printf '%s\n' '[General]' 'FirstRun=true' '' '[Basic]' 'Profile=Twitch' 'ProfileDir=Twitch' \
		'SceneCollection=Omarchy Scene' 'SceneCollectionFile=Omarchy_Scene' '' '[Appearance]' 'Theme=com.obsproject.Yami')" \
		"$(<"$OBS_DIR/user.ini")" 'user.ini selects the set and changes nothing else' || return 1
	assert_eq 1 "$(find "$OBS_DIR/backups" -name 'user.ini.*' | wc -l)" 'user.ini is backed up' || return 1
	assert_eq '' "$(find "$PROFILES" "$SCENES" -name '.*')" 'no temporary copy remains' || return 1
	assert_eq 'ffmpeg h264_vaapi' "$(grep '^ffmpeg ' "$CALL_LOG" | sort -u)" 'the encoder is trial-encoded' || return 1
	assert_path_absent "$FIXTURE_STATE/dotfiles/obs" 'no receipt is written'
}

test_install_without_obs_scene_copies_profiles_and_skips_the_scene() {
	setup_set_fixture || return 1

	install_set 'y\n' pc
	assert_eq 0 "$COMMAND_STATUS" "install should succeed: $COMMAND_OUTPUT" || return 1
	[[ -f $PROFILES/Twitch/basic.ini ]] || {
		printf '  the profile should be copied\n' >&2
		return 1
	}
	assert_contains "$COMMAND_OUTPUT" 'obs-scene is not applied' 'the scene skip should be explained' || return 1
	assert_contains "$COMMAND_OUTPUT" 'apply obs-scene, then choose Install OBS set again' 'the note should name the rerun' || return 1
	assert_path_absent "$SCENES/$COLLECTION_FILE" 'the collection is skipped' || return 1
	assert_path_absent "$OBS_DIR/omarchy-scene" 'no geometry is written' || return 1
	assert_eq 'Untitled|Untitled' "$(ini_value "$OBS_DIR/user.ini" Basic SceneCollection)|$(ini_value "$OBS_DIR/user.ini" Basic SceneCollectionFile)" \
		'the collection selection stays' || return 1
	assert_eq 'Twitch' "$(ini_value "$OBS_DIR/user.ini" Basic Profile)" 'the profile is selected'
}

test_install_is_blocked_without_the_obs_command() {
	setup_set_fixture || return 1
	rm "$FIXTURE_BIN/obs"
	local restricted=$FIXTURE_ROOT/restricted source before
	mkdir -p "$restricted"
	for source in /usr/bin/*; do
		[[ ${source##*/} == obs ]] || ln -s "$source" "$restricted/"
	done
	before=$(obs_tree)

	DOTFILES_TEST_PATH=$FIXTURE_BIN:$restricted install_set 'y\n' laptop
	assert_eq 1 "$COMMAND_STATUS" "a missing obs should block: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'the obs command is missing' 'the block should be explained' || return 1
	assert_no_changes "$before" 'missing obs' || return 1
	assert_eq '' "$(grep -E '^(ffmpeg|omarchy) .*(pkg|install)' "$CALL_LOG")" 'nothing is installed'
}

test_install_refuses_while_obs_runs() {
	setup_set_fixture || return 1
	set_obs_running true
	local before=$(obs_tree)

	install_set 'y\n' laptop
	assert_eq 1 "$COMMAND_STATUS" "a running OBS should refuse: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'OBS is running' 'the refusal should be explained' || return 1
	assert_no_changes "$before" 'running OBS'
}

# The wizard version gates can be switched off in core.sh, which removes the
# consent prompts these checks assert.
version_gates_disabled() {
	grep -Fxq 'readonly DOTFILES_VERSION_CHECKS_DISABLED=true' "$SOURCE_REPO/lib/dotfiles/core.sh"
}

skip_without_version_gates() {
	version_gates_disabled || return 1
	printf '  notice: wizard version gates are disabled in core.sh; skipped %s\n' "$1" >&2
}

test_install_asks_for_consent_outside_the_version_series() {
	skip_without_version_gates 'the OBS and Omarchy consent checks' && return 0
	setup_set_fixture || return 1
	set_obs_version 33.0.1
	local before=$(obs_tree)

	install_set 'n\n' laptop
	assert_eq 0 "$COMMAND_STATUS" "a declined OBS consent is a no-op: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" $'Tested OBS: 32.2\nDetected OBS: 33.0.1' 'both OBS versions are shown' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Continue despite the OBS version mismatch?' 'OBS consent is asked' || return 1
	assert_no_changes "$before" 'declined OBS consent' || return 1

	set_obs_version 32.2.2
	DOTFILES_TEST_OMARCHY_VERSION=4.1.0-1 install_set 'n\n' laptop
	assert_eq 0 "$COMMAND_STATUS" "a declined Omarchy consent is a no-op: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Continue despite the Omarchy version mismatch?' 'Omarchy consent is asked' || return 1
	assert_no_changes "$before" 'declined Omarchy consent'
}

test_install_refuses_a_profile_whose_encoder_fails_or_is_unknown() {
	local case before
	for case in failing unknown; do
		setup_set_fixture || return 1
		if [[ $case == failing ]]; then
			make_trial_ffmpeg h264_vaapi
		else
			sed -i 's/^RecEncoder=ffmpeg_vaapi_tex$/RecEncoder=jim_nvenc/' "$FIXTURE_REPO/obs/sets/laptop/profiles/Twitch/basic.ini"
		fi
		before=$(obs_tree)
		install_set 'y\n' laptop
		assert_eq 1 "$COMMAND_STATUS" "a $case encoder should refuse the profile: $COMMAND_OUTPUT" || return 1
		assert_contains "$COMMAND_OUTPUT" 'Refused profile Twitch' "the $case encoder refusal should be explained" || return 1
		assert_no_changes "$before" "$case encoder" || return 1
	done
	assert_contains "$COMMAND_OUTPUT" 'jim_nvenc' 'the unknown encoder id is named'
}

test_install_refuses_duplicate_names() {
	setup_set_fixture && link_obs_scene || return 1
	mkdir -p "$PROFILES/Stream"
	printf '[General]\nName=Twitch\n' >"$PROFILES/Stream/basic.ini"
	printf '{"name":"Omarchy Scene"}\n' >"$SCENES/Other.json"
	local before=$(obs_tree)

	install_set 'y\n' laptop
	assert_eq 1 "$COMMAND_STATUS" "duplicate names should be refused: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" "Refused profile Twitch: $PROFILES/Stream already uses that name" 'the profile duplicate is named' || return 1
	assert_contains "$COMMAND_OUTPUT" "Refused collection Omarchy Scene: $SCENES/Other.json already uses that name" 'the collection duplicate is named' || return 1
	assert_no_changes "$before" 'duplicate names'
}

test_install_skips_existing_items_unless_forced_with_a_backup() {
	setup_set_fixture && link_obs_scene || return 1
	mkdir -p "$PROFILES/Twitch"
	printf '[General]\nName=Twitch\n[Video]\nBaseCX=1\n' >"$PROFILES/Twitch/basic.ini"
	printf '{"name":"Omarchy Scene","mine":true}\n' >"$SCENES/$COLLECTION_FILE"

	install_set 'n\nn\ny\n' laptop
	assert_eq 0 "$COMMAND_STATUS" "skipping existing items should succeed: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'Replace the existing profile Twitch?' 'replacing the profile is asked' || return 1
	assert_contains "$(<"$PROFILES/Twitch/basic.ini")" 'BaseCX=1' 'a declined replacement keeps the profile' || return 1
	assert_eq true "$(jq .mine "$SCENES/$COLLECTION_FILE")" 'a declined replacement keeps the collection' || return 1
	assert_eq "$(jq -c . "$FIXTURE_REPO/obs/sets/laptop/scene/geometry.json")" "$(jq -c . "$OBS_DIR/omarchy-scene/geometry.json")" \
		'the geometry is written even when the collection is skipped' || return 1
	assert_path_absent "$OBS_DIR/backups/profile-Twitch" 'nothing is backed up without force' || return 1

	install_set 'y\n' laptop --force
	assert_eq 0 "$COMMAND_STATUS" "forced replacement should succeed: $COMMAND_OUTPUT" || return 1
	if [[ $COMMAND_OUTPUT == *'Replace the existing'* ]]; then
		printf '  --force should replace without asking\n' >&2
		return 1
	fi
	assert_contains "$(<"$PROFILES/Twitch/basic.ini")" 'BaseCX=1920' 'a forced replacement installs the set profile' || return 1
	assert_eq 'Omarchy Scene' "$(jq -r .name "$SCENES/$COLLECTION_FILE")" 'a forced replacement installs the collection' || return 1
	assert_contains "$(cat "$OBS_DIR"/backups/profile-Twitch.*/basic.ini)" 'BaseCX=1' 'the old profile is backed up first' || return 1
	assert_eq true "$(jq .mine "$OBS_DIR"/backups/"$COLLECTION_FILE".*)" 'the old collection is backed up first'
}

test_install_leaves_no_partial_copy_when_a_copy_fails() {
	setup_set_fixture || return 1
	make_fake cp 'for argument in "$@"; do [[ $argument != *recordEncoder.json ]] || exit 1; done
exec /usr/bin/cp "$@"'
	local before=$(obs_tree)

	install_set 'y\n' laptop
	assert_eq 1 "$COMMAND_STATUS" "a failed copy should fail: $COMMAND_OUTPUT" || return 1
	assert_path_absent "$PROFILES/Twitch" 'no partial profile is left' || return 1
	assert_eq '' "$(find "$PROFILES" -name '.*')" 'the temporary copy is removed' || return 1
	assert_eq "$(ini_value "$OBS_DIR/user.ini" Basic Profile)" Untitled 'user.ini is unchanged'
}

test_install_offers_the_sets_and_writes_no_receipt() {
	setup_set_fixture || return 1
	local before=$(obs_tree)

	install_set '1\n'
	assert_eq 0 "$COMMAND_STATUS" "cancelling the set choice is a no-op: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" $'  1. Cancel\n  2. laptop\n  3. pc' 'every set is offered' || return 1
	assert_no_changes "$before" 'cancelled choice' || return 1

	install_set '3\ny\n'
	assert_eq 0 "$COMMAND_STATUS" "choosing a set should install it: $COMMAND_OUTPUT" || return 1
	assert_contains "$(<"$PROFILES/Twitch/basic.ini")" 'BaseCX=2560' 'the chosen set is installed' || return 1
	if grep -rqi 'remove' <(grep -n 'OBS set' "$FIXTURE_REPO/lib/dotfiles/wizard.sh"); then
		printf '  the wizard should offer no Remove for OBS sets\n' >&2
		return 1
	fi
	assert_path_absent "$FIXTURE_STATE/dotfiles/obs" 'no receipt is written'
}

test_install_rejects_an_unknown_set() {
	setup_set_fixture || return 1
	install_set 'y\n' studio
	assert_eq 1 "$COMMAND_STATUS" "an unknown set should fail: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'unknown OBS machine set: studio' 'the unknown set is named'
}

test_diagnose_reports_display_geometry_and_trial_encodes() {
	new_fixture || return 1
	set_obs_version 32.2.2
	make_fake hyprctl "[[ \$* == 'monitors -j' ]] && printf '%s\n' '[{\"name\":\"DP-1\",\"width\":2560,\"height\":1440,\"scale\":1.25}]'"
	make_trial_ffmpeg av1_vaapi

	run_dotfiles "$FIXTURE_ROOT" --action obs-diagnose
	assert_eq 0 "$COMMAND_STATUS" "diagnosis should succeed: $COMMAND_OUTPUT" || return 1
	assert_contains "$COMMAND_OUTPUT" 'OBS: 32.2.2' 'the report should name the OBS version' || return 1
	assert_contains "$COMMAND_OUTPUT" 'DP-1: 2560x1440 at scale 1.25, bar crop 33 px' 'the report should round the crop up' || return 1
	assert_contains "$COMMAND_OUTPUT" 'canvas 2560x1440: screen 2560x1407 px, strip width 0 px, band height 16 px' \
		'a screen wider than the canvas gets bands' || return 1
	assert_contains "$COMMAND_OUTPUT" $'h264_vaapi: ok\n  hevc_vaapi: ok\n  av1_vaapi: failed' 'the report should list each trial encode' || return 1
	assert_eq "$COMMAND_OUTPUT" "$(<"$FIXTURE_STATE/dotfiles/obs-diagnosis.txt")"$'\n'"Report saved: $FIXTURE_STATE/dotfiles/obs-diagnosis.txt" \
		'the report should be saved as printed'
}

run_test test_every_tracked_set_is_portable 'every tracked OBS set passes the portability rules'
run_test test_portability_rules_catch_each_forbidden_addition 'portability rules catch each forbidden addition'
run_test test_sets_carry_the_approved_profile_values 'OBS sets carry the approved profile values'
run_test test_committed_collections_equal_a_fresh_generation 'committed OBS collections equal a fresh generation'
run_test test_collections_hold_the_nine_scenes_and_their_sources 'OBS collections hold the nine scenes and their sources'
run_test test_install_copies_profiles_and_scene_and_selects_them 'Install OBS set copies profiles and scene, then selects them'
run_test test_install_without_obs_scene_copies_profiles_and_skips_the_scene 'Install OBS set without obs-scene copies profiles and skips the scene'
run_test test_install_is_blocked_without_the_obs_command 'Install OBS set is blocked without the obs command'
run_test test_install_refuses_while_obs_runs 'Install OBS set refuses while OBS runs'
run_test test_install_asks_for_consent_outside_the_version_series 'Install OBS set asks for consent outside the version series'
run_test test_install_refuses_a_profile_whose_encoder_fails_or_is_unknown 'Install OBS set refuses a profile whose encoder fails or is unknown'
run_test test_install_refuses_duplicate_names 'Install OBS set refuses duplicate names'
run_test test_install_skips_existing_items_unless_forced_with_a_backup 'Install OBS set skips existing items unless forced, with a backup'
run_test test_install_leaves_no_partial_copy_when_a_copy_fails 'Install OBS set leaves no partial copy when a copy fails'
run_test test_install_offers_the_sets_and_writes_no_receipt 'Install OBS set offers the sets and writes no receipt'
run_test test_install_rejects_an_unknown_set 'Install OBS set rejects an unknown set'
run_test test_diagnose_reports_display_geometry_and_trial_encodes 'OBS diagnosis reports display geometry and trial encodes'
finish_tests
