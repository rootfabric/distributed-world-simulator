# V0 P7 — Matter Production Convergence

**Status:** CANONICAL PLAN / ACTIVATION INPUT  
**Date:** 2026-08-30  
**Predecessor:** V0 SM1 ACCEPTED  
**Accepted SM1 runtime:** `b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f`  
**SM1 runtime merge:** `acb9379cacc413fc25a65117fb1627f5a01b9736`  
**SM1 formal acceptance:** `9cc89e6e8c6cfc81fc32873a29743e443d8229e6`  
**Current canonical P7 stage:** `P7.7 GRAPHICAL_DIGGING_SLICE`

## 1. Purpose

P7 does not invent terrain mutation. The Matter program already provides the canonical
mutation, durability, replication, handoff, cross-region transaction and representation foundations.

P7's job is to compose those foundations into the real V0 planetary product.

```text
P7 = PRODUCTION CONVERGENCE
P7 != TERRAIN FOUNDATION
```

## 2. Canonical owner map

| Concern | Existing owner |
|---|---|
| equipped tool/equipment | P5 / canonical Item Graph equipment state |
| player action identity | existing V0 action / OperationId semantics |
| player authority route | SM1 + existing Gateway |
| Matter mutation | MW4 |
| Matter persistence/restart | MW5 |
| Matter network replication | MW6 |
| Matter interest | MW7 |
| regional Matter authority handoff | MW8 |
| durable handoff/recovery | MW9 |
| one mutation across >=2 Matter regions | MW10 |
| meshing / representation invalidation | RL2 |
| representation-aware network streaming | RL3 |
| extracted material DTO | MatterMaterialBatch |
| inventory/resources | canonical Item Graph |
| persistence owner | existing canonical persistence |

Acceptance for P7.0 is zero duplicate owners. **P7.0 R2 is ACCEPTED**: reviewed head `6b4b6573d002ea7550b6e5f84bb7571a03d9a5cd`, owner-map blob `8867355fe2cb33dcf2ce3c70de252d245dcb9908`, REVIEW-002 PASS.

## 3. Hard stop conditions

P7 MUST stop if an implementation proposes any of:

```text
TerrainMutationRequest
TerrainMutationResult
P7MatterStore
P7TerrainStore
P7Persistence
P7ReplicationProtocol
P7AuthorityDirectory
P7ResourceInventory
second Item Graph
second Matter truth
```

A bounded adapter is allowed only when it translates an existing product command into an
existing canonical owner contract.

## 4. P7.0 — Matter Production Owner Map / Convergence Gate — ✅ ACCEPTED

Deliverables:

1. exact current-main owner map;
2. exact code paths for P5 action, SM1 routing, MW4-MW10, RL2/RL3 and Item Graph;
3. no-second-owner audit;
4. operation identity and replay mapping;
5. single-region vs multi-region routing rule;
6. persistence and representation boundaries;
7. acceptance matrix for P7.1-P7.7.

P7.0 completed without gameplay runtime mutation.

Accepted identity mapping:

```text
logical_player_id
→ existing canonical player_entity_id ("player/<logical_player_id>")
→ MatterMutationRequest.actor_id
```

The first review rejected direct logical-player → Matter actor mapping because single-segment V0 IDs do not satisfy the Matter canonical-ID contract. R2 corrects this without creating a new identity owner.

Machine owner map: `config/control/harness/v0-p7-matter-production-owner-map.v1.json`.

## 5. P7.1 — Product Tool → MW4 adapter — ✅ COMPLETE

```text
equipped canonical tool
→ canonical player_entity_id
→ accepted MW6 Gateway MATTER_MUTATION ingress
→ stateless P7 authorize_mutation gate
→ SM1 ACTIVE tuple + MW8/MW9 fences
→ existing MatterMutationRequest
→ MatterExcavationService
```

Required rejects: no/wrong tool, stale authority/epoch, out-of-range target, invalid request,
stale revision, duplicate fingerprint conflict.

Exact replay must return the prior canonical result without a second mutation.

## 5.1 Parallel observable test lane

P7 has a dedicated non-mutating test/composition companion:

`docs/plans/V0_PLAYABLE_SEAMLESS_TEST_LADDER_RU.md`.

The lane starts immediately and is allowed in parallel with P7 runtime work because it owns
no runtime mutation lease and may not implement production semantics.

Promotion points:

```text
V1 now              component graphical precheck / local observation
V2 after P7.3       material → Item Graph evidence
V3 at P7.5          one live two-client convergence topology
V4 at P7.6          one live seam + items + Matter topology
V5 at P7.7          graphical equip→aim→dig→hole→material
FINAL                V0 PLAYABLE SEAMLESS PLANET composition acceptance
```

A green test fixture is never allowed to substitute for a missing production path.

## 6. P7.2 — Bounded planetary Matter bubble — ✅ COMPLETE_MERGED

Reuse the migration path in `DYNAMIC_MATTER_FABRIC_RU.md`.

```text
legacy planetary LOCAL/REGIONAL/GLOBAL presentation
+
one bounded volumetric Matter bubble
```

Inside the bubble, canonical geometry/query/collision derives from Matter. Outside it the
legacy planetary presentation remains unchanged.

Do not convert the whole planet in P7.

## 7. P7.3 — MatterMaterialBatch → canonical Item Graph — ✅ COMPLETE_MERGED

```text
removed canonical Matter
→ MatterMaterialBatch
→ bounded Item Graph production adapter
→ canonical inventory/container/resource state
```

Invariant:

```text
removed mass
= transferred material mass
+ explicitly declared bounded loss
```

No hidden deletion and no P7-private resource store.

## 8. P7.4 — Persistence / restart composition — ✅ COMPLETE_MERGED

Reuse MW5 and existing V0 recovery owners.

Acceptance:

```text
dig
→ canonical commit
→ process/server restart
→ same Matter revisions/hole
→ same operation replay result
→ no duplicate MatterMaterialBatch
→ same Item Graph accounting
```

## 9. P7.5 — Two-client convergence — ✅ COMPLETE_MERGED

Reuse MW6/MW7 and RL2/RL3.

```text
Client A digs
→ active Authority canonical commit
→ Matter/representation invalidation
→ A and B converge
```

No client-private terrain truth.

## 10. P7.6 — Seam composition — ✅ COMPLETE_MERGED

Distinguish actor handoff from mutation transaction scope.

```text
actor crosses A→B
mutation targets only B
→ SM1/MW8/MW9 + ordinary MW4 operation
```

```text
one canonical swept mutation touches region A + region B
→ MW10 cross-region Matter transaction
```

Do not introduce a P7 coordination protocol.

## 11. P7.7 — Graphical product slice — ← CURRENT

Mandatory visible acceptance stand: `Digging Playground`.

Detailed contract and A–H test matrix:
`docs/plans/V0_P7_7_DIGGING_PLAYGROUND_RU.md`.

The stand must prove both visual behavior and canonical ownership. A visible crater produced by private presentation state is a FAIL.

```text
equip
→ aim
→ dig
→ visible hole
→ canonical material yield
→ Item Graph inventory
→ second client sees same result
→ handoff
→ continue digging
→ reconnect/restart
→ same world
```

## 12. V0 successor checkpoint

After P7 acceptance:

```text
V0 PLAYABLE SEAMLESS PLANET
TYPE = COMPOSITION ACCEPTANCE
```

It composes P4/P5/P6/Gateway/SM1/P7. It is not permission to create a new foundation.

## 13. Post-V0 lanes

```text
                 ┌── P8 First Mobile Construct
V0 PLAYABLE ─────┤
                 └── RF1 Shadow Retained Cache → RF2
```

The lanes are dependency-independent. Until H0.3 multi-worker scheduling is accepted,
only one runtime mutation checkpoint may execute at a time.


## 14. WORLDGEN1 successor research frontier

P7 deliberately does not attempt to turn the bounded Moon Matter bubble into a universal terrain generator while its production mutation/convergence path is still being closed.

The planned successor research lane is:

`docs/plans/WORLDGEN1_PROCEDURAL_MATTER_TERRAIN_ROADMAP_RU.md`.

Its core rule is:

```text
WORLDGEN1 = deterministic procedural revision-0 Matter
P7/MW4/MW10 = runtime mutation of that same Matter
RL2/RL3 = derived representation
```

WORLDGEN1 is intended to extend the current near-spherical sampler into composable terrain fields for mountains, hills, ridges, craters, canyons, ravines, cliffs, overhangs, caves, lava tubes and geological stratification.

It must reuse the existing lazy materialization model:

```text
no stored mutated brick
    → deterministic generator/materializer
    → revision 0

stored mutated brick
    → canonical persisted snapshot
```

This keeps a huge procedural planet representable as generator identity + profiles + feature catalogs + only changed brick snapshots.

Activation boundary:

```text
NOW
  WORLDGEN1 design/documentation and fixture-only research are allowed.

P7.7 COMPLETE_MERGED
+ formal P7 checkpoint ACCEPTED
  WORLDGEN1 executable research becomes eligible,
  subject to scheduler/runtime-mutation capacity.

V0 PLAYABLE SEAMLESS PLANET ACCEPTED
  WORLDGEN1 may be considered for product promotion/default-world integration
  after its own exact LOD/performance/persistence verification.
```

WORLDGEN1 must not become an implicit blocker for P7 or the first V0 composition acceptance.
