# FABRIC R5.6.2 R1.2 — независимый falsifier / GENESIS MAX_EVENTS

**Reviewed PRODUCT_HEAD:** `c9966b4f51dd623ddc6ec335b67452ccf96f7090`, TREE `5a8db3a3ba25f1ecd86636b8461af7e8bf68cce3`.
**Falsifier branch:** `review/fabric-r562-r12-genesis-event-budget-falsifier-r1`, commit `df2fe5488bbba3ddc2e0050bea0eb980209cf49d` (test-only; no product modifications).
**Risk:** HIGH (recoverability), **REVIEW FINDING: FAIL**, merge forbidden until repair and fresh exact.

## New adversarial scenario (not in existing 616 assertions)

Genuine Construction Store with 4 sorted parts, 3 bonds, valid Matter and compatible Authority.
Canonical sorted 17 initial event IDs `event/review-r562/00` ... `/16`.
Call `Life.bootstrap(... initial_events=17)` on exact product HEAD and then
`Life.new().recover(..., bootstrap.details.journal)` without changing owner or input.

Expected: `bootstrap` must refuse with `R562_EVENT_BUDGET_EXCEEDED` because
`MAX_EVENTS = 16`; success and accepted journal must never be unrecoverable.

Observed local exact canonical Godot double `4.7.1.stable.double.custom_build.a13da4feb`,
SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`:
```text
REVIEW_OVERSIZE_BOOTSTRAP=ACCEPTED, COLD_RECOVERY=false, RECOVERY_CODE=R562_EVENT_BUDGET_EXCEEDED
REVIEW_FAIL=bootstrap returns READY but own journal fails recovery
REVIEW_FALSIFIER_RESULT={"checks":4,"failures":["bootstrap returns READY but own journal fails recovery"],"schema":"fabric.r562.review.initial_event_budget.v1"}
```
Boundary 16-event bootstrap + recover both PASS.

**Cause:** `bootstrap` checks initial parts and binding, but skips MAX_EVENTS;
`_replay` at cold recovery checks `events.size()+committed+pending > MAX_EVENTS`,
so exact same genesis is accepted then rejected on restart.

## Scope and remedy

Narrow repair in `bootstrap` before any journal/index publication:
reject `initial_events.size() > MAX_EVENTS` with
`R562_EVENT_BUDGET_EXCEEDED`. Preserve 16-event success and cold replay.
Integrate regression into official lifecycle acceptance, check both platforms
at new HEAD and re-evaluate required evidence hashes. No rollback of existing
R1.2 Windows/Linux exact PASS on the old frozen subject.
Do not change Construction/Matter, full physical calculations, or the R2 parent.

This adversarial exercise provides a reproducible *finding*, not a separate
human/agent Reviewer signature and not an approval for merge.
