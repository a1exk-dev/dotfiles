// PROTOTYPE - throwaway. Answers issue #7 "Prototype the wizard flow and status report".
// This is the flow the owner picked from variants.ts. Nothing here touches the machine:
// the engine is a stub with fake delays, fake failures, a fake OBS-running check,
// and a fake pkexec password prompt.
//
// Run:  bun index.ts
//       FAIL=none bun index.ts   (no simulated failures)
import * as p from "@clack/prompts";
import { spawnSync } from "node:child_process";

// ---------------------------------------------------------------- fake world

type Machine = "pc" | "laptop";
type Kind = "stowed" | "copied" | "system" | "app" | "removal";
type Item = {
  name: string;
  kind: Kind;
  machine?: Machine; // undefined = both
  root?: boolean; // needs pkexec
  obs?: boolean; // blocked while OBS runs
  plan: string[];
  applied: boolean;
  fail?: string; // simulated failure
  checkFail?: string; // simulated failed file check
  warn?: string; // simulated version mismatch
};

const FAILS = process.env.FAIL !== "none";
const APPS: Item[] = [
  { name: "Bruno", kind: "app", plan: ["install bruno-bin (AUR) via Omarchy"], applied: false, fail: FAILS ? "omarchy pkg add bruno-bin: AUR build failed (pgp key 0xDEADBEEF unknown)" : undefined },
  { name: "OBS Studio", kind: "app", plan: ["install obs-studio via Omarchy"], applied: true },
  { name: "Telegram", kind: "app", plan: ["install telegram-desktop via Omarchy"], applied: false },
  { name: "llama.cpp + models", kind: "app", machine: "pc", plan: ["install llama.cpp-vulkan via Omarchy", "download 2 models"], applied: false },
  { name: "voxtype", kind: "app", plan: ["install voxtype via Omarchy"], applied: true, warn: "voxtype 0.4.1 installed, manifest wants >= 0.5.0" },
];
const REMOVALS: Item[] = [
  { name: "1password-beta", kind: "removal", plan: ["remove 1password-beta via Omarchy"], applied: false },
  { name: "HEY (web app)", kind: "removal", plan: ["remove web app HEY"], applied: false },
  { name: "Basecamp (web app)", kind: "removal", plan: ["remove web app Basecamp"], applied: false },
];
const CONFIGS: Item[] = [
  { name: "bash", kind: "stowed", plan: ["link ~/.bashrc", "link ~/.inputrc"], applied: true },
  { name: "Claude settings", kind: "copied", plan: ["back up and overwrite ~/.claude/settings.json", "link ~/.claude/CLAUDE.md"], applied: false },
  { name: "Discord settings", kind: "copied", plan: ["back up and overwrite ~/.config/discord/settings.json"], applied: false },
  { name: "Discord system24", kind: "stowed", plan: ["link system24 theme", "run theme hook"], applied: false, fail: FAILS ? "theme hook exited 1: vencord themes folder not found (~/.config/Vencord/themes)" : undefined },
  { name: "hyprland", kind: "stowed", plan: ["link 6 files under ~/.config/hypr", "link machine profiles under ~/.config/dotfiles/hypr"], applied: false },
  { name: "OBS machine set (pc)", kind: "copied", machine: "pc", obs: true, plan: ["back up and overwrite 2 profiles", "back up and overwrite scene collection", "back up and overwrite geometry.json", "prune 1 stale file (receipt)"], applied: false },
  { name: "OBS machine set (laptop)", kind: "copied", machine: "laptop", obs: true, plan: ["back up and overwrite 1 profile", "back up and overwrite scene collection", "back up and overwrite geometry.json"], applied: false },
  { name: "OBS theme", kind: "stowed", obs: true, plan: ["set 3 keys in OBS user.ini"], applied: true },
  { name: "Screensaver effects", kind: "stowed", plan: ["link effect allowlist", "enable plugin"], applied: false, checkFail: FAILS ? "~/.config/omarchy/screensaver.json differs from repo after write" : undefined },
  { name: "tmux", kind: "stowed", plan: ["link ~/.config/tmux/tmux.conf"], applied: false },
  { name: "Wallpaper library", kind: "copied", plan: ["copy 42 wallpapers into 6 theme folders", "prune 3 stale files (receipt)"], applied: false },
  { name: "Shared Brave policy", kind: "system", root: true, plan: ["back up and overwrite /etc/brave/policies/managed/dotfiles.json"], applied: false },
  { name: "Laptop power policy", kind: "system", machine: "laptop", root: true, plan: ["write UPower drop-in in /etc/UPower", "write logind drop-in in /etc/systemd/logind.conf.d"], applied: false },
];

let machine: Machine = "pc"; // how the wizard knows this outside Wizard Setup is issue #11
const LOGS = new Map<string, string>(); // item -> full output, in memory only
let obsRunning = true; // fake: OBS is open at first
let rootCached = false; // fake: pkexec asks once per run
let obsSkipped = false; // a skip covers every OBS write in the run

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const C = { dim: (s: string) => `\x1b[2m${s}\x1b[22m`, red: (s: string) => `\x1b[31m${s}\x1b[39m`, green: (s: string) => `\x1b[32m${s}\x1b[39m`, yellow: (s: string) => `\x1b[33m${s}\x1b[39m`, bold: (s: string) => `\x1b[1m${s}\x1b[22m` };
const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "");
const cancelled = (v: unknown): v is symbol => p.isCancel(v);
const forMachine = (i: Item) => !i.machine || i.machine === machine;

// ---------------------------------------------------------------- tables

type Status = "ok" | "changed" | "removed" | "skipped" | "failed" | "check failed" | "warning";
type Row = { item: string; result: Status; detail: string };

const colour = (r: Status) => (r === "failed" || r === "check failed" ? C.red(r) : r === "skipped" || r === "warning" ? C.yellow(r) : C.green(r));
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s);
const pad = (s: string, n: number) => s + " ".repeat(Math.max(0, n - strip(s).length));

function columns(rows: Row[]) {
  const width = Math.min(process.stdout.columns ?? 80, 110) - 10;
  const w1 = Math.max(4, ...rows.map((r) => r.item.length));
  const w2 = 12;
  return { w1, w2, w3: Math.max(10, width - w1 - w2 - 4) };
}

function table(rows: Row[]): string {
  const { w1, w2, w3 } = columns(rows);
  const line = (a: string, b: string, c: string) => `${pad(a, w1)}  ${pad(b, w2)}  ${cut(c, w3)}`;
  return [C.bold(line("Item", "Result", "Detail")), ...rows.map((r) => line(r.item, colour(r.result), r.detail))].join("\n");
}

function summary(rows: Row[]): string {
  const n = (k: Status) => rows.filter((r) => r.result === k).length;
  const parts = [`${n("changed")} changed`];
  if (n("removed")) parts.push(`${n("removed")} removed`);
  parts.push(`${n("ok")} already in place`);
  if (n("skipped")) parts.push(C.yellow(`${n("skipped")} skipped`));
  if (n("warning")) parts.push(C.yellow(`${n("warning")} warning`));
  const bad = n("failed") + n("check failed");
  if (bad) parts.push(C.red(`${bad} failed`));
  return parts.join(", ");
}

function planText(items: Item[]): string {
  return items
    .map((i) => {
      const tags = [i.root ? C.yellow("needs password") : "", i.obs ? C.yellow("OBS must be closed") : "", i.applied ? C.dim("already in place, reapplied") : ""].filter(Boolean).join(", ");
      return [`${C.bold(i.name)} ${C.dim(`(${i.kind})`)}${tags ? "  " + tags : ""}`, ...i.plan.map((x) => `  - ${x}`)].join("\n");
    })
    .join("\n");
}

// ---------------------------------------------------------------- running

// The OBS close prompt from issue #6: ask, check again, skip OBS writes on cancel.
async function ensureObsClosed(): Promise<boolean> {
  if (obsSkipped) return false;
  while (obsRunning) {
    const a = await p.select({
      message: "OBS is running. Close OBS, then continue.",
      options: [
        { value: "retry", label: "I closed OBS, check again" },
        { value: "skip", label: "Skip the OBS writes this run" },
      ],
    });
    if (cancelled(a) || a === "skip") return !(obsSkipped = true);
    obsRunning = Math.random() < 0.3; // fake: sometimes it is still open
    if (obsRunning) p.log.warn("OBS is still running.");
  }
  return true;
}

// Stand-in for pkexec. With no graphical polkit agent, pkexec asks in this terminal,
// so nothing live (spinner, taskLog) may be on screen while it runs.
async function fakePkexec(what: string): Promise<boolean> {
  if (rootCached) return true;
  p.log.step(`${what} needs root. pkexec asks for your password.`);
  const pw = await p.password({ message: "[pkexec] Password (anything works, Esc cancels):" });
  if (cancelled(pw)) return false;
  rootCached = true;
  return true;
}

// One item at a time. One failure never stops the rest.
async function runOne(i: Item): Promise<Row> {
  if (i.obs && !(await ensureObsClosed())) return { item: i.name, result: "skipped", detail: "OBS was running" };
  if (i.root && !(await fakePkexec(i.name))) return { item: i.name, result: "skipped", detail: "password prompt cancelled" };
  const log = p.taskLog({ title: i.name, limit: 4 });
  const out: string[] = [];
  for (const step of i.plan) {
    await sleep(120 + Math.random() * 250);
    log.message(step);
    out.push(step);
  }
  if (i.fail) {
    LOGS.set(i.name, [...out, `ERROR ${i.fail}`].join("\n"));
    log.error(`${i.name}: failed`, { showLog: false });
    return { item: i.name, result: "failed", detail: i.fail };
  }
  log.success(`${i.name}: done`);
  if (i.checkFail) {
    LOGS.set(i.name, [...out, `CHECK ${i.checkFail}`].join("\n"));
    return { item: i.name, result: "check failed", detail: i.checkFail };
  }
  if (i.warn) return { item: i.name, result: "warning", detail: i.warn };
  const was = i.applied;
  i.applied = true;
  if (i.kind === "removal") return { item: i.name, result: "removed", detail: "" };
  return { item: i.name, result: was ? "ok" : "changed", detail: was ? "matched the repo" : `${i.plan.length} change(s)` };
}

async function runItems(items: Item[]): Promise<Row[]> {
  const rows: Row[] = [];
  for (const i of items) rows.push(await runOne(i));
  return rows;
}

function newRun() {
  rootCached = false;
  obsSkipped = false;
}

// Report table, then the failed items as a table you can open in less, then back.
async function finish(rows: Row[], title: string) {
  p.note(`${table(rows)}\n\n${summary(rows)}`, title);
  const bad = rows.filter((r) => LOGS.has(r.item));
  if (!bad.length) return;
  const { w1, w2, w3 } = columns(bad);
  for (;;) {
    const pick = await p.select({
      message: `Open a failed item's output?\n  ${C.bold(`${pad("Item", w1)}  ${pad("Result", w2)}  Detail`)}`,
      options: [
        ...bad.map((r) => ({ value: r.item, label: `${pad(r.item, w1)}  ${pad(colour(r.result), w2)}  ${cut(r.detail, w3 - 12)}` })),
        { value: "__done", label: "Done" },
      ],
    });
    if (cancelled(pick) || pick === "__done") return;
    spawnSync("less", ["-R"], { input: `${pick}\n\n${LOGS.get(pick) ?? "(no output)"}\n`, stdio: ["pipe", "inherit", "inherit"] });
  }
}

// Pick -> plan with every change -> confirm -> run -> report.
async function pickAndApply(label: string, pool: Item[]) {
  // A table: padded columns under a header row; search matches the whole row.
  const w1 = Math.max(4, ...pool.map((i) => i.name.length));
  const status = (i: Item) => (i.applied ? C.green("in place") : C.yellow("not applied"));
  const picked = await p.autocompleteMultiselect({
    message: `${label}: pick items (Tab to select, type to search)\n  ${C.bold(`   ${pad("Item", w1)}  ${pad("Kind", 8)}  ${pad("Machine", 7)}  ${pad("Status", 11)}  Changes`)}`,
    options: pool.map((i) => ({
      value: i.name,
      label: `${pad(i.name, w1)}  ${pad(i.kind, 8)}  ${pad(i.machine ?? "both", 7)}  ${pad(status(i), 11)}  ${C.dim(String(i.plan.length))}`,
    })),
  });
  if (cancelled(picked) || !picked.length) return;
  const items = pool.filter((i) => picked.includes(i.name));
  p.note(planText(items), `Plan: ${items.length} items`);
  const ok = await p.confirm({ message: "Apply this plan?" });
  if (cancelled(ok) || !ok) return;
  newRun();
  await finish(await runItems(items), "Status report");
}

// ---------------------------------------------------------------- Wizard Setup

async function wizardSetup() {
  const m = await p.select({ message: "Which machine is this?", options: [{ value: "pc", label: "PC" }, { value: "laptop", label: "Laptop" }], initialValue: machine });
  if (cancelled(m)) return;
  machine = m;
  // Install before removal, so a replacement (a terminal, say) is in place before its old app goes.
  const phases = [
    { name: "Install applications", items: APPS.filter(forMachine) },
    { name: "Clean up Omarchy apps", items: REMOVALS },
    { name: "Configs", items: CONFIGS.filter(forMachine) },
  ];
  newRun();
  const rows: Row[] = [];
  for (const [n, ph] of phases.entries()) {
    p.log.step(C.bold(`Phase ${n + 1}/${phases.length}: ${ph.name}`));
    p.note(planText(ph.items), `Plan: ${ph.name}, ${ph.items.length} items`);
    const d = await p.select({ message: `Run ${ph.name}?`, options: [{ value: "run", label: "Run" }, { value: "skip", label: "Skip this phase" }, { value: "stop", label: "Stop Wizard Setup" }] });
    if (cancelled(d) || d === "stop") {
      rows.push(...phases.slice(n).flatMap((x) => x.items.map((i) => ({ item: i.name, result: "skipped" as const, detail: "setup stopped" }))));
      break;
    }
    if (d === "skip") {
      rows.push(...ph.items.map((i) => ({ item: i.name, result: "skipped" as const, detail: "phase skipped" })));
      continue;
    }
    const r = await runItems(ph.items);
    p.log.message(`${ph.name}: ${summary(r)}`);
    rows.push(...r);
  }
  await finish(rows, `Wizard Setup report (${machine})`);
}

// ---------------------------------------------------------------- menus

const stub = (name: string) => p.log.info(`${name}: its own steps go here (not in the prototype). It uses the same plan -> confirm -> run -> report shape.`);

async function submenu(title: string, actions: string[], run: (a: string) => Promise<void>) {
  for (;;) {
    const a = await p.select({ message: `${title}  ${C.dim(`machine: ${machine}`)}`, options: [...actions.map((x) => ({ value: x, label: x })), { value: "back", label: "Back" }] });
    if (cancelled(a) || a === "back") return;
    await run(a);
  }
}

const applications = () =>
  submenu("Applications", ["Install applications", "Clean up Omarchy apps", "Patch Discord with Vencord", "Recover ZTE USB modem", "Diagnose OBS machine"], async (a) => {
    if (a === "Install applications") return pickAndApply(a, APPS.filter(forMachine));
    if (a === "Clean up Omarchy apps") return pickAndApply(a, REMOVALS);
    stub(a);
  });

const configs = () =>
  submenu(
    "Configs",
    ["Apply configs", "Remove a config", "Wallpapers (add, apply, remove)", "Select Hyprland profile", "Select Voxtype profile", "Brave policy", "Laptop power policy", "Screensaver effects", "Telegram theme", "Shell layout"],
    async (a) => {
      if (a === "Apply configs") return pickAndApply(a, CONFIGS.filter(forMachine));
      stub(a);
    },
  );

p.intro(C.bold("Dotfiles  PROTOTYPE"));
if (process.getuid?.() === 0) {
  p.cancel("Refusing to run as root. Run as your user; steps that need root ask through pkexec.");
  process.exit(1);
}
for (;;) {
  const a = await p.select({
    message: "Dotfiles",
    options: [
      { value: "setup", label: "Wizard Setup", hint: "fresh machine: install, clean up, configs" },
      { value: "apps", label: "Applications" },
      { value: "configs", label: "Configs" },
      { value: "exit", label: "Exit" },
    ],
  });
  if (cancelled(a) || a === "exit") break;
  if (a === "setup") await wizardSetup();
  if (a === "apps") await applications();
  if (a === "configs") await configs();
}
p.outro("Bye");
