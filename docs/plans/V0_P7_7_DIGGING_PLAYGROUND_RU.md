# P7.7 — Digging Playground

**Status:** ACTIVATION CONTRACT / REQUIRED ACCEPTANCE STAND  
**Stage:** `P7.7 GRAPHICAL_DIGGING_SLICE`  
**Canonical control base:** `ada3f79e02168046c6d1e1430fd25fc2224d7b7f`  
**Runtime branch:** `feature/v0-p7-bounded-terrain-mutation`

## 1. Purpose

`Digging Playground` is the mandatory visible acceptance stand for P7.7. It is not a new terrain or inventory system.

The stand must compose the already-canonical owners:

```text
P5 equipment
  → aim / target selection
  → P7.1 product intent + authority checks
  → P7.6 region classification
      ├─ 1 region  → existing MW4 mutation path
      └─ 2+ regions → existing MW10 transaction
  → canonical Matter commit
  → RL2/RL3-derived visible hole
  → MatterMaterialBatch
  → P7.3 delivery
  → canonical Item Graph
  → P7.5 client convergence
```

Hard rule:

```text
VISIBLE HOLE != PRESENTATION-PRIVATE TERRAIN TRUTH
INVENTORY UI != PRIVATE RESOURCE TRUTH
ACTOR SEAM != AUTOMATIC MW10
```

## 2. Playground layout

The first stand uses two adjacent Matter authority regions, A and B, with one continuous diggable surface crossing the seam.

```text
                  REGION A             │             REGION B
                                       │
          ________                     │
     ____/        \_______             │
____/                     \____________│________
                               seam     │

Player A: equip / aim / dig / cross seam
Player B: observe canonical convergence
```

The surface should be intentionally non-flat enough to make the hole visually obvious, but P7.7 must not introduce a new procedural terrain generator.

## 3. Required test matrix A–H

### A — single-region excavation

Dig entirely inside region A.

Expected:
- existing single-region P7.1 → MW4 path;
- MW10 invocation count = 0;
- one canonical Matter mutation;
- one visible hole derived from canonical state;
- one material delivery.

### B — seam-near but still single-region

Aim close to the A/B seam while the actual target set remains entirely in A.

Expected:
- still MW4;
- boundary proximity alone must not invoke MW10;
- no false cross-region classification.

### C — true A+B excavation

Use a swept/volumetric dig whose canonical target set intersects both A and B.

Expected:
- P7.6 classifies >=2 target regions;
- existing MW10 plan/coordinator executes;
- operation/body/participant set is exact;
- visible result is one atomic logical excavation.

### D — reservation conflict

While the true multi-region operation owns the MW10 reservation, attempt a conflicting single-region dig or actor handoff touching the reserved region.

Expected:
- fail closed;
- no partial second mutation;
- no handoff/mutation overlap that violates the existing reservation interlock.

### E — actor handoff without false MW10

Move Player A from region A to B and then perform a normal B-only dig.

Expected:
- handoff uses SM1/MW8/MW9;
- actor boundary crossing itself invokes MW10 zero times;
- post-handoff B-only mutation uses the ordinary single-region path.

### F — exactly-once material accounting

For a successful dig, observe `MatterMaterialBatch` and canonical Item Graph.

Expected:
- removed material enters canonical Item Graph exactly once;
- replay/duplicate delivery does not mint additional items;
- no P7-private resource counter/store.

### G — second-client convergence

Player B must converge to the same hole and inventory/revision outcome after Player A digs.

Expected:
- no client-private terrain truth;
- representation invalidation converges;
- canonical Item Graph replica converges;
- no duplicate aggregate revision owner.

### H — replay / reconnect / restart

Replay the operation and reconnect the observing client; include restart coverage by reusing P7.4 owners where the stand supports it.

Expected:
- no second hole;
- no second material delivery;
- same canonical Matter revision/state;
- same canonical Item Graph accounting.

## 4. Automated acceptance layers

P7.7 should have three test layers.

1. **Contract/route test** — deterministic headless test around the P7.7 composition adapter. Proves equip/aim validation, single vs multi-region routing, fail-closed malformed results and exactly-once handoff to existing output owners.
2. **Playground integration test** — headless scene/test that instantiates the Digging Playground fixture and proves A–H observable state transitions without needing manual input.
3. **Manual graphical smoke** — human can launch the scene, equip the tool, aim and dig to visually inspect hole/material/client convergence. This is supporting evidence, not a substitute for automated gates.

## 5. Planned first runtime surfaces

Allowed first implementation is bounded to product composition and test/lab presentation:

- `scripts/runtime/networked_gameplay/p7/p7_graphical_digging_slice.gd`
- `tests/runtime/test_v0_p7_7_graphical_digging_slice.gd`
- `scenes/labs/p7/p7_7_digging_playground.tscn`
- a bounded lab controller under `scripts/runtime/networked_gameplay/p7/` if required.

Existing Matter, Item Graph, SM1/MW8/MW9/MW10, persistence and network foundations are consumed, not rewritten.

## 6. Stop conditions

Stop and return to control/review if implementation requires any of:

- a new terrain/Matter store;
- a new inventory/resource store;
- a second raycast/aim truth that can disagree with canonical target binding;
- a P7-private cross-region transaction;
- a second replay/durability ledger;
- a second replication protocol;
- direct visual mesh mutation not derived from canonical Matter mutation/invalidation.

## 7. P7.7 exit

P7.7 is not complete merely because a scene looks correct.

Exit requires:

```text
equip
→ aim
→ dig
→ canonical hole
→ material exactly once
→ canonical inventory
→ client convergence
→ seam classification correct
→ replay/reconnect stable
→ exact-head Reviewer PASS
→ fresh Verifier VERIFIED
→ Human runtime merge approval
→ post-merge Project Control NON_RED
```
