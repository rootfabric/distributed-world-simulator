# H0 restart-safe control scaffold

`CONTROL_DEVELOPMENT.ps1` is the only public entry point. It supports exactly one of `-Status`, `-Plan`, or `-Resume`; `-Execute` is deliberately rejected.

Append-only execution events remain authoritative. Main movement blocks continuation unless a recorded audit permits it; an invalidated epoch always requires refresh.

## Continuation output

`Status`, `Plan` and `Resume` expose a machine-derived `next` transition:

```text
mission_id
mission_complete
handoff_class
next_actor
next_action
evidence_sink
resume_condition
on_success
on_failure
human_decision_required
```

A missing/stale independent review is `ROLE_BOUNDARY -> REVIEWER`, not a terminal human stop. A review result existing only in chat is non-authoritative. The transition completes only after the verdict is persisted to the declared durable sink and binds the exact reviewed head.

`-Resume` also reports the parent mission and the same continuation fields so a fresh session does not need chat history to discover what happens next.

## Hygiene

`python scripts/harness/instruction_hygiene.py --root .` audits root router budgets, mutable prose state and rule lifecycle. Protected safety/security/control/architecture invariants cannot be auto-retired.

No command installs dependencies or creates runtime branches. Install the pinned dependency from `scripts/harness/requirements.txt`, then run:

```text
python -m unittest discover -s tests/harness -v
python scripts/harness/instruction_hygiene.py --root .
```
