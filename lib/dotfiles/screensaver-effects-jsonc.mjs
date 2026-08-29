#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const MANAGED_ID = "system.screensaver";
const MANAGED_ENTRY = {
  icon: "\udb84\udd04",
  label: "Screensaver",
  action: "omarchy-shell idle screensaver",
};
const MANAGED_BLOCK =
  '\n  // dotfiles:screensaver-effects\n  "system.screensaver": {"icon":"\\udb84\\udd04","label":"Screensaver","action":"omarchy-shell idle screensaver"},';

function fail(message) {
  process.stderr.write(`screensaver-effects-jsonc: ${message}\n`);
  process.exit(1);
}

function stripJsonc(input) {
  const chars = [...input];
  let inString = false;
  let escaped = false;

  for (let index = 0; index < chars.length; index += 1) {
    const current = chars[index];
    const next = chars[index + 1];

    if (inString) {
      if (escaped) escaped = false;
      else if (current === "\\") escaped = true;
      else if (current === '"') inString = false;
      continue;
    }

    if (current === '"') {
      inString = true;
      continue;
    }

    if (current === "/" && next === "/") {
      chars[index] = " ";
      chars[index + 1] = " ";
      index += 2;
      while (index < chars.length && chars[index] !== "\n") {
        chars[index] = " ";
        index += 1;
      }
      index -= 1;
      continue;
    }

    if (current === "/" && next === "*") {
      chars[index] = " ";
      chars[index + 1] = " ";
      index += 2;
      let closed = false;
      while (index < chars.length) {
        if (chars[index] === "*" && chars[index + 1] === "/") {
          chars[index] = " ";
          chars[index + 1] = " ";
          index += 1;
          closed = true;
          break;
        }
        if (chars[index] !== "\n") chars[index] = " ";
        index += 1;
      }
      if (!closed) fail("unterminated block comment");
    }
  }

  const stripped = chars.join("");
  const output = [...stripped];
  inString = false;
  escaped = false;
  for (let index = 0; index < output.length; index += 1) {
    const current = output[index];
    if (inString) {
      if (escaped) escaped = false;
      else if (current === "\\") escaped = true;
      else if (current === '"') inString = false;
      continue;
    }
    if (current === '"') {
      inString = true;
      continue;
    }
    if (current !== ",") continue;
    let next = index + 1;
    while (next < output.length && /\s/.test(output[next])) next += 1;
    if (output[next] === "}" || output[next] === "]") output[index] = " ";
  }
  return output.join("");
}

function countTopLevelKey(stripped, wanted) {
  let depth = 0;
  let count = 0;
  let index = 0;
  while (index < stripped.length) {
    const current = stripped[index];
    if (current === '"') {
      const start = index;
      index += 1;
      let escaped = false;
      while (index < stripped.length) {
        const character = stripped[index];
        if (escaped) escaped = false;
        else if (character === "\\") escaped = true;
        else if (character === '"') break;
        index += 1;
      }
      if (index >= stripped.length) fail("unterminated string");
      if (depth === 1) {
        const token = stripped.slice(start, index + 1);
        let cursor = index + 1;
        while (cursor < stripped.length && /\s/.test(stripped[cursor])) cursor += 1;
        if (stripped[cursor] === ":" && JSON.parse(token) === wanted) count += 1;
      }
    } else if (current === "{" || current === "[") depth += 1;
    else if (current === "}" || current === "]") depth -= 1;
    index += 1;
  }
  return count;
}

function entriesAreEqual(left, right) {
  if (!left || typeof left !== "object" || Array.isArray(left)) return false;
  const leftKeys = Object.keys(left).sort();
  const rightKeys = Object.keys(right).sort();
  return (
    JSON.stringify(leftKeys) === JSON.stringify(rightKeys) &&
    rightKeys.every((key) => left[key] === right[key])
  );
}

function inspect(file) {
  let metadata;
  try {
    metadata = fs.lstatSync(file);
  } catch (error) {
    if (error.code !== "ENOENT") fail(`cannot inspect menu extension at ${file}: ${error.message}`);
    return {
      fileExists: false,
      present: false,
      identical: false,
      ownedMarker: false,
      content: "",
      mode: 0o600,
    };
  }
  if (!metadata.isFile()) fail(`menu extension is not a regular file: ${file}`);
  const content = fs.readFileSync(file, "utf8");
  const stripped = stripJsonc(content);
  let parsed;
  try {
    parsed = JSON.parse(stripped);
  } catch (error) {
    fail(`invalid menu JSONC at ${file}: ${error.message}`);
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    fail(`menu JSONC root must be an object: ${file}`);
  }
  const count = countTopLevelKey(stripped, MANAGED_ID);
  if (count > 1) fail(`menu JSONC contains duplicate ${MANAGED_ID} entries: ${file}`);
  const present = count === 1;
  return {
    fileExists: true,
    present,
    identical: present && entriesAreEqual(parsed[MANAGED_ID], MANAGED_ENTRY),
    ownedMarker: content.includes(MANAGED_BLOCK),
    content,
    mode: metadata.mode & 0o7777,
    objectStart: stripped.indexOf("{"),
  };
}

function atomicWrite(file, content, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.dotfiles.${process.pid}.${Date.now()}.tmp`;
  try {
    fs.writeFileSync(temporary, content, { mode, flag: "wx" });
    fs.renameSync(temporary, file);
    fs.chmodSync(file, mode);
  } finally {
    try {
      fs.unlinkSync(temporary);
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
}

function parseJsoncTree(content, label) {
  const stripped = stripJsonc(content);
  try {
    JSON.parse(stripped);
  } catch (error) {
    fail(`invalid ${label} JSONC: ${error.message}`);
  }

  let cursor = 0;
  const skipWhitespace = () => {
    while (cursor < stripped.length && /\s/.test(stripped[cursor])) cursor += 1;
  };
  const parseString = () => {
    const start = cursor;
    cursor += 1;
    let escaped = false;
    while (cursor < stripped.length) {
      const character = stripped[cursor];
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === '"') {
        cursor += 1;
        const token = stripped.slice(start, cursor);
        return { type: "string", value: JSON.parse(token), start, end: cursor };
      }
      cursor += 1;
    }
    fail(`unterminated string in ${label} JSONC`);
  };
  const parseValue = () => {
    skipWhitespace();
    const start = cursor;
    const character = stripped[cursor];
    if (character === '"') return parseString();
    if (character === "{") {
      cursor += 1;
      const properties = [];
      const value = {};
      skipWhitespace();
      while (stripped[cursor] !== "}") {
        if (stripped[cursor] !== '"') fail(`expected object key in ${label} JSONC`);
        const keyNode = parseString();
        if (properties.some((property) => property.key === keyNode.value)) {
          fail(`duplicate object key ${keyNode.value} in ${label} JSONC`);
        }
        skipWhitespace();
        if (stripped[cursor] !== ":") fail(`expected colon in ${label} JSONC`);
        cursor += 1;
        const valueNode = parseValue();
        properties.push({ key: keyNode.value, keyNode, valueNode });
        value[keyNode.value] = valueNode.value;
        skipWhitespace();
        if (stripped[cursor] === ",") {
          cursor += 1;
          skipWhitespace();
        } else if (stripped[cursor] !== "}") {
          fail(`expected comma or closing brace in ${label} JSONC`);
        }
      }
      cursor += 1;
      return { type: "object", value, properties, start, end: cursor };
    }
    if (character === "[") {
      cursor += 1;
      const items = [];
      skipWhitespace();
      while (stripped[cursor] !== "]") {
        const item = parseValue();
        items.push(item);
        skipWhitespace();
        if (stripped[cursor] === ",") {
          cursor += 1;
          skipWhitespace();
        } else if (stripped[cursor] !== "]") {
          fail(`expected comma or closing bracket in ${label} JSONC`);
        }
      }
      cursor += 1;
      return { type: "array", value: items.map((item) => item.value), items, start, end: cursor };
    }

    const token = stripped.slice(cursor).match(/^(?:true|false|null|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/)?.[0];
    if (!token) fail(`invalid value in ${label} JSONC`);
    cursor += token.length;
    return { type: "scalar", value: JSON.parse(token), start, end: cursor };
  };

  const root = parseValue();
  skipWhitespace();
  if (cursor !== stripped.length) fail(`unexpected trailing content in ${label} JSONC`);
  return root;
}

function objectProperty(node, key, context) {
  if (node.type !== "object") fail(`${context} must be an object`);
  const property = node.properties.find((candidate) => candidate.key === key);
  if (!property) fail(`${context} is missing ${key}`);
  return property.valueNode;
}

function optionalObjectProperty(node, key) {
  if (node.type !== "object") fail("shell configuration root must be an object");
  return node.properties.find((candidate) => candidate.key === key);
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function jsonEqual(left, right) {
  return canonicalJson(left) === canonicalJson(right);
}

function readRegularFile(file, label) {
  let metadata;
  try {
    metadata = fs.lstatSync(file);
  } catch (error) {
    fail(`cannot inspect ${label} at ${file}: ${error.message}`);
  }
  if (!metadata.isFile()) fail(`${label} is not a regular file: ${file}`);
  const content = fs.readFileSync(file, "utf8");
  return {
    content,
    mode: metadata.mode & 0o7777,
    root: parseJsoncTree(content, `${label} at ${file}`),
  };
}

function replaceRange(content, start, end, replacement) {
  return content.slice(0, start) + replacement + content.slice(end);
}

function withoutComma(separator, context) {
  const index = separator.indexOf(",");
  if (index < 0) fail(`missing comma while removing ${context}`);
  return separator.slice(0, index) + separator.slice(index + 1);
}

function addArrayItem(content, key, item) {
  const root = parseJsoncTree(content, "shell configuration");
  const property = optionalObjectProperty(root, key);
  const serialized = JSON.stringify(item);
  if (!property) {
    const insertion = `${JSON.stringify(key)}:[${serialized}]`;
    if (root.properties.length === 0) return replaceRange(content, root.start + 1, root.start + 1, insertion);
    const last = root.properties[root.properties.length - 1].valueNode;
    return replaceRange(content, last.end, last.end, `,${insertion}`);
  }
  const array = property.valueNode;
  if (array.type !== "array") fail(`${key} must be an array`);
  if (array.items.some((candidate) => jsonEqual(candidate.value, item))) fail(`${key} already contains an owned entry`);
  if (array.items.length === 0) return replaceRange(content, array.start + 1, array.start + 1, serialized);
  const last = array.items[array.items.length - 1];
  return replaceRange(content, last.end, last.end, `,${serialized}`);
}

function removeObjectProperty(content, key) {
  const root = parseJsoncTree(content, "shell configuration");
  const index = root.properties.findIndex((candidate) => candidate.key === key);
  if (index < 0) return content;
  const property = root.properties[index];
  if (root.properties.length === 1) {
    return replaceRange(content, property.keyNode.start, property.valueNode.end, "");
  }
  if (index > 0) {
    const start = root.properties[index - 1].valueNode.end;
    const separator = withoutComma(content.slice(start, property.keyNode.start), `shell field ${key}`);
    return replaceRange(content, start, property.valueNode.end, separator);
  }
  const end = root.properties[1].keyNode.start;
  const separator = withoutComma(content.slice(property.valueNode.end, end), `shell field ${key}`);
  return replaceRange(content, property.keyNode.start, end, separator);
}

function removeArrayItems(content, key, predicate, removeEmptyProperty) {
  let root = parseJsoncTree(content, "shell configuration");
  let property = optionalObjectProperty(root, key);
  if (!property) return content;
  let array = property.valueNode;
  if (array.type !== "array") fail(`${key} must be an array`);
  const matches = array.items.filter((candidate) => predicate(candidate.value));
  if (matches.length > 1) fail(`${key} contains duplicate owned entries`);
  if (matches.length === 1) {
    const index = array.items.indexOf(matches[0]);
    if (array.items.length === 1) {
      content = replaceRange(content, matches[0].start, matches[0].end, "");
    } else if (index > 0) {
      const start = array.items[index - 1].end;
      const separator = withoutComma(content.slice(start, matches[0].start), `owned ${key} entry`);
      content = replaceRange(content, start, matches[0].end, separator);
    } else {
      const end = array.items[1].start;
      const separator = withoutComma(content.slice(matches[0].end, end), `owned ${key} entry`);
      content = replaceRange(content, matches[0].start, end, separator);
    }
  }
  root = parseJsoncTree(content, "shell configuration");
  property = optionalObjectProperty(root, key);
  array = property?.valueNode;
  if (removeEmptyProperty && array?.type === "array" && array.items.length === 0) {
    content = removeObjectProperty(content, key);
  }
  return content;
}

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function arrayValue(config, key) {
  return Array.isArray(config[key]) ? config[key] : [];
}

function expectedIdleCommand(before, operation) {
  const config = cloneJson(before);
  if (!config.bar || typeof config.bar !== "object" || Array.isArray(config.bar)) {
    config.bar = { layout: { left: [], center: [], right: [] } };
  }
  if (!config.bar.layout || typeof config.bar.layout !== "object" || Array.isArray(config.bar.layout)) {
    config.bar.layout = { left: [], center: [], right: [] };
  }
  for (const section of ["left", "center", "right"]) {
    if (!Array.isArray(config.bar.layout[section])) config.bar.layout[section] = [];
  }
  if (!Array.isArray(config.plugins)) config.plugins = [];

  const pluginIndexes = config.plugins
    .map((entry, index) => (entry && typeof entry === "object" && entry.id === "dotfiles.idle" ? index : -1))
    .filter((index) => index >= 0);
  if (pluginIndexes.length > 1) fail("plugins contains duplicate dotfiles.idle entries");

  if (operation === "shell-idle-enable") {
    if (Array.isArray(config.disabledPlugins)) {
      config.disabledPlugins = config.disabledPlugins.filter((id) => id !== "dotfiles.idle");
    }
    if (pluginIndexes.length === 0) config.plugins.push({ id: "dotfiles.idle" });
    if (!arrayValue(config, "disabledPlugins").includes("omarchy.idle")) {
      if (!Array.isArray(config.disabledPlugins)) config.disabledPlugins = [];
      config.disabledPlugins.push("omarchy.idle");
      config.cloneSourceRestores = arrayValue(config, "cloneSourceRestores").filter(
        (id) => id !== "dotfiles.idle",
      );
      config.cloneSourceRestores.push("dotfiles.idle");
    }
  } else if (operation === "shell-idle-disable") {
    if (pluginIndexes.length === 1) config.plugins.splice(pluginIndexes[0], 1);
    if (arrayValue(config, "cloneSourceRestores").includes("dotfiles.idle")) {
      config.disabledPlugins = arrayValue(config, "disabledPlugins").filter((id) => id !== "omarchy.idle");
      config.cloneSourceRestores = arrayValue(config, "cloneSourceRestores").filter(
        (id) => id !== "dotfiles.idle",
      );
      if (config.cloneSourceRestores.length === 0) delete config.cloneSourceRestores;
    }
  } else {
    fail(`unknown idle command operation: ${operation}`);
  }
  config.version = 1;
  return config;
}

function normalizedShellSemantics(value) {
  const config = cloneJson(value);
  for (const key of ["plugins", "disabledPlugins", "cloneSourceRestores"]) {
    if (!Array.isArray(config[key])) config[key] = [];
  }
  return config;
}

function parseShellFields(value) {
  let fields;
  try {
    fields = JSON.parse(value);
  } catch (error) {
    fail(`invalid prior shell field state: ${error.message}`);
  }
  const keys = Object.keys(fields).sort();
  const expected = ["clone_source_restores", "disabled_plugins", "plugins"];
  if (
    JSON.stringify(keys) !== JSON.stringify(expected) ||
    expected.some((key) => typeof fields[key] !== "boolean")
  ) {
    fail("invalid prior shell field state");
  }
  return fields;
}

function reconcileIdleCommand(file, snapshotFile, operation, fieldsText) {
  const before = readRegularFile(snapshotFile, "pre-command shell snapshot");
  const current = readRegularFile(file, "shell configuration");
  const expected = expectedIdleCommand(before.root.value, operation);
  if (!jsonEqual(current.root.value, expected)) {
    atomicWrite(file, before.content, before.mode);
    fail(`omarchy command made unexpected shell configuration changes during ${operation}`);
  }

  let updated = before.content;
  if (operation === "shell-idle-enable") {
    const beforeValue = before.root.value;
    if (!arrayValue(beforeValue, "plugins").some((entry) => entry?.id === "dotfiles.idle")) {
      updated = addArrayItem(updated, "plugins", { id: "dotfiles.idle" });
    }
    if (arrayValue(beforeValue, "disabledPlugins").includes("dotfiles.idle")) {
      updated = removeArrayItems(updated, "disabledPlugins", (id) => id === "dotfiles.idle", false);
    }
    if (!arrayValue(beforeValue, "disabledPlugins").includes("omarchy.idle")) {
      updated = addArrayItem(updated, "disabledPlugins", "omarchy.idle");
      updated = removeArrayItems(updated, "cloneSourceRestores", (id) => id === "dotfiles.idle", false);
      updated = addArrayItem(updated, "cloneSourceRestores", "dotfiles.idle");
    }
  } else {
    const fields = parseShellFields(fieldsText);
    const beforeValue = before.root.value;
    const restoresSource = arrayValue(beforeValue, "cloneSourceRestores").includes("dotfiles.idle");
    updated = removeArrayItems(updated, "plugins", (entry) => entry?.id === "dotfiles.idle", !fields.plugins);
    if (restoresSource) {
      updated = removeArrayItems(
        updated,
        "cloneSourceRestores",
        (id) => id === "dotfiles.idle",
        !fields.clone_source_restores,
      );
      updated = removeArrayItems(
        updated,
        "disabledPlugins",
        (id) => id === "omarchy.idle",
        !fields.disabled_plugins,
      );
    }
  }

  const updatedRoot = parseJsoncTree(updated, "reconciled shell configuration");
  if (!jsonEqual(normalizedShellSemantics(updatedRoot.value), normalizedShellSemantics(expected))) {
    atomicWrite(file, before.content, before.mode);
    fail(`narrow shell reconciliation did not preserve ${operation} semantics`);
  }
  atomicWrite(file, updated, before.mode);
  return { changed: updated !== before.content };
}

function shellFieldPresence(file) {
  const shell = readRegularFile(file, "shell configuration");
  return {
    plugins: Boolean(optionalObjectProperty(shell.root, "plugins")),
    disabled_plugins: Boolean(optionalObjectProperty(shell.root, "disabledPlugins")),
    clone_source_restores: Boolean(optionalObjectProperty(shell.root, "cloneSourceRestores")),
  };
}

function restoreSnapshot(file, snapshotFile) {
  const before = readRegularFile(snapshotFile, "shell snapshot");
  atomicWrite(file, before.content, before.mode);
  return { changed: true };
}

function patchIndicators(file, entriesText, operation) {
  let entries;
  try {
    entries = JSON.parse(entriesText);
  } catch (error) {
    fail(`invalid recorded Indicators entries: ${error.message}`);
  }
  if (!Array.isArray(entries)) fail("recorded Indicators entries must be an array");

  const coordinates = new Set();
  for (const recorded of entries) {
    if (
      !recorded ||
      typeof recorded !== "object" ||
      !["left", "center", "right"].includes(recorded.section) ||
      !Number.isInteger(recorded.index) ||
      recorded.index < 0 ||
      !recorded.entry ||
      typeof recorded.entry !== "object" ||
      Array.isArray(recorded.entry) ||
      !["omarchy.indicators", "dotfiles.indicators"].includes(recorded.entry.id)
    ) {
      fail("invalid recorded Indicators coordinate");
    }
    const coordinate = `${recorded.section}:${recorded.index}`;
    if (coordinates.has(coordinate)) fail(`duplicate recorded Indicators coordinate ${coordinate}`);
    coordinates.add(coordinate);
  }

  let metadata;
  try {
    metadata = fs.lstatSync(file);
  } catch (error) {
    fail(`cannot inspect shell configuration at ${file}: ${error.message}`);
  }
  if (!metadata.isFile()) fail(`shell configuration is not a regular file: ${file}`);
  const content = fs.readFileSync(file, "utf8");
  const root = parseJsoncTree(content, `shell configuration at ${file}`);
  const bar = objectProperty(root, "bar", "shell configuration");
  const layout = objectProperty(bar, "layout", "shell configuration bar");
  const patches = [];

  for (const recorded of entries) {
    const section = objectProperty(layout, recorded.section, "shell configuration bar layout");
    if (section.type !== "array" || recorded.index >= section.items.length) {
      fail(`recorded Indicators coordinate is missing: ${recorded.section}[${recorded.index}]`);
    }
    const entryNode = section.items[recorded.index];
    const idNode = objectProperty(entryNode, "id", `Indicators entry at ${recorded.section}[${recorded.index}]`);
    if (idNode.type !== "string") {
      fail(`Indicators id is not a string at ${recorded.section}[${recorded.index}]`);
    }

    const original = recorded.entry;
    const active = { ...recorded.entry, id: "dotfiles.indicators" };
    if (operation === "shell-bar-activate") {
      if (original.id !== "omarchy.indicators") fail("activation entries must record omarchy.indicators");
      if (jsonEqual(entryNode.value, active)) continue;
      if (!jsonEqual(entryNode.value, original) || idNode.value !== "omarchy.indicators") {
        fail(`recorded Indicators coordinate changed: ${recorded.section}[${recorded.index}]`);
      }
      patches.push({ start: idNode.start, end: idNode.end, value: JSON.stringify("dotfiles.indicators") });
    } else if (operation === "shell-bar-restore") {
      if (original.id === "dotfiles.indicators") {
        if (!jsonEqual(entryNode.value, original)) {
          fail(`recorded Indicators coordinate changed: ${recorded.section}[${recorded.index}]`);
        }
        continue;
      }
      if (jsonEqual(entryNode.value, original)) continue;
      if (!jsonEqual(entryNode.value, active) || idNode.value !== "dotfiles.indicators") {
        fail(`recorded Indicators coordinate changed: ${recorded.section}[${recorded.index}]`);
      }
      patches.push({ start: idNode.start, end: idNode.end, value: JSON.stringify("omarchy.indicators") });
    } else {
      fail(`unknown Indicators patch operation: ${operation}`);
    }
  }

  if (patches.length === 0) return { changed: false };
  let updated = content;
  for (const patch of patches.sort((left, right) => right.start - left.start)) {
    updated = updated.slice(0, patch.start) + patch.value + updated.slice(patch.end);
  }
  parseJsoncTree(updated, `updated shell configuration at ${file}`);
  atomicWrite(file, updated, metadata.mode & 0o7777);
  return { changed: true };
}

function publicInspection(file) {
  const result = inspect(file);
  return {
    file_exists: result.fileExists,
    present: result.present,
    identical: result.identical,
    owned_marker: result.ownedMarker,
  };
}

function insert(file) {
  const result = inspect(file);
  if (result.present) {
    if (!result.identical) fail(`a different ${MANAGED_ID} entry already exists: ${file}`);
    return { changed: false, owned: result.ownedMarker };
  }
  if (result.ownedMarker) fail(`menu JSONC contains a stale ownership block: ${file}`);

  if (!result.fileExists) {
    atomicWrite(file, `{${MANAGED_BLOCK}\n}\n`, 0o600);
  } else {
    if (result.objectStart < 0) fail(`menu JSONC has no root object: ${file}`);
    const content =
      result.content.slice(0, result.objectStart + 1) +
      MANAGED_BLOCK +
      result.content.slice(result.objectStart + 1);
    atomicWrite(file, content, result.mode);
  }
  return { changed: true, owned: true };
}

function remove(file, fileExistedBefore) {
  const result = inspect(file);
  if (!result.present || !result.identical || !result.ownedMarker) {
    fail(`receipt-owned ${MANAGED_ID} entry changed or is missing: ${file}`);
  }
  const updated = result.content.replace(MANAGED_BLOCK, "");
  const stripped = stripJsonc(updated);
  try {
    JSON.parse(stripped);
  } catch (error) {
    fail(`removing ${MANAGED_ID} would produce invalid JSONC at ${file}: ${error.message}`);
  }
  if (countTopLevelKey(stripped, MANAGED_ID) !== 0 || updated.includes(MANAGED_BLOCK)) {
    fail(`ownership block does not uniquely identify ${MANAGED_ID}: ${file}`);
  }
  if (!fileExistedBefore && updated === "{\n}\n") {
    fs.unlinkSync(file);
  } else {
    atomicWrite(file, updated, result.mode);
  }
  return { changed: true, owned: false };
}

const [operation, file, option, extra] = process.argv.slice(2);
if (!operation || !file) {
  fail(
    "usage: screensaver-effects-jsonc.mjs <operation> <file> [option] [extra]",
  );
}

let result;
if (operation === "inspect") result = publicInspection(file);
else if (operation === "insert") result = insert(file);
else if (operation === "remove") {
  if (option !== "true" && option !== "false") fail("remove requires true or false for prior file existence");
  result = remove(file, option === "true");
} else if (operation === "shell-bar-activate" || operation === "shell-bar-restore") {
  if (option === undefined) fail(`${operation} requires recorded Indicators entries`);
  result = patchIndicators(file, option, operation);
} else if (operation === "shell-fields") {
  result = shellFieldPresence(file);
} else if (operation === "shell-idle-enable" || operation === "shell-idle-disable") {
  if (option === undefined) fail(`${operation} requires a pre-command snapshot`);
  if (operation === "shell-idle-disable" && extra === undefined) fail(`${operation} requires prior shell fields`);
  result = reconcileIdleCommand(file, option, operation, extra);
} else if (operation === "shell-restore-snapshot") {
  if (option === undefined) fail(`${operation} requires a shell snapshot`);
  result = restoreSnapshot(file, option);
} else fail(`unknown operation: ${operation}`);

process.stdout.write(`${JSON.stringify(result)}\n`);
