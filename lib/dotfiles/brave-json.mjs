#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { constants } from 'node:fs';
import { lstat, open, unlink } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { TextDecoder } from 'node:util';

const TARGET = '/etc/brave/policies/managed/dotfiles.json';
const SOURCE = 'brave/managed-policy.json';
const SCHEMA_VERSION = 1;
const DIGEST = /^[0-9a-f]{64}$/;
const TRANSACTION_ID = /^\d{8}T\d{6}Z-[0-9]+-[0-9a-f]{8}$/;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const MODE = /^[0-7]{4}$/;

const CANONICAL_POLICY = {
	BackgroundModeEnabled: false,
	BookmarkBarEnabled: true,
	BraveAIChatEnabled: false,
	BraveP3AEnabled: false,
	EnableMediaRouter: true,
	ExtensionSettings: {
		bgnkhhnnamicmpeenaelnjfhikgbkllg: {
			installation_mode: 'normal_installed',
			update_url: 'https://clients2.google.com/service/update2/crx',
		},
		nngceckbapebfimnlniiiahkandclblb: {
			installation_mode: 'normal_installed',
			update_url: 'https://clients2.google.com/service/update2/crx',
		},
	},
	HomepageIsNewTabPage: true,
	MetricsReportingEnabled: false,
	ShowHomeButton: false,
	SpellcheckEnabled: true,
	SpellcheckLanguage: ['en-US'],
};

class DuplicateAwareJsonParser {
	constructor(text) {
		this.text = text;
		this.offset = 0;
	}

	parse() {
		this.skipWhitespace();
		const value = this.parseValue('$');
		this.skipWhitespace();
		if (this.offset !== this.text.length) {
			this.fail('unexpected content after the JSON value');
		}
		return value;
	}

	parseValue(location) {
		const character = this.text[this.offset];
		if (character === '{') return this.parseObject(location);
		if (character === '[') return this.parseArray(location);
		if (character === '"') return this.parseString();
		if (character === 't') return this.parseKeyword('true', true);
		if (character === 'f') return this.parseKeyword('false', false);
		if (character === 'n') return this.parseKeyword('null', null);
		if (character === '-' || (character >= '0' && character <= '9')) return this.parseNumber();
		this.fail('expected a JSON value');
	}

	parseObject(location) {
		this.offset += 1;
		const result = Object.create(null);
		const members = new Set();
		this.skipWhitespace();
		if (this.text[this.offset] === '}') {
			this.offset += 1;
			return result;
		}

		while (true) {
			if (this.text[this.offset] !== '"') this.fail('expected an object member name');
			const name = this.parseString();
			if (members.has(name)) {
				throw new Error(`duplicate object member ${JSON.stringify(name)} at ${location}`);
			}
			members.add(name);
			this.skipWhitespace();
			if (this.text[this.offset] !== ':') this.fail('expected a colon after an object member name');
			this.offset += 1;
			this.skipWhitespace();
			result[name] = this.parseValue(`${location}.${name}`);
			this.skipWhitespace();
			const separator = this.text[this.offset];
			if (separator === '}') {
				this.offset += 1;
				return result;
			}
			if (separator !== ',') this.fail('expected a comma or closing brace');
			this.offset += 1;
			this.skipWhitespace();
		}
	}

	parseArray(location) {
		this.offset += 1;
		const result = [];
		this.skipWhitespace();
		if (this.text[this.offset] === ']') {
			this.offset += 1;
			return result;
		}

		while (true) {
			result.push(this.parseValue(`${location}[${result.length}]`));
			this.skipWhitespace();
			const separator = this.text[this.offset];
			if (separator === ']') {
				this.offset += 1;
				return result;
			}
			if (separator !== ',') this.fail('expected a comma or closing bracket');
			this.offset += 1;
			this.skipWhitespace();
		}
	}

	parseString() {
		this.offset += 1;
		let result = '';
		while (this.offset < this.text.length) {
			const character = this.text[this.offset++];
			if (character === '"') return result;
			if (character === '\\') {
				if (this.offset >= this.text.length) this.fail('unterminated string escape');
				const escape = this.text[this.offset++];
				const simpleEscapes = {
					'"': '"',
					'\\': '\\',
					'/': '/',
					b: '\b',
					f: '\f',
					n: '\n',
					r: '\r',
					t: '\t',
				};
				if (Object.hasOwn(simpleEscapes, escape)) {
					result += simpleEscapes[escape];
					continue;
				}
				if (escape !== 'u') this.fail('invalid string escape');
				const first = this.parseHexCodeUnit();
				if (first >= 0xd800 && first <= 0xdbff) {
					if (this.text.slice(this.offset, this.offset + 2) !== '\\u') {
						this.fail('high surrogate is not followed by a low surrogate');
					}
					this.offset += 2;
					const second = this.parseHexCodeUnit();
					if (second < 0xdc00 || second > 0xdfff) this.fail('invalid low surrogate');
					result += String.fromCodePoint(0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00));
				} else if (first >= 0xdc00 && first <= 0xdfff) {
					this.fail('unpaired low surrogate');
				} else {
					result += String.fromCharCode(first);
				}
				continue;
			}
			if (character.charCodeAt(0) < 0x20) this.fail('unescaped control character in string');
			result += character;
		}
		this.fail('unterminated string');
	}

	parseHexCodeUnit() {
		const digits = this.text.slice(this.offset, this.offset + 4);
		if (!/^[0-9a-fA-F]{4}$/.test(digits)) this.fail('invalid Unicode escape');
		this.offset += 4;
		return Number.parseInt(digits, 16);
	}

	parseKeyword(keyword, value) {
		if (this.text.slice(this.offset, this.offset + keyword.length) !== keyword) {
			this.fail(`invalid token; expected ${keyword}`);
		}
		this.offset += keyword.length;
		return value;
	}

	parseNumber() {
		const remainder = this.text.slice(this.offset);
		const match = /^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/.exec(remainder);
		if (!match) this.fail('invalid number');
		this.offset += match[0].length;
		const value = Number(match[0]);
		if (!Number.isFinite(value)) this.fail('number is outside the supported finite range');
		return value;
	}

	skipWhitespace() {
		while (this.offset < this.text.length && /[\u0009\u000a\u000d\u0020]/.test(this.text[this.offset])) {
			this.offset += 1;
		}
	}

	fail(message) {
		throw new Error(`${message} at byte ${Buffer.byteLength(this.text.slice(0, this.offset), 'utf8')}`);
	}
}

function isObject(value) {
	return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function assert(condition, message) {
	if (!condition) throw new Error(message);
}

function assertExactKeys(value, keys, location) {
	assert(isObject(value), `${location} must be an object`);
	const actual = Object.keys(value).sort();
	const expected = [...keys].sort();
	assert(
		actual.length === expected.length && actual.every((key, index) => key === expected[index]),
		`${location} must contain exactly: ${expected.join(', ')}`,
	);
}

function assertExactValue(actual, expected, location = '$') {
	if (Array.isArray(expected)) {
		assert(Array.isArray(actual), `${location} must be an array`);
		assert(actual.length === expected.length, `${location} must contain exactly ${expected.length} entries`);
		expected.forEach((value, index) => assertExactValue(actual[index], value, `${location}[${index}]`));
		return;
	}
	if (isObject(expected)) {
		assertExactKeys(actual, Object.keys(expected), location);
		for (const [key, value] of Object.entries(expected)) {
			assertExactValue(actual[key], value, `${location}.${key}`);
		}
		return;
	}
	assert(typeof actual === typeof expected && Object.is(actual, expected), `${location} has an unexpected value`);
}

function assertString(value, pattern, location) {
	assert(typeof value === 'string' && pattern.test(value), `${location} has an invalid value`);
}

function assertTimestamp(value, location) {
	assertString(value, TIMESTAMP, location);
	const parsed = Date.parse(value);
	assert(Number.isFinite(parsed), `${location} is not a real UTC timestamp`);
	assert(new Date(parsed).toISOString() === value.replace(/Z$/, '.000Z'), `${location} is not a normalized UTC timestamp`);
}

function assertTransactionId(value, location) {
	assertString(value, TRANSACTION_ID, location);
	const compact = value.slice(0, 16);
	const timestamp = `${compact.slice(0, 4)}-${compact.slice(4, 6)}-${compact.slice(6, 11)}:${compact.slice(11, 13)}:${compact.slice(13, 15)}Z`;
	assertTimestamp(timestamp, location);
}

function assertMetadata(value, location) {
	assertExactKeys(value, ['present', 'uid', 'gid', 'mode'], location);
	assert(typeof value.present === 'boolean', `${location}.present must be boolean`);
	if (value.present) {
		assert(Number.isSafeInteger(value.uid) && value.uid >= 0, `${location}.uid must be a non-negative integer`);
		assert(Number.isSafeInteger(value.gid) && value.gid >= 0, `${location}.gid must be a non-negative integer`);
		assertString(value.mode, MODE, `${location}.mode`);
	} else {
		assert(value.uid === null && value.gid === null && value.mode === null, `${location} absent metadata must be null`);
	}
}

function assertContainedPath(value, expected, stateRoot, location) {
	assert(typeof value === 'string' && path.isAbsolute(value), `${location} must be an absolute path`);
	const resolved = path.resolve(value);
	const relative = path.relative(stateRoot, resolved);
	assert(relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative), `${location} escapes the state root`);
	assert(resolved === expected, `${location} does not match the fixed transaction backup path`);
}

function assertPriorTarget(value, stateRoot, transactionId, location) {
	assertExactKeys(value, ['present', 'digest', 'uid', 'gid', 'mode', 'backup_path'], location);
	assert(typeof value.present === 'boolean', `${location}.present must be boolean`);
	if (value.present) {
		assertString(value.digest, DIGEST, `${location}.digest`);
		assert(Number.isSafeInteger(value.uid) && value.uid >= 0, `${location}.uid must be a non-negative integer`);
		assert(Number.isSafeInteger(value.gid) && value.gid >= 0, `${location}.gid must be a non-negative integer`);
		assertString(value.mode, MODE, `${location}.mode`);
		assertContainedPath(
			value.backup_path,
			path.join(stateRoot, 'backups', transactionId, 'dotfiles.json'),
			stateRoot,
			`${location}.backup_path`,
		);
	} else {
		assert(
			value.digest === null && value.uid === null && value.gid === null && value.mode === null && value.backup_path === null,
			`${location} absent target fields must be null`,
		);
	}
}

function assertPriorActive(value, stateRoot, transactionId, location) {
	assertExactKeys(value, ['present', 'digest', 'backup_path'], location);
	assert(typeof value.present === 'boolean', `${location}.present must be boolean`);
	if (value.present) {
		assertString(value.digest, DIGEST, `${location}.digest`);
		assertContainedPath(
			value.backup_path,
			path.join(stateRoot, 'backups', transactionId, 'active.json'),
			stateRoot,
			`${location}.backup_path`,
		);
	} else {
		assert(value.digest === null && value.backup_path === null, `${location} absent active fields must be null`);
	}
}

function assertPending(value, stateRoot, location = '$') {
	assertExactKeys(
		value,
		[
			'schema_version',
			'kind',
			'operation',
			'transaction_id',
			'created_at',
			'target',
			'prior_target',
			'desired_digest',
			'stage_path',
			'managed_directory_original',
			'prior_active',
		],
		location,
	);
	assert(value.schema_version === SCHEMA_VERSION, `${location}.schema_version must be ${SCHEMA_VERSION}`);
	assert(value.kind === 'pending', `${location}.kind must be pending`);
	assert(value.operation === 'apply' || value.operation === 'remove', `${location}.operation is invalid`);
	assertTransactionId(value.transaction_id, `${location}.transaction_id`);
	assertTimestamp(value.created_at, `${location}.created_at`);
	assert(value.target === TARGET, `${location}.target must be ${TARGET}`);
	assertPriorTarget(value.prior_target, stateRoot, value.transaction_id, `${location}.prior_target`);
	assertMetadata(value.managed_directory_original, `${location}.managed_directory_original`);
	assertPriorActive(value.prior_active, stateRoot, value.transaction_id, `${location}.prior_active`);
	if (value.operation === 'apply') {
		assertString(value.desired_digest, DIGEST, `${location}.desired_digest`);
		assert(
			value.stage_path === `/etc/brave/policies/.dotfiles-${value.transaction_id}.stage`,
			`${location}.stage_path does not match the fixed transaction stage`,
		);
	} else {
		assert(value.desired_digest === null && value.stage_path === null, `${location} remove-only fields must be null`);
	}
}

function assertActive(value, location = '$') {
	assertExactKeys(
		value,
		['schema_version', 'kind', 'target', 'source', 'deployed_digest', 'transaction_id', 'activated_at', 'managed_directory_original'],
		location,
	);
	assert(value.schema_version === SCHEMA_VERSION, `${location}.schema_version must be ${SCHEMA_VERSION}`);
	assert(value.kind === 'active', `${location}.kind must be active`);
	assert(value.target === TARGET, `${location}.target must be ${TARGET}`);
	assert(value.source === SOURCE, `${location}.source must be ${SOURCE}`);
	assertString(value.deployed_digest, DIGEST, `${location}.deployed_digest`);
	assertTransactionId(value.transaction_id, `${location}.transaction_id`);
	assertTimestamp(value.activated_at, `${location}.activated_at`);
	assertMetadata(value.managed_directory_original, `${location}.managed_directory_original`);
}

function assertRecovery(value, stateRoot, location = '$') {
	assertExactKeys(value, ['schema_version', 'kind', 'transaction_id', 'created_at', 'failed_step', 'pending'], location);
	assert(value.schema_version === SCHEMA_VERSION, `${location}.schema_version must be ${SCHEMA_VERSION}`);
	assert(value.kind === 'recovery-required', `${location}.kind must be recovery-required`);
	assertTransactionId(value.transaction_id, `${location}.transaction_id`);
	assertTimestamp(value.created_at, `${location}.created_at`);
	assert(typeof value.failed_step === 'string' && /^[a-z0-9-]+$/.test(value.failed_step), `${location}.failed_step is invalid`);
	assertPending(value.pending, stateRoot, `${location}.pending`);
	assert(value.pending.transaction_id === value.transaction_id, `${location} transaction identities do not match`);
}

function isRegularFile(stats) {
	return (stats.mode & BigInt(constants.S_IFMT)) === BigInt(constants.S_IFREG);
}

function sameFile(left, right) {
	return left.dev === right.dev && left.ino === right.ino;
}

function unchangedFile(before, after) {
	return sameFile(before, after)
		&& before.size === after.size
		&& before.mtimeNs === after.mtimeNs
		&& before.ctimeNs === after.ctimeNs;
}

async function readHandle(handle) {
	const chunks = [];
	let position = 0;
	while (true) {
		const buffer = Buffer.allocUnsafe(64 * 1024);
		const { bytesRead } = await handle.read(buffer, 0, buffer.length, position);
		if (bytesRead === 0) break;
		chunks.push(buffer.subarray(0, bytesRead));
		position += bytesRead;
	}
	return Buffer.concat(chunks);
}

async function readRegularNoFollow(file) {
	const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
	try {
		const before = await handle.stat({ bigint: true });
		assert(isRegularFile(before), `input is not a regular file: ${file}`);
		const bytes = await readHandle(handle);
		const after = await handle.stat({ bigint: true });
		assert(unchangedFile(before, after), `input changed while being read: ${file}`);
		assert(after.size === BigInt(bytes.length), `input size changed while being read: ${file}`);
		const pathStats = await lstat(file, { bigint: true });
		assert(isRegularFile(pathStats) && sameFile(after, pathStats), `input path changed while being read: ${file}`);
		return bytes;
	} finally {
		await handle.close();
	}
}

async function copyRegularNoFollow(source, destination) {
	const bytes = await readRegularNoFollow(source);
	const sourceDigest = createHash('sha256').update(bytes).digest('hex');
	let destinationHandle;
	let destinationStats;
	let destinationCreated = false;
	try {
		destinationHandle = await open(
			destination,
			constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
			0o600,
		);
		destinationCreated = true;
		await destinationHandle.chmod(0o600);
		destinationStats = await destinationHandle.stat({ bigint: true });
		assert(isRegularFile(destinationStats), `backup destination is not a regular file: ${destination}`);
		let position = 0;
		while (position < bytes.length) {
			const { bytesWritten } = await destinationHandle.write(bytes, position, bytes.length - position, position);
			assert(bytesWritten > 0, `backup write made no progress: ${destination}`);
			position += bytesWritten;
		}
		await destinationHandle.sync();
		const afterWrite = await destinationHandle.stat({ bigint: true });
		assert(isRegularFile(afterWrite), `backup destination changed type: ${destination}`);
		assert(afterWrite.size === BigInt(bytes.length), `backup destination has an unexpected size: ${destination}`);
		assert((afterWrite.mode & 0o7777n) === 0o600n, `backup destination mode is not 0600: ${destination}`);
		const destinationBytes = await readHandle(destinationHandle);
		const destinationDigest = createHash('sha256').update(destinationBytes).digest('hex');
		assert(destinationDigest === sourceDigest && destinationBytes.equals(bytes), `backup byte verification failed: ${destination}`);
		const pathStats = await lstat(destination, { bigint: true });
		assert(isRegularFile(pathStats) && sameFile(afterWrite, pathStats), `backup destination path changed: ${destination}`);
		return { ok: true, kind: 'no-follow-copy', digest: sourceDigest, bytes: bytes.length };
	} catch (error) {
		if (destinationCreated) {
			try {
				if (!destinationStats && destinationHandle) destinationStats = await destinationHandle.stat({ bigint: true });
				const pathStats = await lstat(destination, { bigint: true });
				if (destinationStats && sameFile(destinationStats, pathStats)) await unlink(destination);
			} catch {
				// The exclusive destination is already absent or no longer names the inode we created.
			}
		}
		throw error;
	} finally {
		if (destinationHandle) await destinationHandle.close();
	}
}

async function parseFile(file) {
	const bytes = await readRegularNoFollow(file);
	let text;
	try {
		text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
	} catch {
		throw new Error('input is not valid UTF-8');
	}
	const value = new DuplicateAwareJsonParser(text).parse();
	return {
		bytes,
		value,
		digest: createHash('sha256').update(bytes).digest('hex'),
	};
}

async function main() {
	const [operation, file, receiptKind, stateRootArgument, ...extra] = process.argv.slice(2);
	assert(extra.length === 0, 'too many arguments');
	assert(operation && file, 'usage: brave-json.mjs <canonical|inventory|digest-no-follow> <file> | receipt <file> <kind> <state-root> | copy-no-follow <source> <destination> | compare-no-follow <left> <right> | emit-no-follow <source> <digest>');

	if (operation === 'digest-no-follow') {
		assert(receiptKind === undefined && stateRootArgument === undefined, 'digest-no-follow accepts no additional argument');
		const bytes = await readRegularNoFollow(file);
		return {
			ok: true,
			kind: 'no-follow-digest',
			digest: createHash('sha256').update(bytes).digest('hex'),
			bytes: bytes.length,
		};
	}

	if (operation === 'copy-no-follow') {
		assert(receiptKind && stateRootArgument === undefined, 'copy-no-follow requires a source and destination');
		return copyRegularNoFollow(file, receiptKind);
	}

	if (operation === 'compare-no-follow') {
		assert(receiptKind && stateRootArgument === undefined, 'compare-no-follow requires two file paths');
		const left = await readRegularNoFollow(file);
		const right = await readRegularNoFollow(receiptKind);
		return {
			ok: true,
			kind: 'no-follow-comparison',
			equal: left.equals(right),
			left_digest: createHash('sha256').update(left).digest('hex'),
			right_digest: createHash('sha256').update(right).digest('hex'),
		};
	}

	if (operation === 'emit-no-follow') {
		assert(receiptKind && stateRootArgument === undefined, 'emit-no-follow requires a source and expected digest');
		assertString(receiptKind, DIGEST, 'expected digest');
		const bytes = await readRegularNoFollow(file);
		const digest = createHash('sha256').update(bytes).digest('hex');
		assert(digest === receiptKind, 'input digest does not match the expected bytes');
		process.stdout.write(bytes);
		return undefined;
	}

	const parsed = await parseFile(file);

	if (operation === 'canonical') {
		assert(receiptKind === undefined && stateRootArgument === undefined, 'canonical validation accepts no additional argument');
		assertExactValue(parsed.value, CANONICAL_POLICY);
		return {
			ok: true,
			kind: 'canonical-policy',
			digest: parsed.digest,
			top_level_keys: Object.keys(parsed.value).sort(),
			top_level_key_count: Object.keys(parsed.value).length,
			scalar_leaf_count: 14,
		};
	}

	if (operation === 'inventory') {
		assert(receiptKind === undefined && stateRootArgument === undefined, 'inventory accepts no additional argument');
		assert(isObject(parsed.value), 'foreign policy must be a JSON object');
		return {
			ok: true,
			kind: 'policy-inventory',
			digest: parsed.digest,
			top_level_keys: Object.keys(parsed.value).sort(),
		};
	}

	if (operation === 'receipt') {
		assert(receiptKind && stateRootArgument, 'receipt validation requires a kind and absolute state root');
		const stateRoot = path.resolve(stateRootArgument);
		assert(path.isAbsolute(stateRootArgument), 'receipt state root must be absolute');
		if (receiptKind === 'active') assertActive(parsed.value);
		else if (receiptKind === 'pending') assertPending(parsed.value, stateRoot);
		else if (receiptKind === 'recovery-required') assertRecovery(parsed.value, stateRoot);
		else throw new Error(`unknown receipt kind: ${receiptKind}`);
		return { ok: true, kind: receiptKind, digest: parsed.digest, value: parsed.value };
	}

	throw new Error(`unknown operation: ${operation}`);
}

try {
	const result = await main();
	if (result !== undefined) process.stdout.write(`${JSON.stringify(result)}\n`);
} catch (error) {
	const failure = `${JSON.stringify({ ok: false, error: error.message })}\n`;
	if (process.argv[2] === 'emit-no-follow') process.stderr.write(failure);
	else process.stdout.write(failure);
	process.exitCode = 1;
}
