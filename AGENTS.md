## Agent skills

- **Tickets:** Before creating, locating, changing, reviewing, blocking, or completing local specs, maps, and tickets, read `docs/agents/issue-tracker.md`.
- **Triage:** When a skill names a canonical triage role, translate it through `docs/agents/triage-labels.md`.
- **Grilling:** Ask one question at a time, provide concrete answer options with a recommended option first, and wait for the human's answer before asking the next question.
- **Tests:** Run focused affected tests for changed scopes. When the complete repository suite is required, give test commands no wall-clock limit, use the execution tool's longest supported timeout, never wrap a test command with `timeout`, rerun only failed or incomplete portions, and collect one final result.
- **Commits:** Present verified changes for human review and wait for an explicit `Commit` decision before committing. When no decision is already present, ask one question with `Commit`, `Request changes`, and `Reject` options; apply requested changes or leave rejected work uncommitted. Before proposing or using a commit message, use `wait-what` and then `humanizer` to review and rewrite it.
- **Omarchy:** Before changing Omarchy-managed or user configuration, use the `omarchy` skill. Route system updates through `omarchy update`; never invoke Pacman directly for repository synchronization or package upgrades. Keep packaged files under `/usr/share/omarchy/` read-only and place customizations in user configuration.
- **Human docs:** When work changes setup, usage, or repository structure, update root `README.md`. Before applying any user-facing documentation change, use `wait-what` and then `humanizer` to review and rewrite the draft, show the revised text to the human, and edit only after approval. Keep README as the purpose and quick start with a complete requirements section, keep shared Stow guidance in `docs/stow.md`, keep global skill setup in `docs/agent-setup.md`, and add package guides under `docs/` only when a package needs more detail.
- **Knowledge:** Before exploring or changing the repo, read `CONTEXT.md` for canonical concepts and `MEMORY.md` for applicable durable guidance.
- **Preservation:** Before defining or editing `AGENTS.md`, `CONTEXT.md`, or `MEMORY.md`, and at task completion, follow `docs/agents/domain.md`.

## System design

- Let evidence-led KISS govern system design. Choose the simplest design that meets current requirements.
- Consider SOLID for every system design decision, and prefer composition over inheritance.
- Design functionality and tests around standard usage and feasible failures reachable through production inputs, dependencies, or execution paths. Failures possible only through test-only construction are outside scope.
