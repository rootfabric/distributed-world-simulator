# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO0 CAL1-D IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

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
```

Canonical hashes:

- CAL1-A `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- CAL1-C `d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`.

## Central route

```text
CAL1-A ACCEPTED
   ↓
CAL1-B ACCEPTED
   ↓
CAL1-C ACCEPTED
   ↓
CAL1-D ← CURRENT CANDIDATE GATE
lifecycle / reproduction / dispersal / disturbance
   ↓
CAL1-E combined mechanisms, no calibration
   ↓
CAL1-F calibration/full-pool robustness
   ↓
EVO1 PLANT WORLD PROOF
```

## CAL1-D implementation

Implementation head: `88adcc609fdfbc5511dc2aa0a4b779edc9a114e0`.

Files:

- `scripts/research/ecology/plant_lifecycle_payoff_v1.gd`;
- `scripts/research/ecology/plant_lifecycle_payoff_experiment_v1.gd`;
- `tests/research/ecology/eco_cal1_d_lifecycle_payoff_acceptance.gd`;
- `tests/research/ecology/eco_cal1_d_restart_replay_probe.gd`;
- `RUN_ECO_CAL1_D_TESTS.ps1`.

CAL1-D does not output one hidden lifecycle fitness scalar. It exposes a vector of separate observables:

```text
maturity_fraction
reserve_fraction
realized_seed_output
release-height dispersal
maturity_time_index
reproductive_window
structural amortization
exposure / anchoring
disturbance damage / survival
recovery_time
post-disturbance reproductive window
```

### Reproduction

```text
maturity = current_height / inherited target height
reserve  = reserve / (reserve + standing biomass)
realized seeds = genetic seed ceiling * maturity * reserve
```

Thus high fecundity is not free: an immature or reserve-starved plant cannot realize its full seed ceiling.

### Release-height dispersal

For the same inherited seed dispersal trait:

```text
effective distance = base distance * sqrt(release height / 1m)
```

The path is explicit release geometry rather than a generic height reward.

### Lifetime

```text
maturity_time_index = target height / growth rate
reproductive_window = lifespan - maturity_time_index
annual structural amortization = accepted P1 structural cost / lifespan
```

The terms remain observable separately until CAL1-E.

### Disturbance

The controlled mechanical-disturbance model uses:

```text
exposure  = height / (height + root depth)
anchoring = root depth / (height + root depth)
damage    = severity * exposure * (1 - anchoring)
survival  = 1 - damage
recovery time index = damage / growth rate
```

This creates explicit matched controls: deeper roots improve anchoring; faster growth shortens recovery for the same damage; greater severity reduces survival and remaining reproduction.

## Causal experiment

17 cases isolate:

- immature vs mature;
- low vs high reserve;
- low vs high release height;
- fast vs slow growth;
- short vs long lifespan;
- no disturbance;
- shallow vs deep roots;
- fast vs slow recovery;
- mild vs severe disturbance.

Pre-run formula sanity predicts mature/immature seed ratio `4×`, high/low reserve about `3.33×`, release distance `2×`, fast/slow maturity `2.5 vs 8.0`, deep/shallow survival `0.8 vs ~0.4122`. These are diagnostic expectations, not calibration targets or accepted evidence.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_D_TESTS.ps1 -GodotPath $Godot
```

Runner first executes the complete accepted CAL1-C chain, then CAL1-D acceptance and two fresh-process probes.

Until PASS:

```text
CAL1-D = IMPLEMENTED_CANDIDATE
CAL1-D != ACCEPTED
CAL1-E = BLOCKED
```

After D acceptance, CAL1-E combines A/B/C/D without coefficient calibration. CAL1-F is the first calibration stage. After CAL1 closure the branch moves to `ECO.EVO1_PLANT_WORLD_PROOF` rather than adding more presentation work.

## Global boundary

Standalone EVO remains research-only. `XFER1/LIVE` wait for canonical simulator foundations. ECO does not create private global runtime foundations.

Current resolver: `RUN CAL1-D EXACT WINDOWS LIFECYCLE CAUSAL GATE`.
