# Checkpoint v17.2.0 — MW2 sparse bricks and canonical query

**Checkpoint:** `v17.2.0-simulation-mw2-sparse-bricks`
**Build ID:** `mw2-sparse-bricks`
**Base:** accepted `v17.1.0-simulation-mw1-fixed-seed-asteroid`
**Branch:** `feature/mw2-sparse-bricks`
**Delivery status:** `CANDIDATE FOR INDEPENDENT REVIEW`

## Scope

MW2 добавляет materialization boundary поверх неизменённого MW1 procedural asteroid:

- feature-aware validation root bounds;
- checksum-protected matter grid profile;
- body-fixed octree cells через существующий `SimulationCellAddress`;
- один sparse brick на cell;
- lattice `8³` interior cells, `11³` samples с ghost border;
- deterministic `MatterBrickSnapshot` materializer;
- revision-fenced in-memory sparse store;
- checksum-protected query result;
- canonical query service с procedural fallback;
- focused property/seam/storage/query tests.

## Explicit non-scope

```text
Moon runtime changes:          no
world catalog changes:         no
mesh or collision:             no
streaming scene:               no
mutations or excavation:       no
Item Graph transfer:           no
persistence:                   no
network authority:             no
fragmentation:                 no
```

## Fixed fixture

```text
body_id:             body/asteroid-mw0
body_frame_id:       body/asteroid-mw0/fixed
seed:                2026073101
reference_radius_m:  1000
root_half_extent_m:  1450
max_cell_level:      5
interior_resolution: 8
sample_axis_count:   11
ghost_border:        1 sample per side
sample_count:        1331 per materialized brick
```

## Required test command

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_MW2_SPARSE_BRICKS_TESTS.ps1 -GodotPath $godot
.\RUN_MW1_FIXED_SEED_ASTEROID_TESTS.ps1 -GodotPath $godot
.\RUN_MW0_MATTER_CONTRACTS_TESTS.ps1
.\RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1 -GodotPath $godot
.\RUN_M6_DEDICATED_RECOVERY_TESTS.ps1 -GodotPath $godot

git diff --check
```

## Acceptance criteria

1. Focused MW2 runner prints `MW2 sparse bricks and query: PASS`; ожидаемая топология — `7470 assertions`.
2. MW1 remains at `3685 assertions, PASS`.
3. MW0 remains at `2011 assertions, PASS`.
4. A3 remains `12/12 PASS`.
5. M6 remains `10/10 PASS`.
6. Every adjacent shared/ghost sample comparison passes, включая пять вложенных sibling-пар до level 5.
7. Empty service/store allocates no bricks.
8. Stale and same-revision conflicting snapshots are rejected.
9. Exact materialized lattice queries select `MATERIALIZED_BRICK`.
10. Off-lattice queries select `PROCEDURAL_BASE`.
11. Parser/preload and `git diff --check` pass.
12. Existing production worlds remain unchanged.

## Review workflow

Любое исправление, обнаруженное при проверке этой поставки, остаётся в той же ветке:

```text
feature/mw2-sparse-bricks
```

Новая ветка MW3 создаётся только после принятия MW2.
