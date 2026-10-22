# FABRIC R5.6.2 R1.3 — GENESIS EVENT BUDGET (narrow repair)

**Status:** narrow implementer repair candidate; not merge / not accepted.
**Risk:** HIGH — protocol/recovery admission. **Parent:** frozen R5.6.2 R1.2 `c9966b4f51dd623ddc6ec335b67452ccf96f7090`, TREE `5a8db3a3ba25f1ecd86636b8461af7e8bf68cce3`.
**Delivery:** separate branch `repair/fabric-r562-r13-genesis-admission-r1` and Draft PR, based on frozen R1.2; `main`, R5.6.1 R2 PR #784 and R1.2 branch must stay unchanged.

## Fresh reviewer / RED

Independent bounded genesis falsifier on the unchanged R1.2 subject:
`bootstrap(... initial_events=17)` unexpectedly returns a READY journal,
while `recover(... exact same journal)` rejects with
`R562_EVENT_BUDGET_EXCEEDED`. 16 initial event IDs survive replay.
This is **one failing assertion in four** (unrecoverable accepted initial state).
Published [review branch and RED script](https://github.com/rootfabric/distributed-world-simulator/blob/review/fabric-r562-r12-genesis-event-budget-falsifier-r1/tests/research/fabric_bake0/review_r562_genesis_budget_falsifier.gd) and [diagnosis](https://github.com/rootfabric/distributed-world-simulator/blob/review/fabric-r562-r12-genesis-event-budget-falsifier-r1/docs/research/FABRIC_R562_R12_REVIEW_GENESIS_BUDGET_RED_RU.md).

The defect does not invalidate the already frozen R1.2 Windows/Linux exact evidence for the cases it covers; it **blocks full R1 acceptance** until a new repaired subject is independently accepted.

## Repair Map

- Affected module: research-only `r5_6_2_r1_event_lifecycle_v1.gd`, `bootstrap` admission.
- Canonical owner: unchanged Construction Store, Matter, Authority.
- Sibling path: `_replay` already enforces `MAX_EVENTS=16`; `_prepare` refuses a 17th event. Only genesis admission lacks matching guard.
- Root cause: missing `initial_events.size() > MAX_EVENTS` check **before publishing** journal and physical index.
- Fix location: single fail-closed guard returning `R562_EVENT_BUDGET_EXCEEDED` in `bootstrap`, before snapshot compile/index construction.
- Negative: 17 valid canonical sorted IDs are refused at admission (not merely later on restart).
- Positive: 16 IDs are accepted and fully replayed; next attempted event fails with existing `R562_EVENT_BUDGET_OR_PENDING`.
- Regression: both 18-part and 25-part layouts run fresh 16/17 boundary checks inside mandatory lifecycle acceptance, increasing expected checks from 616 to 628 and negative rejects from 72 to 76. 10 commits/30 restarts/42 receipts/14 FULL oracles otherwise unchanged.
- Safety: no relaxation of any checksum, identity, numeric envelope, stale fence, authority check, snapshot schema or runner fatal policy. No new canonical writer.
- Alternative rejected: raising MAX_EVENTS to 17 would also change the established bounded contract and replay budget; not a narrow repair.
- Cross-event replay and boot existing positive path still require exact Windows/Linux regressions at the **new** HEAD.

## Evidence gates / follow-up

1. Exact original reviewer falsifier **RED on R1.2 → GREEN on R1.3** on canonical double Godot.
2. New lifecycle 3× identical 628/0, all inherited R2 (626), COM Recovery (18), R1 (203), BRIDGE-4 (49), strict collector evidence and identities on new HEAD, Windows and Linux.
3. Separate fresh Reviewer and Verifier must assess repairs including off-by-one, underflow/overflow and tamper + owner/restart invariants.
4. PC0/directional audit as required, no merge until human research-branch permission and PR #784 dependency acceptance.

Explicit nonclaims remain: no authenticated owner receipt, power-loss atomicity, arbitrary structural split, distributed exactly-once, or integration R6. Research index may still rebuild O(N). R1.2 Windows exact PASS is historical, not transferrable to R1.3 without new execution.
