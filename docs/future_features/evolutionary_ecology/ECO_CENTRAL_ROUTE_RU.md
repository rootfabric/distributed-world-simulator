# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO1 P2.1 IMPLEMENTED CANDIDATE / EXACT WINDOWS GATE`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.

## Accepted foundation

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F classification     ROBUST_UNITY_CALIBRATION
```

Canonical CAL1-F aggregate:

`f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed`.

EVO0 / Plant Causal Ecology Foundation is complete.

## Central route

```text
EVO0 / CAL1 COMPLETE
   ↓
EVO1 / P2.1 ← CURRENT CANDIDATE GATE
Seed Dispersal Kernel
   ↓ PASS
P2.2 Establishment / Recruitment / Seed Bank
   ↓
P2.3 Local Population Turnover + Succession
   ↓
P2.4 Patch Colonization / Isolation / Migration
   ↓
P2.5 Disturbance + Recovery
   ↓
P2.6 Long-Horizon Biogeography
   ↓
P2.7 Lineage Divergence / Speciation Candidate Diagnostics
   ↓
P2.8 Deterministic Save/Restart Plant World Proof
```

EVO1 final acceptance:

`NO_BIOME_SPECIES_TABLES_AND_MULTIPLE_CAUSALLY_EXPLAINABLE_PERSISTENT_COMMUNITIES`.

## P2.1 implementation

Implementation head: `5a325549dd2b8bca64437fd42c549d798e7e3905`.

Implementation diff from accepted CAL1 closure adds exactly five ECO files and modifies no accepted CAL1 source or runtime path.

### Cohort truth

P2.1 never creates planet-scale individual seed entities. One reproduction event is represented as a bounded set of seed packets. Default packet count is at most 16.

Each packet preserves:

```text
lineage_id
genome_checksum
reproduction_event
seed_count
source position
destination position
local or long-tail stratum
inside or outside current domain
```

### Transport scale

Accepted lifecycle release-height semantics are reused:

```text
effective dispersal distance
= inherited seed_dispersal_distance_m
× sqrt(release_height_m)
```

Controlled exact checks are `30m / 5m -> 6×` mean distance and `4m / 1m release height -> 2×` mean distance.

### Radial transport

The deterministic stratified kernel contains a local core and explicit long-tail strata. It does not query a biome, species name or target habitat table.

Different reproduction event hashes change spatial phase/jitter while preserving the same transport scale.

### Directional environment projection

The kernel accepts a dimensionless transport vector and turbulence. This is not a private wind/weather foundation; it is a projection seam for later canonical ENV/WQ integration.

East and west vectors must produce opposite mean transport directions. Higher turbulence must weaken matched directional bias.

### Conservation and domain boundaries

Seeds leaving the current domain remain explicit output:

```text
emitted
= transported
= inside + outside
= local + long-tail
```

This is required for later regional/planet migration rather than silently treating domain exit as death.

### Strict P2.2 boundary

P2.1 does not decide:

- germination;
- establishment;
- seed-bank survival;
- carrying capacity;
- recruitment competition;
- local mortality.

Those enter only in P2.2.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_1_TESTS.ps1 -GodotPath $Godot
```

Runner first repeats the full accepted CAL1-F chain, then P2.1 acceptance and two fresh-process replay probes.

Until PASS:

```text
P2.1 = IMPLEMENTED_CANDIDATE
P2.1 != ACCEPTED
P2.2 = BLOCKED
```

## Global boundary

Standalone EVO remains research-only. P2.1 owns ecological dispersal semantics and portable propagule cohort meaning, not canonical spatial/weather/runtime foundations. `XFER1/LIVE` remain deferred until their global contracts exist.

Current resolver: `RUN EVO1/P2.1 EXACT WINDOWS SEED DISPERSAL GATE`.
