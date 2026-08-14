# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.5 ACCEPTED / P4.6 REAL-INTEGRATION GATE READY / P4.7 PRE-ACCEPTANCE IMPLEMENTATION MAY PROCEED`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **ACCEPTED exact Windows full committed chain**.
6. P4.6 Interest + Client Read Model — **CANDIDATE; unit/targeted PASS; real committed integration gate READY**.
7. P4.7 Production Integration Soak — **canonical gate CLOSED until P4.6 acceptance; pre-acceptance harness may proceed**.
8. P4.8 P4 Acceptance — **NOT OPENED**.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.5 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.6 = CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_REAL_COMMITTED_INTEGRATION_GATE_READY.
P4.7 canonical acceptance = CLOSED pending P4.6 acceptance.
P4.8 = NOT OPENED.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.
Accepted P4.5 aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.
Frozen P4.6 unit aggregate: `88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2`.

P4.6 now has two independent surfaces: a frozen unit contract and a real accepted-state integration path. The real path reconstructs the same P3→P4.5 fixture used by accepted lifecycle tests, performs ownership handoff, creates read summaries/interest, advances ecology, persists/restarts the P4.4 snapshot, reconstructs P4.5 ownership and verifies exact P4.6 read identity continuity.

Canonical P4.6 acceptance requires one exact committed A/B run of that real integration gate and freezing the discovered identities. P4.7 may be developed ahead only as a deterministic test harness; it cannot acquire scheduler/authority semantics or become canonical before P4.6 accepts.
