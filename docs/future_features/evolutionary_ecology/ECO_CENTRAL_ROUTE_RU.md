# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-B EXECUTE_NOW`.

Canonical North Star:

`docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap:

`config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## 1. Что строит ECO

ECO — самостоятельный evolutionary-ecology mini-project внутри Distributed World Simulator.

Цель:

> взять landscape + environment/history + initial ancestry, автономно вырастить spatial ecology без hardcoded biome/species placement, сохранить её restartable state и позднее позволить World Simulator материализовать и продолжить ту же ecology локально и в background.

Три слоя:

```text
A. EVOLUTIONARY ECOSYSTEM
   standalone / headless / no player
                ↓
B. SIMULATOR LIVING ECOLOGY
   import / local activation / background continuation
                ↓
C. DERIVED PRESENTATION
   mesh / assets / animation / LOD
```

Один ecological state должен поддерживать три режима исполнения:

`INCUBATE_FAST / BACKGROUND_COARSE / LOCAL_ACTIVE`.

## 2. Accepted foundation

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH4              ACCEPTED
ECO.PH5-S1..S4            ACCEPTED
ECO.PH representation     RESEARCH COMPLETE
ECO.CONV0-A               ACCEPTED DESIGN REQUIREMENTS
ECO.CAL1-A                ACCEPTED EXACT WINDOWS CANONICAL
```

CAL1-A canonical baseline:

`280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`.

Accepted PH3C aggregate preserved:

`294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`.

## 3. Центральный маршрут

```text
FOUNDATION ACCEPTED
        │
        ▼
EVO0 — PLANT CAUSAL ECOLOGY
CAL1-A ACCEPTED
        │
        ▼
CAL1-B ← EXECUTE_NOW
relative vertical light competition
        │
        ▼
CAL1-C crown/root competition
        │
        ▼
CAL1-D lifetime/reproduction/disturbance payoffs
        │
        ▼
CAL1-E combined mechanism matrix
        │
        ▼
CAL1-F calibration/full-pool robustness
        │
        ▼
EVO1 — PLANT WORLD PROOF
seed dispersal / recruitment / seed bank /
succession / disturbance / migration /
biogeography / lineage divergence
        │
        ▼
EVO2 — LONG-RUN EVOLUTIONARY LANDSCAPE
history / isolation / extinction-recolonization /
dynamic attractors / save-restart
        │
        ▼
EVO3 — MULTI-TROPHIC ECOSYSTEM
organic matter → herbivores → predators → coevolution
        │
        ▼
EVO4 — AUTONOMOUS REGIONAL / PLANET ECOLOGY
INCUBATE_FAST + BACKGROUND_COARSE
        │
        ▼
XFER0 — PORTABLE ECOLOGY ARCHIVE
        │
        ├──── wait canonical simulator foundations
        ▼
XFER1 — WORLD GENERATION BRIDGE
G/MAT/ENV → EcologyLocalProjection → materialization
        │
        ▼
LIVE1/2/3
local active ↔ background ↔ world/player feedback
```

## 4. CAL1-A — что доказано

Exact Windows Godot 4.7.1 double runner прошёл:

- PH3 `217 PASS`;
- PH3 fresh-process `5 PASS`;
- PH3C `97 PASS`;
- PH3C fresh-process `6 PASS`;
- CAL1-A `1094 PASS`;
- CAL1-A fresh-process `5 PASS × 2`.

Full-pool result:

```text
REFERENCE  HEIGHT_LOW rank 1 / HEIGHT_HIGH rank 7
SHADE      HEIGHT_LOW rank 1 / HEIGHT_HIGH rank 7
SUN        HEIGHT_LOW rank 1 / HEIGHT_HIGH rank 7
DRY        HEIGHT_LOW rank 1 / HEIGHT_HIGH rank 7
```

Exact `HEIGHT_LOW - HEIGHT_HIGH` selection-score deltas:

```text
REFERENCE  0.577805307
SHADE      0.545990845
SUN        0.614010029
DRY        0.455052978
```

Strongest driver in every environment:

`structural_cost`.

Interpretation:

```text
height cost = super-linear and always active
relative neighbour-height payoff = absent
```

This does not authorize lowering structural cost. It authorizes testing the missing competition mechanism.

Accepted checkpoint:

`docs/checkpoints/ECO_CAL1_A_BASELINE_DECOMPOSITION_ACCEPTED_RU.md`.

Validation:

`validation/ecology/eco-cal1-a-baseline-decomposition-validation.json`.

## 5. CAL1-B — EXECUTE_NOW

Name:

`Relative Vertical Light Competition`.

Goal:

> prove that height can become beneficial because overlapping shorter neighbours exist, not because tall plants receive an unconditional bonus.

CAL1-B is a separate research layer over accepted PH3/PH3C. Accepted PH3 coefficients remain unchanged.

Required causal controls:

```text
NO_NEIGHBOURS
  → competition delta ~ 0

EQUAL_HEIGHT
  → symmetric / no fake height winner

TALL_VS_SHORT_DENSE
  → tall gains relative light access
  → short loses relative light access

TALL_VS_SHORT_SPARSE
  → effect collapses strongly

DRY_DENSE
  → relative light advantage exists
  → but water/structure costs remain active

A/B SWAP
  → exact symmetric output swap
```

Mechanism concept:

```text
canopy overlap/density
        ×
relative canopy height
        ×
available incoming light
        ↓
redistribution of contested light
        ↓
+delta for exposed canopy
-delta for suppressed canopy
```

Important properties:

- no neighbour -> no competition redistribution;
- no crown overlap -> near-zero redistribution;
- equal height -> equal shares;
- competition should redistribute a bounded light pool rather than invent unlimited energy;
- deterministic hash/restart required;
- CAL1-B acceptance does not require HEIGHT_HIGH to become global winner.

## 6. CAL1-C..F

After CAL1-B acceptance:

- CAL1-C: crown overlap/self shading + root water/nutrient competition;
- CAL1-D: maturity/reproduction/dispersal/longevity/disturbance payoffs;
- CAL1-E: combine accepted mechanisms without calibration;
- CAL1-F: only then calibrate magnitudes and run full-pool robustness.

Forbidden sequence:

```text
HEIGHT_LOW wins
→ turn knobs until it stops
```

Required sequence:

```text
missing mechanism
→ causal control
→ mechanism acceptance
→ combination
→ calibration
```

## 7. EVO1 — следующий большой milestone

После CAL1:

`ECO.EVO1_PLANT_WORLD_PROOF`.

A small deterministic heterogeneous landscape + common ancestral pool must generate:

- spatial propagation from seed dispersal;
- condition-dependent establishment;
- competition-driven community change;
- seed-bank continuity;
- emergent succession;
- disturbance/recovery;
- isolation/migration differences;
- bounded long-run dynamics;
- deterministic save/restart;
- lineage niche divergence.

No biome->species table.

## 8. Future convergence boundary

Standalone `EVO0..EVO4` may progress without becoming the main runtime critical path.

`XFER1/LIVE` wait for canonical simulator foundations.

CONV0-A findings remain active:

- `ECO` means Evolutionary Ecology; future economy should use `ECON`;
- generic production population fabric remains `POP`-owned;
- ECO must not create private G/WQ/SD/TF/MAT/LIFE/WB/NX/WT/persistence/authority foundations.

## 9. Operational resolver

When told `continue ECO`:

1. read North Star;
2. read machine roadmap/passport;
3. execute `current_step` only;
4. preserve accepted evidence;
5. never calibrate before mechanism acceptance;
6. after CAL1, move toward autonomous Plant World rather than renderer sophistication.

Current resolver:

`ECO.CAL1-B RELATIVE VERTICAL LIGHT COMPETITION — EXECUTE_NOW`.
