# V0 — Current Primary Work Map

**Refresh:** 2026-08-30  
**Canonical main at this refresh:** `7055aef6c163099101588d5252d90ff77e089330`  
**SM1:** ACCEPTED  
**P7.0:** ACCEPTED  
**P7.1:** COMPLETE / MERGED  
**Current product gate:** P7.2 Bounded Planetary Matter Bubble  
**Next runtime checkpoint:** `V0_P7_BOUNDED_TERRAIN_MUTATION`

> Human-readable routing map. Machine eligibility remains owned by `config/control/**`.

## 1. Product critical path

```text
P4 Real Resource Construction       ACCEPTED
    ↓
P5 Equipment / Tools                ACCEPTED
    ↓
P6 Persistent Shared Outpost        ACCEPTED
    ↓
Edge Gateway Foundation             ACCEPTED
    ↓
SM1 Seamless Product Integration    ACCEPTED
    ↓
RF0 Replication Semantic Boundary   ARCHITECTURE GUARDRAIL / NON-BLOCKING
    ↓
P7 Matter Production Convergence    P7.1 COMPLETE / P7.2 NEXT
    ↓
V0 PLAYABLE SEAMLESS PLANET         COMPOSITION ACCEPTANCE
    ↓
    ├── P8 First Mobile Construct
    └── RF1 Shadow Retained Cache → RF2 Read-Only Consumer
            ↓
       static N-authority
            ↓
       Placement Observatory / SHADOW
            ↓
       dynamic placement / split / merge later
```

## 2. Exact SM1 closure

```text
runtime source      b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
runtime tree        7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68
runtime merge       acb9379cacc413fc25a65117fb1627f5a01b9736  PR #327
formal acceptance  9cc89e6e8c6cfc81fc32873a29743e443d8229e6  PR #329
```

Canonical acceptance record:
`config/control/harness/acceptance/V0-SM1-R1-CHECKPOINT-ACCEPTED-001.v1.json`.

PR #326 is historical proposal evidence and is not the current gate.

## 3. RF0 boundary

RF0 is accepted architecture only:

```text
REPLICATION != AUTHORITY
CACHE != PERSISTENCE
INTEREST != ACTIVATION
SERVER PROCESS != WORLD IDENTITY
```

Replica hydration may prepare WARM/read-only state but cannot activate authority.

```text
cache evidence
    ≠ authority proof

WARM → ACTIVE requires
Directory + owner/lease + AuthorityEpoch/fence + canonical recovery/handoff validation
```

## 4. P7 means integration, not a new terrain subsystem

Canonical ownership map:

```text
Tool/equipment             → P5 / existing V0 action owner
Player/seam authority      → SM1
Local Matter mutation      → MW4
Matter persistence         → MW5
Matter network             → MW6
Matter interest            → MW7
Regional authority         → MW8
Durable handoff/recovery   → MW9
Multi-region mutation      → MW10
Representation/meshing     → RL2/RL3
Material output            → MatterMaterialBatch
Inventory truth            → canonical Item Graph
Gateway                    → existing Edge Gateway
```

P7 MUST NOT create `TerrainMutationRequest`, `TerrainMutationResult`, a second Matter
truth, P7 persistence, P7 replication protocol, P7 authority directory or P7 resource store.

## 5. P7 train

```text
P7.0 Matter Production Owner Map / Convergence Gate  ✅ ACCEPTED
    ↓
P7.1 Product Tool → existing MatterMutationRequest adapter  ✅ COMPLETE
    ↓
P7.2 Bounded Planetary Matter Bubble  ← CURRENT PRODUCT RUNTIME
    ↓
P7.3 MatterMaterialBatch → canonical Item Graph
    ↓
P7.4 MW5 + V0 persistence/restart composition
    ↓
P7.5 MW6/MW7/RL2/RL3 two-client convergence
    ↓
P7.6 Seam composition:
     SM1/MW8/MW9 for authority lifecycle
     MW10 only when one mutation spans multiple regions
    ↓
P7.7 Graphical digging product slice
```

Detailed plan: `docs/plans/V0_P7_MATTER_PRODUCTION_CONVERGENCE_RU.md`.

## 6. V0 PLAYABLE SEAMLESS PLANET

Classification:

```text
TYPE = COMPOSITION_ACCEPTANCE
NEW FOUNDATION = FORBIDDEN
```

It composes P4+P5+P6+Gateway+SM1+P7 and proves two graphical clients can walk, equip,
dig, obtain canonical material, build, cross A↔B seamlessly, reconnect and survive server
restart with one canonical world truth.

## 7. P8 and RF1

After V0 composition acceptance:

```text
                 ┌── P8 PRODUCT LANE
V0 PLAYABLE ─────┤
                 └── RF1 SHADOW LANE → RF2
```

There is no architecture dependency `P8 → RF1`.

However, until H0.3 multi-worker scheduling is accepted:

```text
one active runtime mutation checkpoint at a time
```

Eligibility may be parallel; execution is still serialized.

## 8. Immediate execution order

```text
RUNTIME LANE
  P7.1 COMPLETE
  → P7.2 bounded planetary Matter bubble
  → P7.3 → P7.7

PARALLEL TEST / COMPOSITION LANE
  V1 PLAYABLE SEAMLESS PRECHECK
  → local AUTOMATED + OBSERVE modes
  → two graphical clients for seam scenario
  → two graphical clients for Item Graph scenario
  → existing SM1+Item/P6 composition gate
  → one exact-head summary
  → production runtime changes = 0

THEN
  promote test ladder at P7.3 / P7.5 / P7.6 / P7.7
  → V0 PLAYABLE SEAMLESS PLANET composition acceptance
```

Detailed test plan:
`docs/plans/V0_PLAYABLE_SEAMLESS_TEST_LADDER_RU.md`.

The test lane does not consume the pre-H0.3 runtime mutation worker. If a test requires
new production behavior, that change is routed back to the owning P7 stage instead of
being implemented in a fixture.

## 9. Stop conditions

Stop and return to architecture/control if implementation attempts a second
Item Graph/Construction/Matter/Persistence/Directory/Authority owner, Gateway canonical
gameplay truth, cache-as-recovery-authority, Worker direct canonical publication,
new terrain DTOs duplicating MW4, mandatory broker/database for RF0/RF1, or dynamic
split/merge before static N-authority correctness.


## 10. P7.0 accepted exact-source result

P7.0 owner map R2 is accepted by fresh review.

- reviewed head: `6b4b6573d002ea7550b6e5f84bb7571a03d9a5cd`;
- owner-map blob: `8867355fe2cb33dcf2ce3c70de252d245dcb9908`;
- REVIEW-001: FIX_REQUIRED on raw logical-player → Matter actor mapping;
- REVIEW-002: PASS after switching to existing canonical `player_entity_id`;
- exact-head Project Control: run `33293163667` SUCCESS;
- runtime mutation: none.

The P7.1 actor rule is now:

```text
logical_player_id
→ existing player_entity_id = "player/<logical_player_id>"
→ MatterMutationRequest.actor_id
```

P7 does not create an identity projection store.


## 11. P7.0 post-merge closure

Canonical P7.0 merge:

```text
main  6b0143281a4a2bedeff7889f0bd6470a5fcfd60d
tree  fa83cdf08c0b487c6939aeaa4b7bbb3211365b64
```

Canonical post-merge audit:

```text
Project Control  33293384467  SUCCESS
standard PC0     YELLOW / NON_RED
directional PC0  YELLOW / NON_RED
runtime mutation 0
```

P7.0 is complete. The only remaining activation prerequisite for P7.1 is `DIRECTOR_DISPATCH`.
