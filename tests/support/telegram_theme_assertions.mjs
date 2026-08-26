#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { inflateRawSync, inflateSync } from 'node:zlib';

const EXPECTED_ROLE_COUNT = 586;
const EXPECTED_ROLE_ORDER_SHA256 = 'f28bcceba0ab9c945292e07eaac4b62d4b88162203b7a22195c7550251ca66d7';
const EXPECTED_MEMBERS = ['colors.tdesktop-theme', 'background.png'];
const MAX_THEME = 5 * 1024 * 1024;
const MAX_PALETTE = 1024 * 1024;
const MAX_BACKGROUND = 4 * 1024 * 1024;
const MAX_PIXELS = 25_000_000;

const CONTRAST_PAIRS = [
	['windowFg', 'windowBg'],
	['windowSubTextFg', 'windowBg'],
	['windowBoldFg', 'windowBg'],
	['windowFgOver', 'windowBgOver'],
	['windowSubTextFgOver', 'windowBgOver'],
	['windowBoldFgOver', 'windowBgOver'],
	['windowFgActive', 'windowBgActive'],
	['windowFg', 'menuBg'],
	['windowFgOver', 'menuBgOver'],
	['boxTextFg', 'boxBg'],
	['windowFg', 'filterInputActiveBg'],
	['windowSubTextFg', 'filterInputInactiveBg'],
	['activeButtonFg', 'activeButtonBg'],
	['historyComposeAreaFgService', 'historyComposeAreaBg'],
	['lightButtonFg', 'lightButtonBg'],
	['lightButtonFgOver', 'lightButtonBgOver'],
	['dialogsNameFg', 'dialogsBg'],
	['dialogsTextFg', 'dialogsBg'],
	['dialogsTextFgService', 'dialogsBg'],
	['dialogsDateFg', 'dialogsBg'],
	['dialogsNameFgOver', 'dialogsBgOver'],
	['dialogsTextFgOver', 'dialogsBgOver'],
	['dialogsTextFgServiceOver', 'dialogsBgOver'],
	['dialogsDateFgOver', 'dialogsBgOver'],
	['dialogsNameFgActive', 'dialogsBgActive'],
	['dialogsTextFgActive', 'dialogsBgActive'],
	['dialogsTextFgServiceActive', 'dialogsBgActive'],
	['dialogsDateFgActive', 'dialogsBgActive'],
	['dialogsUnreadFg', 'dialogsUnreadBg'],
	['dialogsUnreadFgOver', 'dialogsUnreadBgOver'],
	['dialogsUnreadFgActive', 'dialogsUnreadBgActive'],
	['dialogsVerifiedIconFg', 'dialogsVerifiedIconBg'],
	['dialogsVerifiedIconFgOver', 'dialogsVerifiedIconBgOver'],
	['dialogsVerifiedIconFgActive', 'dialogsVerifiedIconBgActive'],
	['historyTextInFg', 'msgInBg'],
	['historyTextOutFg', 'msgOutBg'],
	['historyTextInFgSelected', 'msgInBgSelected'],
	['historyTextOutFgSelected', 'msgOutBgSelected'],
	['historyLinkInFg', 'msgInBg'],
	['historyLinkOutFg', 'msgOutBg'],
	['historyLinkInFgSelected', 'msgInBgSelected'],
	['historyLinkOutFgSelected', 'msgOutBgSelected'],
	['msgInDateFg', 'msgInBg'],
	['msgOutDateFg', 'msgOutBg'],
	['msgInDateFgSelected', 'msgInBgSelected'],
	['msgOutDateFgSelected', 'msgOutBgSelected'],
	['historyFileNameInFg', 'msgInBg'],
	['historyFileNameOutFg', 'msgOutBg'],
	['historyComposeAreaFg', 'historyComposeAreaBg'],
	['historyUnreadBarFg', 'historyUnreadBarBg'],
];

const DISTINCT_STATE_COMPARISONS = [
	{
		label: 'dialogs read-row normal/hover',
		left: [
			'dialogsBg', 'dialogsNameFg', 'dialogsChatIconFg', 'dialogsDateFg',
			'dialogsTextFg', 'dialogsTextFgService', 'dialogsVerifiedIconBg',
			'dialogsVerifiedIconFg', 'dialogsSendingIconFg', 'dialogsSentIconFg',
		],
		right: [
			'dialogsBgOver', 'dialogsNameFgOver', 'dialogsChatIconFgOver', 'dialogsDateFgOver',
			'dialogsTextFgOver', 'dialogsTextFgServiceOver', 'dialogsVerifiedIconBgOver',
			'dialogsVerifiedIconFgOver', 'dialogsSendingIconFgOver', 'dialogsSentIconFgOver',
		],
	},
	{
		label: 'dialogs unread normal/hover',
		left: ['dialogsUnreadBg', 'dialogsUnreadBgMuted', 'dialogsUnreadFg'],
		right: ['dialogsUnreadBgOver', 'dialogsUnreadBgMutedOver', 'dialogsUnreadFgOver'],
	},
	{
		label: 'dialogs hover/active',
		left: ['dialogsBgOver', 'dialogsUnreadBgOver', 'dialogsUnreadFgOver'],
		right: ['dialogsBgActive', 'dialogsUnreadBgActive', 'dialogsUnreadFgActive'],
	},
	{
		label: 'dialogs normal/active',
		left: ['dialogsBg', 'dialogsUnreadBg', 'dialogsUnreadFg'],
		right: ['dialogsBgActive', 'dialogsUnreadBgActive', 'dialogsUnreadFgActive'],
	},
	{
		label: 'incoming/outgoing messages',
		left: ['msgInBg', 'historyTextInFg'],
		right: ['msgOutBg', 'historyTextOutFg'],
	},
	{
		label: 'incoming normal/selected messages',
		left: ['msgInBg', 'historyTextInFg'],
		right: ['msgInBgSelected', 'historyTextInFgSelected'],
	},
	{
		label: 'outgoing normal/selected messages',
		left: ['msgOutBg', 'historyTextOutFg'],
		right: ['msgOutBgSelected', 'historyTextOutFgSelected'],
	},
];

function fail(message) {
	throw new Error(message);
}

function crc32(data) {
	let crc = 0xffffffff;
	for (const byte of data) {
		crc ^= byte;
		for (let bit = 0; bit < 8; bit += 1) {
			crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
		}
	}
	return (crc ^ 0xffffffff) >>> 0;
}

function readZip(data) {
	if (data.length > MAX_THEME) fail('archive exceeds Telegram 5 MiB limit');
	let eocd = -1;
	for (let offset = data.length - 22; offset >= Math.max(0, data.length - 65557); offset -= 1) {
		if (data.readUInt32LE(offset) === 0x06054b50) {
			eocd = offset;
			break;
		}
	}
	if (eocd < 0) fail('ZIP end record is missing');
	const disk = data.readUInt16LE(eocd + 4);
	const centralDisk = data.readUInt16LE(eocd + 6);
	const diskEntries = data.readUInt16LE(eocd + 8);
	const entries = data.readUInt16LE(eocd + 10);
	const centralSize = data.readUInt32LE(eocd + 12);
	const centralOffset = data.readUInt32LE(eocd + 16);
	const commentLength = data.readUInt16LE(eocd + 20);
	if (disk !== 0 || centralDisk !== 0 || diskEntries !== entries) fail('multi-disk ZIP is not allowed');
	if (commentLength !== 0 || eocd + 22 !== data.length) fail('ZIP comment or trailing bytes are not allowed');
	if (centralOffset + centralSize !== eocd) fail('ZIP central directory boundaries are invalid');

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
		const memberCommentLength = data.readUInt16LE(position + 32);
		const diskStart = data.readUInt16LE(position + 34);
		const externalAttributes = data.readUInt32LE(position + 38);
		const localOffset = data.readUInt32LE(position + 42);
		const name = data.subarray(position + 46, position + 46 + nameLength).toString('utf8');
		if (flags & 0x1) fail(`encrypted ZIP member: ${name}`);
		if (flags & 0x8) fail(`data-descriptor ZIP member is not deterministic: ${name}`);
		if (![0, 8].includes(method)) fail(`unsupported ZIP compression method for ${name}`);
		if (extraLength !== 0 || memberCommentLength !== 0 || diskStart !== 0) {
			fail(`non-normalized ZIP metadata for ${name}`);
		}
		if (compressedSize > 0 && size / compressedSize > 1000) fail(`unsafe compression ratio for ${name}`);
		if (data.readUInt32LE(localOffset) !== 0x04034b50) fail(`local ZIP entry is missing for ${name}`);
		const localFlags = data.readUInt16LE(localOffset + 6);
		const localMethod = data.readUInt16LE(localOffset + 8);
		const localNameLength = data.readUInt16LE(localOffset + 26);
		const localExtraLength = data.readUInt16LE(localOffset + 28);
		const localName = data.subarray(localOffset + 30, localOffset + 30 + localNameLength).toString('utf8');
		if (localName !== name || localFlags !== flags || localMethod !== method || localExtraLength !== 0) {
			fail(`local and central ZIP metadata differ for ${name}`);
		}
		const payloadOffset = localOffset + 30 + localNameLength;
		const compressed = data.subarray(payloadOffset, payloadOffset + compressedSize);
		const payload = method === 0 ? compressed : inflateRawSync(compressed);
		if (payload.length !== size || crc32(payload) !== expectedCrc) fail(`ZIP CRC or size mismatch for ${name}`);
		members.push({ name, payload, dosTime, dosDate, externalAttributes });
		position += 46 + nameLength + extraLength + memberCommentLength;
	}
	if (position !== eocd) fail('ZIP central directory has unparsed bytes');
	return members;
}

function parsePalette(data) {
	const assignments = new Map();
	for (const raw of data.toString('utf8').split(/\r?\n/)) {
		const line = raw.replace(/\/\/.*$/, '').trim();
		if (!line) continue;
		const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?);$/);
		if (!match) fail(`palette value is not direct hexadecimal: ${raw}`);
		if (assignments.has(match[1])) fail(`duplicate palette role: ${match[1]}`);
		assignments.set(match[1], match[2].toLowerCase());
	}
	if (assignments.size !== EXPECTED_ROLE_COUNT) fail(`expected 586 palette roles, found ${assignments.size}`);
	const order = `${[...assignments.keys()].join('\n')}\n`;
	const orderHash = createHash('sha256').update(order).digest('hex');
	if (orderHash !== EXPECTED_ROLE_ORDER_SHA256) fail(`pinned role order changed: ${orderHash}`);
	return assignments;
}

function parsePng(data) {
	if (!data.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) fail('background is not PNG');
	let position = 8;
	let width;
	let height;
	const idat = [];
	const kinds = [];
	while (position < data.length) {
		if (position + 12 > data.length) fail('truncated PNG chunk');
		const length = data.readUInt32BE(position);
		const kind = data.subarray(position + 4, position + 8);
		const payload = data.subarray(position + 8, position + 8 + length);
		const storedCrc = data.readUInt32BE(position + 8 + length);
		if (crc32(Buffer.concat([kind, payload])) !== storedCrc) fail(`bad PNG CRC: ${kind}`);
		const name = kind.toString('ascii');
		kinds.push(name);
		if (name === 'IHDR') {
			width = payload.readUInt32BE(0);
			height = payload.readUInt32BE(4);
			if (payload[8] !== 8 || payload[9] !== 2 || payload[10] !== 0 || payload[11] !== 0 || payload[12] !== 0) {
				fail('background must be opaque non-interlaced 8-bit RGB');
			}
		} else if (name === 'IDAT') {
			idat.push(payload);
		}
		position += length + 12;
	}
	if (position !== data.length || kinds[0] !== 'IHDR' || kinds.at(-1) !== 'IEND') fail('invalid PNG structure');
	if (!width || !height || width * height > MAX_PIXELS) fail('invalid PNG dimensions');
	const rowSize = width * 3 + 1;
	const decoded = inflateSync(Buffer.concat(idat));
	if (decoded.length !== rowSize * height) fail('unexpected PNG decoded size');
	let first;
	for (let row = 0; row < height; row += 1) {
		if (decoded[row * rowSize] !== 0) fail('flat PNG must use filter type zero');
		for (let column = 0; column < width; column += 1) {
			const offset = row * rowSize + 1 + column * 3;
			const pixel = decoded.subarray(offset, offset + 3).toString('hex');
			first ??= pixel;
			if (pixel !== first) fail('background PNG is not flat');
		}
	}
	return { width, height, color: `#${first}` };
}

function rgb(value) {
	return value.slice(1, 7).match(/../g).map((channel) => Number.parseInt(channel, 16));
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

function main() {
	const [archivePath, manifestPath] = process.argv.slice(2);
	if (!archivePath || !manifestPath) fail('usage: telegram_theme_assertions.mjs ARCHIVE MANIFEST');
	const archive = readFileSync(archivePath);
	const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
	const members = readZip(archive);
	if (members.map(({ name }) => name).join('\n') !== EXPECTED_MEMBERS.join('\n')) {
		fail(`unexpected ZIP members or order: ${members.map(({ name }) => name).join(',')}`);
	}
	if (new Set(members.map(({ name }) => name)).size !== members.length) fail('duplicate ZIP member');
	if (members[0].payload.length > MAX_PALETTE || members[1].payload.length > MAX_BACKGROUND) {
		fail('ZIP member exceeds Telegram limit');
	}
	if (members[0].dosTime !== members[1].dosTime || members[0].dosDate !== members[1].dosDate) {
		fail('ZIP member timestamps are not normalized');
	}
	for (const member of members) {
		const mode = member.externalAttributes >>> 16;
		if (mode !== 0 && (mode & 0o777) !== 0o644) fail(`ZIP member mode is not 0644: ${member.name}`);
	}

	const assignments = parsePalette(members[0].payload);
	const roleValueBytes = [...assignments]
		.map(([name, value]) => `${name}:${value}\n`)
		.join('');
	const png = parsePng(members[1].payload);
	let minimumContrast = Number.POSITIVE_INFINITY;
	for (const [foreground, background] of CONTRAST_PAIRS) {
		if (!assignments.has(foreground) || !assignments.has(background)) fail(`contrast role missing: ${foreground}/${background}`);
		const ratio = contrast(assignments.get(foreground), assignments.get(background));
		minimumContrast = Math.min(minimumContrast, ratio);
		if (ratio < 4.5) fail(`contrast below 4.50: ${foreground}/${background}=${ratio.toFixed(4)}`);
	}
	for (const comparison of DISTINCT_STATE_COMPARISONS) {
		const left = comparison.left.map((role) => assignments.get(role)).join('/');
		const right = comparison.right.map((role) => assignments.get(role)).join('/');
		if (left === right) fail(`declared Telegram states are indistinguishable: ${comparison.label}`);
	}
	const sourceColors = new Set(Object.values(manifest.colors).map((value) => value.toLowerCase()));
	const primarySurface = assignments.get('msgInBg').slice(0, 7);
	if (!sourceColors.has(primarySurface) || !sourceColors.has(png.color)) fail('primary surface fallback invented a non-source color');
	const primaryDistance = oklabDistance(primarySurface, png.color);
	if (primaryDistance < 0.025) fail(`primary surface OKLab distance below 0.025: ${primaryDistance.toFixed(6)}`);

	process.stdout.write(`${JSON.stringify({
		archive_sha256: createHash('sha256').update(archive).digest('hex'),
		palette_sha256: createHash('sha256').update(members[0].payload).digest('hex'),
		role_value_sha256: createHash('sha256').update(roleValueBytes).digest('hex'),
		roles: assignments.size,
		role_order_sha256: EXPECTED_ROLE_ORDER_SHA256,
		members: members.map(({ name }) => name),
		background: png,
		contrast_pairs: CONTRAST_PAIRS.length,
		distinct_state_comparisons: DISTINCT_STATE_COMPARISONS.length,
		minimum_contrast: minimumContrast,
		primary_surface: primarySurface,
		primary_distance: primaryDistance,
	})}\n`);
}

try {
	main();
} catch (error) {
	process.stderr.write(`telegram theme assertion failed: ${error.message}\n`);
	process.exit(1);
}
