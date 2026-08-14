# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1 ACCEPTED / P4.2 ACCEPTED / P4.3 ACCEPTED / P4.4 OPEN`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — production-facing region identity/state adapter over accepted P3.8. **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — world-time to ecology-generation scheduling independent of FPS/network arrival. **ACCEPTED**.
3. P4.3 Offline Catch-up — deterministic bounded advancement after unloaded/offline time. **ACCEPTED**.
4. P4.4 Production Persistence — world persistence ownership/schema/migration; P3.8 codec remains reference-only. **OPEN FOR IMPLEMENTATION**.
5. P4.5 Region Ownership / Server Handoff — transfer canonical region ecology without history divergence.
6. P4.6 Interest + Client Read Model — server-authoritative read projection; clients do not own canonical ecology.
7. P4.7 Production Integration Soak — many regions, unload/load, restart/handoff and bounded backlog.
8. P4.8 P4 Acceptance — integrated production ecology checkpoint.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = OPEN FOR IMPLEMENTATION.
P4.5..P4.8 = NOT OPENED.

Accepted P4.1 aggregate: `1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717`.

Accepted P4.2 aggregate: `607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e`.

Accepted P4.3 aggregate: `4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62`.

Immutable P3.8 parent aggregate: `6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0`.

P4.4 may define a production-owned persistence envelope, canonical serialization, integrity checks, version/schema migration and restart restoration for accepted P4.3 state. P3.8 persistence bytes remain an internal/reference ancestor and are not the production storage contract.

P4.4 must preserve exact RegionState, Clock and Catch-up identities, reject malformed/tampered snapshots fail-closed, keep migrations explicit/deterministic, and avoid implicit wall-clock reads. It must not absorb P4.5 region/server ownership or handoff, P4.6 replication/read authority, or client mutation authority.

P4.5 remains closed until P4.4 has its own exact committed runtime gate and separate lifecycle acceptance.
