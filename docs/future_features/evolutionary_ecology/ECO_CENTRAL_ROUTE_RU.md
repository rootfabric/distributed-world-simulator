# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-B IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

Canonical North Star:

`docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap:

`config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## 1. North Star

ECO — standalone evolutionary-ecology mini-project.

```text
landscape + environment/history + initial ancestry
                       ↓
             EVOLUTIONARY ECOLOGY
                       ↓
 spatial populations / lineages / succession /
 migration / extinction / later trophic webs
                       ↓
              restartable ecology state
                       ↓
          later XFER into World Simulator
```

The same ecological state meaning must survive `INCUBATE_FAST`, `BACKGROUND_COARSE` and `LOCAL_ACTIVE` execution resolutions.

## 2. Accepted checkpoints

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.PH representation     RESEARCH COMPLETE
ECO.CONV0-A               ACCEPTED DESIGN REQUIREMENTS
ECO.CAL1-A                ACCEPTED EXACT WINDOWS CANONICAL
```

CAL1-A canonical evidence:

- baseline hash `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C hash `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- `HEIGHT_LOW` winner in REFERENCE/SHADE/SUN/DRY;
- `HEIGHT_HIGH` rank 7 in all four;
- strongest height-pair driver everywhere: `structural_cost`.

## 3. Central route

```text
EVO0 — PLANT CAUSAL ECOLOGY
CAL1-A ACCEPTED
        │
        ▼
CAL1-B ← CURRENT CANDIDATE GATE
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
        │
        ▼
EVO2 long-run landscape evolution
        │
        ▼
EVO3 multi-trophic ecosystem
        │
        ▼
EVO4 autonomous regional/planet runner
        │
        ▼
XFER0 EcologyArchive
        │
        ▼ when simulator foundations are canonical
XFER1 world-generation ecology bridge
        │
        ▼
LIVE local/background continuation
```

## 4. CAL1-B implementation

Implementation head:

`561daee4cd9fa48bcef5c78e6f2b0d050451f3b9`.

Files:

- `scripts/research/ecology/plant_relative_vertical_light_competition_v1.gd`;
- `scripts/research/ecology/plant_vertical_light_competition_experiment_v1.gd`;
- `tests/research/ecology/eco_cal1_b_relative_vertical_light_competition_acceptance.gd`;
- `tests/research/ecology/eco_cal1_b_restart_replay_probe.gd`;
- `RUN_ECO_CAL1_B_TESTS.ps1`.

Diff from accepted CAL1-A control head changes exactly those five new ECO research/test/runner files. Accepted PH3/PH3C sources and runtime paths are unchanged.

### Mechanism

```text
competition_intensity
 = canopy_overlap * local_density

relative_height_bias
 = (height_a - height_b) / (height_a + height_b)

contested_light_pool
 = accepted PH3 height_light_access_gain
   * sunlight
   * competition_intensity

a_light_delta = pool * relative_height_bias
b_light_delta = -a_light_delta
```

Key property:

`a_light_delta + b_light_delta = 0`.

CAL1-B redistributes contested access; it does not invent unlimited light energy.

No custom morphology profile is created and no accepted PH3 coefficient is modified.

## 5. CAL1-B causal gates

```text
NO_NEIGHBOURS
  → zero effect

EQUAL_HEIGHT_DENSE
  → 0.5 / 0.5 relative access
  → zero delta

TALL_SHORT_DENSE
  → tall positive delta
  → short equal negative delta

TALL_SHORT_SPARSE
  → same sign, much smaller magnitude

DRY_TALL_SHORT_DENSE
  → relative tall advantage exists
  → existing structural/water costs remain active

TALL_SHORT_DENSE_SWAP
  → exact A/B symmetry
```

Acceptance does not require `HEIGHT_HIGH` to become the global winner. The proof is that height has a real neighbour-dependent benefit path.

## 6. Current exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_B_TESTS.ps1 -GodotPath $Godot
```

Runner sequence:

```text
accepted CAL1-A full runner
        ↓
CAL1-B causal acceptance
        ↓
fresh process A
        ↓
fresh process B
        ↓
aggregate hash equality
```

Required output:

- `ECO.CAL1-B Relative Vertical Light Competition: PASS`;
- aggregate hash;
- dense and sparse deltas;
- dense/sparse ratio;
- reference score gap before/after;
- dry score gap before/after;
- fresh-process PASS;
- candidate automated gates PASS.

Until that evidence exists:

```text
CAL1-B = IMPLEMENTED_CANDIDATE
CAL1-B != ACCEPTED
CAL1-C = BLOCKED
```

## 7. After CAL1-B

CAL1-C adds spatial crown overlap/self-shading and root water/nutrient competition.

CAL1-D adds lifecycle-scale payoffs: maturity, reproduction, dispersal, longevity and disturbance response.

CAL1-E combines accepted mechanisms **without calibration**.

CAL1-F is the first stage allowed to calibrate magnitudes and run full-pool robustness.

## 8. Next major ECO milestone

After CAL1 closure:

`ECO.EVO1_PLANT_WORLD_PROOF`.

Goal: heterogeneous deterministic landscape + common ancestral pool must produce spatial propagation, recruitment, succession, disturbance/recovery, migration/isolation, bounded long-run communities and lineage niche divergence without biome->species placement tables.

## 9. Global boundary

Standalone `EVO0..EVO4` remains research-only and does not become the main runtime critical path.

`XFER1/LIVE` wait for canonical G/ENV/MAT/WQ/SD/TF/POP/LIFE/WB/NX/persistence/authority foundations.

CONV0-A findings remain active, including reservation of `ECO` for Evolutionary Ecology and use of a separate `ECON` identity for future World Economy.

## 10. Operational resolver

When told `continue ECO`:

1. read North Star and machine roadmap;
2. execute current gate only;
3. preserve accepted hashes;
4. do not calibrate before CAL1-E;
5. do not jump into XFER/LIVE before global foundations;
6. after CAL1, prioritize autonomous Plant World over presentation work.

Current resolver:

`RUN CAL1-B EXACT WINDOWS CANONICAL CAUSAL GATE`.
