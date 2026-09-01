#!/usr/bin/env node

import { createHash, randomBytes } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import {
	closeSync,
	constants,
	fchmodSync,
	fstatSync,
	fsyncSync,
	lstatSync,
	openSync,
	readlinkSync,
	readSync,
	rmdirSync,
	unlinkSync,
	writeSync,
} from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import process from 'node:process';

const IDENTITY_KEYS = [
	'ctime_ns',
	'device',
	'digest',
	'gid',
	'inode',
	'mode',
	'mtime_ns',
	'nlink',
	'size',
	'uid',
];
const LSTAT_KEYS = ['ctime_ns', 'device', 'gid', 'inode', 'mode', 'mtime_ns', 'nlink', 'size', 'target', 'type', 'uid'];
const LINUX_O_PATH = 0o10000000;
const SERVER_FRAME_TERMINATOR = 'F';

function fail(message) {
	throw new Error(message);
}

function modeOf(stat) {
	return Number(stat.mode & 0o7777n).toString(8).padStart(4, '0');
}

function stableStat(stat) {
	return {
		ctime_ns: stat.ctimeNs.toString(),
		device: stat.dev.toString(),
		gid: stat.gid.toString(),
		inode: stat.ino.toString(),
		mode: modeOf(stat),
		mtime_ns: stat.mtimeNs.toString(),
		nlink: Number(stat.nlink),
		size: stat.size.toString(),
		uid: stat.uid.toString(),
	};
}

function sameStableStat(left, right) {
	return Object.keys(left).every((key) => left[key] === right[key]);
}

function openRegular(file, allowMultipleLinks = false) {
	let descriptor;
	try {
		descriptor = openSync(file, constants.O_RDONLY | constants.O_NOFOLLOW);
	} catch (error) {
		if (error?.code === 'ELOOP') fail(`path must be a regular non-symlink file: ${file}`);
		throw error;
	}
	const stat = fstatSync(descriptor, { bigint: true });
	if (!stat.isFile()) {
		closeSync(descriptor);
		fail(`path must be a regular non-symlink file: ${file}`);
	}
	if (stat.nlink < 1n || (!allowMultipleLinks && stat.nlink !== 1n)) {
		closeSync(descriptor);
		fail(allowMultipleLinks ? `hard link count must be at least one: ${file}` : `hard link count must be exactly one: ${file}`);
	}
	return { descriptor, stat };
}

function hashDescriptor(descriptor, size) {
	const hash = createHash('sha256');
	const buffer = Buffer.allocUnsafe(64 * 1024);
	let position = 0;
	while (position < size) {
		const count = readSync(descriptor, buffer, 0, Math.min(buffer.length, size - position), position);
		if (count === 0) fail('file changed while hashing');
		hash.update(buffer.subarray(0, count));
		position += count;
	}
	return hash.digest('hex');
}

function inspectDescriptor(descriptor, firstStat, allowMultipleLinks = false) {
	const before = stableStat(firstStat);
	const digest = hashDescriptor(descriptor, Number(firstStat.size));
	const afterStat = fstatSync(descriptor, { bigint: true });
	const after = stableStat(afterStat);
	if (
		!afterStat.isFile() ||
		afterStat.nlink < 1n ||
		(!allowMultipleLinks && afterStat.nlink !== 1n) ||
		!sameStableStat(before, after)
	) {
		fail('file changed during stable no-follow read');
	}
	return { ...after, digest };
}

function inspect(file, allowMultipleLinks = false) {
	const { descriptor, stat } = openRegular(file, allowMultipleLinks);
	try {
		return inspectDescriptor(descriptor, stat, allowMultipleLinks);
	} finally {
		closeSync(descriptor);
	}
}

function parseExpected(value) {
	let expected;
	try {
		expected = JSON.parse(value);
	} catch {
		fail('expected identity must be valid JSON');
	}
	if (
		expected === null ||
		Array.isArray(expected) ||
		Object.keys(expected).sort().join('\0') !== [...IDENTITY_KEYS].sort().join('\0')
	) {
		fail('expected identity has an invalid shape');
	}
	return expected;
}

function assertIdentity(actual, expected, location) {
	for (const key of IDENTITY_KEYS) {
		if (actual[key] !== expected[key]) fail(`file identity changed before ${location}: ${key}`);
	}
}

function assertExchangedIdentity(actual, expected, location) {
	for (const key of IDENTITY_KEYS.filter((key) => key !== 'ctime_ns')) {
		if (actual[key] !== expected[key]) fail(`file identity changed during ${location}: ${key}`);
	}
}

function inspectExpected(file, expected) {
	return inspect(file, expected.nlink !== 1);
}

function parseLstatExpected(value) {
	let expected;
	try {
		expected = JSON.parse(value);
	} catch {
		fail('expected path identity must be valid JSON');
	}
	if (
		expected === null ||
		Array.isArray(expected) ||
		Object.keys(expected).sort().join('\0') !== [...LSTAT_KEYS].sort().join('\0')
	) {
		fail('expected path identity has an invalid shape');
	}
	return expected;
}

function assertObjectIdentity(actual, expected, location) {
	for (const key of ['device', 'gid', 'inode', 'mode', 'type', 'uid']) {
		if (actual[key] !== expected[key]) fail(`path identity changed before ${location}: ${key}`);
	}
}

function assertRenamedObjectIdentity(actual, expected, location) {
	for (const key of LSTAT_KEYS.filter((key) => key !== 'ctime_ns')) {
		if (actual[key] !== expected[key]) fail(`path identity changed during ${location}: ${key}`);
	}
}

function assertPathIdentity(actual, expected, location) {
	for (const key of LSTAT_KEYS) {
		if (actual[key] !== expected[key]) fail(`path identity changed before ${location}: ${key}`);
	}
}

function assertRegularPathIdentity(actual, expected, location) {
	if (actual.type !== 'regular') fail(`path identity changed before ${location}: type`);
	for (const key of IDENTITY_KEYS.filter((key) => key !== 'digest')) {
		if (actual[key] !== expected[key]) fail(`path identity changed before ${location}: ${key}`);
	}
}

function assertDescriptorIdentity(stat, expected, type, location) {
	if ((type === 'regular' && !stat.isFile()) || (type === 'directory' && !stat.isDirectory())) {
		fail(`path identity changed before ${location}: type`);
	}
	const actual = stableStat(stat);
	for (const key of Object.keys(actual)) {
		if (actual[key] !== expected[key]) fail(`path identity changed before ${location}: ${key}`);
	}
}

function assertPostRemovalDescriptorIdentity(stat, expected, type, expectedNlink, location) {
	if ((type === 'regular' && !stat.isFile()) || (type === 'directory' && !stat.isDirectory())) {
		fail(`path identity changed during ${location}: type`);
	}
	const actual = stableStat(stat);
	if (actual.nlink !== expectedNlink) fail(`path identity changed during ${location}: nlink`);
	for (const key of Object.keys(actual).filter((key) => key !== 'ctime_ns' && key !== 'nlink')) {
		if (actual[key] !== expected[key]) fail(`path identity changed during ${location}: ${key}`);
	}
}

function lstatIdentity(file) {
	const first = lstatSync(file, { bigint: true });
	let type = 'other';
	let target = null;
	if (first.isDirectory()) type = 'directory';
	if (first.isFile()) type = 'regular';
	if (first.isSymbolicLink()) {
		type = 'symlink';
		target = readlinkSync(file);
	}
	const second = lstatSync(file, { bigint: true });
	const result = { ...stableStat(second), target, type };
	delete result.digest;
	if (!sameStableStat(stableStat(first), stableStat(second))) fail(`path changed during no-follow inspection: ${file}`);
	if (Object.keys(result).sort().join('\0') !== [...LSTAT_KEYS].sort().join('\0')) fail('internal lstat shape error');
	return result;
}

function isAbsent(file) {
	try {
		lstatSync(file);
		return false;
	} catch (error) {
		if (error?.code === 'ENOENT') return true;
		throw error;
	}
}

function moveNoClobber(source, target) {
	return spawnSync(
		'/usr/bin/mv',
		['--verbose', '--no-clobber', '--no-copy', '--no-target-directory', '--', source, target],
		{ encoding: 'utf8' },
	);
}

function assertMoveSucceeded(result, location) {
	if (result.error !== undefined) fail(`${location} failed: ${result.error.message}`);
	if (result.status !== 0) {
		const detail = (result.stderr || result.stdout).trim() || (result.signal ? `signal ${result.signal}` : `status ${result.status}`);
		fail(`${location} failed: ${detail}`);
	}
}

function moveReportedAction(result) {
	return (result.stdout || '').length > 0;
}

function privateQuarantinePath(file) {
	// Linux has no compare-and-unlink/rmdir operation. Entropy narrows the final path race, and an open descriptor
	// detects substitution after the syscall. A process kill after the rename can still leave this sibling behind.
	for (let attempt = 0; attempt < 10; attempt++) {
		const quarantine = join(
			dirname(file),
			`.dotfiles-wallpaper-remove-${process.pid}-${randomBytes(16).toString('hex')}`,
		);
		if (isAbsent(quarantine)) return quarantine;
	}
	fail(`could not allocate a private removal quarantine beside: ${file}`);
}

function copyStable(source, destination, modeText, expectedSource) {
	const mode = Number.parseInt(modeText, 8);
	if (!/^0[0-7]{3}$/.test(modeText)) fail('copy mode must be four octal digits');
	const sourceOpen = openRegular(source);
	let destinationDescriptor;
	let created = false;
	let createdStat;
	try {
		destinationDescriptor = openSync(
			destination,
			constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
			mode,
		);
		created = true;
		createdStat = fstatSync(destinationDescriptor, { bigint: true });
		const buffer = Buffer.allocUnsafe(64 * 1024);
		let position = 0;
		const size = Number(sourceOpen.stat.size);
		while (position < size) {
			const count = readSync(
				sourceOpen.descriptor,
				buffer,
				0,
				Math.min(buffer.length, size - position),
				position,
			);
			if (count === 0) fail('source changed while copying');
			let written = 0;
			while (written < count) {
				written += writeSync(destinationDescriptor, buffer, written, count - written, position + written);
			}
			position += count;
		}
		fchmodSync(destinationDescriptor, mode);
		fsyncSync(destinationDescriptor);
		closeSync(destinationDescriptor);
		destinationDescriptor = undefined;
		const sourceIdentity = inspectDescriptor(sourceOpen.descriptor, sourceOpen.stat);
		if (expectedSource !== undefined) assertIdentity(sourceIdentity, expectedSource, 'stable copy source');
		const destinationIdentity = inspect(destination);
		if (sourceIdentity.digest !== destinationIdentity.digest || sourceIdentity.size !== destinationIdentity.size) {
			fail('stable copy does not match its source');
		}
		return { destination: destinationIdentity, source: sourceIdentity };
	} catch (error) {
		if (destinationDescriptor !== undefined) closeSync(destinationDescriptor);
		if (created && !isAbsent(destination)) {
			try {
				const actual = inspect(destination);
				if (BigInt(actual.device) === createdStat.dev && BigInt(actual.inode) === createdStat.ino) removeExpected(destination, actual);
			} catch {}
		}
		throw error;
	} finally {
		closeSync(sourceOpen.descriptor);
	}
}

function createStable(destination, modeText, content) {
	const mode = Number.parseInt(modeText, 8);
	if (!/^0[0-7]{3}$/.test(modeText)) fail('create mode must be four octal digits');
	let descriptor;
	let createdStat;
	try {
		descriptor = openSync(
			destination,
			constants.O_RDWR | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW,
			mode,
		);
		createdStat = fstatSync(descriptor, { bigint: true });
		const data = Buffer.from(content);
		let written = 0;
		while (written < data.length) written += writeSync(descriptor, data, written, data.length - written, written);
		fchmodSync(descriptor, mode);
		fsyncSync(descriptor);
		const identity = inspectDescriptor(descriptor, fstatSync(descriptor, { bigint: true }));
		const pathIdentity = inspect(destination);
		assertIdentity(pathIdentity, identity, 'stable creation');
		return pathIdentity;
	} catch (error) {
		if (descriptor !== undefined) closeSync(descriptor);
		descriptor = undefined;
		if (createdStat !== undefined && !isAbsent(destination)) {
			try {
				const actual = inspect(destination);
				if (BigInt(actual.device) === createdStat.dev && BigInt(actual.inode) === createdStat.ino) removeExpected(destination, actual);
			} catch {}
		}
		throw error;
	} finally {
		if (descriptor !== undefined) closeSync(descriptor);
	}
}

function publishAbsent(stage, target) {
	const stageIdentity = inspect(stage);
	if (resolve(dirname(stage)) !== resolve(dirname(target))) {
		fail('planned-absent publication requires stage and target in the same directory');
	}
	if (!isAbsent(target)) fail(`planned-absent publication target now exists: ${target}`);
	const move = moveNoClobber(stage, target);
	assertMoveSucceeded(move, 'atomic planned-absent publication');
	if (!isAbsent(stage)) fail(`atomic planned-absent publication did not move its stage: ${stage}`);
	const targetIdentity = inspect(target);
	assertExchangedIdentity(targetIdentity, stageIdentity, 'planned-absent publication');
	return targetIdentity;
}

function publishReplace(stage, target, expected) {
	const stageIdentity = inspect(stage);
	assertIdentity(inspect(target), expected, 'atomic replacement');
	const exchange = spawnSync('/usr/bin/mv', ['--exchange', '--no-copy', '--', stage, target], {
		encoding: 'utf8',
	});
	if (exchange.status !== 0) {
		fail(`atomic exchange failed: ${(exchange.stderr || exchange.stdout).trim() || `status ${exchange.status}`}`);
	}
	try {
		const targetIdentity = inspect(target);
		const displacedIdentity = inspect(stage);
		assertExchangedIdentity(targetIdentity, stageIdentity, 'atomic replacement');
		assertExchangedIdentity(displacedIdentity, expected, 'atomic replacement displacement');
		removeExpected(stage, displacedIdentity);
		return targetIdentity;
	} catch (error) {
		const rollback = spawnSync('/usr/bin/mv', ['--exchange', '--no-copy', '--', stage, target], {
			encoding: 'utf8',
		});
		if (rollback.status !== 0) {
			fail(`atomic exchange verification failed and rollback failed: ${error.message}`);
		}
		throw error;
	}
}

function removeExpected(file, expected) {
	const allowMultipleLinks = expected.nlink !== 1;
	assertIdentity(inspect(file, allowMultipleLinks), expected, 'removal');
	const quarantine = privateQuarantinePath(file);
	const quarantinedIdentity = removeTo(file, expected, quarantine);
	try {
		const opened = openRegular(quarantine, allowMultipleLinks);
		try {
			assertIdentity(
				inspectDescriptor(opened.descriptor, opened.stat, allowMultipleLinks),
				quarantinedIdentity,
				'private quarantine removal',
			);
			assertRegularPathIdentity(lstatIdentity(quarantine), quarantinedIdentity, 'private quarantine removal');
			unlinkSync(quarantine);
			assertPostRemovalDescriptorIdentity(
				fstatSync(opened.descriptor, { bigint: true }),
				quarantinedIdentity,
				'regular',
				quarantinedIdentity.nlink - 1,
				'private quarantine removal',
			);
		} finally {
			closeSync(opened.descriptor);
		}
		if (!isAbsent(quarantine)) fail(`reported-success removal left its private quarantine present: ${quarantine}`);
		if (!isAbsent(file)) fail(`reported-success removal left its public path present: ${file}`);
	} catch (error) {
		restoreAfterCleanupFailure(file, quarantine, error);
	}
}

function removeCoreExpected(file, expected) {
	const actual = inspect(file);
	assertExchangedIdentity(actual, expected, 'owned temporary cleanup');
	removeExpected(file, actual);
}

function restoreMovedObject(file, quarantine) {
	if (!isAbsent(file) || isAbsent(quarantine)) return;
	const quarantinedIdentity = lstatIdentity(quarantine);
	const rollback = moveNoClobber(quarantine, file);
	assertMoveSucceeded(rollback, 'atomic quarantine rollback');
	if (!isAbsent(quarantine)) fail(`atomic quarantine rollback left its source present: ${quarantine}`);
	assertRenamedObjectIdentity(lstatIdentity(file), quarantinedIdentity, 'atomic quarantine rollback');
}

function restoreAfterCleanupFailure(file, quarantine, error) {
	try {
		restoreMovedObject(file, quarantine);
	} catch (rollbackError) {
		fail(`${error.message}; ${rollbackError.message}`);
	}
	throw error;
}

function removeTo(file, expected, quarantine) {
	if (!isAbsent(quarantine)) fail(`removal quarantine now exists: ${quarantine}`);
	assertIdentity(inspectExpected(file, expected), expected, 'quarantine removal');
	const move = moveNoClobber(file, quarantine);
	try {
		assertMoveSucceeded(move, 'atomic quarantine move');
		if (!isAbsent(file)) fail(`atomic quarantine move left its source present: ${file}`);
		const quarantinedIdentity = inspectExpected(quarantine, expected);
		assertExchangedIdentity(quarantinedIdentity, expected, 'atomic quarantine move');
		return quarantinedIdentity;
	} catch (error) {
		if (moveReportedAction(move)) {
			try {
				restoreMovedObject(file, quarantine);
			} catch (rollbackError) {
				fail(`${error.message}; ${rollbackError.message}`);
			}
		}
		throw error;
	}
}

function moveDirectoryToQuarantine(directory, expected, quarantine) {
	const sourceIdentity = lstatIdentity(directory);
	if (sourceIdentity.type !== 'directory' || expected.type !== 'directory') fail(`path must be a real directory: ${directory}`);
	assertObjectIdentity(sourceIdentity, expected, 'directory quarantine move');
	const move = moveNoClobber(directory, quarantine);
	try {
		assertMoveSucceeded(move, 'atomic directory quarantine move');
		if (!isAbsent(directory)) fail(`atomic directory quarantine move left its source present: ${directory}`);
		const quarantinedIdentity = lstatIdentity(quarantine);
		assertRenamedObjectIdentity(quarantinedIdentity, sourceIdentity, 'atomic directory quarantine move');
		return quarantinedIdentity;
	} catch (error) {
		if (moveReportedAction(move)) {
			try {
				restoreMovedObject(directory, quarantine);
			} catch (rollbackError) {
				fail(`${error.message}; ${rollbackError.message}`);
			}
		}
		throw error;
	}
}

function removeDirectoryExpected(directory, expected) {
	const quarantine = privateQuarantinePath(directory);
	const quarantinedIdentity = moveDirectoryToQuarantine(directory, expected, quarantine);
	try {
		const descriptor = openSync(quarantine, LINUX_O_PATH | constants.O_NOFOLLOW | constants.O_DIRECTORY);
		try {
			assertDescriptorIdentity(
				fstatSync(descriptor, { bigint: true }),
				quarantinedIdentity,
				'directory',
				'private directory quarantine removal',
			);
			assertPathIdentity(lstatIdentity(quarantine), quarantinedIdentity, 'private directory quarantine removal');
			rmdirSync(quarantine);
			assertPostRemovalDescriptorIdentity(
				fstatSync(descriptor, { bigint: true }),
				quarantinedIdentity,
				'directory',
				0,
				'private directory quarantine removal',
			);
		} finally {
			closeSync(descriptor);
		}
		if (!isAbsent(quarantine)) fail(`reported-success directory removal left its private quarantine present: ${quarantine}`);
		if (!isAbsent(directory)) fail(`reported-success directory removal left its public path present: ${directory}`);
	} catch (error) {
		restoreAfterCleanupFailure(directory, quarantine, error);
	}
}

function readStable(file, expected) {
	const opened = openRegular(file);
	try {
		const identity = inspectDescriptor(opened.descriptor, opened.stat);
		if (expected !== undefined) assertIdentity(identity, expected, 'stable read source');
		const content = Buffer.alloc(Number(opened.stat.size));
		let position = 0;
		while (position < content.length) {
			const count = readSync(opened.descriptor, content, position, content.length - position, position);
			if (count === 0) fail('file changed during stable read');
			position += count;
		}
		assertIdentity(inspectDescriptor(opened.descriptor, opened.stat), identity, 'stable reread');
		return content;
	} finally {
		closeSync(opened.descriptor);
	}
}

function sameFiles(left, right, allowRightMultipleLinks = false) {
	const leftOpen = openRegular(left);
	const rightOpen = openRegular(right, allowRightMultipleLinks);
	try {
		const leftIdentity = inspectDescriptor(leftOpen.descriptor, leftOpen.stat);
		const rightIdentity = inspectDescriptor(rightOpen.descriptor, rightOpen.stat, allowRightMultipleLinks);
		if (leftIdentity.size !== rightIdentity.size || leftIdentity.digest !== rightIdentity.digest) return false;
		const leftBuffer = Buffer.allocUnsafe(64 * 1024);
		const rightBuffer = Buffer.allocUnsafe(64 * 1024);
		let position = 0;
		const size = Number(leftOpen.stat.size);
		while (position < size) {
			const length = Math.min(leftBuffer.length, size - position);
			const leftCount = readSync(leftOpen.descriptor, leftBuffer, 0, length, position);
			const rightCount = readSync(rightOpen.descriptor, rightBuffer, 0, length, position);
			if (leftCount === 0 || rightCount === 0) fail('file changed during comparison');
			if (leftCount !== rightCount || !leftBuffer.subarray(0, leftCount).equals(rightBuffer.subarray(0, rightCount))) return false;
			position += leftCount;
		}
		assertIdentity(inspectDescriptor(leftOpen.descriptor, leftOpen.stat), leftIdentity, 'comparison');
		assertIdentity(
			inspectDescriptor(rightOpen.descriptor, rightOpen.stat, allowRightMultipleLinks),
			rightIdentity,
			'comparison',
		);
		return true;
	} finally {
		closeSync(leftOpen.descriptor);
		closeSync(rightOpen.descriptor);
	}
}

function printJson(value) {
	process.stdout.write(`${JSON.stringify(value)}\n`);
}

function performOperation(operation, args) {
	switch (operation) {
		case 'identity':
			if (args.length !== 1) fail('identity requires one path');
			return inspect(args[0]);
		case 'identity-live':
			if (args.length !== 1) fail('identity-live requires one path');
			return inspect(args[0], true);
		case 'lstat':
			if (args.length !== 1) fail('lstat requires one path');
			return lstatIdentity(args[0]);
		case 'absent':
			if (args.length !== 1 || !isAbsent(args[0])) fail(`path is not absent: ${args[0]}`);
			return undefined;
		case 'same':
			return args.length === 2 && sameFiles(args[0], args[1]);
		case 'same-live':
			return args.length === 2 && sameFiles(args[0], args[1], true);
		case 'copy':
			if (args.length !== 3 && args.length !== 4) fail('copy requires source, destination, mode, and optional expected source identity');
			return copyStable(args[0], args[1], args[2], args[3] === undefined ? undefined : parseExpected(args[3]));
		case 'create':
			if (args.length !== 3) fail('create requires destination, mode, and content');
			return createStable(args[0], args[1], args[2]);
		case 'publish-absent':
			if (args.length !== 2) fail('publish-absent requires stage and target');
			return publishAbsent(args[0], args[1]);
		case 'publish-replace':
			if (args.length !== 3) fail('publish-replace requires stage, target, and expected identity');
			return publishReplace(args[0], args[1], parseExpected(args[2]));
		case 'remove':
			if (args.length !== 2) fail('remove requires path and expected identity');
			removeExpected(args[0], parseExpected(args[1]));
			return undefined;
		case 'remove-core':
			if (args.length !== 2) fail('remove-core requires path and expected identity');
			removeCoreExpected(args[0], parseExpected(args[1]));
			return undefined;
		case 'remove-to':
			if (args.length !== 3) fail('remove-to requires path, expected identity, and quarantine');
			return removeTo(args[0], parseExpected(args[1]), args[2]);
		case 'remove-dir':
			if (args.length !== 2) fail('remove-dir requires path and expected directory identity');
			removeDirectoryExpected(args[0], parseLstatExpected(args[1]));
			return undefined;
		case 'read':
			if (args.length !== 1 && args.length !== 2) fail('read requires one path and optional expected identity');
			return readStable(args[0], args[1] === undefined ? undefined : parseExpected(args[1]));
		default:
			fail(`unknown wallpaper file operation: ${operation ?? ''}`);
	}
}

function executeServerOperation(operation, args) {
	try {
		const value = performOperation(operation, args);
		if (operation === 'same' || operation === 'same-live') {
			return { status: value ? 0 : 1, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0) };
		}
		const stdout = Buffer.isBuffer(value) ? value : value === undefined ? Buffer.alloc(0) : Buffer.from(`${JSON.stringify(value)}\n`);
		return { status: 0, stdout, stderr: Buffer.alloc(0) };
	} catch (error) {
		return { status: 1, stdout: Buffer.alloc(0), stderr: Buffer.from(`Error: ${error.message}\n`) };
	}
}

function printServerResult(result) {
	const stdout = result.stdout ?? Buffer.alloc(0);
	const stderr = result.stderr ?? Buffer.alloc(0);
	// The header is text, but both following frames are raw bytes. Their lengths
	// keep arbitrary stdout and stderr (including NULs and newlines) outside the
	// protocol's delimiter grammar. A fixed ASCII terminator lets the client
	// detect a server that stops before completing a declared frame.
	process.stdout.write(`status=${result.status} stdout=${stdout.length} stderr=${stderr.length}\n`);
	process.stdout.write(stdout);
	process.stdout.write(SERVER_FRAME_TERMINATOR);
	process.stdout.write(stderr);
	process.stdout.write(SERVER_FRAME_TERMINATOR);
}

function serverError(error) {
	const message = error instanceof Error ? error.message : String(error);
	return { status: 1, stdout: Buffer.alloc(0), stderr: Buffer.from(`Error: ${message}\n`) };
}

function executeServerRequest(line) {
	try {
		const request = JSON.parse(line.toString('utf8'));
		if (!Array.isArray(request)) fail('server request must be a JSON array');
		return executeServerOperation(request[0], request.slice(1));
	} catch (error) {
		return serverError(error);
	}
}

function reportServerFailure(error) {
	const message = error instanceof Error ? error.message : String(error);
	process.stderr.write(`Error: wallpaper file server failed: ${message}\n`);
	process.exitCode = 1;
}

function runServer() {
	let input = Buffer.alloc(0);
	process.stdin.on('data', (chunk) => {
		input = Buffer.concat([input, chunk]);
		let newline;
		while ((newline = input.indexOf(0x0a)) !== -1) {
			const line = input.subarray(0, newline);
			input = input.slice(newline + 1);
			printServerResult(executeServerRequest(line));
		}
	});
	process.stdin.on('end', () => {
		if (input.length > 0) reportServerFailure(new Error('incomplete request frame'));
	});
	process.stdin.on('error', reportServerFailure);
	process.stdout.on('error', reportServerFailure);
}

if (process.argv[2] === '--server') runServer();
else try {
	const [operation, ...args] = process.argv.slice(2);
	const value = performOperation(operation, args);
	if (operation === 'same' || operation === 'same-live') {
		if (!value) process.exitCode = 1;
	} else if (operation === 'read') {
		process.stdout.write(value);
	} else if (value !== undefined) {
		printJson(value);
	}
} catch (error) {
	process.stderr.write(`Error: ${error.message}\n`);
	process.exitCode = 1;
}
