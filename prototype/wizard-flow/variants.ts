// PROTOTYPE - throwaway. Answers issue #7 "Prototype the wizard flow and status report".
// Nothing here touches the machine: the engine is a stub with fake delays, fake failures,
// a fake OBS-running check, and a fake pkexec password prompt.
//
// Run:  bun variants.ts              (variant A)
//       bun variants.ts --variant=B     (A, B, or C; the variant is also switchable from the menu)
//       FAIL=none bun variants.ts      (no simulated failures)
import * as p from "@clack/prompts";
import { spawnSync } from "node:child_process";

// ---------------------------------------------------------------- fake world

type Kind = "stowed" | "copied" | "app" | "system";
type Mod = {
  id: string;
  name: string;
  kind: Kind;
  machine?: "pc" | "laptop"; // undefined = both
  root?: boolean; // needs pkexec
  obs?: boolean; // blocked while OBS runs
  plan: string[];
  state: "in sync" | "drift" | "missing";
  fail?: string; // simulated failure detail
  checkFail?: string; // simulated failed file check
  warn?: string; // simulated version mismatch
};

const MACHINE: "pc" | "laptop" = "pc";
const FAILS = process.env.FAIL !== "none";

const MODS: Mod[] = [
  { id: "bash", name: "bash", kind: "stowed", plan: ["link ~/.bashrc", "link ~/.inputrc"], state: "in sync" },
  { id: "btop", name: "btop", kind: "stowed", plan: ["link ~/.config/btop/btop.conf"], state: "in sync" },
  { id: "claude", name: "Claude settings", kind: "copied", plan: ["back up and overwrite ~/.claude/settings.json", "link ~/.claude/CLAUDE.md"], state: "drift" },
  { id: "discord", name: "Discord settings", kind: "copied", plan: ["back up and overwrite ~/.config/discord/settings.json"], state: "drift" },
  { id: "discord-system24", name: "Discord system24", kind: "stowed", plan: ["link system24 theme", "run theme hook"], state: "missing", fail: FAILS ? "theme hook exited 1: vencord themes folder not found (~/.config/Vencord/themes)" : undefined },
  { id: "ghostty", name: "ghostty", kind: "stowed", plan: ["link ~/.config/ghostty/config"], state: "in sync" },
  { id: "hyprland", name: "hyprland", kind: "stowed", plan: ["link 6 files under ~/.config/hypr", "link machine profiles under ~/.config/dotfiles/hypr"], state: "drift" },
  { id: "obs-set", name: "OBS machine set (pc)", kind: "copied", machine: "pc", obs: true, plan: ["back up and overwrite 2 profiles", "back up and overwrite scene collection", "back up and overwrite geometry.json", "prune 1 stale file (receipt)"], state: "drift" },
  { id: "obs-theme", name: "OBS theme", kind: "stowed", obs: true, plan: ["set 3 keys in OBS user.ini"], state: "in sync" },
  { id: "opencode", name: "opencode", kind: "stowed", plan: ["link ~/.config/opencode/opencode.json"], state: "in sync" },
  { id: "screensaver", name: "Screensaver effects", kind: "stowed", plan: ["link effect allowlist", "enable plugin"], state: "drift", checkFail: FAILS ? "~/.config/omarchy/screensaver.json differs from repo after write" : undefined },
  { id: "starship", name: "starship", kind: "stowed", plan: ["link ~/.config/starship.toml"], state: "in sync" },
  { id: "tmux", name: "tmux", kind: "stowed", plan: ["link ~/.config/tmux/tmux.conf"], state: "missing" },
  { id: "voxtype", name: "voxtype", kind: "stowed", plan: ["link ~/.config/voxtype/config.toml"], state: "in sync", warn: "voxtype 0.4.1 installed, manifest wants >= 0.5.0" },
  { id: "brave", name: "Shared Brave policy", kind: "system", root: true, plan: ["back up and overwrite /etc/brave/policies/managed/dotfiles.json"], state: "drift" },
  { id: "power", name: "Laptop power policy", kind: "system", machine: "laptop", root: true, plan: ["write UPower and logind drop-ins"], state: "missing" },
  { id: "llama", name: "llama.cpp + models", kind: "app", machine: "pc", plan: ["install llama.cpp-vulkan via Omarchy", "download 2 models"], state: "missing" },
  { id: "bruno", name: "Bruno", kind: "app", plan: ["install bruno-bin (AUR) via Omarchy"], state: "missing", fail: FAILS ? "omarchy pkg add bruno-bin: AUR build failed (pgp key 0xDEADBEEF unknown)" : undefined },
];
const forMachine = (m: Mod) => !m.machine || m.machine === MACHINE;
const LOGS = new Map<string, string>(); // item -> full output, in memory only
let obsRunning = true; // fake: OBS is open at first
let rootCached = false; // fake: pkexec asks once per run
let obsSkipped = false; // a skip covers every OBS write in this run

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const C = { dim: (s: string) => `\x1b[2m${s}\x1b[22m`, red: (s: string) => `\x1b[31m${s}\x1b[39m`, green: (s: string) => `\x1b[32m${s}\x1b[39m`, yellow: (s: string) => `\x1b[33m${s}\x1b[39m`, bold: (s: string) => `\x1b[1m${s}\x1b[22m` };
const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "");
const cancelled = (v: unknown): v is symbol => p.isCancel(v);

// ---------------------------------------------------------------- shared helpers

type Result = { item: string; result: "ok" | "changed" | "skipped" | "failed" | "check failed" | "warning"; detail: string };

function table(rows: Result[]): string {
  const colour = (r: Result["result"]) =>
    r === "failed" || r === "check failed" ? C.red(r) : r === "skipped" || r === "warning" ? C.yellow(r) : C.green(r);
  const width = Math.min(process.stdout.columns ?? 80, 100) - 8;
  const w1 = Math.max(4, ...rows.map((r) => r.item.length));
  const w2 = 12;
  const w3 = Math.max(10, width - w1 - w2 - 4);
  const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1) + "…" : s);
  const line = (a: string, b: string, c: string) => `${a.padEnd(w1)}  ${b}${" ".repeat(Math.max(0, w2 - strip(b).length))}  ${cut(c, w3)}`;
  return [C.bold(line("Item", "Result", "Detail")), ...rows.map((r) => line(r.item, colour(r.result), r.detail))].join("\n");
}

function summary(rows: Result[]): string {
  const n = (k: Result["result"]) => rows.filter((r) => r.result === k).length;
  const parts = [`${n("changed")} changed`, `${n("ok")} already in sync`];
  if (n("skipped")) parts.push(C.yellow(`${n("skipped")} skipped`));
  if (n("warning")) parts.push(C.yellow(`${n("warning")} warning`));
  const bad = n("failed") + n("check failed");
  if (bad) parts.push(C.red(`${bad} failed`));
  return parts.join(", ");
}

function planText(mods: Mod[], full: boolean): string {
  return mods
    .map((m) => {
      const tag = [m.root ? C.yellow("needs password") : "", m.obs ? C.yellow("OBS must be closed") : ""].filter(Boolean).join(", ");
      const head = `${C.bold(m.name)} ${C.dim(`(${m.kind})`)}${tag ? "  " + tag : ""}`;
      return full ? [head, ...m.plan.map((x) => `  - ${x}`)].join("\n") : `${head}  ${C.dim(`${m.plan.length} change${m.plan.length > 1 ? "s" : ""}`)}`;
    })
    .join("\n");
}

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

// Runs one item with per-item isolation. One failure never stops the rest.
async function runOne(m: Mod): Promise<Result> {
  if (m.obs && !(await ensureObsClosed())) return { item: m.name, result: "skipped", detail: "OBS was running" };
  if (m.root && !(await fakePkexec(m.name))) return { item: m.name, result: "skipped", detail: "password prompt cancelled" };
  const log = p.taskLog({ title: m.name, limit: 4 });
  const out: string[] = [];
  for (const step of m.plan) {
    await sleep(120 + Math.random() * 250);
    log.message(step);
    out.push(step);
  }
  if (m.fail) {
    out.push(`ERROR ${m.fail}`);
    LOGS.set(m.name, out.join("\n"));
    log.error(`${m.name}: failed`, { showLog: false });
    return { item: m.name, result: "failed", detail: m.fail };
  }
  log.success(`${m.name}: done`);
  if (m.checkFail) {
    LOGS.set(m.name, [...out, `CHECK ${m.checkFail}`].join("\n"));
    return { item: m.name, result: "check failed", detail: m.checkFail };
  }
  if (m.warn) return { item: m.name, result: "warning", detail: m.warn };
  const res: Result = { item: m.name, result: m.state === "in sync" ? "ok" : "changed", detail: m.state === "in sync" ? "nothing to change" : `${m.plan.length} change(s)` };
  m.state = "in sync";
  return res;
}

async function runAll(mods: Mod[]): Promise<Result[]> {
  rootCached = false;
  obsSkipped = false;
  const rows: Result[] = [];
  for (const m of mods) rows.push(await runOne(m));
  return rows;
}

function report(rows: Result[], title = "Status report") {
  p.note(`${table(rows)}\n\n${summary(rows)}`, title);
}

function pager(item: string) {
  spawnSync("less", ["-R"], { input: `${item}\n\n${LOGS.get(item) ?? "(no output)"}\n`, stdio: ["pipe", "inherit", "inherit"] });
}

async function viewFailures(rows: Result[]) {
  const bad = rows.filter((r) => LOGS.has(r.item));
  while (bad.length) {
    const pick = await p.select({ message: "Open a failed item's output?", options: [...bad.map((r) => ({ value: r.item, label: r.item, hint: r.result })), { value: "__done", label: "Done" }] });
    if (cancelled(pick) || pick === "__done") return;
    pager(pick);
  }
}

const OTHER_ACTIONS = [
  "Remove a config",
  "Clean up Omarchy apps",
  "Manage wallpapers",
  "Apply wallpapers",
  "Manage Brave policy",
  "Manage Telegram theme",
  "Manage screensaver effects",
  "Manage laptop power policy",
  "Patch Discord with Vencord",
  "Diagnose OBS machine",
  "Select Voxtype profile",
  "Select Hyprland profile",
  "Apply Shell layout",
  "Recover ZTE USB modem",
];
async function stubAction(name: string) {
  p.log.info(`${name}: its own wizard goes here (not prototyped). It follows the same preview -> confirm -> run -> report shape.`);
}

// ---------------------------------------------------------------- variant A: flat search, one plan, one report

async function variantA() {
  for (;;) {
    const choice = await p.autocomplete({
      message: `Dotfiles  ${C.dim(`machine: ${MACHINE}`)}  Type to search`,
      options: [
        { value: "guided", label: "Guided setup", hint: "everything for this machine" },
        { value: "configs", label: "Apply configs" },
        { value: "apps", label: "Install optional apps" },
        ...OTHER_ACTIONS.map((a) => ({ value: a, label: a })),
        { value: "variant", label: "(prototype) switch variant" },
        { value: "exit", label: "Exit" },
      ],
      maxItems: 12,
    });
    if (cancelled(choice) || choice === "exit") return;
    if (choice === "variant") return switchVariant();
    if (choice === "guided" || choice === "configs" || choice === "apps") {
      const pool = MODS.filter(forMachine).filter((m) => (choice === "apps" ? m.kind === "app" : choice === "configs" ? m.kind !== "app" : true));
      const picked = await p.autocompleteMultiselect({
        message: "What to apply? (Tab to select, type to search)",
        options: pool.map((m) => ({ value: m.id, label: m.name, hint: `${m.kind}, ${m.state}` })),
        initialValues: choice === "guided" ? pool.map((m) => m.id) : [],
      });
      if (cancelled(picked) || !picked.length) continue;
      const mods = pool.filter((m) => picked.includes(m.id));
      p.note(planText(mods, true), `Plan: ${mods.length} items`);
      const ok = await p.confirm({ message: "Apply this plan?" });
      if (cancelled(ok) || !ok) continue;
      const rows = await runAll(mods);
      report(rows);
      await viewFailures(rows);
    } else await stubAction(choice);
    // after an action: straight back to the menu
  }
}

// ---------------------------------------------------------------- variant B: grouped menu, phase by phase

const PHASES: { name: string; pick: (m: Mod) => boolean }[] = [
  { name: "Clean up Omarchy apps", pick: () => false },
  { name: "Optional apps", pick: (m) => m.kind === "app" },
  { name: "Configs", pick: (m) => m.kind === "stowed" || m.kind === "copied" },
  { name: "Wallpapers", pick: () => false },
  { name: "System policies", pick: (m) => m.kind === "system" },
];

async function variantB() {
  const groups: Record<string, string[]> = {
    Setup: ["Guided setup", "Status"],
    "Apps and configs": ["Apply configs", "Install optional apps", "Remove a config", "Clean up Omarchy apps"],
    Look: ["Manage wallpapers", "Apply wallpapers", "Manage Telegram theme", "Manage screensaver effects", "Apply Shell layout"],
    Machine: ["Select Hyprland profile", "Select Voxtype profile", "Manage laptop power policy", "Manage Brave policy"],
    "Apps with extras": ["Patch Discord with Vencord", "Diagnose OBS machine", "Recover ZTE USB modem"],
  };
  for (;;) {
    const g = await p.select({
      message: `Dotfiles  ${C.dim(`machine: ${MACHINE}`)}`,
      options: [...Object.keys(groups).map((k) => ({ value: k, label: k, hint: groups[k].length + " actions" })), { value: "variant", label: "(prototype) switch variant" }, { value: "exit", label: "Exit" }],
    });
    if (cancelled(g) || g === "exit") return;
    if (g === "variant") return switchVariant();
    const a = await p.select({ message: g, options: [...groups[g].map((x) => ({ value: x, label: x })), { value: "back", label: "Back" }] });
    if (cancelled(a) || a === "back") continue;

    let rows: Result[] = [];
    if (a === "Guided setup") {
      for (const [i, ph] of PHASES.entries()) {
        const mods = MODS.filter(forMachine).filter(ph.pick);
        p.log.step(C.bold(`Phase ${i + 1}/${PHASES.length}: ${ph.name}`));
        if (!mods.length) {
          p.log.info("Nothing to do in the prototype for this phase.");
          continue;
        }
        p.note(planText(mods, true), `Plan for ${ph.name}`);
        const d = await p.select({ message: `Run ${ph.name}?`, options: [{ value: "run", label: "Run" }, { value: "skip", label: "Skip this phase" }, { value: "stop", label: "Stop guided setup" }] });
        if (cancelled(d) || d === "stop") break;
        if (d === "skip") {
          rows.push(...mods.map((m) => ({ item: m.name, result: "skipped" as const, detail: "phase skipped" })));
          continue;
        }
        const r = await runAll(mods);
        p.log.message(summary(r));
        rows.push(...r);
      }
    } else if (a === "Status") {
      p.note(statusTable(), "Status");
      continue;
    } else if (a === "Apply configs" || a === "Install optional apps") {
      const pool = MODS.filter(forMachine).filter((m) => (a === "Install optional apps" ? m.kind === "app" : m.kind !== "app"));
      const picked = await p.multiselect({ message: "What to apply? (Space to select)", options: pool.map((m) => ({ value: m.id, label: m.name, hint: m.state })), required: false });
      if (cancelled(picked) || !picked.length) continue;
      const mods = pool.filter((m) => picked.includes(m.id));
      p.note(planText(mods, true), "Plan");
      const ok = await p.confirm({ message: "Apply this plan?" });
      if (cancelled(ok) || !ok) continue;
      rows = await runAll(mods);
    } else {
      await stubAction(a);
      continue;
    }
    if (!rows.length) continue;
    report(rows, "Run finished");
    // after an action: explicit choice
    for (;;) {
      const next = await p.select({
        message: "What next?",
        options: [
          { value: "menu", label: "Back to menu" },
          ...(rows.some((r) => LOGS.has(r.item)) ? [{ value: "logs", label: "Open failed output" }] : []),
          { value: "retry", label: "Retry failed items", hint: "same as a rerun, only the failures" },
          { value: "exit", label: "Exit" },
        ],
      });
      if (cancelled(next) || next === "menu") break;
      if (next === "exit") return;
      if (next === "logs") await viewFailures(rows);
      if (next === "retry") {
        const again = MODS.filter((m) => rows.some((r) => r.item === m.name && r.result !== "ok" && r.result !== "changed"));
        rows = await runAll(again);
        report(rows, "Retry finished");
      }
    }
  }
}

// ---------------------------------------------------------------- variant C: status first

function statusTable(): string {
  const rows: Result[] = MODS.map((m) => ({
    item: m.name,
    result: !forMachine(m) ? "skipped" : m.state === "in sync" ? "ok" : "changed",
    detail: !forMachine(m) ? `${m.machine} only` : m.state === "in sync" ? "in sync" : m.state === "drift" ? "differs from repo" : "not applied",
  }));
  return table(rows).replace(/\bchanged\b/g, "needs apply").replace(/\bskipped\b/g, "n/a    ").replace(/\bok\b/g, "ok");
}

async function variantC() {
  for (;;) {
    p.note(statusTable(), `Dotfiles status  machine: ${MACHINE}`);
    const pool = MODS.filter(forMachine);
    const due = pool.filter((m) => m.state !== "in sync");
    const choice = await p.autocompleteMultiselect({
      message: due.length ? `${due.length} items need apply (preselected). Tab to change, Enter to continue.` : "Everything is in sync. Tab to pick items to reapply.",
      options: [
        ...pool.map((m) => ({ value: m.id, label: m.name, hint: m.state })),
        ...OTHER_ACTIONS.map((a) => ({ value: "action:" + a, label: "Action: " + a })),
        { value: "action:variant", label: "Action: (prototype) switch variant" },
        { value: "action:exit", label: "Action: Exit" },
      ],
      initialValues: due.map((m) => m.id),
    });
    if (cancelled(choice)) return;
    const action = choice.find((v) => v.startsWith("action:"));
    if (action === "action:exit") return;
    if (action === "action:variant") return switchVariant();
    if (action) {
      await stubAction(action.slice(7));
      continue;
    }
    const mods = pool.filter((m) => choice.includes(m.id));
    if (!mods.length) return;
    let full = false;
    for (;;) {
      p.note(planText(mods, full), `Plan: ${mods.length} items, ${mods.reduce((n, m) => n + m.plan.length, 0)} changes`);
      const d = await p.select({ message: "Apply?", options: [{ value: "go", label: "Apply" }, { value: "toggle", label: full ? "Hide details" : "Show every change" }, { value: "back", label: "Back" }] });
      if (cancelled(d) || d === "back") break;
      if (d === "toggle") {
        full = !full;
        continue;
      }
      const rows = await runAll(mods);
      report(rows);
      await viewFailures(rows);
      break;
    }
    // after an action: back to a refreshed status screen
  }
}

// ---------------------------------------------------------------- entry

let variant = (process.argv.find((a) => a.startsWith("--variant="))?.split("=")[1] ?? "A").toUpperCase();
async function switchVariant() {
  const v = await p.select({ message: "Prototype variant", options: [{ value: "A", label: "A: flat search, one plan, one report" }, { value: "B", label: "B: grouped menu, phase by phase" }, { value: "C", label: "C: status screen first" }] });
  if (!cancelled(v)) variant = v;
  next = true;
}
let next = true;
while (next) {
  next = false;
  p.intro(C.bold(`Dotfiles  PROTOTYPE variant ${variant}`));
  if (process.getuid?.() === 0) {
    p.cancel("Refusing to run as root. Run as your user; steps that need root ask through pkexec.");
    process.exit(1);
  }
  if (variant === "B") await variantB();
  else if (variant === "C") await variantC();
  else await variantA();
}
p.outro("Bye");
