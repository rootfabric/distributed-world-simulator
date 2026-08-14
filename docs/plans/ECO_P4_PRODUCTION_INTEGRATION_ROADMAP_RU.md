# ECO P4 — Production Ecology Integration Roadmap

Статус: `ACTIVE / P4.1 ACCEPTED / P4.2 ACCEPTED / P4.3 ACCEPTED / P4.4 CANDIDATE`.

Parent: `P3 RESEARCH ROUTE COMPLETE / P3.1..P3.8 ACCEPTED`.

## Sequence

1. P4.1 Production Ecology Region State — production-facing region identity/state adapter over accepted P3.8. **ACCEPTED**.
2. P4.2 Deterministic Ecology Clock — world-time to ecology-generation scheduling independent of FPS/network arrival. **ACCEPTED**.
3. P4.3 Offline Catch-up — deterministic bounded advancement after unloaded/offline time. **ACCEPTED**.
4. P4.4 Production Persistence — world persistence ownership/schema/migration; P3.8 codec remains reference-only. **CANDIDATE; targeted exact-Godot PASS, committed full-chain gate pending**.
5. P4.5 Region Ownership / Server Handoff — transfer canonical region ecology without history divergence. **NOT OPENED**.
6. P4.6 Interest + Client Read Model — server-authoritative read projection; clients do not own canonical ecology.
7. P4.7 Production Integration Soak — many regions, unload/load, restart/handoff and bounded backlog.
8. P4.8 P4 Acceptance — integrated production ecology checkpoint.

## Current lifecycle

P3.8 = ACCEPTED_EXACT_ATTACHED_GODOT_CANONICAL.
P4.1 = ACCEPTED_EXACT_ATTACHED_GODOT_FULL_COMMITTED_CHAIN.
P4.2 = ACCEPTED_EXACT_ATTACHED_GODOT_REMOTE_BLOBS_MATCH.
P4.3 = ACCEPTED_EXACT_WINDOWS_FULL_COMMITTED_CHAIN.
P4.4 = CANDIDATE_TARGETED_EXACT_ATTACHED_GODOT_PASS_FULL_CHAIN_GATE_PENDING.
P4.5..P4.8 = NOT OPENED.

Accepted P4.1 aggregate: `1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717`.

Accepted P4.2 aggregate: `607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e`.

Accepted P4.3 aggregate: `4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62`.

Immutable P3.8 parent aggregate: `6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0`.

P4.4 owns the first production persistence envelope for ecology regions: fixed format version, deterministic typed bytes, payload integrity, exact restore, explicit migration boundary and file save/load contract. It intentionally does not treat P3.8 research checkpoint bytes as production storage.

Because P4.4 is production format version 1, there is no legitimate older production schema to migrate yet. Current-format migration is identity; unknown versions fail closed until a real explicit migration is introduced.

P4.4 must preserve exact P4.3 Catch-up, P4.2 Clock and P4.1 RegionState identities and must not read wall clock implicitly. It must not absorb P4.5 region/server ownership or handoff, P4.6 replication/read authority, or client mutation authority.

P4.5 remains closed until P4.4 has passed its committed full-chain exact runtime gate and a separate lifecycle acceptance commit.
