# ECO.EVO1 / P2.3 — Local Population Turnover + Succession — REPAIRED CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / PARSER REPAIR APPLIED / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation origin: `b8d6553df911a4eca9765509c018987fe9f5cd4b`.

Parser repair: `87c7838f9d476735ef92db0d662290b58861cd56`.

Parent: `ECO.EVO1/P2.2 ACCEPTED`, aggregate `633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86`.

## Exact Windows finding

Первый exact Windows запуск дошёл до P2.3 и остановился до исполнения модели на GDScript parse error:

```text
Parse Error: The member "Engine" shadows a native class.
```

Finding относится только к preload alias в `plant_local_population_succession_experiment_v1.gd`.

Repair:

```text
Engine -> PopulationEngine
```

Расчёты, causal coefficients, succession experiment, acceptance thresholds, P2.2 parent hash и P2.4 boundary не изменялись.

## Purpose

P2.3 is the first repeated local population engine. It connects accepted recruitment/seed-bank cohorts to adult cohort aging, resource-causal growth, mortality, repeated local reproduction and changing lineage abundance through time.

It is still a single local domain. It does not move a population to neighbouring patches; that remains P2.4.

## Adult cohort truth

Adult state remains cohort-based:

```text
lineage_id
genome_checksum
recruitment_traits_checksum
age_years
biomass_kg_m2
origin_recruit_count
position
source_hash
```

## Turnover

```text
baseline survival = exp(-1 / lifespan)
stress survival   = exp(-0.24 * max(-net_resource_balance, 0))
vegetative growth = positive_net * growth_rate * surviving_biomass * 0.20
```

P2.3 reuses the existing P1 patch capacity `8.0 kg/m²` and the existing research turnover coefficients rather than creating duplicate calibration truth.

## Repeated local reproduction

```text
adult cohort aggregate
  -> CAL1-D maturity/reserve seed output
  -> P2.1 dispersal packets
  -> P2.2 recruitment + seed bank
  -> new local adult cohorts / persistent bank
```

Outside-domain seeds remain export accounting only.

## Succession control

- `EARLY`: fast growth, short lifespan, low dormancy, low shade tolerance;
- `BANKED`: slower growth, long lifespan, high dormancy/long bank, high shade tolerance.

Both start under open light. At year 4 the succession run enters deep shade while an open control remains unchanged.

Required evidence remains unchanged:

- EARLY leads initially;
- BANKED gains share after shade transition;
- BANKED final share under shade history exceeds open control;
- seed bank reactivation > 0;
- adult reproduction events > 0;
- matched short lifespan has higher cumulative adult mortality than matched long lifespan;
- biomass and cohort counts stay bounded;
- same-process and fresh-process hashes match exactly.

## Repair boundary

Original implementation diff:

`ec1a7aa8... -> b8d6553d...` adds exactly five P2.3 files.

Repair diff:

`39ceac44... -> 87c7838f...` modifies exactly one P2.3 experiment file and only renames a preload alias.

Accepted P2.2/P2.1/CAL1 and runtime paths remain unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_3_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
P2.3 = REPAIRED_IMPLEMENTED_CANDIDATE
P2.3 != ACCEPTED
P2.4 = BLOCKED
```
