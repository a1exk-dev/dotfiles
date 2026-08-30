# Agent guide

This file defines the delivery workflow and where to make documentation and configuration changes in this repository.

## Delivery workflow

### Subagent delegation

Rely on subagents for every separable unit of work. Give each subagent a non-overlapping scope, an explicit deliverable, and a verification target, then launch independent scopes in parallel. Each delegated unit has one owner; lead agents retain cross-cutting decisions and integrate the returned results.

Use at most this many workers concurrently:

- 3 coding subagents, coordinated by Terra at `xhigh` effort, for independent implementation slices
- 1 reviewer: Sol Max owns code and architecture review
- 1 tester, coordinated by Terra at `xhigh` effort, for independent verification
- 5 Terra agents for fast discovery, search, and mechanical changes

Choose the number of subagents from the number of genuinely independent scopes; one indivisible scope uses one agent.

### Terra fast path

Use Terra, the smallest agent, for mechanical tasks where the requested transformation is exact, the scope is known, and verification is direct. Examples include literal search-and-replace, typo fixes, formatting-only edits, and changing a known value. The fast path is complete when Terra makes the exact requested change and focused verification passes.

### Architected changes

Use this sequence when a code or configuration task requires design judgment, behavioral decisions, broader testing, or architectural review:

1. **Sol Max architects.** Inspect the relevant code and write an implementation brief covering the goal, constraints, affected areas, design decisions, risks, acceptance criteria, and verification commands. Hand the brief to Terra at `xhigh` effort when the architectural decisions are explicit and any remaining implementation choices are clearly delegated.
2. **Terra implements and tests at `xhigh` effort.** Own the primary code changes, add or update tests, and run the relevant verification commands. Return the changed-file summary, test results, and any unresolved decisions to Sol Max.
3. **Sol Max reviews.** Review the resulting diff independently for correctness, architectural fit, regressions, security, maintainability, and missing tests. Report findings by severity with file and line references. Send required fixes back to Terra at `xhigh` effort, then repeat implementation and review until no blocking findings remain.

The task is complete when Terra's `xhigh` verification passes and Sol Max approves both the implementation and architecture.

## Docs location

- All user-facing docs live in `_docs/`.
- Do not create new docs in module folders (for example, `zsh/`).
- Keep one doc per tool/topic in `_docs/`.
- If you need to add docs for a module, update the existing file in `_docs/`.
- Keep a root `ReadMe.md` with a table of contents linking to all `_docs/*.md` files.

## Zsh changes

- Config file: `zsh/.zshrc`
- Docs file: `_docs/03-zsh.md`
- Stow command (repo root): `stow --adopt -t "$HOME" zsh`

## Other modules

- Add module docs to `_docs/` using the next available number.
- Keep docs short, focused, and distro-agnostic when possible.
