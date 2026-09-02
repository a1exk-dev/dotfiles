#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { constants, closeSync, fstatSync, lstatSync, openSync, readSync, readdirSync } from 'node:fs';
import path from 'node:path';

const MAX_BYTES = 1024 * 1024;
const DIGEST = /^[0-9a-f]{64}$/u;
const TRANSACTION_PATTERN = '\\d{8}T\\d{6}Z-\\d+-[0-9a-f]{8}';
const TRANSACTION = new RegExp(`^${TRANSACTION_PATTERN}$`, 'u');
const SOURCES = {
	upower: '[UPower]\nUsePercentageForPolicy=true\nPercentageLow=20.0\nPercentageCritical=10.0\nPercentageAction=5.0\nCriticalPowerAction=Hibernate\n',
	logind: '[Login]\nHandleLidSwitch=hibernate\nHandleLidSwitchExternalPower=suspend\nHandleLidSwitchDocked=ignore\n',
};
const TARGETS = [
	{ name: 'upower', source: 'power-policy/upower.conf', target: '/etc/UPower/UPower.conf.d/90-dotfiles-laptop-power.conf', directory: '/etc/UPower/UPower.conf.d' },
	{ name: 'logind', source: 'power-policy/logind.conf', target: '/etc/systemd/logind.conf.d/90-dotfiles-laptop-power.conf', directory: '/etc/systemd/logind.conf.d' },
];
const UPOWER_KEYS = ['UsePercentageForPolicy', 'PercentageLow', 'PercentageCritical', 'PercentageAction', 'CriticalPowerAction'];
const LOGIND_KEYS = ['HandleLidSwitch', 'HandleLidSwitchExternalPower', 'HandleLidSwitchDocked', 'InhibitDelayMaxSec'];

function fail(message) { throw new Error(message); }
function assert(value, message) { if (!value) fail(message); }
function digest(bytes) { return createHash('sha256').update(bytes).digest('hex'); }
function regular(stats) { return stats.isFile(); }

function readRegular(file) {
	let descriptor;
	try {
		descriptor = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW);
		const before = fstatSync(descriptor);
		assert(regular(before), `not a regular file: ${file}`);
		assert(before.size <= MAX_BYTES, `input exceeds the ${MAX_BYTES}-byte safety limit: ${file}`);
		const bytes = Buffer.alloc(before.size);
		let offset = 0;
		while (offset < bytes.length) {
			const read = readSync(descriptor, bytes, offset, bytes.length - offset, offset);
			assert(read > 0, `input changed while being read: ${file}`);
			offset += read;
		}
		const after = fstatSync(descriptor);
		const named = lstatSync(file);
		assert(after.dev === before.dev && after.ino === before.ino && after.size === before.size && named.dev === after.dev && named.ino === after.ino && regular(named), `input changed while being read: ${file}`);
		return bytes;
	} finally {
		if (descriptor !== undefined) closeSync(descriptor);
	}
}

function entries(bytes, section, keys) {
	const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
	let active = false;
	const result = [];
	for (const raw of text.split(/\r?\n/u)) {
		const line = raw.trim();
		if (!line || line.startsWith('#') || line.startsWith(';')) continue;
		const heading = /^\[([^\]]+)\]$/u.exec(line);
		if (heading) { active = heading[1] === section; continue; }
		const assignment = /^([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*?)\s*$/u.exec(line);
		if (active && assignment && keys.includes(assignment[1])) result.push({ key: assignment[1], value: assignment[2] });
	}
	return result;
}

function parseFile(file, section, keys, replacement) {
	const bytes = replacement?.target === file ? replacement.bytes : readRegular(file);
	assert(bytes !== null, `replacement unexpectedly removed ${file}`);
	return { path: file, entries: entries(bytes, section, keys), digest: digest(bytes), simulated: replacement?.target === file };
}

function applyEntries(files, keys) {
	const effective = Object.fromEntries(keys.map((key) => [key, null]));
	for (const file of files) for (const entry of file.entries) effective[entry.key] = entry.value;
	return effective;
}

function upower(main, directory, replacement = null) {
	const names = readdirSync(directory).filter((name) => /^[0-9][0-9]-[A-Za-z0-9_-]*\.conf$/u.test(name)).sort();
	const targetName = replacement && path.basename(replacement.target);
	if (replacement && !names.includes(targetName) && replacement.bytes !== null) names.push(targetName);
	const files = [parseFile(main, 'UPower', UPOWER_KEYS, replacement)];
	for (const name of names.sort()) {
		const file = path.join(directory, name);
		if (replacement?.target === file && replacement.bytes === null) continue;
		files.push(parseFile(file, 'UPower', UPOWER_KEYS, replacement));
	}
	return { effective: applyEntries(files, UPOWER_KEYS), files };
}

function logind(mains, directories, replacement = null) {
	let main = null;
	for (const candidate of mains) {
		try { main = parseFile(candidate, 'Login', LOGIND_KEYS, replacement); break; } catch (error) { if (error.code !== 'ENOENT') throw error; }
	}
	assert(main, 'no readable logind main configuration exists');
	const candidates = new Map();
	for (const directory of directories) {
		let names;
		try { names = readdirSync(directory).filter((name) => name.endsWith('.conf')); } catch (error) { if (error.code === 'ENOENT') continue; throw error; }
		for (const name of names) {
			const values = candidates.get(name) ?? [];
			values.push(path.join(directory, name));
			candidates.set(name, values);
		}
	}
	if (replacement) {
		const name = path.basename(replacement.target);
		const values = (candidates.get(name) ?? []).filter((candidate) => candidate !== replacement.target);
		if (replacement.bytes !== null) values.unshift(replacement.target);
		if (values.length) candidates.set(name, values); else candidates.delete(name);
	}
	const files = [main];
	for (const name of [...candidates.keys()].sort()) files.push(parseFile(candidates.get(name)[0], 'Login', LOGIND_KEYS, replacement));
	return { effective: applyEntries(files, LOGIND_KEYS), files };
}

function exact(object, keys, where) {
	assert(object && typeof object === 'object' && !Array.isArray(object), `${where} must be an object`);
	const actual = Object.keys(object).sort();
	const wanted = [...keys].sort();
	assert(actual.length === wanted.length && actual.every((key, index) => key === wanted[index]), `${where} has an unexpected schema`);
}

function state(value, stateRoot, name, transaction, where, currentTransaction = true) {
	exact(value, ['present', 'digest', 'backup_path'], where);
	assert(typeof value.present === 'boolean', `${where}.present is invalid`);
	if (!value.present) { assert(value.digest === null && value.backup_path === null, `${where} absent fields must be null`); return; }
	assert(typeof value.digest === 'string' && DIGEST.test(value.digest), `${where}.digest is invalid`);
	const expected = currentTransaction ? path.join(stateRoot, 'backups', transaction, `${name}.conf`) : new RegExp(`^${escape(stateRoot)}/backups/${TRANSACTION_PATTERN}/${name}\\.conf$`, 'u');
	assert(currentTransaction ? value.backup_path === expected : expected.test(value.backup_path), `${where}.backup_path is invalid`);
}

function escape(value) { return value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&'); }

function service(value, where) {
	exact(value, ['enabled', 'active'], where);
	assert(['enabled', 'disabled'].includes(value.enabled) && ['active', 'inactive'].includes(value.active), `${where} is invalid`);
}

function active(value, stateRoot, where = '$') {
	exact(value, ['schema_version', 'kind', 'transaction_id', 'activated_at', 'targets', 'service_original'], where);
	assert(value.schema_version === 1 && value.kind === 'active' && TRANSACTION.test(value.transaction_id), `${where} is invalid`);
	assert(typeof value.activated_at === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/u.test(value.activated_at), `${where}.activated_at is invalid`);
	assert(Array.isArray(value.targets) && value.targets.length === TARGETS.length, `${where}.targets is invalid`);
	value.targets.forEach((target, index) => {
		const definition = TARGETS[index];
		exact(target, ['name', 'source', 'target', 'digest', 'original'], `${where}.targets[${index}]`);
		assert(target.name === definition.name && target.source === definition.source && target.target === definition.target && DIGEST.test(target.digest), `${where}.targets[${index}] is invalid`);
		state(target.original, stateRoot, definition.name, value.transaction_id, `${where}.targets[${index}].original`, false);
	});
	service(value.service_original, `${where}.service_original`);
}

function pending(value, stateRoot) {
	exact(value, ['schema_version', 'kind', 'operation', 'phase', 'transaction_id', 'targets', 'service_prior', 'service_original', 'inhibit_delay_prior', 'prior_active'], '$');
	assert(value.schema_version === 1 && value.kind === 'pending' && ['apply', 'remove'].includes(value.operation) && ['prepared', 'mutating'].includes(value.phase) && TRANSACTION.test(value.transaction_id), 'pending receipt is invalid');
	assert(Array.isArray(value.targets) && value.targets.length === TARGETS.length, 'pending targets are invalid');
	value.targets.forEach((target, index) => {
		const definition = TARGETS[index];
		exact(target, ['name', 'target', 'desired_digest', 'stage_path', 'prior', 'original'], `targets[${index}]`);
		assert(target.name === definition.name && target.target === definition.target && DIGEST.test(target.desired_digest) && target.stage_path === `${definition.directory}/.dotfiles-${value.transaction_id}.stage`, `targets[${index}] is invalid`);
		state(target.prior, stateRoot, definition.name, value.transaction_id, `targets[${index}].prior`);
		state(target.original, stateRoot, definition.name, value.transaction_id, `targets[${index}].original`, false);
	});
	service(value.service_prior, 'service_prior');
	service(value.service_original, 'service_original');
	assert(Number.isSafeInteger(value.inhibit_delay_prior) && value.inhibit_delay_prior >= 0, 'inhibit_delay_prior is invalid');
	if (value.prior_active !== null) active(value.prior_active, stateRoot, 'prior_active');
}

function receipt(file, kind, stateRoot) {
	const bytes = readRegular(file);
	const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
	assertNoDuplicateMembers(text);
	const value = JSON.parse(text);
	if (kind === 'active') active(value, stateRoot); else if (kind === 'pending') pending(value, stateRoot); else fail(`unknown receipt kind: ${kind}`);
	return { kind, digest: digest(bytes), value };
}

function assertNoDuplicateMembers(text) {
	let index = 0;
	const space = () => { while (/\s/u.test(text[index] ?? '')) index += 1; };
	const string = () => {
		assert(text[index] === '"', 'receipt JSON contains an invalid string');
		const start = index;
		index += 1;
		while (index < text.length) {
			const character = text[index++];
			if (character === '"') return JSON.parse(text.slice(start, index));
			if (character === '\\') { assert(index < text.length, 'receipt JSON contains an invalid escape'); index += 1; }
			else assert(character.charCodeAt(0) >= 0x20, 'receipt JSON contains an invalid control character');
		}
		fail('receipt JSON has an unterminated string');
	};
	const value = () => {
		space();
		if (text[index] === '{') {
			index += 1; space();
			const keys = new Set();
			if (text[index] === '}') { index += 1; return; }
			while (true) {
				const key = string();
				assert(!keys.has(key), `receipt JSON has a duplicate member: ${key}`);
				keys.add(key); space(); assert(text[index++] === ':', 'receipt JSON has an invalid object member'); value(); space();
				if (text[index] === '}') { index += 1; return; }
				assert(text[index++] === ',', 'receipt JSON has an invalid object separator'); space();
			}
		}
		if (text[index] === '[') {
			index += 1; space(); if (text[index] === ']') { index += 1; return; }
			while (true) { value(); space(); if (text[index] === ']') { index += 1; return; } assert(text[index++] === ',', 'receipt JSON has an invalid array separator'); }
		}
		if (text[index] === '"') { string(); return; }
		const literal = /^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/u.exec(text.slice(index));
		assert(literal, 'receipt JSON contains an invalid value'); index += literal[0].length;
	};
	value(); space(); assert(index === text.length, 'receipt JSON has trailing content');
}

function output(value) { process.stdout.write(`${JSON.stringify(value)}\n`); }
try {
	const [operation, ...args] = process.argv.slice(2);
	if (operation === 'digest') { assert(args.length === 1, 'digest needs one file'); output({ digest: digest(readRegular(args[0])) }); }
	else if (operation === 'digest-bytes') { assert(args.length === 2 && DIGEST.test(args[1]), 'digest-bytes needs a file and digest'); const bytes = readRegular(args[0]); assert(digest(bytes) === args[1], 'file digest changed'); process.stdout.write(bytes); }
	else if (operation === 'source') { assert(args.length === 2 && Object.hasOwn(SOURCES, args[1]), 'source needs a file and known source name'); const bytes = readRegular(args[0]); assert(bytes.equals(Buffer.from(SOURCES[args[1]])), `${args[1]} source does not match approved bytes`); output({ digest: digest(bytes) }); }
	else if (operation === 'source-bytes') { assert(args.length === 2 && Object.hasOwn(SOURCES, args[1]), 'source-bytes needs a file and known source name'); const bytes = readRegular(args[0]); assert(bytes.equals(Buffer.from(SOURCES[args[1]])), `${args[1]} source does not match approved bytes`); process.stdout.write(bytes); }
	else if (operation === 'receipt') { assert(args.length === 3, 'receipt needs file, kind, and state root'); output(receipt(args[0], args[1], args[2])); }
	else if (operation === 'upower-effective') { assert(args.length === 2, 'upower-effective needs main and directory'); output(upower(args[0], args[1])); }
	else if (operation === 'upower-plan') { assert(args.length === 4, 'upower-plan needs main, directory, target, replacement'); output(upower(args[0], args[1], { target: args[2], bytes: args[3] === '-' ? null : readRegular(args[3]) })); }
	else if (operation === 'logind-effective' || operation === 'logind-plan') {
		const planning = operation === 'logind-plan';
		assert(args.length === (planning ? 10 : 8), `${operation} has invalid arguments`);
		const replacement = planning ? { target: args[8], bytes: args[9] === '-' ? null : readRegular(args[9]) } : null;
		output(logind([args[0], args[2], args[4], args[6]], [args[1], args[3], args[5], args[7]], replacement));
	} else fail(`unknown operation: ${operation}`);
} catch (error) {
	process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
	process.exitCode = 1;
}
