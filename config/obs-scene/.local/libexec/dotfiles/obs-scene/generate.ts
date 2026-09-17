// Omarchy OBS scene generator, run by Bun with no third-party modules.
//
//   bun generate.ts render --geometry FILE --colors FILE --font NAME --avatar FILE --output DIR
//     Renders the scene assets for one machine set's canvas from the active
//     Omarchy theme. Every file is written through a same-folder temporary file
//     and a rename, and unchanged files are left alone. title.txt is created
//     only when it is missing. The avatar image must be the pinned portrait, or
//     nothing is written.
//
//   bun generate.ts collection --geometry FILE --output FILE
//     Writes a machine set's "Omarchy Scene" collection for the same canvas.
//     Home paths use the $HOME placeholder that Install OBS set expands.
//
// The layout below is theme-free, so the scene collection written from the
// same geometry never depends on the theme that was active when it was made.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

type Geometry = { canvas: { width: number; height: number }; bar_crop: number; strip_width: number; band_height: number };
type Rect = { x: number; y: number; w: number; h: number };
type Theme = {
	background: string;
	foreground: string;
	accent: string;
	selection: string;
	red: string;
	yellow: string;
	mode: "dark" | "light";
	font: string;
};

const PULSES = 6;
const CARDS = [
	{ key: "starting", scene: "Starting", label: "starting", headline: "starting soon", sub: "grab a drink · stream begins shortly", color: "accent" },
	{ key: "intro", scene: "Intro", label: "episode", headline: "", sub: "up next", color: "accent" },
	{ key: "brb", scene: "BRB", label: "paused", headline: "be right back", sub: "stream paused · back in a few minutes", color: "accent" },
	{ key: "ending", scene: "Ending", label: "ended", headline: "thanks for watching", sub: "that's all for today · see you next time", color: "accent" },
	{ key: "privacy", scene: "Privacy", label: "private", headline: "screen hidden", sub: "entering something private · back in a moment", color: "red" },
] as const;

// ---------------------------------------------------------------------------
// Layout: every size is designed at 1080p and scaled to the canvas height.

function readGeometry(file: string): Geometry {
	const raw = JSON.parse(fs.readFileSync(file, "utf8"));
	// band_height joined the geometry after the first sets shipped, so a file
	// written without it keeps the full-height screen it was made for.
	const g: Geometry = { ...raw, band_height: raw?.band_height ?? 0 };
	const positive = (n: unknown) => Number.isInteger(n) && (n as number) > 0;
	const slack = (n: unknown, limit: number) => Number.isInteger(n) && (n as number) >= 0 && 2 * (n as number) < limit;
	if (!positive(g?.canvas?.width) || !positive(g?.canvas?.height) || !Number.isInteger(g.bar_crop) || g.bar_crop < 0 ||
		!slack(g.strip_width, g.canvas.width) || !slack(g.band_height, g.canvas.height)) {
		throw new Error(`invalid geometry in ${file}`);
	}
	return g;
}

function metrics(g: Geometry) {
	const W = g.canvas.width;
	const H = g.canvas.height;
	const s = (n: number) => Math.round((n * H) / 1080);
	// The screen keeps the capture's own shape, so whichever axis the canvas
	// does not fill is left to the chrome: side strips or top and bottom bands.
	const screen: Rect = { x: g.strip_width, y: g.band_height, w: W - 2 * g.strip_width, h: H - 2 * g.band_height };
	const gap = s(24);
	const pad = s(16);
	const inset = s(10);
	const boxW = s(420);
	const camW = boxW - 2 * inset;
	const camH = Math.round((camW * 9) / 16);
	const stackX = screen.x + screen.w - gap - boxW;
	const cam: Rect = { x: stackX, y: screen.y + gap, w: boxW, h: camH + 2 * inset };
	const time: Rect = { x: stackX, y: screen.y + screen.h - gap - s(84), w: boxW, h: s(84) };
	const chatY = cam.y + cam.h + pad;
	const chat: Rect = { x: stackX, y: chatY, w: boxW, h: time.y - pad - chatY };
	const fullCam: Rect = { x: stackX, y: screen.y + screen.h - gap - cam.h, w: boxW, h: cam.h };
	const cardW = s(1000);
	const cardH = s(380);
	const card: Rect = { x: Math.floor((W - cardW) / 2), y: Math.floor((H - cardH) / 2), w: cardW, h: cardH };
	return {
		W, H, s, screen, inset, camW, camH, cam, time, chat, fullCam, card,
		strips: g.strip_width > 0,
		bands: g.band_height > 0,
		barCrop: g.bar_crop,
		fontSize: s(20),
		stroke: 2 * Math.max(1, Math.round(H / 1080)),
		texts: {
			Clock: { color: "foreground", size: s(20), x: stackX + s(90), y: time.y + s(16) },
			Date: { color: "foreground", size: s(20), x: stackX + s(90), y: time.y + s(46) },
			Countdown: { color: "accent", size: s(48), x: Math.floor(W / 2), y: card.y + s(230) },
			Title: { color: "foreground", size: s(64), x: Math.floor(W / 2), y: card.y + s(150) },
		} as const,
	};
}

type Metrics = ReturnType<typeof metrics>;

// ---------------------------------------------------------------------------
// Theme

function readTheme(colorsFile: string, font: string): Theme {
	const values: Record<string, string> = {};
	for (const line of fs.readFileSync(colorsFile, "utf8").split("\n")) {
		const match = line.match(/^\s*([a-z_]+)\s*=\s*"([^"]*)"/);
		if (match) values[match[1]] = match[2];
	}
	const theme: Record<string, string> = { font };
	for (const key of ["background", "foreground", "accent", "selection", "red", "yellow"]) {
		const value = values[key]?.toLowerCase();
		if (!value || !/^#[0-9a-f]{6}$/.test(value)) throw new Error(`${colorsFile} has no valid ${key} colour`);
		theme[key] = value;
	}
	theme.mode = values.mode === "light" ? "light" : "dark";
	if (!font) throw new Error("the Omarchy font name is empty");
	return theme as Theme;
}

const channels = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const toHex = (rgb: number[]) => "#" + rgb.map((v) => v.toString(16).padStart(2, "0")).join("");

// Omarchy's template mix: a*(1-p) + b*p, rounded half up.
function mix(a: string, b: string, percent: number): string {
	const x = channels(a);
	const y = channels(b);
	return toHex(x.map((v, i) => Math.floor((v * (100 - percent) + y[i] * percent) / 100 + 0.5)));
}

// OBS stores colours as 0xAABBGGRR.
function obsColor(hex: string): number {
	const [r, g, b] = channels(hex);
	return (0xff000000 + (b << 16) + (g << 8) + r) >>> 0;
}

// ---------------------------------------------------------------------------
// SVG drawing

function escape(text: string): string {
	return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

class Draw {
	constructor(readonly m: Metrics, readonly t: Theme) {}

	get border() { return mix(this.t.foreground, this.t.background, 40); }
	get muted() { return mix(this.t.foreground, this.t.background, 45); }

	svg(body: string, ground: boolean): string {
		const { W, H } = this.m;
		const fill = ground ? `<rect width="${W}" height="${H}" fill="${this.t.background}"/>` : "";
		return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" ` +
			`font-family="${escape(this.t.font)}" xml:space="preserve">${fill}${body}</svg>\n`;
	}

	text(x: number, y: number, value: string, fill: string, size = this.m.fontSize, anchor = "start", weight = "normal"): string {
		return `<text x="${x}" y="${y}" fill="${fill}" font-size="${size}" font-weight="${weight}" ` +
			`text-anchor="${anchor}" dominant-baseline="central">${escape(value)}</text>`;
	}

	// A square TUI box whose title breaks the top border, like "┌─ title ─┐".
	box(r: Rect, title: string, color: string, stroke = this.m.stroke): string {
		const size = this.m.fontSize;
		const label = ` ${title} `;
		const labelW = Math.round(label.length * size * 0.6);
		const labelX = r.x + this.m.s(18);
		return `<rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" fill="none" stroke="${color}" stroke-width="${stroke}"/>` +
			`<rect x="${labelX}" y="${r.y - size / 2}" width="${labelW}" height="${size}" fill="${this.t.background}"/>` +
			this.text(labelX, r.y, label, color, size, "start", "bold");
	}

	translucent(r: Rect): string {
		return `<rect x="${r.x}" y="${r.y}" width="${r.w}" height="${r.h}" fill="${this.t.background}" fill-opacity="0.88"/>`;
	}

	cell(x: number, y: number, fill: string): string {
		const { s } = this.m;
		return `<rect x="${x}" y="${y + s(2)}" width="${s(16)}" height="${s(16)}" fill="${fill}"/>`;
	}
}

// Deterministic cells, so every render places the same blocks and the pulse
// layers stay aligned with the static cells.
function random(seed: number): () => number {
	let state = seed >>> 0;
	return () => {
		state = (state + 0x6d2b79f5) >>> 0;
		let t = state;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
}

type Blocks = { cells: string; pulses: string[] };

function blocks(d: Draw, seed: number, density: (x: number, y: number) => number): Blocks {
	const { W, H, s } = d.m;
	const next = random(seed);
	const shades = [mix(d.t.background, d.t.foreground, 14), mix(d.t.background, d.t.foreground, 14), mix(d.t.background, d.t.foreground, 24)];
	const glow = mix(d.t.background, d.t.foreground, 42);
	const cells: string[] = [];
	const pulses: string[][] = Array.from({ length: PULSES }, () => []);
	for (let y = 0; y + s(20) <= H; y += s(20)) {
		for (let x = s(4); x + s(16) <= W; x += s(20)) {
			const p = density(x, y);
			if (p <= 0 || next() >= p) continue;
			cells.push(d.cell(x, y, shades[Math.floor(next() * shades.length)]));
			if (next() < 0.3) pulses[Math.floor(next() * PULSES)].push(d.cell(x, y, glow));
		}
	}
	return { cells: cells.join(""), pulses: pulses.map((layer) => d.svg(layer.join(""), false)) };
}

// Side strips: denser toward the screen edge.
function stripBlocks(d: Draw): Blocks {
	const { screen, s } = d.m;
	const right = screen.x + screen.w;
	return blocks(d, 9, (x) => {
		if (x + s(16) <= screen.x - s(2)) return 0.25 + (0.2 * (x - s(4))) / s(20);
		if (x >= right + s(4)) return 0.25 + (0.2 * (d.m.W - s(16) - x)) / s(20);
		return 0;
	});
}

// Card blocks: thinning toward the card, with a clear margin around it.
function cardBlocks(d: Draw): Blocks {
	const { card, s } = d.m;
	const margin = s(40);
	return blocks(d, 11, (x, y) => {
		const dx = Math.max(card.x - margin - x - s(16), x - (card.x + card.w + margin), 0);
		const dy = Math.max(card.y - margin - y - s(18), y - (card.y + card.h + margin), 0);
		const distance = Math.max(dx, dy);
		return distance > 0 ? Math.min(0.1 + distance / s(400), 0.6) : 0;
	});
}

function drawAssets(g: Geometry, t: Theme): Map<string, string> {
	const m = metrics(g);
	const d = new Draw(m, t);
	const files = new Map<string, string>();
	const { s, screen } = m;

	// Bands are the bar crop's leftover height, too thin for a block cell, so
	// they carry the ground and the screen's edge alone.
	if (m.strips || m.bands) {
		const strips = m.strips ? stripBlocks(d) : { cells: "", pulses: [] as string[] };
		const edges = (m.strips ? [screen.x - m.stroke / 2, screen.x + screen.w + m.stroke / 2] : [])
			.map((x) => `<line x1="${x}" y1="0" x2="${x}" y2="${m.H}" stroke="${d.border}" stroke-width="${m.stroke}"/>`)
			.concat((m.bands ? [screen.y - m.stroke / 2, screen.y + screen.h + m.stroke / 2] : [])
				.map((y) => `<line x1="0" y1="${y}" x2="${m.W}" y2="${y}" stroke="${d.border}" stroke-width="${m.stroke}"/>`))
			.join("");
		files.set("screen.svg", d.svg(strips.cells + edges, true));
		strips.pulses.forEach((layer, k) => files.set(`strip-pulse-${k}.svg`, layer));
	}

	let overlay = "";
	for (const [name, r] of [["camera", m.cam], ["chat", m.chat], ["time", m.time]] as const) {
		overlay += d.translucent(r) + d.box(r, name, name === "camera" ? t.accent : d.border);
	}
	["now", "date"].forEach((label, i) => {
		overlay += d.text(m.time.x + s(20), m.time.y + s(28) + i * s(30), label, d.muted);
	});
	files.set("stream-overlay.svg", d.svg(overlay, false));

	const frame = `<rect x="${m.fullCam.x}" y="${m.fullCam.y}" width="${m.fullCam.w}" height="${m.fullCam.h}" fill="${t.background}"/>`;
	files.set("cam-frame.svg", d.svg(frame + d.box(m.fullCam, "camera", t.accent), false));

	const cards = cardBlocks(d);
	cards.pulses.forEach((layer, k) => files.set(`card-pulse-${k}.svg`, layer));
	for (const card of CARDS) {
		const color = card.color === "red" ? t.red : t.accent;
		let body = cards.cells + d.box(m.card, card.label, color, m.stroke + s(1));
		if (card.headline) body += d.text(Math.floor(m.W / 2), m.card.y + s(140), card.headline, t.foreground, s(64), "middle", "bold");
		body += d.text(Math.floor(m.W / 2), m.card.y + m.card.h - s(70), card.sub, d.muted, m.fontSize, "middle");
		files.set(`card-${card.key}.svg`, d.svg(body, true));
	}

	const texts = Object.entries(m.texts).map(([name, text]) => `${name}\t${obsColor(t[text.color])}\t${text.size}`);
	files.set("theme.txt", [`face=${t.font}`, ...texts].join("\n") + "\n");
	files.set("chat.css", chatCss(t, s(16)));
	return files;
}

// Page markup of Twitch popout chat and YouTube live_chat is undocumented, so a
// site redesign can break parts of this styling.
function chatCss(t: Theme, size: number): string {
	const muted = mix(t.foreground, t.background, 45);
	return `:root, html, body { background: transparent !important; }
* { font-family: "${t.font}", monospace !important; }

/* Twitch */
:root, .tw-root--theme-dark, .tw-root--theme-light {
  --color-background-base: transparent !important;
  --color-background-body: transparent !important;
  --color-background-alt: transparent !important;
  --color-text-base: ${t.foreground} !important;
  --color-text-alt: ${muted} !important;
  --color-text-alt-2: ${muted} !important;
  --color-text-link: ${t.accent} !important;
  --color-border-base: transparent !important;
}
.stream-chat-header, .chat-input, .chat-input__buttons-container, [data-a-target="chat-welcome-message"],
.chat-paused-footer { display: none !important; }
/* The highlight stack: hype trains, pinned and paid messages, leaderboards. */
[class*="community-highlight"], [class*="hype-train"], [data-test-selector*="hype-train"], [class*="pinned-chat"],
[class*="paid-pinned"], [class*="channel-leaderboard"], [class*="chat-room__notifications"],
[class*="consent-banner"] { display: none !important; }
.chat-room, .chat-shell, .stream-chat, .chat-scrollable-area__message-container,
.chat-list--default, .chat-list--other { background: transparent !important; }
.chat-line__message, .text-fragment { color: ${t.foreground} !important; font-size: ${size}px !important; }
.chat-line__message { padding: 2px 0 !important; }

/* YouTube */
yt-live-chat-renderer, yt-live-chat-item-list-renderer, #item-scroller, #items, #contents {
  --yt-live-chat-background-color: transparent !important;
  --yt-live-chat-primary-text-color: ${t.foreground} !important;
  --yt-live-chat-secondary-text-color: ${muted} !important;
  background: transparent !important;
}
yt-live-chat-header-renderer, #input-panel, yt-live-chat-ticker-renderer, #panel-pages,
yt-live-chat-banner-manager, #show-more { display: none !important; }
yt-live-chat-text-message-renderer { padding: 2px 0 !important; }
yt-live-chat-text-message-renderer #message { color: ${t.foreground} !important; font-size: ${size}px !important; }
yt-live-chat-text-message-renderer #author-name { color: ${t.accent} !important; }
#author-photo, yt-img-shadow#author-photo { display: none !important; }
`;
}

// ---------------------------------------------------------------------------
// Camera-off avatar: the human's Craiyon portrait, recoloured from the theme and
// cut into layers that omarchy-scene.lua animates. The crop, head, eye and band
// geometry below belongs to that one image, so any other file is refused.

const AVATAR_SHA256 = "df58402f9dde4149751c0a6dae239169efb752cc567849431c0836fd664dcf02";
const AVATAR_W = 400;
const AVATAR_H = 225;
const AVATAR_CROP = "860x484+0+180";
// Boxes in avatar pixels: [left, top, right, bottom), from the source geometry scaled by 400/860.
const HEAD_BOX = [105, 9, 286, 191];
const EYES_BOX = [153, 99, 229, 117];
// Head bands, bottom to top: rows below 165 stay in the back layer.
const BAND_BOTTOMS = [165, 128, 72];
const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];

type Pixel = { kind: "base" | "hot" | "warm"; value: number };
type Layer = (string | null)[];

function magick(args: string[], input?: Uint8Array): Buffer {
	const result = Bun.spawnSync(["magick", ...args], { stdin: input, stdout: "pipe", stderr: "pipe" });
	if (result.exitCode !== 0) throw new Error(`magick failed: ${result.stderr.toString().trim()}`);
	return result.stdout;
}

function classify(r: number, g: number, b: number): Pixel {
	const max = Math.max(r, g, b);
	const min = Math.min(r, g, b);
	const value = max / 255;
	const saturation = max === 0 ? 0 : (max - min) / max;
	let hue = 0;
	if (max !== min) {
		if (max === r) hue = (60 * (g - b)) / (max - min);
		else if (max === g) hue = 120 + (60 * (b - r)) / (max - min);
		else hue = 240 + (60 * (r - g)) / (max - min);
		hue = (hue + 360) % 360;
	}
	if (saturation > 0.35 && value > 0.3 && (hue > 320 || hue < 15)) return { kind: "hot", value };
	if (saturation > 0.4 && value > 0.3 && hue >= 15 && hue < 50) return { kind: "warm", value };
	return { kind: "base", value: (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 };
}

const inBox = (x: number, y: number, box: number[]) => x >= box[0] && x < box[2] && y >= box[1] && y < box[3];

function avatarLayers(image: Buffer, t: Theme): Map<string, Layer> {
	const black = "#000000";
	const white = "#ffffff";
	const pixels: Pixel[] = [];
	for (let i = 0; i < AVATAR_W * AVATAR_H; i++) pixels.push(classify(image[3 * i], image[3 * i + 1], image[3 * i + 2]));
	const at = (x: number, y: number) => pixels[y * AVATAR_W + x];

	// The base ramp spans the image's own luminance, trimmed of outliers.
	const values = pixels.filter((p) => p.kind === "base").map((p) => p.value).sort((a, b) => a - b);
	const low = values[Math.floor(values.length / 50)];
	const high = values[values.length - 1 - Math.floor(values.length / 200)];
	const bg = t.background;
	const fg = t.foreground;
	const ramp = t.mode === "light"
		? [mix(fg, black, 50), mix(fg, black, 20), fg, mix(fg, bg, 25), mix(fg, bg, 50), mix(fg, bg, 70)]
		: [mix(bg, black, 60), mix(bg, black, 30), bg, mix(bg, fg, 10), mix(bg, fg, 20), mix(bg, fg, 34)];
	const hot = [mix(t.accent, bg, 55), mix(t.accent, bg, 30), t.accent, mix(t.accent, white, 45)];
	const warm = [mix(t.yellow, bg, 40), t.yellow];
	const face = t.mode === "light" ? mix(fg, black, 40) : mix(bg, black, 55);
	const clamp = (n: number, top: number) => Math.max(0, Math.min(top, Math.trunc(n)));

	const painted: string[] = [];
	for (let y = 0; y < AVATAR_H; y++) {
		for (let x = 0; x < AVATAR_W; x++) {
			const p = at(x, y);
			const dither = (BAYER[y % 4][x % 4] + 0.5) / 16 - 0.5;
			if (p.kind === "hot") painted.push(hot[clamp(((p.value - 0.3) / 0.7) * 4 + dither * 0.6, 3)]);
			else if (p.kind === "warm") painted.push(warm[p.value < 0.65 ? 0 : 1]);
			else painted.push(ramp[clamp(((p.value - low) / Math.max(high - low, 1e-6)) * 6 + dither * 0.8, 5)]);
		}
	}
	const color = (x: number, y: number) => painted[y * AVATAR_W + x];

	// The head is everything between the outermost rim pixels of each row.
	const head: [number, number][] = [];
	for (let y = HEAD_BOX[1]; y < HEAD_BOX[3]; y++) {
		const rim: number[] = [];
		for (let x = HEAD_BOX[0]; x < HEAD_BOX[2]; x++) {
			if (at(x, y).kind === "hot" && !inBox(x, y, EYES_BOX)) rim.push(x);
		}
		if (rim.length >= 2 && rim[rim.length - 1] - rim[0] > 8) {
			for (let x = rim[0]; x <= rim[rim.length - 1]; x++) head.push([x, y]);
		}
	}
	const eyes = new Set<number>();
	const glow = new Set<number>();
	for (let y = EYES_BOX[1]; y < EYES_BOX[3]; y++) {
		for (let x = EYES_BOX[0]; x < EYES_BOX[2]; x++) {
			const p = at(x, y);
			if (p.kind === "hot") (p.value > 0.6 ? eyes : glow).add(y * AVATAR_W + x);
		}
	}

	const empty = (): Layer => new Array(AVATAR_W * AVATAR_H).fill(null);
	const layers = new Map<string, Layer>([
		["back", [...painted]], ["head1", empty()], ["head2", empty()], ["head3", empty()], ["eyes", empty()], ["glow", empty()],
	]);
	// The head bends instead of sliding: bands 1 to 3 move a third, two thirds
	// and all of the nod. Only the top band uncovers the back layer, so its
	// area there is patched with the sky colour of the same row.
	for (const [x, y] of head) {
		const band = y < BAND_BOTTOMS[2] ? 3 : y < BAND_BOTTOMS[1] ? 2 : y < BAND_BOTTOMS[0] ? 1 : 0;
		if (band === 0) continue;
		const i = y * AVATAR_W + x;
		layers.get(`head${band}`)![i] = eyes.has(i) || glow.has(i) ? face : color(x, y);
		if (band === 3) layers.get("back")![i] = color(Math.max(0, HEAD_BOX[0] - 6), y);
	}
	for (const i of eyes) layers.get("eyes")![i] = painted[i];
	for (const i of glow) layers.get("glow")![i] = painted[i];
	// A soft halo one pixel around the eyes.
	for (const i of eyes) {
		const x = i % AVATAR_W;
		const y = Math.floor(i / AVATAR_W);
		for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1], [2, 0], [-2, 0]]) {
			const nx = x + dx;
			const ny = y + dy;
			const n = ny * AVATAR_W + nx;
			if (nx >= 0 && nx < AVATAR_W && ny >= 0 && ny < AVATAR_H && !eyes.has(n) && !glow.has(n)) layers.get("glow")![n] = hot[1];
		}
	}
	return layers;
}

function encodePng(layer: Layer): Uint8Array {
	const rgba = new Uint8Array(AVATAR_W * AVATAR_H * 4);
	layer.forEach((hex, i) => {
		if (hex === null) return;
		rgba.set([...channels(hex), 255], 4 * i);
	});
	return magick(["-size", `${AVATAR_W}x${AVATAR_H}`, "-depth", "8", "rgba:-", "-strip",
		"-define", "png:exclude-chunks=date,time", "png:-"], rgba);
}

// Fails when the image is missing or not the pinned one. Every scene collection
// declares the six avatar sources, so a render without them leaves OBS pointing
// at files that never arrive.
function drawAvatar(file: string, t: Theme): Map<string, Uint8Array> {
	let image: Buffer;
	try {
		image = fs.readFileSync(file);
	} catch {
		throw new Error(`no avatar image at ${file}; apply the obs-scene package, which links the portrait it tracks`);
	}
	if (crypto.createHash("sha256").update(image).digest("hex") !== AVATAR_SHA256) {
		throw new Error(`${file} is not the pinned avatar image; restore the portrait the obs-scene package tracks`);
	}
	const pixels = magick(["-", "-crop", AVATAR_CROP, "+repage", "-filter", "box", "-resize", `${AVATAR_W}x${AVATAR_H}!`,
		"-depth", "8", "rgb:-"], image);
	const files = new Map<string, Uint8Array>();
	for (const [name, layer] of avatarLayers(pixels, t)) files.set(`avatar-${name}.png`, encodePng(layer));
	return files;
}

// ---------------------------------------------------------------------------
// Scene collection: OBS's version-2 JSON. Sources get stable name-based UUIDs,
// so a fresh generation from the same geometry is byte-identical.

const COLLECTION_NAME = "Omarchy Scene";
const SCENE_ASSETS = "$HOME/.config/obs-studio/omarchy-scene";
const SCENE_SCRIPT = "$HOME/.local/libexec/dotfiles/obs-scene/omarchy-scene.lua";
const MAIN_CANVAS_UUID = "6c69626f-6273-4c00-9d88-c5136d61696e";
const ALIGN_TOP_LEFT = 5;
const ALIGN_CENTER = 0;
const BOUNDS_SCALE_INNER = 2;

// RFC 4122 version 5 UUID in the URL namespace.
function uuid(name: string): string {
	const namespace = Buffer.from("6ba7b8119dad11d180b400c04fd430c8", "hex");
	const hash = crypto.createHash("sha1").update(namespace).update(`omarchy-scene/${name}`).digest();
	hash[6] = (hash[6] & 0x0f) | 0x50;
	hash[8] = (hash[8] & 0x3f) | 0x80;
	const hex = hash.subarray(0, 16).toString("hex");
	return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

type Json = Record<string, unknown>;

function source(name: string, id: string, settings: Json, extra: Json = {}, versionedId = id): Json {
	return {
		prev_ver: 537001986, name, uuid: uuid(name), id, versioned_id: versionedId, settings,
		mixers: 0, sync: 0, flags: 0, volume: 1.0, balance: 0.5, enabled: true, muted: false,
		hotkeys: {}, private_settings: {}, ...extra,
	};
}

function opacityFilter(owner: string, name: string, opacity: number): Json {
	return source(`${owner} ${name} filter`, "color_filter", { opacity }, { name }, "color_filter_v2");
}

function image(name: string, file: string, filters: Json[] = []): Json {
	return source(name, "image_source", { file: `${SCENE_ASSETS}/${file}` }, filters.length ? { filters } : {});
}

function textSource(name: string, size: number, settings: Json): Json {
	return source(name, "text_ft2_source", {
		font: { face: "Monospace", style: "Regular", size, flags: 0 }, color1: 4294967295, color2: 4294967295, ...settings,
	}, {}, "text_ft2_source_v2");
}

type Placement = { source: string; x: number; y: number; bounds?: [number, number]; align?: number; cropTop?: number; point?: boolean };

function item(m: Metrics, id: number, p: Placement): Json {
	const [bw, bh] = p.bounds ?? [0, 0];
	return {
		name: p.source, source_uuid: uuid(p.source), visible: true, locked: true, rot: 0.0,
		scale_ref: { x: m.W, y: m.H }, align: p.align ?? ALIGN_TOP_LEFT,
		bounds_type: p.bounds ? BOUNDS_SCALE_INNER : 0, bounds_align: 0, bounds_crop: false,
		crop_left: 0, crop_top: p.cropTop ?? 0, crop_right: 0, crop_bottom: 0, id, group_item_backup: false,
		pos: { x: p.x, y: p.y }, pos_rel: { x: (2 * p.x - m.W) / m.H, y: (2 * p.y - m.H) / m.H },
		scale: { x: 1.0, y: 1.0 }, scale_rel: { x: 1.0, y: 1.0 },
		bounds: { x: bw, y: bh }, bounds_rel: { x: (2 * bw) / m.H, y: (2 * bh) / m.H },
		scale_filter: p.point ? "point" : "lanczos", blend_method: "default", blend_type: "normal",
		private_settings: {},
	};
}

const AVATAR_SOURCES = ["back", "head1", "head2", "head3", "eyes", "glow"].map((k) => `Avatar ${k}`);
const pulses = (prefix: string) => Array.from({ length: PULSES }, (_, k) => `${prefix} pulse ${k}`);

// Scene contents, bottom to top.
function scenes(m: Metrics): [string, Placement[]][] {
	const at = (name: string, x = 0, y = 0): Placement => ({ source: name, x, y });
	const inside = (r: Rect) => ({ x: r.x + m.inset, y: r.y + m.inset });
	const camera = (r: Rect): Placement[] => {
		const { x, y } = inside(r);
		const bounds: [number, number] = [m.camW, m.camH];
		return [{ source: "Camera", x, y, bounds }, ...AVATAR_SOURCES.map((name) => ({ source: name, x, y, bounds, point: true }))];
	};
	const screen: Placement[] = [
		...(m.strips || m.bands ? [at("Screen chrome")] : []),
		...(m.strips ? pulses("Strip").map((name) => at(name)) : []),
		{ source: "Screen", x: m.screen.x, y: m.screen.y, bounds: [m.screen.w, m.screen.h], cropTop: m.barCrop },
	];
	const text = (name: keyof Metrics["texts"], align = ALIGN_TOP_LEFT): Placement => ({
		source: name, x: m.texts[name].x, y: m.texts[name].y, align,
	});
	const cardText: Record<string, Placement[]> = {
		starting: [text("Countdown", ALIGN_CENTER)],
		intro: [text("Title", ALIGN_CENTER)],
	};
	return [
		["Stream", [...screen, at("Stream overlay"), ...camera(m.cam), { source: "Chat", ...inside(m.chat) }, text("Clock"), text("Date")]],
		["Full", screen],
		["Full cam", [...screen, at("Camera frame"), ...camera(m.fullCam)]],
		...CARDS.map((card): [string, Placement[]] => [
			card.scene, [at(`Card ${card.key}`), ...pulses("Card").map((name) => at(name)), ...(cardText[card.key] ?? [])],
		]),
	];
}

function collection(g: Geometry): Json {
	const m = metrics(g);
	const audio = (name: string, id: string) => source(name, id, { device_id: "default" }, {
		mixers: 255, hotkeys: { "libobs.mute": [], "libobs.unmute": [], "libobs.push-to-mute": [], "libobs.push-to-talk": [] },
	});
	const blur = source("Camera background blur", "background_removal", {
		blur_background: 4, enable_threshold: true, threshold: 0.5, useGPU: "cpu",
		model_select: "models/mediapipe.with_runtime_opt.ort", numThreads: 2,
	}, { name: "background blur" });
	const sources: Json[] = [
		source("Screen", "pipewire-screen-capture-source", {}),
		source("Camera", "v4l2_input", {}, { filters: [blur] }),
		source("Chat", "browser_source", {
			url: "about:blank", width: m.camW, height: m.chat.h - 2 * m.inset, css: "",
			reroute_audio: false, shutdown: false, restart_when_active: false,
		}),
		textSource("Clock", m.texts.Clock.size, { text: "--:--:--" }),
		textSource("Date", m.texts.Date.size, { text: "----------" }),
		textSource("Countdown", m.texts.Countdown.size, { text: "05:00" }),
		textSource("Title", m.texts.Title.size, { from_file: true, text_file: `${SCENE_ASSETS}/title.txt` }),
		image("Stream overlay", "stream-overlay.svg"),
		image("Camera frame", "cam-frame.svg"),
		...AVATAR_SOURCES.map((name) => {
			const layer = name.replace("Avatar ", "");
			return image(name, `avatar-${layer}.png`, layer === "glow" ? [opacityFilter(name, "glow", 1.0)] : []);
		}),
		...CARDS.map((card) => image(`Card ${card.key}`, `card-${card.key}.svg`)),
		...pulses("Card").map((name, k) => image(name, `card-pulse-${k}.svg`, [opacityFilter(name, "pulse", 0.0)])),
	];
	if (m.strips || m.bands) sources.push(image("Screen chrome", "screen.svg"));
	if (m.strips) {
		sources.push(...pulses("Strip").map((name, k) => image(name, `strip-pulse-${k}.svg`, [opacityFilter(name, "pulse", 0.0)])));
	}
	const order = scenes(m);
	for (const [name, placements] of order) {
		const items = placements.map((p, i) => item(m, i + 1, p));
		sources.push(source(name, "scene", { id_counter: items.length, custom_size: false, items }, { canvas_uuid: MAIN_CANVAS_UUID }));
	}
	return {
		name: COLLECTION_NAME,
		DesktopAudioDevice1: audio("Desktop Audio", "pulse_output_capture"),
		AuxAudioDevice1: audio("Mic/Aux", "pulse_input_capture"),
		current_scene: "Stream",
		current_program_scene: "Stream",
		scene_order: order.map(([name]) => ({ name })),
		sources,
		groups: [],
		quick_transitions: [
			{ name: "Cut", duration: 300, hotkeys: [], id: 1, fade_to_black: false },
			{ name: "Fade", duration: 300, hotkeys: [], id: 2, fade_to_black: false },
			{ name: "Fade", duration: 300, hotkeys: [], id: 3, fade_to_black: true },
		],
		transitions: [],
		current_transition: "Fade",
		transition_duration: 300,
		saved_projectors: [],
		canvases: [],
		modules: { "scripts-tool": [{ path: SCENE_SCRIPT, settings: {} }] },
		resolution: { x: m.W, y: m.H },
		version: 2,
	};
}

// ---------------------------------------------------------------------------
// Output

function publish(dir: string, name: string, data: string | Uint8Array): void {
	const target = path.join(dir, name);
	const content = typeof data === "string" ? Buffer.from(data) : Buffer.from(data);
	try {
		if (fs.readFileSync(target).equals(content)) return;
	} catch {
		// A missing target is written below.
	}
	const temporary = path.join(dir, `.${name}.${crypto.randomBytes(6).toString("hex")}`);
	try {
		fs.writeFileSync(temporary, content, { flag: "wx", mode: 0o644 });
		fs.renameSync(temporary, target);
	} catch (error) {
		fs.rmSync(temporary, { force: true });
		throw error;
	}
}

function options(args: string[], names: string[]): Record<string, string> {
	const result: Record<string, string> = {};
	for (let i = 0; i < args.length; i += 2) {
		const name = args[i]?.replace(/^--/, "");
		if (!names.includes(name) || args[i + 1] === undefined) throw new Error(`unexpected argument: ${args[i]}`);
		result[name] = args[i + 1];
	}
	for (const name of names) if (!(name in result)) throw new Error(`missing --${name}`);
	return result;
}

function render(args: string[]): void {
	const o = options(args, ["geometry", "colors", "font", "avatar", "output"]);
	const geometry = readGeometry(o.geometry);
	const theme = readTheme(o.colors, o.font);
	// Everything is drawn before the first write, so a failure leaves the last output in place.
	const files = new Map<string, string | Uint8Array>([...drawAssets(geometry, theme), ...drawAvatar(o.avatar, theme)]);
	fs.mkdirSync(o.output, { recursive: true });
	for (const [name, data] of files) publish(o.output, name, data);
	if (!fs.existsSync(path.join(o.output, "title.txt"))) publish(o.output, "title.txt", "Untitled episode\n");
}

function writeCollection(args: string[]): void {
	const o = options(args, ["geometry", "output"]);
	const json = JSON.stringify(collection(readGeometry(o.geometry)), null, 1) + "\n";
	publish(path.dirname(o.output), path.basename(o.output), json);
}

function main(): void {
	const [mode, ...args] = process.argv.slice(2);
	try {
		if (mode === "render") render(args);
		else if (mode === "collection") writeCollection(args);
		else throw new Error("usage: generate.ts render --geometry FILE --colors FILE --font NAME --avatar FILE --output DIR\n" +
			"       generate.ts collection --geometry FILE --output FILE");
	} catch (error) {
		console.error(`obs-scene generator: ${error instanceof Error ? error.message : error}`);
		process.exit(1);
	}
}

if (import.meta.main) main();
