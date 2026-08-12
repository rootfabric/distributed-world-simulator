# ECO.EVO1 / P2.2 — Establishment / Recruitment / Seed Bank — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `d09857528adee1010f2177095f2afb04bf651532`.

Parent: `ECO.EVO1/P2.1 ACCEPTED`, aggregate `cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6`.

## Purpose

P2.2 consumes **inside-domain P2.1 seed packets** and introduces persistent local propagule/recruitment state. It does not move seeds again and does not yet advance adult population turnover.

For every packet or seed-bank cohort, integer accounting is explicit:

```text
input seeds
= exported
+ decayed
+ failed after germination
+ recruited
+ remaining viable seed bank
```

Outside-domain P2.1 packets remain export and bypass local establishment completely.

## Truth granularity

P2.2 remains cohort-based. There is no one-entity-per-seed truth.

Derived outputs are bounded recruitment cohorts and seed-bank cohorts preserving:

```text
seed_count
lineage_id
genome_checksum
reproduction_event
position
recruitment_traits_checksum
age
cohort_hash
```

## Recruitment traits

P2.2 adds a separate research trait sidecar rather than modifying the accepted plant genome schema:

```text
dormancy_fraction
seed_bank_half_life_years
```

Default values (`0.45`, `3 years`) are research defaults, not empirical calibration targets. Controlled variants test dormancy and longevity causally.

## Causal stage split

### Viability / seed-bank aging

Seed-bank viability follows half-life decay:

```text
survival = exp(-ln(2) * elapsed_years / half_life)
```

Integer cohort counts use deterministic hash-based fractional rounding.

### Germination activation

Germination uses seed-stage water preference matching and temperature. Adult root-depth access is deliberately **not** granted to an ungerminated seed.

```text
seed_water_response = gaussian(soil_moisture vs inherited water preference/tolerance)
germination_activation = sqrt(seed_water_response * temperature_response)
germination_fraction = germination_activation * (1 - dormancy_fraction)
```

### Post-germination establishment

Establishment is a separate causal gate:

```text
establishment_fraction
= geometric_mean(light_response, nutrient_response, 1 - flood_frequency)
```

This keeps activation and establishment distinct and avoids a hidden biome/species suitability table.

## Controlled cases

- favourable matched environment;
- severe dry mismatch;
- high flood exposure;
- low vs high dormancy;
- short vs long seed-bank half-life after 2 years;
- dormant bank reactivation after environment improves;
- P2.1 outside-domain boundary export.

Required directions:

```text
favourable recruitment > dry recruitment
favourable recruitment > flooded recruitment
low dormancy recruitment > high dormancy recruitment
high dormancy bank > low dormancy bank
long half-life bank > short half-life bank after 2 years
reactivation recruitment > 0
boundary export = 80 and local recruitment = 0
```

Every case must conserve integer seed counts exactly and same/fresh-process hashes must match.

## Strict P2.3 boundary

P2.2 does not contain:

- adult population biomass update;
- carrying-capacity competition;
- mortality turnover of established cohorts;
- succession state;
- repeated reproductive cycles;
- patch colonization/migration graph.

Those semantics start at `P2.3 Local Population Turnover + Succession` and later checkpoints.

## Implementation boundary

`380620ff371321a53959d7d2985670b3133d1df4 -> d09857528adee1010f2177095f2afb04bf651532` adds exactly six files:

- `scripts/research/ecology/plant_recruitment_traits_v1.gd`;
- `scripts/research/ecology/plant_establishment_seed_bank_v1.gd`;
- `scripts/research/ecology/plant_establishment_seed_bank_experiment_v1.gd`;
- `tests/research/ecology/eco_evo1_p2_2_establishment_seed_bank_acceptance.gd`;
- `tests/research/ecology/eco_evo1_p2_2_restart_replay_probe.gd`;
- `RUN_ECO_EVO1_P2_2_TESTS.ps1`.

Accepted P2.1/CAL1 sources and runtime paths are unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_2_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
P2.2 = IMPLEMENTED_CANDIDATE
P2.2 != ACCEPTED
P2.3 = BLOCKED
```
