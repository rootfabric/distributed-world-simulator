# V0 P7 — Matter Production Convergence

**Status:** CANONICAL PLAN / ACTIVATION INPUT  
**Date:** 2026-08-30  
**Predecessor:** V0 SM1 ACCEPTED  
**Accepted SM1 runtime:** `b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f`  
**SM1 runtime merge:** `acb9379cacc413fc25a65117fb1627f5a01b9736`  
**SM1 formal acceptance:** `9cc89e6e8c6cfc81fc32873a29743e443d8229e6`

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

Acceptance for P7.0 is zero duplicate owners.

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

## 4. P7.0 — Matter Production Owner Map / Convergence Gate

Deliverables:

1. exact current-main owner map;
2. exact code paths for P5 action, SM1 routing, MW4-MW10, RL2/RL3 and Item Graph;
3. no-second-owner audit;
4. operation identity and replay mapping;
5. single-region vs multi-region routing rule;
6. persistence and representation boundaries;
7. acceptance matrix for P7.1-P7.7.

No gameplay runtime mutation is required for P7.0.

## 5. P7.1 — Product Tool → MW4 adapter

```text
equipped canonical tool
→ authoritative player action
→ Gateway/SM1 active Authority
→ bounded P7 adapter
→ existing MatterMutationRequest
→ MatterExcavationService
```

Required rejects: no/wrong tool, stale authority/epoch, out-of-range target, invalid request,
stale revision, duplicate fingerprint conflict.

Exact replay must return the prior canonical result without a second mutation.

## 6. P7.2 — Bounded planetary Matter bubble

Reuse the migration path in `DYNAMIC_MATTER_FABRIC_RU.md`.

```text
legacy planetary LOCAL/REGIONAL/GLOBAL presentation
+
one bounded volumetric Matter bubble
```

Inside the bubble, canonical geometry/query/collision derives from Matter. Outside it the
legacy planetary presentation remains unchanged.

Do not convert the whole planet in P7.

## 7. P7.3 — MatterMaterialBatch → canonical Item Graph

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

## 8. P7.4 — Persistence / restart composition

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

## 9. P7.5 — Two-client convergence

Reuse MW6/MW7 and RL2/RL3.

```text
Client A digs
→ active Authority canonical commit
→ Matter/representation invalidation
→ A and B converge
```

No client-private terrain truth.

## 10. P7.6 — Seam composition

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

## 11. P7.7 — Graphical product slice

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
