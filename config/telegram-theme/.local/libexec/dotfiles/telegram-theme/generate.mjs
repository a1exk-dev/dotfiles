#!/usr/bin/env node

import { spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import {
	chmodSync,
	closeSync,
	constants,
	fsyncSync,
	linkSync,
	lstatSync,
	mkdirSync,
	mkdtempSync,
	openSync,
	readFileSync,
	renameSync,
	rmSync,
	utimesSync,
	writeFileSync,
} from 'node:fs';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync, inflateRawSync, inflateSync } from 'node:zlib';

const SCHEMA_VERSION = 1;
const COLOR_KEYS = [
	'accent', 'selection', 'muted',
	'background', 'dark_background', 'darker_background', 'lighter_background',
	'foreground', 'dark_foreground', 'light_foreground', 'bright_foreground',
	'red', 'yellow', 'green', 'cyan', 'blue', 'magenta',
	'bright_red', 'bright_yellow', 'bright_green', 'bright_cyan', 'bright_blue', 'bright_magenta',
];
const EXPECTED_ROLE_COUNT = 586;
const EXPECTED_ROLE_ORDER_SHA256 = 'f28bcceba0ab9c945292e07eaac4b62d4b88162203b7a22195c7550251ca66d7';
const EXPECTED_BASELINE_SHA256 = '4926b89ed166038510ea9fde1a2c8414139f995cb3bba7f00150d880bfe403cb';
const MEMBERS = ['colors.tdesktop-theme', 'background.png'];
const MAX_THEME = 5 * 1024 * 1024;
const MAX_PALETTE = 1024 * 1024;
const MAX_BACKGROUND = 4 * 1024 * 1024;
const MAX_PIXELS = 25_000_000;
const CONTRAST_THRESHOLD = 4.5;
const PRIMARY_DISTANCE_THRESHOLD = 0.025;
const NORMALIZED_TIME = new Date('2000-01-01T00:00:00.000Z');
const BASELINE_PATH = fileURLToPath(new URL('./data/telegram-7.0.9-night.palette', import.meta.url));

const CONTRAST_PAIRS = [
	['windowFg', 'windowBg'], ['windowSubTextFg', 'windowBg'], ['windowBoldFg', 'windowBg'],
	['windowFgOver', 'windowBgOver'], ['windowSubTextFgOver', 'windowBgOver'], ['windowBoldFgOver', 'windowBgOver'],
	['windowFgActive', 'windowBgActive'], ['windowFg', 'menuBg'], ['windowFgOver', 'menuBgOver'],
	['boxTextFg', 'boxBg'], ['windowFg', 'filterInputActiveBg'], ['windowSubTextFg', 'filterInputInactiveBg'],
	['activeButtonFg', 'activeButtonBg'], ['historyComposeAreaFgService', 'historyComposeAreaBg'],
	['lightButtonFg', 'lightButtonBg'], ['lightButtonFgOver', 'lightButtonBgOver'],
	['dialogsNameFg', 'dialogsBg'], ['dialogsTextFg', 'dialogsBg'], ['dialogsTextFgService', 'dialogsBg'],
	['dialogsDateFg', 'dialogsBg'], ['dialogsNameFgOver', 'dialogsBgOver'], ['dialogsTextFgOver', 'dialogsBgOver'],
	['dialogsTextFgServiceOver', 'dialogsBgOver'], ['dialogsDateFgOver', 'dialogsBgOver'],
	['dialogsNameFgActive', 'dialogsBgActive'], ['dialogsTextFgActive', 'dialogsBgActive'],
	['dialogsTextFgServiceActive', 'dialogsBgActive'], ['dialogsDateFgActive', 'dialogsBgActive'],
	['dialogsUnreadFg', 'dialogsUnreadBg'], ['dialogsUnreadFgOver', 'dialogsUnreadBgOver'],
	['dialogsUnreadFgActive', 'dialogsUnreadBgActive'], ['dialogsVerifiedIconFg', 'dialogsVerifiedIconBg'],
	['dialogsVerifiedIconFgOver', 'dialogsVerifiedIconBgOver'],
	['dialogsVerifiedIconFgActive', 'dialogsVerifiedIconBgActive'],
	['historyTextInFg', 'msgInBg'], ['historyTextOutFg', 'msgOutBg'],
	['historyTextInFgSelected', 'msgInBgSelected'], ['historyTextOutFgSelected', 'msgOutBgSelected'],
	['historyLinkInFg', 'msgInBg'], ['historyLinkOutFg', 'msgOutBg'],
	['historyLinkInFgSelected', 'msgInBgSelected'], ['historyLinkOutFgSelected', 'msgOutBgSelected'],
	['msgInDateFg', 'msgInBg'], ['msgOutDateFg', 'msgOutBg'],
	['msgInDateFgSelected', 'msgInBgSelected'], ['msgOutDateFgSelected', 'msgOutBgSelected'],
	['historyFileNameInFg', 'msgInBg'], ['historyFileNameOutFg', 'msgOutBg'],
	['historyComposeAreaFg', 'historyComposeAreaBg'], ['historyUnreadBarFg', 'historyUnreadBarBg'],
];

const DISTINCT_ROLE_PAIRS = [
	['dialogsBg', 'dialogsBgActive'],
	['dialogsBgOver', 'dialogsBgActive'],
	['msgInBg', 'msgOutBg'],
	['msgInBg', 'msgInBgSelected'],
	['msgOutBg', 'msgOutBgSelected'],
];

const DISTINCT_STATE_COMPARISONS = [
	['dialogs read-row normal/hover', [
		'dialogsBg', 'dialogsNameFg', 'dialogsChatIconFg', 'dialogsDateFg', 'dialogsTextFg', 'dialogsTextFgService',
		'dialogsVerifiedIconBg', 'dialogsVerifiedIconFg', 'dialogsSendingIconFg', 'dialogsSentIconFg',
	], [
		'dialogsBgOver', 'dialogsNameFgOver', 'dialogsChatIconFgOver', 'dialogsDateFgOver', 'dialogsTextFgOver',
		'dialogsTextFgServiceOver', 'dialogsVerifiedIconBgOver', 'dialogsVerifiedIconFgOver',
		'dialogsSendingIconFgOver', 'dialogsSentIconFgOver',
	]],
	['dialogs unread normal/hover',
		['dialogsUnreadBg', 'dialogsUnreadBgMuted', 'dialogsUnreadFg'],
		['dialogsUnreadBgOver', 'dialogsUnreadBgMutedOver', 'dialogsUnreadFgOver']],
	['dialogs hover/active', ['dialogsBgOver', 'dialogsUnreadBgOver', 'dialogsUnreadFgOver'], ['dialogsBgActive', 'dialogsUnreadBgActive', 'dialogsUnreadFgActive']],
	['dialogs normal/active', ['dialogsBg', 'dialogsUnreadBg', 'dialogsUnreadFg'], ['dialogsBgActive', 'dialogsUnreadBgActive', 'dialogsUnreadFgActive']],
	['incoming/outgoing messages', ['msgInBg', 'historyTextInFg'], ['msgOutBg', 'historyTextOutFg']],
	['incoming normal/selected messages', ['msgInBg', 'historyTextInFg'], ['msgInBgSelected', 'historyTextInFgSelected']],
	['outgoing normal/selected messages', ['msgOutBg', 'historyTextOutFg'], ['msgOutBgSelected', 'historyTextOutFgSelected']],
];

const EXCEPTIONS = {
	menuBg: 'surface', filterInputInactiveBg: 'surface_recessed', titleBgActive: 'surface', boxDividerBg: 'surface_deep',
	searchedBarBg: 'surface_recessed', topBarBg: 'surface', emojiPanBg: 'surface', emojiPanCategories: 'surface_recessed',
	emojiPanHeaderBg: 'surface@f2', historyUnreadBarBg: 'surface', historyToDownBg: 'surface',
	historyComposeAreaBg: 'surface', historyPinnedBg: 'surface_recessed', historyReplyBg: 'surface',
	historyComposeButtonBg: 'surface', mainMenuBg: 'surface', mediaPlayerBg: 'surface', sideBarBgActive: 'surface',
	windowShadowFgFallback: 'edge', shadowFg: 'surface_deep@cc', slideFadeOutShadowFg: 'edge', menuSeparatorFg: 'edge',
	inputBorderFg: 'edge', tooltipBorderFg: 'edge', titleShadow: 'edge', boxDividerFg: 'edge',
	historyUnreadBarBorder: 'edge', msgInShadow: 'surface_deep@cc', msgInShadowSelected: 'surface_deep@cc',
	msgOutShadow: 'surface_deep@cc', msgOutShadowSelected: 'surface_deep@cc', historyToDownShadow: 'surface_deep@cc',
	windowBgOver: 'hover_surface', windowBgRipple: 'edge', lightButtonBgOver: 'hover_surface', lightButtonBgRipple: 'edge',
	menuBgOver: 'hover_surface', menuBgRipple: 'edge', contactsBgOver: 'hover_surface', dialogsBgOver: 'hover_surface',
	dialogsDraftFgOver: 'hover_warning', dialogsVerifiedIconBgOver: 'accent', dialogsVerifiedIconFgOver: 'surface_deep',
	dialogsUnreadBgOver: 'surface_deep', dialogsUnreadBgMutedOver: 'surface_deep', dialogsScamFgOver: 'hover_warning',
	dialogsRippleBg: 'edge', historyToDownBgOver: 'hover_surface', historyToDownBgRipple: 'edge',
	historyComposeButtonBgOver: 'hover_surface', historyComposeButtonBgRipple: 'edge', mediaviewMenuBgOver: 'hover_surface',
	mediaviewMenuBgRipple: 'edge', sideBarBgRipple: 'edge', dialogsBgActive: 'active_surface',
	dialogsNameFgActive: 'active_text', dialogsChatIconFgActive: 'active_text', dialogsDateFgActive: 'active_text',
	dialogsTextFgActive: 'active_text', dialogsTextFgServiceActive: 'active_text', dialogsDraftFgActive: 'hover_surface',
	dialogsVerifiedIconBgActive: 'hover_surface', dialogsVerifiedIconFgActive: 'active_surface',
	dialogsSendingIconFgActive: 'edge', dialogsSentIconFgActive: 'active_text', dialogsUnreadBgActive: 'hover_surface',
	dialogsUnreadBgMutedActive: 'edge', dialogsUnreadFgActive: 'active_surface', dialogsOnlineBadgeFgActive: 'hover_surface',
	dialogsScamFgActive: 'hover_surface', dialogsRippleBgActive: 'active_ripple', msgInBg: 'surface_recessed',
	msgInBgSelected: 'message_selected', msgOutBg: 'message_out_surface', msgOutBgSelected: 'message_selected',
	historyLinkInFgSelected: 'selected_text', historyLinkOutFg: 'message_link',
	historyLinkOutFgSelected: 'selected_text', historyOutIconFg: 'message_status',
	historySendingOutIconFg: 'message_status', historyCallArrowOutFg: 'message_status',
	msgInDateFgSelected: 'selected_text', msgOutDateFg: 'message_status', msgOutDateFgSelected: 'selected_text',
	msgOutReplyBarColor: 'message_status', msgInMonoFgSelected: 'selected_text',
	msgOutMonoFgSelected: 'selected_text', msgFileThumbLinkInFgSelected: 'selected_text',
	msgFileThumbLinkOutFg: 'message_link', msgFileThumbLinkOutFgSelected: 'selected_text',
};

function fail(message) {
	throw new Error(message);
}

function rejectPublication(message) {
	const error = new Error(message);
	error.preserveStatus = true;
	throw error;
}

function preserveStatusError(error, message = error instanceof Error ? error.message : String(error)) {
	const preserved = error instanceof Error ? error : new Error(message);
	preserved.message = message;
	preserved.preserveStatus = true;
	return preserved;
}

function sha256(data) {
	return createHash('sha256').update(data).digest('hex');
}

function parseArguments(values) {
	const result = {};
	for (let index = 0; index < values.length; index += 2) {
		const key = values[index];
		const value = values[index + 1];
		if (!['--manifest', '--output', '--status', '--guard'].includes(key) || value === undefined || result[key]) {
			fail('usage: node generate.mjs --manifest PATH --output PATH [--status PATH] [--guard SLUG:ACTIVE_THEME_NAME_PATH]');
		}
		result[key] = value;
	}
	if (!result['--manifest'] || !result['--output']) {
		fail('usage: node generate.mjs --manifest PATH --output PATH [--status PATH] [--guard SLUG:ACTIVE_THEME_NAME_PATH]');
	}
	if (result['--status'] && resolve(result['--status']) === resolve(result['--output'])) fail('--status and --output must differ');
	return result;
}

function parseGuard(value, manifestSlug) {
	if (!value) return undefined;
	const match = value.match(/^([A-Za-z0-9][A-Za-z0-9._-]*):(.*)$/s);
	if (!match || !isAbsolute(match[2])) fail('--guard must be SLUG:ABSOLUTE_ACTIVE_THEME_NAME_PATH');
	if (match[1] !== manifestSlug) fail('--guard slug must match manifest.slug');
	return { slug: match[1], path: match[2] };
}

function guardIsCurrent(guard) {
	try {
		return readFileSync(guard.path, 'utf8').replace(/\r?\n$/, '') === guard.slug;
	} catch {
		return false;
	}
}

function exactKeys(value, expected, location) {
	if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${location} must be an object`);
	const actual = Object.keys(value).sort();
	const wanted = [...expected].sort();
	if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
		fail(`${location} must contain exactly: ${wanted.join(', ')}`);
	}
}

function readManifest(path) {
	let manifest;
	try {
		manifest = JSON.parse(readFileSync(path, 'utf8'));
	} catch (error) {
		fail(`could not read manifest: ${error.message}`);
	}
	exactKeys(manifest, ['schema_version', 'slug', 'mode', 'colors'], 'manifest');
	if (manifest.schema_version !== SCHEMA_VERSION) fail(`manifest.schema_version must be ${SCHEMA_VERSION}`);
	if (typeof manifest.slug !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(manifest.slug)) {
		fail('manifest.slug must be a nonempty safe slug');
	}
	if (!['dark', 'light'].includes(manifest.mode)) fail('manifest.mode must be dark or light');
	exactKeys(manifest.colors, COLOR_KEYS, 'manifest.colors');
	for (const key of COLOR_KEYS) {
		if (typeof manifest.colors[key] !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(manifest.colors[key])) {
			fail(`manifest.colors.${key} must be #RRGGBB`);
		}
		manifest.colors[key] = manifest.colors[key].toLowerCase();
	}
	return manifest;
}

function parseBaseline() {
	const source = readFileSync(BASELINE_PATH);
	if (sha256(source) !== EXPECTED_BASELINE_SHA256) fail('pinned Telegram 7.0.9 Night baseline changed');
	const rows = [];
	const seen = new Set();
	for (const raw of source.toString('utf8').split(/\r?\n/)) {
		const line = raw.replace(/\/\/.*$/, '').trim();
		if (!line) continue;
		const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(#[0-9a-f]{6}(?:[0-9a-f]{2})?);$/);
		if (!match) fail(`invalid pinned baseline row: ${raw}`);
		if (seen.has(match[1])) fail(`duplicate pinned role: ${match[1]}`);
		seen.add(match[1]);
		rows.push([match[1], match[2]]);
	}
	if (rows.length !== EXPECTED_ROLE_COUNT) fail(`pinned baseline must contain ${EXPECTED_ROLE_COUNT} roles`);
	const order = `${rows.map(([name]) => name).join('\n')}\n`;
	if (sha256(order) !== EXPECTED_ROLE_ORDER_SHA256) fail('pinned Telegram role order changed');
	return rows;
}

function rgb(value) {
	return value.slice(1, 7).match(/../g).map((channel) => Number.parseInt(channel, 16));
}

function withBaselineAlpha(value, baseline) {
	return baseline.length === 9 ? `${value}${baseline.slice(7)}` : value;
}

function luminance(value) {
	const channels = rgb(value).map((channel) => {
		const normalized = channel / 255;
		return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
	});
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrast(left, right) {
	const [bright, dark] = [luminance(left), luminance(right)].sort((a, b) => b - a);
	return (bright + 0.05) / (dark + 0.05);
}

function oklab(value) {
	const [red, green, blue] = rgb(value).map((channel) => {
		const normalized = channel / 255;
		return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
	});
	const l = Math.cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue);
	const m = Math.cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue);
	const s = Math.cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue);
	return [
		0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
	];
}

function oklabDistance(left, right) {
	const a = oklab(left);
	const b = oklab(right);
	return Math.hypot(...a.map((channel, index) => channel - b[index]));
}

const COMMENT_FAMILIES = {
	error: new Set([
		'msgFile1Bg', 'msgFile1BgDark', 'msgFile1BgOver', 'msgFile1BgSelected',
		'msgFile2Bg', 'msgFile2BgDark', 'msgFile2BgOver', 'msgFile2BgSelected',
		'msgFile3Bg', 'msgFile3BgDark', 'msgFile3BgOver', 'msgFile3BgSelected',
		'msgFile4Bg', 'msgFile4BgDark', 'msgFile4BgOver', 'msgFile4BgSelected',
		'overviewCheckBg', 'overviewCheckBgActive', 'overviewCheckBorder', 'overviewCheckFgActive',
		'overviewPhotoSelectOverlay', 'mediaviewFileRedCornerFg', 'statisticsChartLineRed',
	]),
	success: new Set(['mediaviewFileGreenCornerFg', 'statisticsChartLineGreen', 'statisticsChartLineLightgreen']),
	warning: new Set(),
	magenta: new Set(['msgBotKbIconFg']),
	cyan: new Set(),
	accent: new Set(['mediaviewFileBlueCornerFg', 'statisticsChartLineBlue', 'statisticsChartLineLightblue']),
};

const COMMENT_FOREGROUNDS = new Set([
	'botKbColor', 'botKbInlinePrimaryBg', 'botKbInlineDangerBg', 'botKbInlineSuccessBg',
	'trayCounterBgMacInvert', 'paymentsTipActive', 'dialogsVerifiedIconBgOver', 'stickerPanPremium1',
	'stickerPanPremium2', 'msgImgReplyBarColor', 'msgDateImgBg', 'msgDateImgBgOver',
	'msgWaveformInActive', 'msgWaveformInActiveSelected', 'msgWaveformInInactive',
	'msgWaveformInInactiveSelected', 'msgWaveformOutActive', 'msgWaveformOutActiveSelected',
	'msgWaveformOutInactive', 'msgWaveformOutInactiveSelected', 'msgBotKbOverBgAdd', 'msgBotKbRippleBg',
	'overviewCheckBorder', 'callIconActiveRipple', 'walletTopIconRipple', 'premiumIconBg1',
	'premiumIconBg2', 'premiumIconBg3',
]);

const SPECIAL_SECTION_BACKGROUNDS = new Set([
	'dialogsUnreadBgOver', 'dialogsUnreadBgMutedOver', 'msgDateImgBg', 'msgDateImgBgOver',
	'msgDateImgBgSelected', 'msgFileInBg', 'msgFileInBgOver', 'msgFileInBgSelected',
	'msgFileOutBg', 'msgFileOutBgSelected', 'msgBotKbOverBgAdd',
]);

function colorValue(channels) {
	return `#${channels.map((channel) => channel.toString(16).padStart(2, '0')).join('')}`;
}

function alphaColor(value, opacity) {
	return colorValue([...rgb(value), opacity]);
}

function pythonRound(value) {
	const lower = Math.floor(value);
	const fraction = value - lower;
	if (fraction < 0.5) return lower;
	if (fraction > 0.5) return lower + 1;
	return lower % 2 === 0 ? lower : lower + 1;
}

function mix(left, right, rightWeight) {
	const a = rgb(left);
	const b = rgb(right);
	return colorValue(a.map((channel, index) => pythonRound(channel * (1 - rightWeight) + b[index] * rightWeight)));
}

function buildV1Tokens(colors) {
	const background = colors.background;
	const selection = colors.selection;
	return {
		bg0: colors.darker_background,
		bg1: colors.dark_background,
		bg2: background,
		raised: mix(background, selection, 0.12),
		hover: mix(background, selection, 0.28),
		pressed: mix(background, selection, 0.48),
		selected: selection,
		fg: colors.foreground,
		bold: colors.light_foreground,
		secondary: colors.bright_foreground,
		muted: colors.accent,
		disabled: colors.dark_foreground,
		accent: colors.accent,
		accent_dim: colors.bright_blue,
		error: colors.bright_red,
		warning: colors.bright_yellow,
		success: colors.green,
		yellow: colors.yellow,
		cyan: colors.cyan,
		magenta: colors.magenta,
		magenta_dim: colors.bright_magenta,
	};
}

function explicitV1Roles(t) {
	const { bg0, bg1, bg2, fg, secondary, muted, disabled, accent, selected, hover, pressed, error, warning, success } = t;
	const values = {
		windowBg: bg2, windowFg: fg, windowBgOver: hover, windowBgRipple: pressed,
		windowFgOver: t.bold, windowSubTextFg: secondary, windowSubTextFgOver: fg,
		windowBoldFg: t.bold, windowBoldFgOver: fg, windowBgActive: selected, windowFgActive: fg,
		windowActiveTextFg: accent, windowShadowFg: bg0, windowShadowFgFallback: bg1,
		shadowFg: alphaColor(bg0, 0x80), slideFadeOutBg: alphaColor(bg0, 0x80),
		slideFadeOutShadowFg: bg0, imageBg: '#000000', imageBgTransparent: '#ffffff',
		activeButtonBg: selected, activeButtonBgOver: mix(selected, accent, 0.18), activeButtonBgRipple: disabled,
		activeButtonFg: fg, activeButtonFgOver: fg, activeButtonSecondaryFg: secondary,
		activeButtonSecondaryFgOver: fg, activeLineFg: accent, activeLineFgError: error,
		lightButtonBg: bg2, lightButtonBgOver: hover, lightButtonBgRipple: pressed,
		lightButtonFg: accent, lightButtonFgOver: secondary, attentionButtonFg: error,
		attentionButtonFgOver: error, attentionButtonBgOver: alphaColor(error, 0x24),
		attentionButtonBgRipple: alphaColor(error, 0x38), menuBg: bg1, menuBgOver: hover,
		menuBgRipple: pressed, menuIconFg: muted, menuIconFgOver: secondary, menuSubmenuArrowFg: muted,
		menuFgDisabled: disabled, menuSeparatorFg: selected, scrollBarBg: alphaColor(muted, 0x53),
		scrollBarBgOver: alphaColor(muted, 0x7a), scrollBg: alphaColor(disabled, 0x1a),
		scrollBgOver: alphaColor(disabled, 0x2c), smallCloseIconFg: disabled,
		smallCloseIconFgOver: secondary, radialFg: fg, radialBg: alphaColor(bg0, 0x70),
		placeholderFg: muted, placeholderFgActive: secondary, inputBorderFg: selected,
		filterInputBorderFg: accent, filterInputActiveBg: bg2, filterInputInactiveBg: bg0,
		checkboxFg: t.accent_dim, sliderBgInactive: selected, sliderBgActive: accent,
		tooltipBg: bg0, tooltipFg: secondary, tooltipBorderFg: selected,
		titleShadow: alphaColor(bg0, 0x00), titleBg: bg0, titleBgActive: bg1, titleFg: muted,
		titleFgActive: secondary, trayCounterBg: accent, trayCounterBgMute: disabled,
		trayCounterFg: bg0, layerBg: alphaColor(bg0, 0xb8), cancelIconFg: muted,
		cancelIconFgOver: secondary, boxBg: bg2, boxTextFg: fg, boxTextFgGood: success,
		boxTextFgError: error, boxTitleFg: t.bold, boxSearchBg: bg1, boxTitleAdditionalFg: secondary,
		boxDividerBg: bg1, boxDividerFg: selected, contactsBg: bg2, contactsBgOver: hover,
		contactsNameFg: fg, contactsStatusFg: secondary, contactsStatusFgOver: fg,
		contactsStatusFgOnline: success, introBg: bg2, introTitleFg: t.bold,
		introDescriptionFg: secondary, introCoverTopBg: selected,
		introCoverBottomBg: mix(selected, accent, 0.24), introCoverIconsFg: accent,
		introCoverPlaneTrace: alphaColor(accent, 0x70), introCoverPlaneInner: secondary,
		introCoverPlaneOuter: muted, introCoverPlaneTop: fg,
		dialogsBg: bg1, dialogsNameFg: fg, dialogsChatIconFg: fg, dialogsDateFg: muted,
		dialogsTextFg: secondary, dialogsTextFgService: accent, dialogsDraftFg: error,
		dialogsVerifiedIconBg: accent, dialogsVerifiedIconFg: bg0, dialogsSendingIconFg: disabled,
		dialogsSentIconFg: accent, dialogsUnreadBg: accent, dialogsUnreadBgMuted: disabled,
		dialogsUnreadFg: bg0, dialogsOnlineBadgeFg: success, dialogsBgOver: hover,
		dialogsBgActive: selected, dialogsNameFgActive: fg, dialogsChatIconFgActive: fg,
		dialogsDateFgActive: secondary, dialogsTextFgActive: fg, dialogsTextFgServiceActive: fg,
		dialogsDraftFgActive: warning, dialogsVerifiedIconBgActive: fg,
		dialogsVerifiedIconFgActive: selected, dialogsSendingIconFgActive: secondary,
		dialogsSentIconFgActive: fg, dialogsUnreadBgActive: fg, dialogsUnreadBgMutedActive: secondary,
		dialogsUnreadFgActive: selected, dialogsOnlineBadgeFgActive: fg, dialogsRippleBg: pressed,
		dialogsRippleBgActive: disabled, searchedBarBg: bg0, searchedBarFg: muted,
		searchedTextMatchBg: warning, searchedTextMatchFg: bg0, searchedTextCurrentMatchBg: t.yellow,
		searchedTextCurrentMatchFg: bg0, topBarBg: bg1, emojiPanBg: bg1,
		emojiPanCategories: bg0, emojiPanHeaderFg: secondary, emojiPanHeaderBg: alphaColor(bg1, 0xf2),
		emojiIconFg: muted, emojiSubIconFgActive: secondary, stickerPanDeleteBg: alphaColor(bg0, 0xe0),
		stickerPanDeleteFg: fg, stickerPreviewBg: alphaColor(bg0, 0xd0), historyTextInFg: fg,
		historyTextInFgSelected: t.yellow, historyTextOutFg: fg, historyTextOutFgSelected: t.yellow,
		historyLinkInFg: accent, historyLinkInFgSelected: secondary, historyLinkOutFg: accent,
		historyLinkOutFgSelected: secondary, historyOutIconFg: accent, historyOutIconFgSelected: fg,
		historySendingOutIconFg: muted, historySendingInIconFg: muted, historyUnreadBarBg: bg1,
		historyUnreadBarBorder: alphaColor(bg0, 0x00), historyUnreadBarFg: secondary,
		historyForwardChooseBg: alphaColor(bg0, 0x80), historyForwardChooseFg: fg,
		historyScrollBarBg: alphaColor(muted, 0x7a), historyScrollBarBgOver: alphaColor(muted, 0xbc),
		historyScrollBg: alphaColor(disabled, 0x4c), historyScrollBgOver: alphaColor(disabled, 0x6b),
		msgInBg: bg2, msgInBgSelected: selected, msgOutBg: t.raised, msgOutBgSelected: selected,
		msgSelectOverlay: alphaColor(accent, 0x4c), msgStickerOverlay: alphaColor(accent, 0x7f),
		msgInServiceFg: accent, msgInServiceFgSelected: fg, msgOutServiceFg: secondary,
		msgOutServiceFgSelected: fg, msgInShadow: alphaColor(bg0, 0x00),
		msgInShadowSelected: alphaColor(bg0, 0x00), msgOutShadow: alphaColor(bg0, 0x00),
		msgOutShadowSelected: alphaColor(bg0, 0x00), msgInDateFg: muted,
		msgInDateFgSelected: secondary, msgOutDateFg: muted, msgOutDateFgSelected: secondary,
		msgServiceFg: fg, msgServiceBg: alphaColor(selected, 0xd5), msgServiceBgSelected: disabled,
		msgInReplyBarColor: accent, msgInReplyBarSelColor: secondary, msgOutReplyBarColor: muted,
		msgOutReplyBarSelColor: secondary, msgInMonoFg: secondary, msgOutMonoFg: secondary,
		msgInMonoFgSelected: fg, msgOutMonoFgSelected: fg, toastBg: alphaColor(bg0, 0xe8),
		toastFg: fg, historyToDownBg: bg1, historyToDownBgOver: hover,
		historyToDownBgRipple: pressed, historyToDownFg: muted, historyToDownFgOver: secondary,
		historyToDownShadow: alphaColor(bg0, 0x70), historyComposeAreaBg: bg1,
		historyComposeAreaFg: fg, historyComposeAreaFgService: muted, historyComposeIconFg: muted,
		historyComposeIconFgOver: secondary, historySendIconFg: accent, historySendIconFgOver: secondary,
		historyPinnedBg: bg0, historyReplyBg: bg1, historyReplyIconFg: accent,
		historyComposeButtonBg: bg1, historyComposeButtonBgOver: hover,
		historyComposeButtonBgRipple: pressed, mainMenuBg: bg1, mainMenuCoverBg: selected,
		mainMenuCloudFg: fg, mainMenuCloudBg: selected, mediaPlayerBg: bg1,
		mediaPlayerActiveFg: accent, mediaPlayerInactiveFg: selected, mediaPlayerDisabledFg: disabled,
		mediaviewFileBg: bg2, mediaviewFileNameFg: fg, mediaviewFileSizeFg: secondary,
		mediaviewMenuBg: bg1, mediaviewMenuBgOver: hover, mediaviewMenuBgRipple: pressed,
		mediaviewMenuFg: fg, mediaviewBg: alphaColor(bg0, 0xf2), mediaviewVideoBg: '#000000',
		mediaviewControlBg: alphaColor(bg0, 0x70), mediaviewControlFg: fg,
		mediaviewCaptionBg: alphaColor(bg0, 0xc0), mediaviewCaptionFg: fg,
		mediaviewTextLinkFg: accent, mediaviewTransparentBg: '#ffffff',
		mediaviewTransparentFg: '#cccccc', notificationBg: bg2, callBg: alphaColor(bg0, 0xf5),
		callBgOpaque: bg0, callBgButton: alphaColor(selected, 0x90), callNameFg: fg,
		callStatusFg: secondary, callIconBg: accent, callIconFg: bg0, callIconBgActive: fg,
		callIconFgActive: bg0, callAnswerBg: success, callAnswerRipple: t.accent_dim,
		callAnswerBgOuter: alphaColor(success, 0x26), callHangupBg: error,
		callHangupRipple: mix(error, bg0, 0.22), callMuteRipple: alphaColor(fg, 0x12),
		groupCallBg: bg0, groupCallActiveFg: accent, groupCallMembersBg: bg1,
		groupCallMembersBgOver: hover, groupCallMembersBgRipple: pressed, groupCallMembersFg: fg,
		groupCallMemberActiveIcon: success, groupCallMemberActiveStatus: success,
		groupCallMemberInactiveIcon: muted, groupCallMemberInactiveStatus: secondary,
		groupCallMemberMutedIcon: error, groupCallMemberNotJoinedStatus: muted, groupCallIconFg: fg,
		groupCallMenuBg: bg1, groupCallMenuBgOver: hover, groupCallMenuBgRipple: pressed,
		groupCallLeaveBg: alphaColor(error, 0x7f), groupCallLeaveBgRipple: alphaColor(error, 0x9e),
		groupCallVideoTextFg: fg, groupCallVideoSubTextFg: secondary, callBarBg: selected,
		callBarMuteRipple: pressed, callBarBgMuted: disabled, callBarFg: fg,
		importantTooltipBg: alphaColor(bg0, 0xe8), importantTooltipFg: fg,
		importantTooltipFgLink: accent, outdatedFg: bg0, outdateSoonBg: warning,
		outdatedBg: error, spellUnderline: error, sideBarBg: bg0, sideBarBgActive: bg1,
		sideBarBgRipple: pressed, sideBarTextFg: muted, sideBarTextFgActive: secondary,
		sideBarIconFg: muted, sideBarIconFgActive: accent, sideBarBadgeBg: accent,
		sideBarBadgeBgActive: accent, sideBarBadgeBgMuted: disabled, sideBarBadgeBgMutedActive: muted,
		sideBarBadgeFg: bg0, songCoverOverlayFg: alphaColor(bg0, 0x66),
		photoEditorItemBaseHandleFg: accent, statisticsChartInactive: alphaColor(selected, 0x99),
		statisticsChartActive: alphaColor(muted, 0xd8), rankAdminFg: success, rankOwnerFg: t.magenta,
		rankUserFg: secondary, dialogsMentionIconFg: accent, dialogsReactionIconFg: error,
		dialogsPollIconFg: t.magenta, mapPointDrop: error, mapPointDot: bg0,
		youtubePlayIconBg: alphaColor(error, 0xc8), youtubePlayIconFg: bg0,
		videoPlayIconBg: alphaColor(bg0, 0xb0), videoPlayIconFg: fg,
		profileVerifiedCheckBg: accent, profileVerifiedCheckFg: bg0, settingsIconFg: fg,
		premiumButtonBg1: selected, premiumButtonBg2: mix(selected, accent, 0.14),
		premiumButtonBg3: mix(selected, t.magenta, 0.10), premiumButtonFg: fg,
		creditsBg1: warning, creditsBg2: t.yellow, creditsBg3: t.muted, creditsFg: bg0,
		creditsStroke: t.accent_dim,
	};
	const peerNames = [error, success, warning, accent, t.magenta, t.bold, secondary, t.yellow];
	const peerPictures = [
		selected, disabled, t.accent_dim, mix(selected, accent, 0.18),
		mix(selected, t.magenta, 0.12), mix(selected, t.bold, 0.10),
		mix(selected, secondary, 0.08), mix(selected, warning, 0.08),
	];
	for (let index = 1; index <= 8; index += 1) {
		values[`historyPeer${index}NameFg`] = peerNames[index - 1];
		values[`historyPeer${index}NameFgSelected`] = fg;
		values[`historyPeer${index}UserpicBg`] = peerPictures[index - 1];
		values[`historyPeer${index}UserpicBg2`] = mix(peerPictures[index - 1], bg0, 0.18);
	}
	values.historyPeerUserpicFg = fg;
	values.historyPeerSavedMessagesBg = selected;
	values.historyPeerSavedMessagesBg2 = mix(selected, bg0, 0.18);
	values.historyPeerArchiveUserpicBg = disabled;
	const settings = [
		selected, disabled, t.accent_dim, mix(selected, accent, 0.18),
		mix(selected, t.magenta, 0.12), mix(selected, t.bold, 0.10),
	];
	for (let index = 1; index <= 6; index += 1) values[`settingsIconBg${index}`] = settings[index - 1];
	values.settingsIconBg8 = mix(selected, warning, 0.08);
	values.settingsIconBgArchive = disabled;
	return values;
}

function semanticFamily(name, t) {
	const lower = name.toLowerCase();
	if (/(error|danger|scam|draft|missed|hangup|reaction|redfile)/.test(lower) || COMMENT_FAMILIES.error.has(name)) return t.error;
	if (/(success|good|online|green|answer)/.test(lower) || COMMENT_FAMILIES.success.has(name)) return t.success;
	if (/(yellow|gold|orange|credits|currency)/.test(lower) || COMMENT_FAMILIES.warning.has(name)) return t.warning;
	if (/(purple|pink|indigo|premium|owner|poll)/.test(lower) || COMMENT_FAMILIES.magenta.has(name)) return t.magenta;
	if (/(cyan|sea)/.test(lower) || COMMENT_FAMILIES.cyan.has(name)) return t.cyan;
	if (/(link|blue|verified|mention)/.test(lower) || COMMENT_FAMILIES.accent.has(name)) return t.accent;
	return null;
}

function rgbToHls(value) {
	const [red, green, blue] = rgb(value).map((channel) => channel / 255);
	const maximum = Math.max(red, green, blue);
	const minimum = Math.min(red, green, blue);
	const lightness = (minimum + maximum) / 2;
	if (minimum === maximum) return [0, lightness, 0];
	const saturation = lightness <= 0.5
		? (maximum - minimum) / (maximum + minimum)
		: (maximum - minimum) / (2 - maximum - minimum);
	const redComponent = (maximum - red) / (maximum - minimum);
	const greenComponent = (maximum - green) / (maximum - minimum);
	const blueComponent = (maximum - blue) / (maximum - minimum);
	let hue;
	if (red === maximum) hue = blueComponent - greenComponent;
	else if (green === maximum) hue = 2 + redComponent - blueComponent;
	else hue = 4 + greenComponent - redComponent;
	hue = (hue / 6) % 1;
	if (hue < 0) hue += 1;
	return [hue, lightness, saturation];
}

function mapV1Role(name, baseline, t, explicit) {
	if (Object.hasOwn(explicit, name)) return explicit[name];
	const lower = name.toLowerCase();
	const family = semanticFamily(name, t);
	const isBackground = lower.includes('bg') || lower.includes('overlay');
	const isForeground = lower.includes('fg') || COMMENT_FOREGROUNDS.has(name);
	if (lower.includes('shadow')) return withBaselineAlpha(t.bg0, baseline);
	if (lower.includes('ripple')) return withBaselineAlpha(t.pressed, baseline);
	if (family && isBackground) {
		const strong = /(userpic|settingsicon|chartline|premium|credits|answer|hangup)/.test(lower);
		return withBaselineAlpha(strong ? family : mix(t.bg1, family, 0.38), baseline);
	}
	if (family) return withBaselineAlpha(family, baseline);
	if (isBackground) {
		let mapped;
		if (lower.includes('selected') || lower.includes('active')) mapped = t.selected;
		else if (lower.includes('over')) mapped = t.hover;
		else if (lower.includes('disabled') || lower.includes('inactive') || lower.includes('muted')) mapped = t.disabled;
		else if (/(title|sidebar|wallettop|groupcall)/.test(lower)) mapped = t.bg0;
		else mapped = SPECIAL_SECTION_BACKGROUNDS.has(name) ? t.bg1 : t.bg2;
		return withBaselineAlpha(mapped, baseline);
	}
	if (isForeground) {
		let mapped;
		if (lower.includes('disabled') || lower.includes('inactive') || lower.includes('muted')) mapped = t.disabled;
		else if (/(sub|date|status|additional|placeholder)/.test(lower)) mapped = t.secondary;
		else if (lower.includes('selected') || lower.includes('active') || lower.includes('over')) mapped = t.fg;
		else if (/(icon|arrow|close|separator|border)/.test(lower)) mapped = t.muted;
		else mapped = t.fg;
		return withBaselineAlpha(mapped, baseline);
	}
	// Preserve the prototype's historical rgb_to_hls variable assignment.
	const [hue, saturation, lightness] = rgbToHls(baseline);
	let mapped;
	if (saturation > 0.28) {
		if (hue < 0.06 || hue >= 0.95) mapped = t.error;
		else if (hue < 0.18) mapped = t.warning;
		else if (hue < 0.46) mapped = t.success;
		else if (hue < 0.72) mapped = t.accent;
		else mapped = t.magenta;
	} else if (lightness < 0.08) mapped = t.bg0;
	else if (lightness < 0.16) mapped = t.bg1;
	else if (lightness < 0.31) mapped = t.selected;
	else if (lightness < 0.55) mapped = t.muted;
	else if (lightness < 0.79) mapped = t.secondary;
	else mapped = t.fg;
	return baseline.length === 9 ? alphaColor(mapped, Number.parseInt(baseline.slice(7), 16)) : mapped;
}

function selectPrimarySurface(colors) {
	const background = colors.darker_background;
	for (const key of ['dark_background', 'background', 'selection', 'muted']) {
		if (oklabDistance(colors[key], background) >= PRIMARY_DISTANCE_THRESHOLD) return colors[key];
	}
	fail(`no source surface satisfies the ${PRIMARY_DISTANCE_THRESHOLD} OKLab primary separation threshold`);
}

function resolveToken(expression, tokens) {
	const [name, opacity] = expression.split('@');
	if (!tokens[name]) fail(`unknown semantic mapping token: ${name}`);
	return opacity ? `${tokens[name]}${opacity}` : tokens[name];
}

function contrastSurface(colors, surfaceKeys, foregroundKeys, token) {
	for (const surfaceKey of surfaceKeys) {
		if (foregroundKeys.every((foregroundKey) => contrast(colors[foregroundKey], colors[surfaceKey]) >= CONTRAST_THRESHOLD)) {
			return colors[surfaceKey];
		}
	}
	for (const surfaceKey of surfaceKeys) {
		if (Object.values(colors).some((foreground) => contrast(foreground, colors[surfaceKey]) >= CONTRAST_THRESHOLD)) {
			return colors[surfaceKey];
		}
	}
	fail(`no contrast-safe source surface for semantic token ${token}`);
}

function v2Tokens(colors) {
	const hoverKeys = ['selection', 'dark_background', 'darker_background'];
	return {
		surface: colors.background,
		surface_recessed: colors.dark_background,
		surface_deep: colors.darker_background,
		edge: colors.muted,
		active_surface: colors.foreground,
		active_text: colors.darker_background,
		active_ripple: colors.bright_foreground,
		accent: colors.accent,
		hover_warning: colors.bright_yellow,
		message_link: colors.light_foreground,
		message_status: colors.bright_foreground,
		selected_text: colors.yellow,
		hover_surface: contrastSurface(
			colors,
			hoverKeys,
			['light_foreground', 'foreground', 'bright_foreground', 'bright_yellow'],
			'hover_surface',
		),
		message_out_surface: contrastSurface(
			colors,
			['selection', 'background', 'dark_background', 'darker_background'],
			['light_foreground', 'foreground', 'bright_foreground'],
			'message_out_surface',
		),
		message_selected: contrastSurface(
			colors,
			['muted', 'darker_background'],
			['yellow', 'foreground'],
			'message_selected',
		),
	};
}

function repairTextContrast(assignments, colors) {
	const backgroundsByForeground = new Map();
	for (const [foreground, backgroundRole] of CONTRAST_PAIRS) {
		const list = backgroundsByForeground.get(foreground) ?? [];
		list.push(assignments.get(backgroundRole));
		backgroundsByForeground.set(foreground, list);
	}
	const candidates = [...new Set([
		colors.foreground, colors.light_foreground, colors.bright_foreground, colors.darker_background,
		colors.dark_background, colors.background, colors.yellow, colors.bright_yellow, colors.accent,
		colors.selection, colors.red, colors.green, colors.cyan, colors.blue, colors.magenta,
		...Object.values(colors),
	])];
	const surfaceCandidates = [...new Set([
		colors.background, colors.dark_background, colors.darker_background, colors.lighter_background,
		colors.selection, colors.muted, ...Object.values(colors),
	])];
	for (const [foreground, backgrounds] of backgroundsByForeground) {
		const current = assignments.get(foreground);
		if (backgrounds.every((background) => contrast(current, background) >= CONTRAST_THRESHOLD)) continue;
		const selected = candidates.find((candidate) => backgrounds.every((background) => contrast(candidate, background) >= CONTRAST_THRESHOLD));
		if (selected) {
			assignments.set(foreground, selected);
			continue;
		}
		const backgroundRoles = CONTRAST_PAIRS
			.filter(([candidate]) => candidate === foreground)
			.map(([, background]) => background);
		for (const candidate of candidates) {
			const replacements = backgroundRoles.map((backgroundRole) => {
				const background = assignments.get(backgroundRole);
				return contrast(candidate, background) >= CONTRAST_THRESHOLD
					? background
					: surfaceCandidates.find((surface) => contrast(candidate, surface) >= CONTRAST_THRESHOLD);
			});
			if (replacements.every(Boolean)) {
				assignments.set(foreground, candidate);
				backgroundRoles.forEach((backgroundRole, index) => assignments.set(backgroundRole, replacements[index]));
				break;
			}
		}
		if (backgroundRoles.some((backgroundRole) => contrast(assignments.get(foreground), assignments.get(backgroundRole)) < CONTRAST_THRESHOLD)) {
			fail(`no source text color satisfies ${CONTRAST_THRESHOLD.toFixed(2)} contrast for ${foreground}`);
		}
	}
}

function separateMessageSurfaces(assignments, colors) {
	const textCandidates = [...new Set(Object.values(colors))];
	const outCandidates = [...new Set([
		colors.selection, colors.background, colors.dark_background, colors.darker_background,
		colors.muted, colors.lighter_background,
	])];
	if (assignments.get('msgInBg') === assignments.get('msgOutBg')) {
		const incoming = assignments.get('msgInBg');
		const replacement = outCandidates.find((surface) => surface !== incoming
			&& textCandidates.some((text) => contrast(text, surface) >= CONTRAST_THRESHOLD));
		if (replacement) assignments.set('msgOutBg', replacement);
	}
	const incoming = assignments.get('msgInBg');
	const outgoing = assignments.get('msgOutBg');
	if (assignments.get('msgInBgSelected') === incoming || assignments.get('msgOutBgSelected') === outgoing) {
		const selectedCandidates = [...new Set([
			colors.muted, colors.darker_background, colors.selection, colors.dark_background,
			colors.background, colors.lighter_background,
		])];
		const replacement = selectedCandidates.find((surface) => surface !== incoming && surface !== outgoing
			&& textCandidates.some((text) => contrast(text, surface) >= CONTRAST_THRESHOLD));
		if (replacement) {
			assignments.set('msgInBgSelected', replacement);
			assignments.set('msgOutBgSelected', replacement);
		}
	}
}

function buildAssignments(rows, manifest) {
	const colors = manifest.colors;
	const v1 = buildV1Tokens(colors);
	const explicit = explicitV1Roles(v1);
	if (Object.keys(explicit).length !== 376) fail(`approved v1 explicit mapping changed: ${Object.keys(explicit).length}`);
	const assignments = new Map(rows.map(([name, baseline]) => [name, mapV1Role(name, baseline, v1, explicit)]));
	const tokens = v2Tokens(colors);
	if (Object.keys(EXCEPTIONS).length !== 90) fail(`approved v2 exception mapping changed: ${Object.keys(EXCEPTIONS).length}`);
	for (const [name, expression] of Object.entries(EXCEPTIONS)) {
		if (!assignments.has(name)) fail(`semantic exception references unknown role: ${name}`);
		assignments.set(name, resolveToken(expression, tokens));
	}
	assignments.set('msgInBg', selectPrimarySurface(colors));
	separateMessageSurfaces(assignments, colors);
	repairTextContrast(assignments, colors);
	return assignments;
}

function buildPalette(rows, assignments) {
	const lines = [
		'// Omarchy semantic theme for Telegram Desktop 7.0.9.',
		'// Pinned role order; every value is a direct hexadecimal assignment.',
	];
	for (const [name] of rows) {
		const value = assignments.get(name);
		if (!/^#[0-9a-f]{6}(?:[0-9a-f]{2})?$/.test(value)) fail(`non-direct palette value for ${name}: ${value}`);
		lines.push(`${name}: ${value};`);
	}
	return Buffer.from(`${lines.join('\n')}\n`);
}

function crc32(data) {
	let crc = 0xffffffff;
	for (const byte of data) {
		crc ^= byte;
		for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
	}
	return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(kind, payload) {
	const length = Buffer.alloc(4);
	length.writeUInt32BE(payload.length);
	const checksum = Buffer.alloc(4);
	checksum.writeUInt32BE(crc32(Buffer.concat([kind, payload])));
	return Buffer.concat([length, kind, payload, checksum]);
}

function buildPng(color) {
	const header = Buffer.alloc(13);
	header.writeUInt32BE(1, 0);
	header.writeUInt32BE(1, 4);
	header.set([8, 2, 0, 0, 0], 8);
	const pixel = Buffer.from([0, ...rgb(color)]);
	return Buffer.concat([
		Buffer.from('89504e470d0a1a0a', 'hex'),
		pngChunk(Buffer.from('IHDR'), header),
		pngChunk(Buffer.from('IDAT'), deflateSync(pixel, { level: 9 })),
		pngChunk(Buffer.from('IEND'), Buffer.alloc(0)),
	]);
}

function parsePalette(data) {
	const assignments = new Map();
	for (const raw of data.toString('utf8').split(/\r?\n/)) {
		const line = raw.replace(/\/\/.*$/, '').trim();
		if (!line) continue;
		const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(#[0-9a-f]{6}(?:[0-9a-f]{2})?);$/);
		if (!match) fail(`palette value is not direct hexadecimal: ${raw}`);
		if (assignments.has(match[1])) fail(`duplicate palette role: ${match[1]}`);
		assignments.set(match[1], match[2]);
	}
	if (assignments.size !== EXPECTED_ROLE_COUNT) fail(`expected ${EXPECTED_ROLE_COUNT} palette roles`);
	const order = `${[...assignments.keys()].join('\n')}\n`;
	if (sha256(order) !== EXPECTED_ROLE_ORDER_SHA256) fail('palette role order differs from pinned schema');
	return assignments;
}

function validatePng(data) {
	if (data.length > MAX_BACKGROUND || !data.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) fail('invalid background PNG');
	let position = 8;
	let width;
	let height;
	const compressed = [];
	const kinds = [];
	while (position < data.length) {
		if (position + 12 > data.length) fail('truncated PNG chunk');
		const length = data.readUInt32BE(position);
		if (position + length + 12 > data.length) fail('truncated PNG payload');
		const kind = data.subarray(position + 4, position + 8);
		const payload = data.subarray(position + 8, position + 8 + length);
		if (crc32(Buffer.concat([kind, payload])) !== data.readUInt32BE(position + 8 + length)) fail('bad PNG CRC');
		const name = kind.toString('ascii');
		kinds.push(name);
		if (name === 'IHDR') {
			width = payload.readUInt32BE(0);
			height = payload.readUInt32BE(4);
			if (!payload.subarray(8).equals(Buffer.from([8, 2, 0, 0, 0]))) fail('background must be opaque RGB8');
		} else if (name === 'IDAT') compressed.push(payload);
		position += length + 12;
	}
	if (position !== data.length || kinds[0] !== 'IHDR' || kinds.at(-1) !== 'IEND' || !width || !height || width * height > MAX_PIXELS) {
		fail('invalid PNG structure or dimensions');
	}
	const decoded = inflateSync(Buffer.concat(compressed));
	if (decoded.length !== (width * 3 + 1) * height) fail('invalid decoded PNG size');
	let first;
	for (let row = 0; row < height; row += 1) {
		const rowSize = width * 3 + 1;
		if (decoded[row * rowSize] !== 0) fail('flat PNG must use filter zero');
		for (let column = 0; column < width; column += 1) {
			const offset = row * rowSize + 1 + column * 3;
			const pixel = decoded.subarray(offset, offset + 3).toString('hex');
			first ??= pixel;
			if (pixel !== first) fail('background PNG is not flat');
		}
	}
	return `#${first}`;
}

function readZip(data) {
	if (data.length > MAX_THEME) fail('archive exceeds Telegram 5 MiB limit');
	let eocd = -1;
	for (let offset = data.length - 22; offset >= Math.max(0, data.length - 65557); offset -= 1) {
		if (data.readUInt32LE(offset) === 0x06054b50) { eocd = offset; break; }
	}
	if (eocd < 0 || data.readUInt16LE(eocd + 4) || data.readUInt16LE(eocd + 6)) fail('invalid ZIP end record');
	const entries = data.readUInt16LE(eocd + 10);
	if (entries !== data.readUInt16LE(eocd + 8) || data.readUInt16LE(eocd + 20) || eocd + 22 !== data.length) fail('non-normalized ZIP end record');
	const centralSize = data.readUInt32LE(eocd + 12);
	const centralOffset = data.readUInt32LE(eocd + 16);
	if (centralOffset + centralSize !== eocd) fail('invalid ZIP central directory');
	const members = [];
	let position = centralOffset;
	for (let index = 0; index < entries; index += 1) {
		if (data.readUInt32LE(position) !== 0x02014b50) fail('invalid ZIP central entry');
		const flags = data.readUInt16LE(position + 8);
		const method = data.readUInt16LE(position + 10);
		const dosTime = data.readUInt16LE(position + 12);
		const dosDate = data.readUInt16LE(position + 14);
		const expectedCrc = data.readUInt32LE(position + 16);
		const compressedSize = data.readUInt32LE(position + 20);
		const size = data.readUInt32LE(position + 24);
		const nameLength = data.readUInt16LE(position + 28);
		const extraLength = data.readUInt16LE(position + 30);
		const commentLength = data.readUInt16LE(position + 32);
		const disk = data.readUInt16LE(position + 34);
		const external = data.readUInt32LE(position + 38);
		const localOffset = data.readUInt32LE(position + 42);
		const name = data.subarray(position + 46, position + 46 + nameLength).toString('utf8');
		if ((flags & 0x9) || ![0, 8].includes(method) || extraLength || commentLength || disk) fail(`unsafe or non-normalized ZIP member: ${name}`);
		if (compressedSize && size / compressedSize > 1000) fail(`unsafe ZIP compression ratio: ${name}`);
		if ((external >>> 16 & 0o777) !== 0o644) fail(`ZIP member mode is not 0644: ${name}`);
		if (data.readUInt32LE(localOffset) !== 0x04034b50) fail(`missing local ZIP entry: ${name}`);
		const localFlags = data.readUInt16LE(localOffset + 6);
		const localMethod = data.readUInt16LE(localOffset + 8);
		const localNameLength = data.readUInt16LE(localOffset + 26);
		const localExtraLength = data.readUInt16LE(localOffset + 28);
		const localName = data.subarray(localOffset + 30, localOffset + 30 + localNameLength).toString('utf8');
		if (localFlags !== flags || localMethod !== method || localName !== name || localExtraLength) fail(`local ZIP metadata differs: ${name}`);
		const payloadOffset = localOffset + 30 + localNameLength;
		const compressed = data.subarray(payloadOffset, payloadOffset + compressedSize);
		const payload = method === 0 ? compressed : inflateRawSync(compressed);
		if (payload.length !== size || crc32(payload) !== expectedCrc) fail(`ZIP CRC or size mismatch: ${name}`);
		members.push({ name, payload, dosTime, dosDate });
		position += 46 + nameLength + extraLength + commentLength;
	}
	if (position !== eocd) fail('unparsed ZIP central-directory bytes');
	return members;
}

function validatePayloads(palette, png, manifest) {
	if (palette.length > MAX_PALETTE) fail('palette exceeds Telegram 1 MiB limit');
	const assignments = parsePalette(palette);
	const background = validatePng(png);
	for (const [foreground, surface] of CONTRAST_PAIRS) {
		const ratio = contrast(assignments.get(foreground), assignments.get(surface));
		if (ratio < CONTRAST_THRESHOLD) fail(`contrast below 4.50: ${foreground}/${surface}=${ratio.toFixed(4)}`);
	}
	for (const [left, right] of DISTINCT_ROLE_PAIRS) {
		if (assignments.get(left) === assignments.get(right)) fail(`native states must remain distinct: ${left}/${right}`);
	}
	for (const [label, leftRoles, rightRoles] of DISTINCT_STATE_COMPARISONS) {
		const left = leftRoles.map((role) => assignments.get(role)).join('/');
		const right = rightRoles.map((role) => assignments.get(role)).join('/');
		if (left === right) fail(`declared Telegram states are indistinguishable: ${label}`);
	}
	const source = new Set(Object.values(manifest.colors));
	const primary = assignments.get('msgInBg').slice(0, 7);
	if (!source.has(primary) || !source.has(background)) fail('primary surfaces must use source colors');
	const distance = oklabDistance(primary, background);
	if (distance < PRIMARY_DISTANCE_THRESHOLD) fail(`primary surface OKLab distance below ${PRIMARY_DISTANCE_THRESHOLD}`);
}

function validateArchive(data, palette, png, manifest) {
	const members = readZip(data);
	if (members.map(({ name }) => name).join('\n') !== MEMBERS.join('\n')) fail('unexpected ZIP members or order');
	if (members[0].dosTime !== members[1].dosTime || members[0].dosDate !== members[1].dosDate) fail('ZIP timestamps are not normalized');
	if (!members[0].payload.equals(palette) || !members[1].payload.equals(png)) fail('ZIP payload differs from validated source');
	validatePayloads(members[0].payload, members[1].payload, manifest);
}

function atomicJson(path, value) {
	const parent = dirname(path);
	mkdirSync(parent, { recursive: true, mode: 0o700 });
	const temporary = join(parent, `.${basename(path)}.${process.pid}.${randomBytes(6).toString('hex')}`);
	let descriptor;
	try {
		descriptor = openSync(temporary, constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY, 0o600);
		writeFileSync(descriptor, `${JSON.stringify(value)}\n`);
		fsyncSync(descriptor);
		closeSync(descriptor);
		descriptor = undefined;
		renameSync(temporary, path);
	} finally {
		if (descriptor !== undefined) closeSync(descriptor);
		rmSync(temporary, { force: true });
	}
}

function packageArchive(outputPath, palette, png) {
	const outputDirectory = dirname(outputPath);
	mkdirSync(outputDirectory, { recursive: true, mode: 0o700 });
	const work = mkdtempSync(join(outputDirectory, '.telegram-theme-assets-'));
	const candidate = join(outputDirectory, `.${basename(outputPath)}.${process.pid}.${randomBytes(6).toString('hex')}`);
	try {
		for (const [name, data] of [[MEMBERS[0], palette], [MEMBERS[1], png]]) {
			const path = join(work, name);
			writeFileSync(path, data, { mode: 0o644 });
			chmodSync(path, 0o644);
			utimesSync(path, NORMALIZED_TIME, NORMALIZED_TIME);
		}
		const result = spawnSync('zip', ['-X', '-q', '-9', candidate, ...MEMBERS], {
			cwd: work,
			env: { ...process.env, LC_ALL: 'C', TZ: 'UTC' },
			encoding: 'utf8',
		});
		if (result.error) fail(`zip could not run: ${result.error.message}`);
		if (result.status !== 0) fail(`zip failed with status ${result.status}: ${(result.stderr || result.stdout).trim()}`);
		chmodSync(candidate, 0o644);
		return candidate;
	} catch (error) {
		rmSync(candidate, { force: true });
		throw error;
	} finally {
		rmSync(work, { recursive: true, force: true });
	}
}

function samePriorFile(left, right) {
	return left.dev === right.dev
		&& left.ino === right.ino
		&& left.mode === right.mode
		&& left.size === right.size
		&& left.mtimeNs === right.mtimeNs;
}

function createLastGood(path, lastGood, prior, priorBytes, label) {
	try {
		linkSync(path, lastGood);
	} catch (linkError) {
		const copy = spawnSync('/usr/bin/cp', [
			'--preserve=mode,timestamps', '--reflink=never', '--', path, lastGood,
		], { encoding: 'utf8', env: { ...process.env, LC_ALL: 'C' } });
		if (copy.error || copy.status !== 0) {
			const detail = copy.error?.message || (copy.stderr || copy.stdout).trim() || `status ${copy.status}`;
			fail(`could not preserve last-good ${label} after hard-link failure (${linkError.message}): ${detail}`);
		}
	}
	const current = lstatSync(path, { bigint: true });
	const preserved = lstatSync(lastGood, { bigint: true });
	if (!current.isFile() || !samePriorFile(prior, current)) fail(`${label} changed while preserving last-good state`);
	if (!preserved.isFile()
		|| preserved.mode !== prior.mode
		|| preserved.size !== prior.size
		|| preserved.mtimeNs !== prior.mtimeNs
		|| !readFileSync(lastGood).equals(priorBytes)) {
		fail(`last-good ${label} did not preserve exact bytes, mode, and mtime`);
	}
}

function publishCandidate(candidate, outputPath, statusPath, successStatus, guard) {
	const bytes = readFileSync(candidate);
	const outputPrior = lstatSync(outputPath, { bigint: true, throwIfNoEntry: false });
	const hadOutput = outputPrior !== undefined;
	if (outputPrior?.isSymbolicLink()) rejectPublication('output path must not be a symlink');
	if (outputPrior && !outputPrior.isFile()) rejectPublication('output path exists and is not a regular file');
	const outputPriorBytes = hadOutput ? readFileSync(outputPath) : undefined;
	const unchanged = outputPriorBytes?.equals(bytes) ?? false;
	if (unchanged) {
		if (guard && !guardIsCurrent(guard)) {
			rmSync(candidate);
			return { stale: true };
		}
		rmSync(candidate);
		if (statusPath) atomicJson(statusPath, { ...successStatus, changed: false, archive_sha256: sha256(bytes) });
		return { stale: false };
	}
	const outputTransaction = mkdtempSync(join(dirname(outputPath), '.telegram-theme-last-good-'));
	const outputLastGood = join(outputTransaction, basename(outputPath));
	let statusPrior;
	let statusPriorBytes;
	let statusTransaction;
	let statusLastGood;
	const cleanupTransactions = () => {
		for (const path of [statusTransaction, outputTransaction]) {
			if (!path) continue;
			try {
				rmSync(path, { recursive: true, force: true });
			} catch {
				// Stable files are authoritative; abandoned integration-owned backups are safe recovery material.
			}
		}
	};
	const restoreStatus = () => {
		if (!statusPath) return;
		if (statusPrior) renameSync(statusLastGood, statusPath);
		else rmSync(statusPath, { force: true });
	};
	const recoveryError = (error, restoreError) => {
		const material = [
			`candidate ${candidate}`,
			hadOutput ? `archive last-good ${outputLastGood}` : undefined,
			statusPrior ? `status last-good ${statusLastGood}` : `future status ${statusPath}`,
		].filter(Boolean).join('; ');
		const recovery = preserveStatusError(
			error,
			`${error.message}; status rollback failed: ${restoreError.message}; recovery material retained: ${material}`,
		);
		recovery.retainCandidate = true;
		return recovery;
	};
	try {
		if (statusPath) {
			statusPrior = lstatSync(statusPath, { bigint: true, throwIfNoEntry: false });
			if (statusPrior?.isSymbolicLink()) rejectPublication('status path must not be a symlink');
			if (statusPrior && !statusPrior.isFile()) rejectPublication('status path exists and is not a regular file');
			if (statusPrior) {
				statusPriorBytes = readFileSync(statusPath);
				statusTransaction = mkdtempSync(join(dirname(statusPath), '.telegram-theme-status-last-good-'));
				statusLastGood = join(statusTransaction, basename(statusPath));
				createLastGood(statusPath, statusLastGood, statusPrior, statusPriorBytes, 'status');
			}
		}
		if (hadOutput) createLastGood(outputPath, outputLastGood, outputPrior, outputPriorBytes, 'output');
	} catch (error) {
		cleanupTransactions();
		throw preserveStatusError(error);
	}
	if (guard && !guardIsCurrent(guard)) {
		rmSync(candidate);
		cleanupTransactions();
		return { stale: true };
	}
	if (statusPath) {
		try {
			atomicJson(statusPath, { ...successStatus, changed: true, archive_sha256: sha256(bytes) });
		} catch (error) {
			try {
				restoreStatus();
			} catch (restoreError) {
				throw recoveryError(error, restoreError);
			}
			cleanupTransactions();
			throw preserveStatusError(error);
		}
	}
	try {
		renameSync(candidate, outputPath);
	} catch (error) {
		try {
			restoreStatus();
		} catch (restoreError) {
			throw recoveryError(error, restoreError);
		}
		cleanupTransactions();
		throw preserveStatusError(error);
	}
	cleanupTransactions();
	return { stale: false };
}

let args;
let manifest;
let candidate;
try {
	args = parseArguments(process.argv.slice(2));
	manifest = readManifest(args['--manifest']);
	const guard = parseGuard(args['--guard'], manifest.slug);
	const rows = parseBaseline();
	const assignments = buildAssignments(rows, manifest);
	const palette = buildPalette(rows, assignments);
	const png = buildPng(manifest.colors.darker_background);
	validatePayloads(palette, png, manifest);
	candidate = packageArchive(args['--output'], palette, png);
	const archive = readFileSync(candidate);
	validateArchive(archive, palette, png, manifest);
	const publication = publishCandidate(candidate, args['--output'], args['--status'], {
		schema_version: SCHEMA_VERSION,
		status: 'ok',
		slug: manifest.slug,
		mode: manifest.mode,
	}, guard);
	candidate = undefined;
	if (publication.stale) {
		process.stdout.write('telegram theme generation skipped: stale active theme guard\n');
	}
} catch (error) {
	if (candidate && !error?.retainCandidate) rmSync(candidate, { force: true });
	const message = error instanceof Error ? error.message : String(error);
	if (args?.['--status'] && !error?.preserveStatus) {
		try {
			atomicJson(args['--status'], {
				schema_version: SCHEMA_VERSION,
				status: 'error',
				...(manifest?.slug ? { slug: manifest.slug } : {}),
				message,
			});
		} catch (statusError) {
			process.stderr.write(`telegram theme status error: ${statusError.message}\n`);
		}
	}
	process.stderr.write(`telegram theme generation failed: ${message}\n`);
	process.exitCode = 1;
}
