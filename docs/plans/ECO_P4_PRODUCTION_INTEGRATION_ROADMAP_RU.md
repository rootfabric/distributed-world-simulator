# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.4 ACCEPTED / P4.5 FULL-CHAIN GATE READY / P4.6 PRE-ACCEPTANCE IMPLEMENTATION MAY PROCEED`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **CANDIDATE; targeted exact-Godot PASS; committed full-chain gate READY**.
6. P4.6 Interest + Client Read Model — **canonical gate CLOSED until P4.5 acceptance; pre-acceptance implementation may proceed without authority activation**.
7. P4.7 Production Integration Soak — **NOT OPENED**.
8. P4.8 P4 Acceptance — **NOT OPENED**.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.5 = CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_FULL_CHAIN_GATE_READY.
P4.6 canonical acceptance = CLOSED pending P4.5 acceptance.
P4.7..P4.8 = NOT OPENED.

Accepted P4.1 aggregate: `1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717`.

Accepted P4.2 aggregate: `607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e`.

Accepted P4.3 aggregate: `4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62`.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.

Frozen P4.5 candidate aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.

Immutable P3.8 parent aggregate: `6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0`.

P4.4 is now the accepted production persistence owner/schema boundary. Its committed Windows run passed P4.3 direct parent regression and P4.4 A/B with exact deterministic aggregate, snapshot and restart-continuity identities.

P4.5 embeds validated P4.4 snapshots into deterministic ownership state and handoff packages. It introduces an explicit fencing epoch and compare-and-swap ownership hash. A handoff is valid only against the exact source ownership/snapshot from which it was prepared.

P4.6 may be implemented ahead of P4.5 acceptance only as a read-only pre-acceptance candidate. It must not activate network transport, client mutation authority or canonical ownership. Canonical P4.6 gate remains closed until P4.5 full-chain PASS plus lifecycle acceptance.
