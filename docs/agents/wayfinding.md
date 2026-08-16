# Local Wayfinding

Use this workflow for `/wayfinder`, ticket dependencies, and frontier selection. The publication, lookup, status, evidence, and review rules in `issue-tracker.md` still apply.

## Artifacts

The map lives at `.scratch/<effort>/map.md` with these sections:

```markdown
# <Effort>

## Notes

## Decisions-so-far

## Fog
```

The map supplements `spec.md`; it never replaces it. Research, prototype, and grilling work may begin with only a map, but create `spec.md` before publishing the first `task` child.

Child tickets use `.scratch/<effort>/issues/<NN>-<slug>.md` and the allocation procedure in `issue-tracker.md`. Add `Type:` and one traceability field beside the standard ticket metadata:

```markdown
Type: <research | prototype | grilling>
Map: ../map.md

# or

Type: task
Spec: ../spec.md
```

A map is published when its path and title are correct, all three sections exist, and `## Fog` contains at least one unresolved question or the word `None`. Every child must satisfy the standard gate for unique path, objective, acceptance criteria, blockers, verification, and comments. `research`, `prototype`, and `grilling` children replace the spec requirement with a resolving `Map:` link; `task` children must pass the full accepted-ticket gate with a resolving `Spec:` link. Publication is complete when exactly one allowed `Type:` and its required traceability field are present.

For a non-accepted child intake, use the core intake template with `Type:` and the same traceability rule: `research`, `prototype`, and `grilling` use a resolving `Map:` link instead of `Spec:`, while `task` uses `Spec: pending` or a resolving spec link. For a map-linked child's `waiting-for-info` to `to-do` transition, this child-publication gate is the applicable gate named by `issue-tracker.md`; the core spec requirement does not apply.

## Dependencies

`Blocked by:` is either `none` or a comma-separated list of child numbers from the same effort.

Before adding an edge, follow the proposed blocker's dependencies transitively. Add the edge only when that walk cannot return to the child; a return is a cycle and requires a different dependency plan.

A child is unblocked when every listed blocker is `done`. Resolve a `declined` blocker in one of three ways:

1. Remove it because the dependency is no longer required, recording the reason in `## Comments`.
2. Replace it with a viable blocker, recording the replacement in `## Comments`.
3. Set the dependent child to `declined`, recording why the dependency made the work nonviable.

Reconsideration is complete when the dependent child is `declined`, or every listed blocker exists, is not `declined`, and participates in an acyclic dependency graph. The child returns to the frontier after all remaining blockers become `done`.

## Frontier

1. List every child in numeric order.
2. Keep only `to-do` children whose blockers are all `done`.
3. Select the first remaining child and claim it through the transition in `issue-tracker.md`.

If no child remains, stop before claiming. When unfinished children exist, report each one with its excluding status or blocker. For a cycle, report the exact cycle and ask the human which edge to remove; resume selection only after that edge is removed.

When all children are terminal but the effort-completion gate still fails, perform the missing map bookkeeping, resolve or explicitly defer each remaining Fog item, and create `spec.md` when any child has `Type: task`. Ask the human for the unresolved decision when one of those operations cannot be completed from recorded information, then re-run the completion gate.

## Resolve a child

Append the result under `## Answer`, satisfy every acceptance criterion, and use the standard submit-review transition. After human approval moves the child to `done`, append a pointer to its answer under the map's `## Decisions-so-far` section.

## Complete the effort

The effort is complete when every child is `done` or `declined`, every `done` answer is linked from `## Decisions-so-far`, every declined child is accounted for there, and each `## Fog` item is resolved or explicitly deferred with a reason. When any child has `Type: task`, `spec.md` must also pass the spec publication gate.
