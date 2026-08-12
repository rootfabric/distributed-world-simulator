# ECO.CAL1-D — Lifecycle / Reproduction / Dispersal / Disturbance Payoffs — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `88adcc609fdfbc5511dc2aa0a4b779edc9a114e0`.

Parent: `ECO.CAL1-C ACCEPTED`, aggregate `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`.

## Why CAL1-D exists

CAL1-A/B/C closed major instantaneous morphology and spatial-competition holes, but the model is still too close to current resource balance. Long-lived structures, delayed maturity, seed output and recovery after disturbance need separate time-scale observables before mechanisms are combined.

CAL1-D deliberately does **not** return one final lifecycle fitness score.

It returns independently inspectable causal quantities so CAL1-E can combine accepted mechanisms without smuggling calibration into this checkpoint.

## Mechanism

Source: `scripts/research/ecology/plant_lifecycle_payoff_v1.gd`.

### Maturity and reproduction

```text
maturity_fraction = current_height / inherited_target_height, bounded 0..1
reserve_fraction  = reserve / (reserve + standing_biomass)
realized_seeds    = genome_seed_ceiling * maturity_fraction * reserve_fraction
```

A large genetic seed ceiling cannot produce full output while the plant is immature or reserve-starved.

### Release-height dispersal

The inherited `seed_dispersal_distance_m` is treated as a 1 m release-height baseline for this controlled experiment:

```text
effective_distance = base_distance * sqrt(release_height / 1 m)
```

Thus height affects dispersal through explicit release/flight geometry rather than an abstract `tall_bonus`.

### Maturity time and longevity

```text
maturity_time_index = target_height / growth_rate
reproductive_window = lifespan - maturity_time_index
amortized_structure  = accepted_P1_structural_investment / lifespan
```

These are exposed as diagnostics, not merged into a score.

### Disturbance and recovery

For the matched mechanical-disturbance control:

```text
exposure  = height / (height + root_depth)
anchoring = root_depth / (height + root_depth)
damage    = severity * exposure * (1 - anchoring)
survival  = 1 - damage
recovery_time_index = damage / growth_rate
```

Post-disturbance reproductive window is reduced by recovery time and survival fraction. No generic resilience or tall coefficient is introduced.

## Controlled cases

17 cases isolate:

- immature vs mature;
- low vs high reserve at matched maturity;
- low vs high release height with same dispersal trait;
- fast vs slow growth;
- short vs long lifespan with matched structure;
- no-disturbance control;
- shallow vs deep root anchoring;
- fast vs slow recovery with matched disturbance damage;
- mild vs severe disturbance.

## Expected causal directions

The controlled setup predicts, before canonical execution:

- mature seed output > immature;
- high reserve seed output > low reserve;
- higher release height -> greater effective dispersal;
- fast growth -> shorter maturity time;
- long lifespan -> lower annual structural amortization and longer reproductive window;
- no disturbance -> damage 0, survival 1, recovery 0;
- deeper matched roots -> better survival under the same mechanical disturbance;
- faster matched growth -> shorter recovery time for the same damage fraction;
- severe disturbance -> lower survival and post-disturbance seed potential than mild.

These are mechanism assertions, not calibration targets.

## Parent and boundary requirements

- CAL1-C aggregate must remain exact;
- accepted P1/PH3/CAL1-B/C sources remain unmodified;
- no custom morphology profile;
- no `tall_bonus`;
- no coefficient calibration;
- same-process and fresh-process aggregate determinism.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_D_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
CAL1-D = IMPLEMENTED_CANDIDATE
CAL1-D != ACCEPTED
CAL1-E = BLOCKED
```

After PASS, CAL1-E may combine A/B/C/D mechanisms without calibration.
