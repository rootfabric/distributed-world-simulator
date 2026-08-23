# ECO Program Passport R3 Refresh — control-plane reconciliation record

**Дата:** 2026-08-23
**Контекст:** после merge PR #212 (V0 P6) main поднял `architecture_revision` до `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`; Project Control на всех ветках начал сравнивать программные паспорта с новыми требованиями.

## Что случилось

Project Control на голове EVO7-линии (`504b9e28…`) стал **RED по программе ECO**:

1. `PASSPORT_FIELDS_MISSING`: паспорт `feature__eco-evolutionary-ecology.v1.json` не содержал обязательных R3-полей `expected_outcome`, `parent_branch_or_checkpoint`, `base_commit`, `dependencies`, `validation_paths`.
2. `ARCHITECTURE_REVISION_MISMATCH`: паспорт держал `GLOBAL-P0-2026-08-10-R2` против main-овского `R3-REFRESH-R1`.

Причина: аудит программы читает паспорт с её **собственной ветки** `origin/feature/eco-evolutionary-ecology`, которая осталась на старом формате (голова = merge-base `d9e4356e…`). К содержимому EVO7-ветки это отношения не имело.

## Что сделано

- Рефреш паспорта на его собственной ветке (не форс, обычный push): commit `84f217e8` `control(eco): refresh program passport to R3-REFRESH-R1 with required R3 fields`.
  - `architecture_revision` → `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`; `control_plane_revision` без изменений (`PC0-2026-08-10-R1`, совпадает с реестром).
  - Добавлены пять обязательных полей с правдивыми значениями (`expected_outcome` — итоги линии EVO6-WATER + EVO7 FFF0..FFF5; `parent_branch_or_checkpoint` — `ECO.PH5-S4 … RESEARCH COMPLETE`; `base_commit` — `d9e4356e…`; `dependencies` — глобальная ревизия + canonical contracts R3/WQ/MAT/LIFE/WB; `validation_paths` — канонические ECO-раннеры).
  - Central-mirror поля (`current_stage`, `stage_status`, `blockers`, `health_declared`) приведены к реестровым — снимает `CENTRAL_PASSPORT_DRIFT` жёлтые.
  - Реестр (`project-program-registry.v1.json`, main-owned) **не менялся**.
- Локальный прогон трёх harness-модулей совместимости: **ECO переведён из RED в YELLOW** (остался только чужой `DEPENDENCY_DRIFT` по network `.uid`-артефактам); `PASSPORT_FIELDS_MISSING` и `ARCHITECTURE_REVISION_MISMATCH` для ECO отсутствуют.

## Что осталось (вне компетенции EVO7-линии)

- `test_x_historical_r2_and_refreshed_r3_passports_use_correct_compatibility_mode` всё ещё падает из-за **V0 RED** (`CRITICAL_DEPENDENCY_DRIFT` по `scripts/construction/item_graph/*` и `scripts/runtime/networked_gameplay/m4/*`). Это состояние V0-программы после merge P6; ремонт ведётся на `repair/v0-p6-persistence-exactly-once-r1`. До его завершения сводный PC0 может оставаться красным независимо от ECO — зафиксировано как кросс-программная ситуация, не блокирующая research-candidate статусы этапов EVO7.

## Статус EVO7

FFF0..FFF5 — реализованы, review PASS + verification VERIFIED, все принятые хэши воспроизводятся; FFF6 Succession Lab — в реализации по дизайн-доку.
