# FABRIC CX-VIS0 / CX-VIS1 — Break / Local Unbake / Split / Rebake Observatory

**Статус:** IMPLEMENTED / EXACT DOUBLE VERIFICATION PENDING  
**Дата:** 2026-09-03  
**Ветка:** `feature/fabric-cx-vis0-powered-observatory-r1`  
**Predecessor:** `research/fabric-bake0-5-a-executable-hybrid-r2 @ d63821c7044ddbae33895ea9afb4fd2af7d1344d`  
**Класс:** noncanonical visual observatory / executable acceptance companion.

---

## 1. Зачем существует этот стенд

CX-VIS не вводит новую физику и не становится вторым owner мира.

Его задача — сделать уже доказанную COMPLEX0 / COMPLEX1A причинную цепочку наблюдаемой в Godot:

```text
2000 canonical parts
        ↓
STRUCTURAL_BAKE
        ↓
real refinement guard
        ↓
20-part LOCAL FULL island
        ↓
canonical BOND_BREAK
        ↓
old PhysicalBakeArtifact STALE
        ↓
topology split
        ↓
2 fresh rebaked components
```

Powered companion добавляет:

```text
same canonical structural event
        ↓
wire support relation lost
        ↓
functional bond removed
        ↓
FABRIC effort/flow graph re-solved
        ↓
lamp ON → OFF
```

Никакого `if fence_broken: lamp_off` в visual layer нет.

---

## 2. Truth boundary

Неизменяемое правило:

```text
canonical Construction / Matter
        =
единственная truth

COMPLEX0 fixture/runtime
COMPLEX1A FABRIC solve
PhysicalBakeArtifact
CX-VIS presentation
        =
derived consumers
```

CX-VIS запрещено:

- создавать canonical damage;
- менять Construction revision;
- самостоятельно принимать решение о break;
- самостоятельно отключать functional link;
- придумывать post-split physical trajectory;
- исполнять STALE bake;
- вводить device-specific Fence/Lamp solver shortcuts.

Визуальные stages — **кадры причинной инспекции**, а не искусственно растянутые физические задержки.

---

## 3. CX-VIS0 — 2000-Part Break Observatory

Сцена:

```text
res://scenes/labs/fabric/cx_vis0_break_observatory.tscn
```

Runtime presentation:

```text
2000 canonical elements

1980 stable parts
    → STRUCTURAL_BAKE presentation

20 target-region parts
    → highlighted only when the real guard requests refinement

weak bond
    → exact COMPLEX0 break_bond_id

after authoritative event
    → parent artifact marked STALE
    → stale execution rejection shown
    → two rebaked canonical components shown
```

Observable facts are produced by:

```text
fabric_bake_complex0_fixture.gd
physical_source_lifecycle_v1.gd
structural_refinement_guard_runtime_v1.gd
structural_topology_rebake_runtime_v1.gd
```

The visual controller does not reproduce the rules independently.

---

## 4. CX-VIS1 — Battery → Wire → Lamp

Сцена:

```text
res://scenes/labs/fabric/cx_vis1_powered_break_observatory.tscn
```

Power chain is bound to the **same COMPLEX0 structural bond ID** used by the break event.

Initial:

```text
battery/source
      ↓
wire/path-a
      ↓
lamp

support_bond_id = COMPLEX0 break_bond_id
lamp power > threshold
lamp ON
```

After the canonical break:

```text
same event_id
      ↓
support bond unavailable
      ↓
wire/path-a removed from functional topology
      ↓
Fabric.solve()
      ↓
voltage/current/power at lamp collapse to zero
      ↓
lamp OFF
```

Exactly-once is preserved: re-applying the same event ID must fail with:

```text
COMPLEX1A_STRUCTURAL_EVENT_ALREADY_APPLIED
```

---

## 5. Inspection frames

### CX-VIS0

```text
BASELINE_BAKED
IMPACT_GUARD
LOCAL_FULL
CANONICAL_BREAK
STALE_REJECTED
SPLIT_REBAKED
```

### CX-VIS1

```text
BASELINE_BAKED
IMPACT_GUARD
LOCAL_FULL
CANONICAL_BREAK
STALE_REJECTED
SPLIT_REBAKED
WIRE_TOPOLOGY_LOST
LAMP_OFF
```

Controls:

```text
Space — next frame
R     — reset
1     — ordinary world view
2     — physical representation view
3     — causal explanation view
```

---

## 6. Rendering strategy

The observatory intentionally uses MultiMesh for the 2000 visual parts.

Reason:

```text
canonical part count
!=
required heavy SceneTree node count
```

The scene creates grouped presentation batches for:

- stable baked parts;
- local FULL region;
- rebaked component A;
- rebaked component B.

This keeps the visual stand itself from becoming a misleading 2000-heavy-node benchmark.

The split is shown as component identity/presentation distinction only. CX-VIS0 does **not** invent falling debris motion. A future post-split dynamic-debris stand must consume real physical execution if such a claim is added.

---

## 7. Exact observation model

Shared nonvisual model:

```text
res://scripts/research/fabric_bake0/cx_vis_observation_model_v1.gd
```

It executes:

```text
COMPLEX0 build(2000)
→ parent lifecycle compile / execute
→ structural compile
→ real refinement guard
→ canonical break bundle
→ BakeInvalidation
→ stale execution rejection
→ topology transaction compile
→ topology runtime execute
→ component/rebake diagnostics
→ optional COMPLEX1A supported-wire solve
```

Only the resulting observation DTO is consumed by the scene.

---

## 8. Acceptance

New acceptance:

```text
res://tests/research/fabric_bake0/fabric_bake_cx_vis_observatory_acceptance.gd
```

Required checks include:

- exactly 2000 canonical parts;
- exactly 20 FULL parts at the refinement event;
- guard identifies exact target region and weak bond;
- one canonical BOND_BREAK;
- event commit state = APPLIED;
- old artifact = STALE;
- stale execution fails closed;
- split = 2 components;
- fresh executable rebakes = 2;
- component sizes match canonical break index;
- mass/momentum/state continuity remain inside existing tolerances;
- powered scene uses the same structural bond ID and event ID;
- lamp is ON before;
- supported functional link is removed by topology consequence;
- lamp is OFF after re-solve;
- duplicate event fails closed;
- both Godot scenes load as PackedScene.

Runner:

```text
bash ./RUN_FABRIC_CX_VIS_TESTS.sh
```

It reruns the existing COMPLEX0@2000 and COMPLEX1A gates before the CX-VIS acceptance.

---

## 9. Canonical double Godot

Expected binary:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Expected SHA-256:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Workflow:

```text
.github/workflows/fabric-cx-vis-linux-double.yml
```

The workflow performs fresh import, prerequisite exact gates, CX-VIS acceptance, fatal script-marker scan and final clean-tree check.

---

## 10. What this unlocks

After exact GREEN the next visual falsifiers can be layered without changing canonical ownership:

```text
CX-VIS0
2000-part local break
        ↓
CX-VIS1
battery / wire / lamp consequence
        ↓
CX2-VIS
redundant path A/B
        ↓
COMPLEX1B visual mixed-representation E2E
        ↓
post-split dynamic debris
        only after real physical execution exists
```

The purpose of the observatory is not to make the test prettier. It is to make representation scope, refinement, invalidation, exactly-once event ownership and cross-domain causal consequences visible enough to falsify by inspection.
