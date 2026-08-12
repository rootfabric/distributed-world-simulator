# ECO.CAL1-E — Combined Mechanism Matrix — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING / NO CALIBRATION`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `69a6f569d3a0f6ecbad641fb45b21340323f118e`.

Parent: `ECO.CAL1-D ACCEPTED`, aggregate `c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`.

## Purpose

CAL1-E composes the accepted A/B/C/D causal layers for the first time. It is not a calibration stage and does not invent one weighted fitness scalar.

Matrix:

```text
8 morphology strategies
× 4 environments
× 2 density regimes
× 3 disturbance regimes
= 192 rows / 24 contexts
```

Strategies: `BASE`, `HEIGHT_LOW`, `HEIGHT_HIGH`, `CROWN_NARROW`, `CROWN_WIDE`, `BRANCH_LOW`, `BRANCH_HIGH`, `GIANT_DENSE`.

Environments: `REFERENCE`, `SHADE`, `SUN`, `DRY`.

Density controls: `SPARSE` and `DENSE`.

Disturbance controls: `NONE`, `MILD`, `SEVERE`.

## Accepted mechanism composition

The resource ledger only combines quantities already expressed as resource/selection deltas:

```text
combined_resource_balance
 = accepted PH3 coupled_net_resource_balance
 + accepted CAL1-B relative vertical-light delta
 - accepted CAL1-C crown-overlap loss
 + accepted CAL1-C root-competition delta
```

No coefficient is changed or added.

`SPARSE` uses a 50 m controlled neighbour distance so crown/root overlap is exactly absent; this is the matrix no-neighbour anchor. `DENSE` uses 0.75 m and the accepted local-density context `0.90`, allowing geometry to decide actual overlap.

## Lifecycle projection

CAL1-D remains a vector. For each realized phenotype CAL1-E creates a lifecycle-only projection whose target height is that phenotype's realized adult height while all other base ecological genome traits stay unchanged.

Every strategy is compared at common developmental stage fraction `0.75`, biomass `1.0`, reserve `1.0`. This is a controlled integration state, not a calibrated ecological equilibrium.

Tracked lifecycle objectives:

- maturity time index — minimize;
- post-disturbance seed potential — maximize;
- effective seed dispersal — maximize;
- disturbance survival — maximize;
- recovery time — minimize;
- annual structural amortization — minimize.

## No weighted scalar

CAL1-E deliberately contains no `combined_fitness` / `weighted_fitness`.

Each context reports:

- resource winner set;
- seed-potential winner set;
- dispersal winner set;
- survival winner set;
- maturity winner set;
- amortization winner set;
- recovery winner set;
- Pareto front across all tracked objectives.

A row is Pareto-dominated only if another strategy is no worse on every objective and strictly better on at least one. This preserves trade-offs without choosing hidden weights.

## Acceptance gates

- exact CAL1-D parent hash preserved;
- exactly 24 contexts and 192 rows;
- SPARSE B/C neighbour interactions are zero;
- DENSE activates accepted neighbour mechanisms;
- disturbance severity monotonically reduces survival and post-disturbance seed opportunity in matched rows;
- `HEIGHT_HIGH` receives more relative-light delta than `HEIGHT_LOW` in matched dense REFERENCE context;
- taller matched-stage morphology releases farther but matures later;
- every context has a non-empty Pareto front;
- at least one context retains multiple non-dominated strategies;
- same-process and fresh-process aggregate determinism;
- no weighted scalar and no coefficient calibration.

## Implementation boundary

`8ebeed5ba4721b45d9d4bf0600b3af0691a8d399 -> 69a6f569d3a0f6ecbad641fb45b21340323f118e` changes exactly four new ECO files:

- `scripts/research/ecology/plant_combined_mechanism_matrix_v1.gd`;
- `tests/research/ecology/eco_cal1_e_combined_mechanism_matrix_acceptance.gd`;
- `tests/research/ecology/eco_cal1_e_restart_replay_probe.gd`;
- `RUN_ECO_CAL1_E_TESTS.ps1`.

Accepted P1/PH3/CAL1-B/C/D sources and runtime paths are unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_E_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
CAL1-E = IMPLEMENTED_CANDIDATE
CAL1-E != ACCEPTED
CAL1-F = BLOCKED
```

After PASS, CAL1-F may perform the first magnitude calibration and full-pool robustness sweep.
