# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-E IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE / NO CALIBRATION`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Accepted chain

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A                ACCEPTED
ECO.CAL1-B                ACCEPTED
ECO.CAL1-C                ACCEPTED
ECO.CAL1-D                ACCEPTED
```

Canonical hashes:

- CAL1-A `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- CAL1-C `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`;
- CAL1-D `c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`.

## Central route

```text
CAL1-A ACCEPTED
   ↓
CAL1-B ACCEPTED
   ↓
CAL1-C ACCEPTED
   ↓
CAL1-D ACCEPTED
   ↓
CAL1-E ← CURRENT CANDIDATE GATE
combined mechanisms / Pareto / no calibration
   ↓
CAL1-F calibration + full-pool robustness
   ↓
EVO1 PLANT WORLD PROOF
```

## CAL1-E implementation

Implementation head: `69a6f569d3a0f6ecbad641fb45b21340323f118e`.

Implementation diff from accepted CAL1-D changes exactly four new ECO files and modifies no accepted mechanism source or runtime path.

Matrix:

```text
8 strategies
× REFERENCE/SHADE/SUN/DRY
× SPARSE/DENSE
× NONE/MILD/SEVERE
= 192 rows / 24 contexts
```

### Resource ledger

```text
PH3 coupled resource
+ CAL1-B relative vertical-light delta
- CAL1-C crown-overlap loss
+ CAL1-C root-competition delta
= combined_resource_balance
```

These terms already live on the accepted resource/selection-delta axis. No new coefficient is introduced.

`SPARSE` is a 50 m no-overlap anchor. `DENSE` is a 0.75 m geometry-active context with local density 0.90.

### Lifecycle vector

CAL1-D stays multi-objective. Each realized phenotype is projected into the accepted lifecycle model at common development fraction `0.75`, biomass `1.0` and reserve `1.0`. The projected lifecycle target height is the realized adult phenotype height; other base ecological genome traits remain unchanged.

Tracked objectives:

- maximize combined resource balance;
- maximize post-disturbance seed potential;
- maximize effective seed dispersal;
- maximize disturbance survival;
- minimize maturity time;
- minimize recovery time;
- minimize annual structural amortization.

### Pareto comparison

No `combined_fitness` or `weighted_fitness` exists in CAL1-E. Every context reports separate metric winner sets plus the non-dominated Pareto front. This makes trade-offs visible before CAL1-F chooses/calibrates magnitudes.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_E_TESTS.ps1 -GodotPath $Godot
```

Runner sequence:

```text
accepted CAL1-D full chain
        ↓
CAL1-E 192-row acceptance
        ↓
fresh process A
        ↓
fresh process B
        ↓
aggregate equality
```

Required evidence includes:

- 24 contexts / 192 rows;
- sparse interaction rows = 0;
- dense interaction rows > 0;
- disturbance monotonicity;
- matched height benefit/cost trade-offs;
- non-empty Pareto front in every context;
- at least one multi-member Pareto context;
- aggregate hash equality across fresh processes.

Until PASS:

```text
CAL1-E = IMPLEMENTED_CANDIDATE
CAL1-E != ACCEPTED
CAL1-F = BLOCKED
```

## After CAL1-E

CAL1-F is the first legal calibration stage. It will sweep seeds, environments, density, disturbance, parameter perturbations and strategy-pool composition and determine whether observed dominance is robust rather than an artifact of missing mechanisms or fragile coefficients.

After CAL1-F acceptance the branch moves to `ECO.EVO1_PLANT_WORLD_PROOF`, not to additional presentation work.

## Global boundary

Standalone EVO remains research-only. `XFER1/LIVE` wait for canonical simulator foundations. ECO does not create private global runtime foundations.

Current resolver: `RUN CAL1-E EXACT WINDOWS COMBINED MECHANISM MATRIX GATE`.
