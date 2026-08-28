#!/usr/bin/env bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/support/test_helper.sh"

configure_fake_wallpaper_magick() {
	printf 'PNG|4|3\n' >"$FIXTURE_BIN/imagemagick-identify-output"
	: >"$FIXTURE_BIN/imagemagick-identify-diagnostics"
	printf '0\n' >"$FIXTURE_BIN/imagemagick-identify-status"
	: >"$FIXTURE_BIN/imagemagick-decode-diagnostics"
	printf '0\n' >"$FIXTURE_BIN/imagemagick-decode-status"
	rm -f -- "$FIXTURE_BIN/magick"
	make_fake magick 'printf "magick %s\n" "$*" >>"$DOTFILES_TEST_CALL_LOG"
if [[ ${1-} == identify ]]; then
	cat -- "$DOTFILES_TEST_FAKE_BIN/imagemagick-identify-output"
	cat -- "$DOTFILES_TEST_FAKE_BIN/imagemagick-identify-diagnostics" >&2
	exit "$(<"$DOTFILES_TEST_FAKE_BIN/imagemagick-identify-status")"
fi
cat -- "$DOTFILES_TEST_FAKE_BIN/imagemagick-decode-diagnostics" >&2
exit "$(<"$DOTFILES_TEST_FAKE_BIN/imagemagick-decode-status")"'
}

set_fake_wallpaper_magick_response() {
	local identify_output=$1 identify_diagnostics=$2 identify_status=$3 decode_diagnostics=$4 decode_status=$5
	printf '%s' "$identify_output" >"$FIXTURE_BIN/imagemagick-identify-output"
	printf '%s' "$identify_diagnostics" >"$FIXTURE_BIN/imagemagick-identify-diagnostics"
	printf '%s\n' "$identify_status" >"$FIXTURE_BIN/imagemagick-identify-status"
	printf '%s' "$decode_diagnostics" >"$FIXTURE_BIN/imagemagick-decode-diagnostics"
	printf '%s\n' "$decode_status" >"$FIXTURE_BIN/imagemagick-decode-status"
}

test_validator_accepts_all_supported_exact_byte_formats() {
	new_fixture
	setup_wallpaper_fixture
	local specification format extension image output digest
	for specification in 'JPEG jpg' 'PNG png' 'GIF gif' 'BMP bmp' 'WEBP webp'; do
		read -r format extension <<<"$specification"
		image="$FIXTURE_REPO/wallpapers/inbox/sample.$extension"
		make_wallpaper_image "$format" "$image" || return 1
		digest=$(wallpaper_digest "$image") || return 1
		run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$image"
		assert_eq 0 "$COMMAND_STATUS" "$format should be accepted" || return 1
		output=$COMMAND_OUTPUT
		assert_contains "$output" "Format: $format" "$format should be detected from content" || return 1
		assert_contains "$output" "Canonical extension: $extension" "$format should report its canonical extension" || return 1
		assert_contains "$output" "SHA-256: $digest" "$format should retain exact-byte identity" || return 1
		assert_contains "$output" 'Dimensions: 4x3' "$format should require positive dimensions" || return 1
	done
}

test_validator_rejects_unsupported_corrupt_and_symlink_images() {
	new_fixture
	setup_wallpaper_fixture
	local unsupported="$FIXTURE_REPO/wallpapers/inbox/unsupported.tiff"
	local corrupt="$FIXTURE_REPO/wallpapers/inbox/corrupt.png"
	local link="$FIXTURE_REPO/wallpapers/inbox/link.png"
	make_wallpaper_image TIFF "$unsupported" || return 1
	printf '\211PNG\r\n\032\ntruncated' >"$corrupt"
	ln -s "$corrupt" "$link"

	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$unsupported"
	assert_eq 1 "$COMMAND_STATUS" 'unsupported image content should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unsupported image format' 'unsupported format should be explained' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$corrupt"
	assert_eq 1 "$COMMAND_STATUS" 'truncated image data should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ImageMagick' 'decode rejection should name its authority' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$link"
	assert_eq 1 "$COMMAND_STATUS" 'image symlinks should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'regular non-symlink file' 'unsafe type should be explained'
}

test_library_enforces_safe_slugs_names_formats_and_equal_duplicates() {
	new_fixture
	setup_wallpaper_fixture
	local image="$FIXTURE_REPO/wallpapers/inbox/source.png" digest first second
	make_wallpaper_image PNG "$image" || return 1
	digest=$(wallpaper_digest "$image") || return 1
	first=$(assign_wallpaper_fixture "$image" tokyo-night png) || return 1
	second=$(assign_wallpaper_fixture "$image" catppuccin png) || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_library
	assert_eq 0 "$COMMAND_STATUS" 'equal duplicate assignments should form one valid managed wallpaper' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Managed wallpapers: 1' 'library should count identities once' || return 1
	assert_contains "$COMMAND_OUTPUT" 'Theme assignments: 2' 'library should count both assignments' || return 1

	mv "$second" "${second%/*}/$(printf '0%.0s' {1..64}).png"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_library
	assert_eq 1 "$COMMAND_STATUS" 'a digest/name mismatch should invalidate the complete library' || return 1
	assert_contains "$COMMAND_OUTPUT" 'filename digest does not match exact bytes' 'digest mismatch should be explicit' || return 1
	mv "${second%/*}/$(printf '0%.0s' {1..64}).png" "$second"
	mkdir "$FIXTURE_REPO/wallpapers/library/.hidden"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_library
	assert_eq 1 "$COMMAND_STATUS" 'dot-prefixed theme slugs should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'unsafe theme slug' 'unsafe slug should be explicit' || return 1
	rmdir "$FIXTURE_REPO/wallpapers/library/.hidden"

	make_wallpaper_image PNG "$first" '#bb3355' || return 1
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_library
	assert_eq 1 "$COMMAND_STATUS" 'changed assignment bytes should invalidate the library' || return 1
	assert_contains "$COMMAND_OUTPUT" 'filename digest does not match exact bytes' 'changed exact bytes should be detected'
}

test_library_rejects_non_regular_entries_and_noncanonical_extensions() {
	new_fixture
	setup_wallpaper_fixture
	local image="$FIXTURE_REPO/wallpapers/inbox/source.jpeg" digest target
	make_wallpaper_image JPEG "$image" || return 1
	digest=$(wallpaper_digest "$image") || return 1
	mkdir -p "$FIXTURE_REPO/wallpapers/library/rose-pine"
	target="$FIXTURE_REPO/wallpapers/library/rose-pine/$digest.jpeg"
	cp "$image" "$target"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_library
	assert_eq 1 "$COMMAND_STATUS" 'JPEG assignments must use canonical jpg extension' || return 1
	assert_contains "$COMMAND_OUTPUT" 'canonical extension' 'noncanonical extension should be explained' || return 1
	rm "$target"
	ln -s "$image" "$FIXTURE_REPO/wallpapers/library/rose-pine/$digest.jpg"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_library
	assert_eq 1 "$COMMAND_STATUS" 'library symlinks should be rejected' || return 1
	assert_contains "$COMMAND_OUTPUT" 'regular non-symlink files' 'library type rejection should be explicit'
}

test_validator_rejects_hard_linked_intake_and_library_files() {
	new_fixture
	setup_wallpaper_fixture
	local original="$FIXTURE_REPO/wallpapers/inbox/original.png" linked="$FIXTURE_REPO/wallpapers/inbox/linked.png" digest assignment
	make_wallpaper_image PNG "$original" || return 1
	ln "$original" "$linked"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$linked"
	assert_eq 1 "$COMMAND_STATUS" 'hard-linked Intake must not be accepted as independently owned input' || return 1
	assert_contains "$COMMAND_OUTPUT" 'hard link' 'hard-linked Intake rejection should be explicit' || return 1
	digest=$(wallpaper_digest "$original") || return 1
	mkdir "$FIXTURE_REPO/wallpapers/library/catppuccin"
	assignment="$FIXTURE_REPO/wallpapers/library/catppuccin/$digest.png"
	ln "$original" "$assignment"
	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_library
	assert_eq 1 "$COMMAND_STATUS" 'hard-linked library assignment must fail complete validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'hard link' 'hard-linked assignment rejection should be explicit'
}

test_validator_decodes_stable_snapshot_when_source_changes_during_imagemagick() {
	new_fixture
	setup_wallpaper_fixture
	local source="$FIXTURE_REPO/wallpapers/inbox/source.png" replacement="$FIXTURE_REPO/wallpapers/inbox/replacement.png"
	make_wallpaper_image PNG "$source" '#224466' || return 1
	printf 'substituted invalid image\n' >"$replacement"
	rm "$FIXTURE_BIN/magick"
	make_fake magick 'marker=$TMPDIR/wallpaper-image-race
if [[ ! -e $marker ]]; then
	: >"$marker"
	cp -- "$DOTFILES_TEST_WALLPAPER_IMAGE_RACE_REPLACEMENT" "$DOTFILES_TEST_WALLPAPER_IMAGE_RACE_PATH"
fi
exec "$DOTFILES_TEST_REAL_MAGICK" "$@"'
	DOTFILES_TEST_WALLPAPER_IMAGE_RACE_PATH=$source DOTFILES_TEST_WALLPAPER_IMAGE_RACE_REPLACEMENT=$replacement \
		run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$source"
	assert_eq 1 "$COMMAND_STATUS" 'source replacement during ImageMagick should fail validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'image changed during validation' 'ImageMagick should decode the stable original snapshot before source identity rejection'
}

test_validator_rejects_warning_diagnostics_without_mutation() {
	local phase source before expected
	for phase in identify decode; do
		new_fixture
		setup_wallpaper_fixture
		source="$FIXTURE_REPO/wallpapers/inbox/diagnostic-$phase.png"
		printf 'stable image bytes for %s diagnostics\n' "$phase" >"$source"
		before=$(sha256sum "$source")
		configure_fake_wallpaper_magick
		if [[ $phase == identify ]]; then
			set_fake_wallpaper_magick_response $'PNG|4|3\n' $'identify warning\n' 0 '' 0
			expected='ImageMagick emitted diagnostics while identifying image data: identify warning'
		else
			set_fake_wallpaper_magick_response $'PNG|4|3\n' '' 0 $'decode warning\n' 0
			expected='ImageMagick emitted diagnostics during complete decode: decode warning'
		fi

		run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$source"

		assert_eq 1 "$COMMAND_STATUS" "$phase warnings should reject otherwise successful ImageMagick output" || return 1
		assert_contains "$COMMAND_OUTPUT" "$expected" "$phase diagnostics should remain observable" || return 1
		if [[ $COMMAND_OUTPUT == *'Wallpaper image: valid'* ]]; then
			printf '  validator accepted warning-producing %s output\n' "$phase" >&2
			return 1
		fi
		assert_eq "$before" "$(sha256sum "$source")" "$phase diagnostics must not mutate the source image" || return 1
		if find "$FIXTURE_TMP" -mindepth 1 -print -quit | grep -q .; then
			printf '  validator retained an ImageMagick snapshot after %s diagnostics\n' "$phase" >&2
			return 1
		fi
	done
}

test_validator_rejects_invalid_and_zero_dimensions_without_mutation() {
	local dimensions source before
	for dimensions in 'PNG|0|3' 'PNG|width|3'; do
		new_fixture
		setup_wallpaper_fixture
		source="$FIXTURE_REPO/wallpapers/inbox/invalid-dimensions.png"
		printf 'stable image bytes for invalid dimensions\n' >"$source"
		before=$(sha256sum "$source")
		configure_fake_wallpaper_magick
		set_fake_wallpaper_magick_response "$dimensions"$'\n' '' 0 '' 0

		run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$source"

		assert_eq 1 "$COMMAND_STATUS" "ImageMagick dimensions $dimensions should be rejected" || return 1
		assert_contains "$COMMAND_OUTPUT" 'ImageMagick returned invalid or zero image dimensions' \
			'invalid and zero dimensions should have one explicit rejection' || return 1
		assert_eq "$before" "$(sha256sum "$source")" 'dimension rejection must not mutate the source image' || return 1
	done
}

test_validator_rejects_partial_multiframe_decode_without_mutation() {
	new_fixture
	setup_wallpaper_fixture
	local source="$FIXTURE_REPO/wallpapers/inbox/partial-animation.gif" before
	printf 'stable multi-frame image bytes\n' >"$source"
	before=$(sha256sum "$source")
	configure_fake_wallpaper_magick
	set_fake_wallpaper_magick_response $'GIF|4|3\nGIF|4|3\n' '' 0 \
		$'unexpected end of image data while decoding frame 2\n' 9

	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_image "$source"

	assert_eq 1 "$COMMAND_STATUS" 'a partial multi-frame decode should fail validation' || return 1
	assert_contains "$COMMAND_OUTPUT" 'ImageMagick could not completely decode all image data: unexpected end of image data while decoding frame 2' \
		'the failed frame decode should remain observable' || return 1
	assert_contains "$(<"$CALL_LOG")" '-coalesce null:' \
		'the validator should request complete coalesced decoding of all identified frames' || return 1
	if [[ $COMMAND_OUTPUT == *'Frames: 2'* || $COMMAND_OUTPUT == *'Wallpaper image: valid'* ]]; then
		printf '  validator accepted a partially decoded multi-frame image\n' >&2
		return 1
	fi
	assert_eq "$before" "$(sha256sum "$source")" 'failed multi-frame decode must not mutate the source image'
}

test_library_rejects_same_digest_byte_collision_without_mutation() {
	new_fixture
	setup_wallpaper_fixture
	local digest first second before_first before_second
	digest=$(printf '0%.0s' {1..64})
	mkdir -p "$FIXTURE_REPO/wallpapers/library/one" "$FIXTURE_REPO/wallpapers/library/two"
	first="$FIXTURE_REPO/wallpapers/library/one/$digest.png"
	second="$FIXTURE_REPO/wallpapers/library/two/$digest.png"
	printf 'first collision candidate\n' >"$first"
	printf 'different collision candidate bytes\n' >"$second"
	before_first=$(sha256sum "$first")
	before_second=$(sha256sum "$second")
	cat >>"$FIXTURE_REPO/lib/dotfiles/wizard.sh" <<'EOF'
validate_wallpaper_collision_fixture() {
	wallpaper_validate_image_quiet() {
		WALLPAPER_IMAGE_EXTENSION=png
		WALLPAPER_IMAGE_DIGEST=0000000000000000000000000000000000000000000000000000000000000000
		return 0
	}
	validate_wallpaper_library
}
EOF

	run_wallpaper_operation "$FIXTURE_ROOT" validate_wallpaper_collision_fixture

	assert_eq 1 "$COMMAND_STATUS" 'different bytes forced to the same digest should fail closed' || return 1
	assert_contains "$COMMAND_OUTPUT" 'fatal SHA-256 collision; equal digests have different bytes' \
		'the library should explicitly report the impossible content-identity collision' || return 1
	assert_contains "$COMMAND_OUTPUT" "$first and $second" 'collision output should identify both assignments' || return 1
	assert_eq "$before_first" "$(sha256sum "$first")" 'collision handling must not mutate the first assignment' || return 1
	assert_eq "$before_second" "$(sha256sum "$second")" 'collision handling must not mutate the second assignment'
}

run_test test_validator_accepts_all_supported_exact_byte_formats 'wallpaper image validator accepts every canonical supported format'
run_test test_validator_rejects_unsupported_corrupt_and_symlink_images 'wallpaper image validator rejects unsafe or undecodable input'
run_test test_library_enforces_safe_slugs_names_formats_and_equal_duplicates 'wallpaper library validates exact-byte identity across assignments'
run_test test_library_rejects_non_regular_entries_and_noncanonical_extensions 'wallpaper library rejects unsafe types and noncanonical names'
run_test test_validator_rejects_hard_linked_intake_and_library_files 'validators reject hard-linked wallpaper ownership'
run_test test_validator_decodes_stable_snapshot_when_source_changes_during_imagemagick 'ImageMagick decodes a stable no-follow image snapshot'
run_test test_validator_rejects_warning_diagnostics_without_mutation 'wallpaper image validator rejects warning diagnostics without mutation'
run_test test_validator_rejects_invalid_and_zero_dimensions_without_mutation 'wallpaper image validator rejects invalid and zero dimensions without mutation'
run_test test_validator_rejects_partial_multiframe_decode_without_mutation 'wallpaper image validator rejects partial multi-frame decode without mutation'
run_test test_library_rejects_same_digest_byte_collision_without_mutation 'Wallpaper library rejects same-digest byte collisions without mutation'
finish_tests
