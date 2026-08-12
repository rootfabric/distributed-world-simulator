# ECO.EVO1 / P2.4 — Patch Colonization / Isolation / Migration — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `01042d585fa46aebe5fde090e217c9fcb58be68f`.

Parent: `ECO.EVO1/P2.3 ACCEPTED`, aggregate `15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e`.

## Purpose

P2.4 converts the P2.3 outside-domain export boundary into explicit **research-scale inter-patch propagule routing**. The destination is determined by the actual `destination_position` produced by accepted P2.1 dispersal packets.

No `species -> patch`, `biome -> species`, generic migration score or hand-authored winner table participates.

## Research patch input

P2.4 introduces a local experiment patch record:

```text
patch_id
Rect2 bounds
environment sample
checksum
```

This is an experiment input only. It does **not** claim canonical simulator Spatial Domain Fabric ownership. Production transfer remains deferred to XFER/global foundations.

## Migration ledger

For each reproduction event:

```text
emitted
=
source-retained
+ routed to known target patch
+ unresolved external export
```

A routed packet keeps lineage/genome/reproduction-event identity and source packet provenance. Its target-local arrival packet is re-hashed after `outside_domain=false`, then is passed through the exact accepted P2.2 settlement kernel.

For every target:

```text
arrived
=
recruited
+ viable seed bank
+ failed/decayed
```

## Controlled isolation experiment

Two lineages have the same morphology, growth, roots, water response, shade tolerance, seed count, lifespan and recruitment traits. They differ only in inherited dispersal distance:

```text
SHORT = 5 m
LONG  = 20 m
```

Source patch:

```text
Rect2(-10,-10,20,20)
```

Eastward targets have identical favourable environment:

```text
NEAR = Rect2(11,-20,24,40)
FAR  = Rect2(50,-40,80,80)
```

Each lineage produces eight deterministic 160-seed reproduction events under the same eastward transport context. A separate long-disperser westward control uses the same east-side targets.

Required causal evidence:

- NEAR receives and recruits SHORT and LONG;
- FAR receives/recruits LONG but not SHORT;
- NEAR has two colonized lineages while FAR has one;
- total recruitment is greater in NEAR than FAR;
- LONG share is higher in isolated FAR than NEAR;
- westward control routes zero seeds into the east-side targets;
- every migration and target settlement ledger conserves integer seed counts;
- same-process and fresh-process hashes match exactly.

This demonstrates distance isolation and transport direction from spatial propagule mechanics rather than species placement rules.

## Strict P2.5 boundary

P2.4 contains no explicit fire/storm/flood disturbance-event scheduler, no disturbance recovery state machine and no recovery chronology. Those begin at `P2.5 Disturbance + Recovery`.

## Implementation boundary

`89aec8f317d8046f86369510e5d685fd6a8f2b06 -> 01042d585fa46aebe5fde090e217c9fcb58be68f` adds exactly five ECO files:

- `scripts/research/ecology/plant_patch_migration_v1.gd`;
- `scripts/research/ecology/plant_patch_colonization_experiment_v1.gd`;
- `tests/research/ecology/eco_evo1_p2_4_patch_colonization_acceptance.gd`;
- `tests/research/ecology/eco_evo1_p2_4_restart_replay_probe.gd`;
- `RUN_ECO_EVO1_P2_4_TESTS.ps1`.

Accepted P2.3/P2.2/P2.1/CAL1 sources and runtime paths are unchanged.

The runner performs parser/preload preflight before the long accepted-parent regression chain.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_EVO1_P2_4_TESTS.ps1 -GodotPath $Godot
```

Until PASS:

```text
P2.4 = IMPLEMENTED_CANDIDATE
P2.4 != ACCEPTED
P2.5 = BLOCKED
```
