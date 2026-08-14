# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1 ACCEPTED / P4.2 ACCEPTED / P4.3 CANDIDATE`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — production-facing region identity/state adapter over accepted P3.8. **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — world-time to ecology-generation scheduling independent of FPS/network arrival. **ACCEPTED**.
3. P4.3 Offline Catch-up — deterministic bounded advancement after unloaded/offline time. **CANDIDATE; targeted exact-Godot PASS, committed full-chain gate pending**.
4. P4.4 Production Persistence — world persistence ownership/schema/migration; P3.8 codec remains reference-only. **NOT OPENED**.
5. P4.5 Region Ownership / Server Handoff — transfer canonical region ecology without history divergence.
6. P4.6 Interest + Client Read Model — server-authoritative read projection; clients do not own canonical ecology.
7. P4.7 Production Integration Soak — many regions, unload/load, restart/handoff and bounded backlog.
8. P4.8 P4 Acceptance — integrated production ecology checkpoint.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_FULL_CHAIN_GATE_PENDING.
P4.4..P4.8 = NOT OPENED.

Accepted P4.1 aggregate: `1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717`.

Accepted P4.2 aggregate: `607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e`.

Immutable P3.8 parent aggregate: `6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0`.

P4.3 may own only deterministic staged catch-up policy over accepted P4.2: explicit observed horizon, derived backlog, bounded batches and preservation of fractional remainder. It must not read wall clock implicitly and must not absorb P4.4 storage/schema/migrations, P4.5 ownership/handoff or P4.6 replication/read authority.

P4.4 remains closed until P4.3 has passed its committed full-chain exact runtime gate and a separate lifecycle acceptance commit.
