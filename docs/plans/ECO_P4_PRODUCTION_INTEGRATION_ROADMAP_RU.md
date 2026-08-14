# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1-P4.6 ACCEPTED / P4.7 CANONICAL SOAK GATE OPEN / P4.8 PREPARATION ONLY`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — **ACCEPTED**.
3. P4.3 Offline Catch-up — **ACCEPTED**.
4. P4.4 Production Persistence — **ACCEPTED exact Windows full committed chain**.
5. P4.5 Region Ownership / Server Handoff — **ACCEPTED exact Windows full committed chain**.
6. P4.6 Interest + Client Read Model — **ACCEPTED exact Windows committed unit + real P4.5 integration**.
7. P4.7 Production Integration Soak — **CANONICAL GATE OPEN; accelerated deterministic harness committed; exact committed A/B soak pending**.
8. P4.8 P4 Acceptance — **PREPARATION MAY PROCEED; acceptance CLOSED until P4.7 accepts**.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.5 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.6 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_REAL_INTEGRATION.
P4.7 = CANDIDATE_CANONICAL_SOAK_GATE_OPEN.
P4.8 = PREPARATION_ONLY / NOT ACCEPTED.

Accepted P4.4 aggregate: `4960096ae214a3b5f33a6c2507d0edb26348a0820b3469afc42eb92bdc62c1e2`.
Accepted P4.5 aggregate: `c966d60e6101e934f63945c7a5ea834ecf6e61646d3aaf54fca4657ccc7b5419`.
Accepted P4.6 unit aggregate: `88999825347c805b9ac2b2a35da32415b730566ae3b94eebd4203e9adff387c2`.
Accepted P4.6 real integration: `f8191c46658f345e54c85c61b29059939bbf9c7decda2892b9ef62e733a27bdf`.

P4.7 remains an accelerated deterministic integration soak, not a production scheduler or wall-clock service. It stresses eight regions across twelve cycles with bounded catch-up, repeated production persistence round-trips, ownership CAS/handoffs/restarts, client read-cache updates and interest projection. Forward and reverse processing orders must converge to identical final identities.

P4.8 may prepare a final acceptance manifest and closure runner, but it must remain fail-closed until P4.7 has an exact committed soak PASS and lifecycle acceptance.
