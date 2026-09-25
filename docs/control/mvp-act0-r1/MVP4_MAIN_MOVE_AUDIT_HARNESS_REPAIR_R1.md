# MVP4 main-move audit harness repair R1

## Purpose

Unblock the existing V0 MVP parent after MVP3 leaf closure when canonical `main` advances while the parent Work Order is already `IN_PROGRESS`.

This is a bounded Harness/control repair only. It must not modify runtime/product files, event 0011, frozen MVP3 evidence, or acceptance semantics.

## Exact current subjects

- frozen MVP3 product HEAD: `f1d453fb2af49231c30bdc5cbe415ad199394446`
- frozen MVP3 product TREE: `f1697cc52c1abc7f1bb21922c5fab3b49a3c167d`
- MVP3 closure workflow repair HEAD: `02bd1d464320513fd2e5e95506cf1d227eb4396d`
- authoritative MVP3 event add commit: `3fa11a6314715654525bcff59dbfa11a3fdfa148`
- previously audited main: `7dfc68ab5a1e90254a1b7039807f275b5da04eef`
- current canonical main to audit: `9e10e640ffc53f82195f1fd930ebafbbc85e482f`

## Defect

`transition-table.v1.json` explicitly allows `RECOVERY_RESUMED` self-transition `IN_PROGRESS -> IN_PROGRESS`, but `scripts/harness/state_builder.py::_select_epoch_audit()` recognizes the MVP recovery audit form only when `work_state == DISPATCHED` and requires `audit.main_sha == event.head_sha`.

That was valid before implementation. It deadlocks a progressed parent: after MVP1/MVP2/MVP3 the parent must stay `IN_PROGRESS`; canonical main may advance independently and is not necessarily an ancestor of the stacked product/control branch, while every event `head_sha` must remain an ancestor of the current carrier.

## Required bounded repair

Preserve the existing pre-implementation recovery form unchanged.

Add a second strict post-progress recovery form accepted only when all are true:

- `event_type == RECOVERY_RESUMED`
- `work_state == IN_PROGRESS`
- `actor == INTEGRATOR`
- `command == MVP_ACT0_POST_MERGE_EPOCH_AUDIT`
- integer `exit_code == 0`
- exact project epoch identity
- referenced evidence is a committed `distributed_world_simulator.harness_epoch_audit.v1`
- audit epoch/work-order/base identity matches the event/current epoch
- event `head_sha` remains ordinary event provenance (an implementation/control ancestor)
- audit `main_sha` is NOT required to equal event `head_sha` for this post-progress form; current-main matching remains enforced by `epoch_validator.validate_epoch()` before continuation is granted
- no parent state regression and no predicate completion is implied by the recovery event

The legacy `DISPATCHED` form must continue to require `audit.main_sha == event.head_sha`.

## Tests required

Extend `tests/harness/test_v0_mvp_epoch_resume.py` with real Git fixtures proving at minimum:

1. after a valid initial audit and legitimate `IN_PROGRESS` progress, moving `origin/main` invalidates the retained audit;
2. a committed post-progress `RECOVERY_RESUMED / IN_PROGRESS` event with a new exact audit for that current main restores `MAIN_MOVED_AUDIT_CONTINUE` while preserving parent `IN_PROGRESS` and prior completed predicates/state;
3. wrong actor, wrong command, wrong audit identity, RED PC0/directional status, uncommitted/dirty audit, or audit for a non-current main cannot resume;
4. the legacy pre-implementation `DISPATCHED` recovery tests remain green;
5. full Harness regression remains green.

## Scope

Expected code/test scope only:

- `scripts/harness/state_builder.py`
- `tests/harness/test_v0_mvp_epoch_resume.py`
- this instruction document

No runtime, Godot, network, Matter, P7/SM1, product event, acceptance, or main merge changes.
