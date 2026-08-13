# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1 ACCEPTED / P4.2 OPEN`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — production-facing region identity/state adapter over accepted P3.8. **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — world-time to ecology-generation scheduling independent of FPS/network arrival. **OPEN**.
3. P4.3 Offline Catch-up — deterministic bounded advancement after unloaded/offline time.
4. P4.4 Production Persistence — world persistence ownership/schema/migration; P3.8 codec remains reference-only.
5. P4.5 Region Ownership / Server Handoff — transfer canonical region ecology without history divergence.
6. P4.6 Interest + Client Read Model — server-authoritative read projection; clients do not own canonical ecology.
7. P4.7 Production Integration Soak — many regions, unload/load, restart/handoff and bounded backlog.
8. P4.8 P4 Acceptance — integrated production ecology checkpoint.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = OPEN FOR IMPLEMENTATION.
P4.3..P4.8 = NOT OPENED.

Accepted P4.1 aggregate: `1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717`.

Immutable P3.8 parent aggregate: `6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0`.

P4.2 may define deterministic world-time → ecology-generation scheduling and advancement. It must not absorb P4.3 offline catch-up/backlog policy, P4.4 storage, P4.5 region ownership/handoff, or P4.6 replication.

P4.3 remains closed until P4.2 candidate has its own exact runtime gate and lifecycle acceptance.
