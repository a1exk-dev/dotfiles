# Local Issue Tracker

Specs and tickets live under one feature directory: `.scratch/<feature-slug>/`. Keep the entire `.scratch/` tree local and Git-ignored. Repository deliverables belong outside it.

## Publish a spec

Write the feature spec to `.scratch/<feature-slug>/spec.md` with these non-empty sections:

```markdown
# <Title>

## Goal

## Requirements

## Acceptance criteria
- [ ] <observable outcome>
```

A spec has no `Status:` field. Publishing is complete when the file is at the exact path and every requirement is represented by at least one checkable acceptance criterion. When the spec already exists, merge the new requirements and preserve unrelated content.

## Allocate and write a ticket

Tickets live at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`.

Prepare content that passes its applicable gate except for path and number, then perform the single write through this procedure:

1. Create the feature's `issues/` directory when absent, then atomically create `.scratch/<feature-slug>/issues/.allocate.lock` as a directory.
2. When the lock exists, wait five seconds and retry up to twelve times. After the twelfth failure, report the lock and ask the human whether to remove it. On approval, remove it and retry step 1; otherwise stop.
3. While holding the lock, inspect every `<NN>-*.md` filename. Use `01` when none exist; otherwise use the highest number plus one. Preserve at least two digits and never reuse a gap.
4. Build the path from that number and a descriptive slug, then write the prepared content once.
5. While still holding the lock, verify that the chosen number was `01` for an empty directory or the observed maximum plus one, and that exactly one file uses it. Release the lock as the final action.

On failure, remove only the new incomplete ticket when one was written, preserve every pre-existing ticket, and release your lock. Allocation and writing are complete after the locked verification passes and the lock is released; tickets created later do not invalidate that result.

## Publish an accepted ticket

1. Confirm the feature spec exists and the ticket traces to it.
2. Assemble one ticket with this shape:

```markdown
# <Title>

Status: to-do
Spec: ../spec.md
Blocked by: none

## Objective

## Acceptance criteria
- [ ] <observable outcome>

## Verification
Pending

## Comments
```

3. Confirm the spec link resolves, the objective is concrete, the acceptance criteria collectively cover it, each listed blocker names a ticket in the same feature, and all template fields are present.
4. Pass the prepared content to **Allocate and write a ticket**.

Publishing is complete when the content gate and the allocation-and-write procedure both complete. A published `to-do` ticket is accepted and may be claimed by any capable executor once its blockers are `done`.

## Record a non-accepted intake

When a request is not accepted as `to-do`, preserve it with one of two statuses:

- Use `waiting-for-info` when a concrete unanswered question could make the request actionable.
- Use `declined` whenever the maintainer has decided the request will not be actioned, regardless of whether it was otherwise ready.

Assemble the intake with this shape:

```markdown
# <Title>

Status: <waiting-for-info | declined>
Spec: <pending | ../spec.md>
Blocked by: none

## Objective

<What is known about the request.>

## Acceptance criteria
<Pending | known criteria>

## Verification
Pending

## Comments

### <date> - <actor>: <request-info | decline>

<Concrete question and expected source, or decision and rationale.>
```

Confirm the objective preserves the known request, any listed spec link resolves, the status matches the comment operation, and the required question or rationale is explicit. Then pass the prepared content to **Allocate and write a ticket**.

Recording is complete when the content gate and the allocation-and-write procedure both complete. An intake becomes `to-do` only after its applicable accepted-ticket or specialized publication gate passes.

## Locate a ticket

- For a path, read that exact file.
- For `<feature-slug>/<NN>`, match `.scratch/<feature-slug>/issues/<NN>-*.md`.
- For a bare number, search `.scratch/*/issues/<NN>-*.md`.

The lookup is complete only when exactly one file matches. Ask for the feature or path when zero or multiple files match.

## Status workflow

Each ticket has exactly one `Status:` value:

| Status             | Meaning                                           |
| ------------------ | ------------------------------------------------- |
| `waiting-for-info` | A stated question must be answered before work    |
| `to-do`            | Accepted work, claimable when blockers are `done` |
| `in-progress`      | Claimed and actively being worked                 |
| `human-review`     | Complete work awaiting human review               |
| `done`             | Human-approved and complete                       |
| `declined`         | Closed without implementation                     |

Use only these transitions:

| Operation         | From                                     | To                 | Actor                         | Required evidence                                                |
| ----------------- | ---------------------------------------- | ------------------ | ----------------------------- | ---------------------------------------------------------------- |
| Publish accepted  | no ticket                                | `to-do`            | publisher                     | The accepted-ticket publication gate passes                      |
| Request intake info | no ticket                              | `waiting-for-info` | maintainer or triaging agent  | The non-accepted-intake gate records a concrete question         |
| Decline intake    | no ticket                                | `declined`         | maintainer or authorized agent | The non-accepted-intake gate records the decision and rationale  |
| Request info      | `to-do`, `in-progress`, `human-review`   | `waiting-for-info` | claimant, reviewer, maintainer | Comment states the question and expected source                  |
| Record answer     | `waiting-for-info`                       | `to-do`            | maintainer or processing agent | Comment cites the answer; the ticket's applicable publication gate passes |
| Claim             | `to-do` with every blocker `done`        | `in-progress`      | executor                      | Comment identifies the claimant                                  |
| Submit review     | `in-progress`                            | `human-review`     | executor                      | Every criterion is satisfied and checked; applicable verification passes |
| Request changes   | `human-review`                           | `in-progress`      | human reviewer                | Comment names each unmet criterion                               |
| Approve           | `human-review`                           | `done`             | human reviewer                | Comment records approval                                         |
| Decline           | `waiting-for-info`, `to-do`, `in-progress`, `human-review` | `declined` | maintainer or authorized agent | Comment records the decision and rationale                       |

`done` and `declined` are terminal. A different transition requires explicit human direction.

For every transition after publication, update the single `Status:` line and append this entry under `## Comments`:

```markdown
### <date> - <actor>: <operation>

<reason, evidence, or result>
```

A transition of an existing ticket is complete when both edits are present and the transition's required evidence is satisfied. Verification records commands and passing results, or `Not applicable: <reason>` when no executable check exists. Failed applicable checks keep the ticket `in-progress`.

## Dependencies and wayfinding

When locating or reviewing a map or child ticket, adding `Blocked by:`, creating or updating a map or child, selecting a frontier ticket, resolving a child, or completing a wayfinding effort, read `wayfinding.md`.
