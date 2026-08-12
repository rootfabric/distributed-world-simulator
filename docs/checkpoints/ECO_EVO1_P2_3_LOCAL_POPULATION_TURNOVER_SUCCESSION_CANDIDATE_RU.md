# ECO.EVO1 / P2.3 — Local Population Turnover + Succession — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `b8d6553df911a4eca9765509c018987fe9f5cd4b`.

Parent: `ECO.EVO1/P2.2 ACCEPTED`, aggregate `633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86`.

## Purpose

P2.3 is the first repeated local population engine. It connects accepted recruitment/seed-bank cohorts to adult cohort aging, resource-causal growth, mortality, repeated local reproduction and changing lineage abundance through time.

It is still a single local domain. It does not move a population to neighbouring patches; that remains P2.4.

## Adult cohort truth

Adult state is cohort-based:

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

New recruits are collapsed by lineage/year into bounded cohorts. The model never promotes planet-scale individual plant entities.

## Turnover

Each annual step evaluates the accepted ResourceModel against total local biomass.

```text
baseline survival = exp(-1 / lifespan)
stress survival   = exp(-0.24 * max(-net_resource_balance, 0))
vegetative growth = positive_net * growth_rate * surviving_biomass * 0.20
```

The `0.24` stress and `0.20` vegetative coefficients intentionally reuse the existing P1 single-patch research fixture rather than inventing a second turnover calibration.

Shared biomass capacity reuses `single_plant_patch_simulator_v1.gd::MAX_BIOMASS_KG_M2` (`8.0`). If proposals exceed it, all local adult cohort biomass is scaled proportionally. This is local density competition, not a species table.

## Repeated local reproduction

Once a lineage aggregate matures, P2.3 calls the accepted CAL1-D lifecycle path to determine bounded realized annual seed output, then feeds that output through the exact accepted chain:

```text
adult cohort aggregate
  -> CAL1-D maturity/reserve seed output
  -> P2.1 dispersal packets
  -> P2.2 recruitment + seed bank
  -> new local adult cohorts / persistent bank
```

Seeds leaving the local domain are counted as export and are not inserted elsewhere. P2.4 will own inter-patch transfer.

## Succession experiment

Two causal strategies are compared:

- `EARLY`: fast growth, short lifespan, low dormancy, low shade tolerance;
- `BANKED`: slower growth, long lifespan, high dormancy/long bank, high shade tolerance.

Both begin in an open/high-light environment. At year 4 the succession run changes to deep shade while an open control remains unchanged.

Required directional evidence:

- EARLY has larger initial biomass share;
- BANKED gains share after the shade transition;
- BANKED final share is higher under the shade schedule than under the open control;
- existing seed bank reactivates into recruits;
- adult cohorts produce additional reproduction events beyond the founder pulse;
- matched short-lifespan control accumulates more adult turnover than matched long-lifespan control;
- local biomass never exceeds the accepted shared capacity;
- adult and seed-bank cohort counts stay bounded;
- same-process and fresh-process hashes match exactly.

`top_lineage_changed` is reported diagnostically but is not itself required; succession is measured continuously by lineage abundance shares rather than by a hard winner switch.

## Strict P2.4 boundary

P2.3 contains no migration graph, neighbour patch routing, colonization topology or cross-domain population insertion. Export is accounting only.

It also does not introduce the explicit disturbance-event scheduler of P2.5.

## Implementation boundary

`ec1a7aa8d2e30b876496fd01693d1a6a0257c4dd -> b8d6553df911a4eca9765509c018987fe9f5cd4b` adds exactly five ECO files and modifies no accepted P2.2/P2.1/CAL1 source or runtime path.

## Validation authority

A full local checkout could not be obtained in the assistant environment because GitHub DNS resolution is unavailable. No local full-source PASS is claimed.

Canonical authority is the exact Windows runner:

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_3_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
P2.3 = IMPLEMENTED_CANDIDATE
P2.3 != ACCEPTED
P2.4 = BLOCKED
```
