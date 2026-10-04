# ECO ARCH2 A13 — Spatial Workset Addressing / Work Order R1

Статус: implementation candidate.

База:
845dc2411a4810a5e7e15b6d96ae0d661014ffb8
(A13 Deterministic Exact Worksets merged main)

## Цель

Добавить пространственную адресацию worksets, не создавая второй spatial truth и не меняя ecological causality.

Spatial address — это scheduler-only projection:

canonical organism position_mm
+
canonical field geometry
→
tile address

Адрес не хранится в organism state, Runtime state или checkpoint. После движения организма адрес пересчитывается из новой canonical position.

## R1 contract

- schema: dws.ecology.spatial-workset-plan.v1;
- default tile span = 4x4 field cells;
- default max members per workset = 64;
- address format: tile/<z>/<x>;
- stable ordering: address, shard, individual_id;
- overloaded tile делится на deterministic shards;
- plan bound to field geometry hash;
- plan bound to exact {individual_id, position_mm} projection;
- stale plan after migration rejected fail-closed;
- invalid/tampered membership rejected;
- no spatial address stored in biology/persistence.

## Execution invariant

Spatial worksets MAY change preparation/advance order.

They MUST NOT change resource competition:

1. prepare/sample/demands by spatial workset;
2. ONE GLOBAL Field.allocate_demands() over every demand;
3. advance by same validated spatial units;
4. canonical ID-order merge.

Field allocator canonicalizes requests by request_id, therefore spatial workset order cannot influence grants.

## Acceptance

- 256 founders over 16x16 cells form 16 deterministic 4x4-cell tiles;
- every founder belongs to exactly one spatial address;
- input permutation produces identical plan;
- 256 founders in one tile with max_members=32 produce 8 deterministic shards;
- forged geometry/member coverage rejected;
- canonical migration changes derived address and invalidates stale plan;
- address is absent from organism canonical bytes;
- A5 spatial execution is exact-equivalent to closed exact-workset scheduler;
- 16-tile and single-tile sharded executions have identical field/population/propagule results;
- multi-tile reproduction+mutation runtime remains hash-identical to exact scheduler for 8 ticks;
- checkpoint bytes are identical;
- invalid spatial scheduling leaves source runtime unchanged;
- closed A13 Exact Worksets, A12 and A11 exact suites rerun on the same subject.

## Не входит в R1

- active/sleeping decision;
- thread-level parallelism;
- independent per-tile resource allocation;
- persisted spatial scheduler state;
- approximate PATCH/AGGREGATE dynamics;
- raising population cap above 256.

Следующий этап после Spatial Addressing — active/sleeping population scheduling на этих stable derived addresses.
