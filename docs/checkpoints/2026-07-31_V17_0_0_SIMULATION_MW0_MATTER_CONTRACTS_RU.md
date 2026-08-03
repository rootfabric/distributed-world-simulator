# v17.0.0 — Simulation MW0 Matter Contracts

Дата: `2026-07-31`  
Статус поставки: `CANDIDATE FOR INDEPENDENT REVIEW`  
Base checkpoint: `v16.10.6-architecture-a3-single-server-multiplayer`  
Рекомендуемая ветка: `feature/mw0-matter-contracts`  
Build ID: `mw0-matter-contracts`

## Решение

Начат отдельный geological/mutable-worlds track, который не меняет production gameplay path и текущие поверхности Земли/Луны.

Первый checkpoint реализует чистые канонические контракты `Dynamic Matter Fabric`:

```text
material catalog
→ composition
→ matter sample
→ body definition
→ sparse brick identity/snapshot
→ mutation request/result
→ mass ledger
```

## Реализовано

- `MatterMaterialDefinition` с явными SI-единицами;
- детерминированный каталог семи начальных материалов;
- нормализованный состав вещества;
- occupied/vacuum sample invariants;
- `MatterBodyDefinition` с frozen generator identity;
- адрес brick поверх существующего `SimulationCellAddress`;
- раздельные geometry/composition/property channels;
- checksum-protected snapshots;
- revision-fenced mutation requests;
- committed/rejected results;
- обязательный закрытый mass ledger для commit;
- focused Linux/Windows runners;
- property и negative tests;
- machine-readable MW0 manifest.

## Фиксированный fixture следующего этапа

```text
body_id:             body/asteroid-mw0
body_frame_id:       body/asteroid-mw0/fixed
reference_radius_m:  1000
seed:                2026073101
generator_version:   1.0.0
```

Этот checkpoint только фиксирует identity fixture. Форма и геология появятся в MW1.

## Границы поставки

Не изменены:

- `procedural_moon_terrain.gd`;
- current Moon/Earth world configs;
- runtime composition roots;
- networking/authority implementation;
- Item Graph;
- render и collision layers.

Таким образом MW0 можно независимо принять, отклонить или доработать без риска для текущей игровой ветки.

## Проверка

Focused commands:

```powershell
./RUN_MW0_MATTER_CONTRACTS_TESTS.ps1
```

```bash
./RUN_MW0_MATTER_CONTRACTS_TESTS.sh
```

Статический delivery gate также проверяет:

- JSON manifests;
- preload targets;
- отсутствие unsafe paths;
- отсутствие конфликтных маркеров;
- отсутствие production runtime modifications;
- whitespace/archive manifest.

Фактические Godot assertion totals фиксируются при независимом запуске focused runner на double build.

## Acceptance criteria

1. Focused MW0 runner завершён с exit code `0`.
2. Все contract/property assertions проходят.
3. Runtime/presentation objects отклоняются.
4. Незамкнутый mass ledger не допускает committed result.
5. Checksum и revision mutation обнаруживаются.
6. Existing Moon/main runtime regression не изменился, поскольку его файлы не затронуты.
7. Архив содержит только изменённые файлы с исходными путями.

## Следующий checkpoint

```text
MW1
branch: feature/mw1-fixed-seed-asteroid
checkpoint: v17.0.1-simulation-mw1-fixed-seed-asteroid
scope: deterministic observer-independent 1000 m asteroid sampler
```

Review corrections текущего MW0 должны оставаться на `feature/mw0-matter-contracts` до приёмки checkpoint.
