# System design

- Treat evidence-led KISS and YAGNI as equal primary system design heuristics. Choose the simplest path to the required result, and implement only what current requirements need.
- Consider SOLID for every system design decision, and prefer composition over inheritance.
- Design functionality and tests around standard usage and feasible failures reachable through production inputs, dependencies, or execution paths. Failures possible only through test-only construction are outside scope.

# Questions

1. Before presenting a question or answer, process it with `wait-what`, then `humanizer`.
2. Ask one question at a time through the question tool. Provide concrete answer options, with the recommended option first. This sequence replaces any skill's batched-round format.
3. Wait for the human response before asking the next question.

# Writing

- Classify documentation by its primary audience.
- Human-facing documentation: Process its content with `wait-what`, then `humanizer`, show the revised text to the human, and edit only after approval. When work changes setup, usage, or repository structure, update root `README.md`. Keep README as the purpose and quick start with a complete requirements section, keep shared Stow guidance in `docs/stow.md`, keep global skill setup in `docs/agent-setup.md`, and add package guides under `docs/` only when a package needs more detail.
- Agent-facing documentation: Use `writing-for-agents` for agent docs, instructions, and skills. Apply the question-and-answer sequence only to the surrounding human communication.

# Knowledge

- Before exploring or changing the repo, read `CONTEXT.md` for canonical concepts and `MEMORY.md` for applicable durable guidance.
- Before defining or editing `AGENTS.md`, `CONTEXT.md`, or `MEMORY.md`, and at task completion, follow [`docs/agents/domain.md`](docs/agents/domain.md).

# Workflow

- Commits: Before creating a commit or proposing or using a commit message, read and follow [`docs/agents/commit-policy.md`](docs/agents/commit-policy.md).
- Tests: Run focused affected tests for changed scopes. When the complete repository suite is required, give test commands no wall-clock limit, use the execution tool's longest supported timeout, never wrap a test command with `timeout`, rerun only failed or incomplete portions, and collect one final result.
- Omarchy: Before changing Omarchy-managed or user configuration, use the `omarchy` skill. Route system updates through `omarchy update`; never invoke Pacman directly for repository synchronization or package upgrades. Keep packaged files under `/usr/share/omarchy/` read-only and place customizations in user configuration.

# Agent skills

## Issue tracker

Before creating, locating, changing, reviewing, blocking, or completing GitHub issues, maps, and tickets, read `docs/agents/issue-tracker.md`.

## Triage labels

When a skill names a canonical triage role, translate it through `docs/agents/triage-labels.md`.
