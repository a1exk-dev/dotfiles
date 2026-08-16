# Triage Status Mapping

Use this mapping when an engineering skill names a canonical triage role. `issue-tracker.md` remains the sole authority for status transitions and their required evidence.

| Canonical role      | Persisted result   | Translation                                                        |
| ------------------- | ------------------ | ------------------------------------------------------------------ |
| `needs-triage`      | evaluate now       | Persist `waiting-for-info`, `declined`, or `to-do` in the same operation |
| `needs-info`        | `waiting-for-info` | Record the unanswered question and expected source                 |
| `ready-for-agent`   | `to-do`            | Ensure the accepted-ticket gate passes and record the role          |
| `ready-for-human`   | `to-do`            | Ensure the accepted-ticket gate passes and record the role          |
| `wontfix`           | `declined`         | Record the maintainer's decision and rationale                     |

This tracker persists workflow status only. It has no untriaged status or executor-routing field. `issue-tracker.md` defines the meaning and claim eligibility of `to-do`; comments retain triage rationale without adding another state field.

Translate `needs-triage` in the same operation. For a new request, publish an accepted `to-do` ticket, record a `waiting-for-info` intake, or record a `declined` intake through `issue-tracker.md`. For an existing ticket, use its corresponding transition. Append a comment naming the canonical role and rationale. Translation is complete when the resulting status is valid under `issue-tracker.md` and that comment exists.
