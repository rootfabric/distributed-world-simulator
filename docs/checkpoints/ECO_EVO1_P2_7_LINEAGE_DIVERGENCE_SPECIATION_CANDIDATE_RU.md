# ECO.EVO1 / P2.7 — Lineage Divergence / Speciation Candidate Diagnostics — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `8da9c039a8591d61a0d542aa4e4695a51a9d20d6`.

Parent: `ECO.EVO1/P2.6 ACCEPTED`, aggregate `3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c`.

## Purpose

P2.7 adds a diagnostic layer for lineage divergence. It does **not** implement a canonical taxonomy and does not assign a species identifier.

Inputs are explicit evidence dimensions:

```text
shared ancestry / split chronology
inherited PlantGenome difference
recruitment-trait difference
patch occupancy history
post-split spatial isolation
observed connection years
ecological-history difference
```

Output preserves those dimensions separately. There is no hidden weighted `speciation score` and no fitness aggregation.

## Research candidate policy

The current detector exposes explicit research thresholds:

```text
MIN_SPLIT_AGE_YEARS = 12
MIN_ISOLATION_FRACTION = 0.75
MAX_CONNECTION_FRACTION = 0.10
MIN_GENOME_DISTANCE = 0.18
MIN_ECOLOGICAL_HISTORY_DISTANCE = 0.10
```

These are **candidate-detection policy**, not universal biological constants. They may later be replaced/calibrated by empirical domain evidence. A positive result means only `SPECIATION_CANDIDATE` and always carries `canonical_species_declared=false`.

Recruitment-trait distance is reported independently and intentionally is not a mandatory gate in this first detector.

## Distance semantics

Genome distance is the mean of bounded symmetric relative differences across the accepted PlantGenome fields:

- height;
- growth rate;
- root depth;
- water preference/tolerance;
- shade tolerance;
- seed count;
- dispersal distance;
- lifespan.

Ecological-history distance is the post-split mean difference across accepted EnvironmentSample dimensions: temperature, soil moisture, sunlight, nutrients and flood frequency.

Spatial isolation and connection evidence are counted only during post-split years in which both lineages are present.

## Controlled contrast matrix

All cases preserve common ancestry where applicable:

```text
ISOLATED_DIVERGED
  long split age
  disjoint patches
  no connection years
  strong genome difference
  distinct ecological history
  => MUST be SPECIATION_CANDIDATE

CONNECTED_DIVERGED
  same genome/ecology divergence
  same split age/isolation geometry
  connection every post-split year
  => MUST NOT be candidate

ISOLATED_SIMILAR
  long isolation
  no connection
  near-identical genome
  same ecological history
  => MUST NOT be candidate

RECENT_DIVERGED
  genome/ecology divergence + isolation
  split age only 3 years
  => MUST NOT be candidate
```

Thus geography alone, trait distance alone, or a recent dramatic phenotype difference cannot create a candidate.

## Strict ownership boundary

P2.7 does not:

- create `species_id`;
- create a species placement table;
- infer species from biome;
- implement reproduction compatibility or mating mechanics;
- claim canonical taxonomy;
- implement mutation/selection dynamics that force a target divergence;
- modify accepted P2.6-or-earlier ecology semantics.

P2.7 diagnoses observed lineage endpoints/history only. A later evolutionary engine may generate those endpoints causally; this checkpoint does not fake that mechanism.

## Implementation boundary

`a47127b09dde280525bf5e076b8e3a99d8a7d9a9 -> 8da9c039a8591d61a0d542aa4e4695a51a9d20d6` is exactly one commit adding five files:

- `scripts/research/ecology/plant_lineage_divergence_diagnostics_v1.gd`;
- `scripts/research/ecology/plant_lineage_divergence_experiment_v1.gd`;
- `tests/research/ecology/eco_evo1_p2_7_lineage_divergence_acceptance.gd`;
- `tests/research/ecology/eco_evo1_p2_7_restart_replay_probe.gd`;
- `RUN_ECO_EVO1_P2_7_TESTS.ps1`.

Accepted P2.6-or-earlier source and runtime paths are unchanged.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_7_TESTS.ps1 -GodotPath $Godot
```

The runner performs parser/preload preflight, full accepted P2.6 regression, P2.7 acceptance, and two fresh-process replay probes.

Until PASS:

```text
P2.7 = IMPLEMENTED_CANDIDATE
P2.7 != ACCEPTED
P2.8 = BLOCKED
```
