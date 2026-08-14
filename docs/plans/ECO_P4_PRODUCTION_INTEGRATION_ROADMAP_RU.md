# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.5 ACCEPTED / P4.6 FULL-CHAIN GATE READY / P4.7 PRE-ACCEPTANCE IMPLEMENTATION MAY PROCEED`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **ACCEPTED exact Windows full committed chain**.
6. P4.6 Interest + Client Read Model — **CANDIDATE; targeted exact-Godot PASS; committed full-chain gate READY**.
7. P4.7 Production Integration Soak — **canonical gate CLOSED until P4.6 acceptance; pre-acceptance implementation may proceed without authority activation**.
8. P4.8 P4 Acceptance — **NOT OPENED**.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.5 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.6 = CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_FULL_CHAIN_GATE_READY.
P4.7 canonical acceptance = CLOSED pending P4.6 acceptance.
P4.8 = NOT OPENED.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.
Accepted P4.5 aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.
Frozen P4.6 unit aggregate: `88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2`.

P4.5 is now the accepted region/server authority identity boundary: P4.4 snapshots remain byte/semantic continuity state; P4.5 adds owner identity, fencing epoch, CAS mutation and deterministic handoff without introducing network transport or consensus.

P4.6 is a one-way read boundary: validated P4.5 ownership → bounded deterministic region summaries → interest projection/client cache. Clients receive detached summaries and cannot commit them back into canonical ecology. Its committed full-chain gate is now authorized by P4.5 acceptance.

P4.7 may be implemented ahead of P4.6 acceptance only as a deterministic integration-soak harness. It must exercise many regions, save/load, bounded catch-up, ownership handoff and read projection without inventing a new scheduler/authority layer. Canonical P4.7 acceptance stays closed until P4.6 accepts.
