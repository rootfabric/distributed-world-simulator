# ECO.EVO7 LS3.0 + LS3.1 — Planet Patch + Environment Generator R1 — CANDIDATE

Base planning checkpoint: `05a564f1c49622e78333935f893a14bf268b055b`.

Этот candidate реализует только первый spatial slice LS3. Spatial population, dispersal, recruitment, competition и emergent-biome classifier здесь ещё не активированы.

## LS3.0 — contiguous real-planet patch

- единый `32 x 32` grid, 1024 cell;
- cell size `16 m`, nominal width `512 m`;
- center direction берётся из `ProceduralEarthWorld`;
- координаты cell строятся в tangent east/north basis на сфере через angular offset;
- каждая cell читает только whitelist обязательных физических полей существующего Earth pipeline;
- ecological elevation реконструируется из pre-biome `base_elevation_m` + физических river/lake depth fields; downstream `surface_composer.elevation_m` намеренно не используется;
- сохраняются land/water masks, temperature, moisture, aridity и derived slope/aspect;
- legacy biome labels и vegetation presets в patch state не копируются;
- canonical cell/patch hashes детерминированы и инвариантны к порядку cell array;
- `validate_patch()` fail-closed проверяет topology (`index <-> x/y`), completeness, finite/bounded physical values, каждый `cell_hash` и общий `patch_hash`.

## LS3.1 — physical environment generator

Добавлен RAM-only deterministic high-frequency environment layer поверх real planet anchor.

R1 recipes описывают только физические forcing-параметры:

- `WATER_GRADIENT_STRONG`;
- `RELIEF_DRAINAGE_STRONG`;
- `MIXED_PHYSICAL_HETEROGENEITY`.

Генерируются rainfall forcing, surface-water fraction, soil moisture, sand/clay/loam fractions, water retention, local relief, drainage, incident light, temperature и stable environment hashes.

Environment generator принимает только patch, успешно прошедший `PlanetPatch.validate_patch()`. Stale/tampered/non-finite patch отклоняется до генерации environment field.

Ни recipe id, ни cell/environment identity не связаны с mutation/reproduction path. В этом slice вообще нет reproduction/mutation call site.

## Visual workbench

`eco_evo7_ls31_spatial_patch_lab.tscn` показывает один цельный 32x32 patch.

Controls: `1` moisture, `2` elevation, `3` soil, `4` light, `5` water, `R` cycle physical recipe.

Это read-only physical workbench. Растения будут подключаться только на LS3.2 после отдельного acceptance этого слоя.

## Focused exact-Godot evidence

Engine: `4.7.1.stable.double.custom_build.a13da4feb`.

До fail-closed hardening predecessor candidate прошёл:

- LS3.0/LS3.1 acceptance: `PASS (11358 assertions)`;
- headless spatial patch lab smoke: `PASS cells=1024`.

Текущий fail-closed delta отдельно выполнен на том же exact double build и на байтах, публикуемых в candidate:

- `eco_evo7_ls31_failclosed_acceptance.gd`: `PASS (14 checks)`;
- valid build/generate path проходит;
- reversed cell order валиден и даёт тот же field identity;
- stale cell hash отклоняется;
- out-of-range index отклоняется даже после пересчёта hashes;
- `index <-> x/y` mismatch отклоняется;
- NaN physical cell отклоняется;
- non-finite и missing required source fields fail-closed до materialization;
- EnvironmentField не принимает tampered/non-finite patch.

`RUN_ECO_EVO7_LS31_TESTS.sh` теперь включает inherited LS2.1 chain, основной LS3.0/LS3.1 acceptance, отдельный fail-closed acceptance и headless workbench smoke.

Полный exact-repository runner должен быть заново выполнен на новом immutable candidate после публикации branch. Этот документ не подменяет fresh Reviewer/Verifier и не заявляет production acceptance.

## Authority boundary

```text
world_write                  = false
ecology_production_write     = false
persistence_write            = false
network_replication_write    = false
xfer_authority               = false
alternate_mutation_authority = false
```

Следующий разрешённый слой после отдельного acceptance LS3.0/LS3.1: **LS3.2 Spatial Cohort Lattice**.
