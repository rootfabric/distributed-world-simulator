# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-C IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## North Star

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

## Accepted

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A                ACCEPTED EXACT WINDOWS CANONICAL
ECO.CAL1-B                ACCEPTED EXACT WINDOWS CANONICAL
```

CAL1-A baseline: `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`.

PH3C parent: `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`.

CAL1-B aggregate: `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`.

CAL1-B proved neighbour-relative height benefit without coefficient tuning: dense effect `0.099556363636`, sparse `0.002765454545`, ratio `36×`; reference HEIGHT_HIGH-vs-HEIGHT_LOW gap moved `-0.577805307483 -> -0.378692580210`, dry `-0.455052978213 -> -0.255940250941` while tall did not become universally superior.

## Central route

```text
EVO0 — PLANT CAUSAL ECOLOGY
CAL1-A ACCEPTED
        ↓
CAL1-B ACCEPTED
        ↓
CAL1-C ← CURRENT CANDIDATE GATE
crown + root spatial competition
        ↓
CAL1-D lifetime/reproduction/dispersal/disturbance payoffs
        ↓
CAL1-E combined mechanism matrix
        ↓
CAL1-F calibration/full-pool robustness
        ↓
EVO1 — PLANT WORLD PROOF
        ↓
EVO2 long-run landscape evolution
        ↓
EVO3 multi-trophic ecosystem
        ↓
EVO4 autonomous regional/planet runner
        ↓
XFER0 EcologyArchive
        ↓ when simulator foundations are canonical
XFER1 world-generation ecology bridge
        ↓
LIVE local/background continuation
```

## CAL1-C implementation

Implementation head: `69910d1bd2ed7983df9c0d40213012a11dcb2f6a`.

The implementation commit adds seven ECO-only files and changes no accepted PH3/P1/CAL1-B source or runtime path.

### Crown competition

Crown footprint is an actual circle derived from realized crown spread. Pair overlap uses exact circle-intersection geometry from two world-local positions.

```text
overlap_fraction_focal
    × neighbour realized branch_probability
    ↓
neighbour_shading_pressure
    × accepted PH3 saturating crown-light potential
    ↓
crown_overlap_loss
```

Controls require:

- no overlap -> zero loss;
- closer crowns -> larger overlap/loss than farther crowns;
- denser-branching neighbour -> larger focal shading at equal geometry;
- wide/narrow swap symmetry.

The accepted PH3 crown benefit already saturates; CAL1-C does not create a new free crown bonus.

### Root competition

Temporary controlled research geometry proxy:

`root_zone_radius_m = root_depth_m`.

This is not a canonical botanical law and may later be replaced by an evolved root-spread trait.

Shared uptake capacity:

`capacity = root_depth × growth_rate`.

Within geometrically overlapped root area, pair claims are normalized to sum to one. The competitor removes only its claim from the focal plant's shared resource fraction. Resulting local moisture/nutrients are then passed back through accepted P1 `plant_resource_model_v1.gd`.

Thus there is no duplicate ECO-private water/nutrient fitness equation.

Controls require:

- no root overlap -> no resource delta;
- equal roots -> symmetric 0.5/0.5 claims;
- deep/shallow pair -> deeper controlled root gets larger shared claim;
- dense root overlap -> stronger effect than sparse;
- swap symmetry;
- dry context remains finite and causal.

## Current exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_C_TESTS.ps1 -GodotPath $Godot
```

Runner sequence:

```text
accepted CAL1-B full runner
        ↓
CAL1-C crown/root acceptance
        ↓
fresh process A
        ↓
fresh process B
        ↓
aggregate hash equality
```

Required evidence includes aggregate hash, close/far crown overlap/loss, high/low neighbour shading loss, dense/sparse deep/shallow root competition deltas, deep/shallow shared claims and fresh-process equality.

Until PASS:

```text
CAL1-C = IMPLEMENTED_CANDIDATE
CAL1-C != ACCEPTED
CAL1-D = BLOCKED
```

## After CAL1

CAL1-D adds lifecycle-scale payoffs: maturity, reproduction, seed output/dispersal, longevity and disturbance response.

CAL1-E combines accepted mechanisms without calibration.

CAL1-F is the first stage allowed to calibrate magnitudes and perform full-pool robustness.

After CAL1 closure, the next major target is `ECO.EVO1_PLANT_WORLD_PROOF`: a heterogeneous deterministic landscape plus common ancestral pool must autonomously produce dispersal, recruitment, succession, disturbance/recovery, migration/isolation and lineage niche divergence without biome→species placement tables.

## Global boundary

Standalone EVO work remains research-only. `XFER1/LIVE` wait for canonical G/ENV/MAT/WQ/SD/TF/POP/LIFE/WB/NX/persistence/authority foundations. ECO does not create private replacements for them.

## Operational resolver

When told `continue ECO`:

1. read North Star and machine roadmap;
2. execute current gate only;
3. preserve accepted hashes;
4. do not calibrate before CAL1-E;
5. after CAL1, prioritize autonomous Plant World over presentation work.

Current resolver: `RUN CAL1-C EXACT WINDOWS CROWN+ROOT SPATIAL CAUSAL GATE`.
