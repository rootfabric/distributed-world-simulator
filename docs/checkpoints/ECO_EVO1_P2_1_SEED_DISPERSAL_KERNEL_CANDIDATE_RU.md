# ECO.EVO1 / P2.1 — Seed Dispersal Kernel — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `5a325549dd2b8bca64437fd42c549d798e7e3905`.

Parent: `ECO.CAL1-F ACCEPTED`, aggregate `f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed`, classification `ROBUST_UNITY_CALIBRATION`.

## Purpose

P2.1 is the first EVO1 checkpoint that moves ecological propagules through space. It does not establish plants and does not update population abundance. Its only responsibility is deterministic seed transport from a reproductive source into bounded spatial cohort packets.

The old P1C dynamic-abundance fixture advances biomass independently inside patches; it does not transport lineage propagules between patches. P2.1 therefore fills a genuinely missing mechanism rather than rebranding old patch dynamics.

## Truth granularity

Planet-scale truth is not one entity per seed.

A reproduction event produces at most a bounded number of packets. Each packet carries:

```text
seed_count
lineage_id
genome_checksum
reproduction_event
source_position
destination_position
distance
local/long-tail classification
inside/outside-domain classification
packet_hash
```

Canonical default is at most `16` packets per event, with hard research limit `64`.

## Distance semantics

P2.1 inherits the accepted CAL1-D release-height relation:

```text
effective_distance_scale
= inherited seed_dispersal_distance_m
× sqrt(release_height_m)
```

The radial kernel is stratified. Most packet strata form a local core; the highest `15%` radial strata are an explicit long-tail component. This gives local recruitment opportunity plus rare longer-range movement without a biome/species placement table.

## Deterministic spatial realization

The reproduction event, lineage, genome checksum and source position deterministically define a spatial phase. Packet strata cover the kernel deterministically; event-specific hashes rotate/jitter the realization without changing the inherited transport scale.

The same inputs must reproduce the exact same packet hashes and aggregate hash in the same process and in fresh Godot processes.

Different reproduction events must produce different deterministic spatial realizations.

## Anisotropic transport context

P2.1 deliberately does not create a private weather system.

Input context is:

```text
transport_vector : Vector2, magnitude <= 1
    direction = preferred environmental transport direction
    magnitude = dimensionless transport bias strength

turbulence : 0..1
optional domain bounds
```

This is a research projection contract. A future canonical ENV/WQ path may derive it from wind/topography without changing seed-dispersal truth semantics.

Directional bias is mixed with stratified isotropic directions. Increasing turbulence weakens the matched directional bias rather than inventing random seed loss.

## Conservation and boundaries

For every event:

```text
emitted seeds
= transported seeds
= inside-domain seeds + outside-domain seeds
= local seeds + long-tail seeds
```

Leaving the currently modeled domain is not extinction. Outside-domain packets remain explicit transport output so later regional/planet runners can hand them to adjacent patches/domains.

## Controlled experiment

The acceptance matrix includes:

- still baseline;
- inherited short vs long dispersal (`5m` vs `30m`);
- release height `1m` vs `4m`;
- east and west directional transport;
- low vs high turbulence under the same east bias;
- explicit east-boundary export;
- two different reproduction events.

Key exact controlled expectations:

```text
30m / 5m inherited distance -> mean-distance ratio 6
4m / 1m release height      -> mean-distance ratio sqrt(4) = 2
```

## P2.1 / P2.2 boundary

P2.1 packets contain no:

- establishment probability;
- germination decision;
- seed-bank survival;
- carrying capacity;
- local competition outcome;
- recruitment mortality.

Those semantics belong to `P2.2 Establishment / Recruitment / Seed Bank`.

## Implementation boundary

`98b6a6f5605fcc07ceee74cd853818c610dcc431 -> 5a325549dd2b8bca64437fd42c549d798e7e3905` adds exactly five ECO files:

- `scripts/research/ecology/plant_seed_dispersal_kernel_v1.gd`;
- `scripts/research/ecology/plant_seed_dispersal_experiment_v1.gd`;
- `tests/research/ecology/eco_evo1_p2_1_seed_dispersal_acceptance.gd`;
- `tests/research/ecology/eco_evo1_p2_1_restart_replay_probe.gd`;
- `RUN_ECO_EVO1_P2_1_TESTS.ps1`.

No accepted CAL1 source or runtime path was modified.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_1_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
P2.1 = IMPLEMENTED_CANDIDATE
P2.1 != ACCEPTED
P2.2 = BLOCKED
```

After PASS, `P2.2 Establishment / Recruitment / Seed Bank` may consume these portable seed packets and decide which propagules persist locally.
