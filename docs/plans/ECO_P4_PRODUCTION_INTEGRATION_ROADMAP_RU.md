# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.4 ACCEPTED / P4.5 FULL-CHAIN GATE READY / P4.6 PRE-ACCEPTANCE CANDIDATE`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **CANDIDATE; targeted exact-Godot PASS; committed full-chain gate READY**.
6. P4.6 Interest + Client Read Model — **PRE-ACCEPTANCE CANDIDATE; targeted exact-Godot PASS; canonical gate blocked on P4.5 acceptance**.
7. P4.7 Production Integration Soak — **NOT OPENED**.
8. P4.8 P4 Acceptance — **NOT OPENED**.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.5 = CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_FULL_CHAIN_GATE_READY.
P4.6 = CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_P4_5_ACCEPTANCE_AND_FULL_CHAIN_INTEGRATION_PENDING.
P4.7..P4.8 = NOT OPENED.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.
Frozen P4.5 aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.

P4.5 canonical gate is now authorized by P4.4 acceptance. P4.6 is intentionally implemented ahead of P4.5 acceptance only to shorten the critical path; it cannot become canonical until P4.5 accepts.

P4.6 is a one-way read boundary: validated P4.5 ownership → bounded deterministic region summaries → interest projection/client cache. Clients receive detached summaries and cannot commit them back into canonical ecology. Network transport and subscriptions remain outside this checkpoint.

P4.7 remains closed until P4.5 and P4.6 have both completed their committed gates and lifecycle acceptance.
