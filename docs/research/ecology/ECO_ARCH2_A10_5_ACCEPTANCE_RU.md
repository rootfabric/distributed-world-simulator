# ECO ARCH2 A10.5 / ECO-POLYGON-1 — Acceptance Report (P13, финальная фаза)

Статус: **REPAIR R2 CANDIDATE — implementation complete, exact verification pending**. Дата: 2026-09-22.
Ветка: `repair/eco-arch2-a10-5-polygon-r2`. R2 base: `8c42844e9285dbc145bb32566533009e75e1bf17` (R1 retrain). `origin/main` = `e200a61cb55930378d11c39dcc5950cf49db603c`.

## 1. Окружение

- Godot: `4.7.1.stable.double.custom_build.a13da4feb`,
  SHA256 `3633C3E609C8CE2F9BAE334A9C7E75C7F974DE3AF0415AB4A8050A625A15A7A5`
  (`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`).
- Точный HEAD/TREE на момент acceptance — см. раздел 6 (фиксируется коммитами P13).

## 2. Запуск

```powershell
# GUI: ручная проверка lab-сцены
.\RUN_ECO_A10_5_POLYGON.ps1
# Полный headless-прогон всех тестов сьютa (тяжёлым даётся 900s)
.\RUN_ECO_A10_5_POLYGON.ps1 -Test
# Один тест
.\RUN_ECO_A10_5_POLYGON.ps1 -Test test_manifest
```

Тесты: `validation/ecology/evo_arch2_a10_5/test_*.gd` (Godot `--headless --script`,
Start-Process + `--log-file` + таймаут-watchdog; логи в `artifacts/runtime/eco-a10-5-polygon/`).

## 3. R2 verification matrix

R1 имел локальный evidence `15/15 PASS, 1641 checks`, но этот счётчик **не переносится автоматически на R2**: R2 усиливает P1/P4/P8/P9/P12/P13 и добавляет новые adversarial assertions. Канонический R2 count фиксируется только после exact Windows run на frozen HEAD.

R2 suite: `test_manifest`, `test_controller_equivalence`, `test_lab_scene`, `test_placement_environment`, `test_time_controls`, `test_generic_realizer`, `test_editor`, `test_persistence`, `test_organization_profile`, `test_observatory`, `test_batch_compare`, `test_world_compat`, `test_portability`, `test_runtime_single_state`, `test_final_polygon_e2e`.

Дополнительные R2 gates: Project Control, затем Fresh Reviewer и Fresh Verifier. На незамороженном HEAD результат exact не считается closure evidence.

## 4. Acceptance gates (roadmap R2 §8) — статусы

| Gate | Статус | Подтверждение |
|---|---|---|
| Polygon использует real A1–A10 contracts, не дубликаты | PASS | owner map (`ECO_ARCH2_A10_5_OWNER_MAP_RU.md`); все переходы в `experiment_controller_v1.gd` идут через canonical API; test_lab_scene проверяет отсутствие biology truth в node state |
| Genome editor проходит canonical validation | PASS | test_editor (P7, 78 checks): A3 mutate/crossover/delete_rule + validate; никаких bypass-правок |
| Placement/environment edits детерминированы и versioned | PASS | test_placement_environment (P4, 54); immutable manifest patch, canonical hash меняется |
| Одинаковый manifest + seed → одинаковый результат | PASS | test_controller_equivalence (P2); batch determinism в test_batch_compare; portability-базелин |
| save → restore продолжает ту же историю | PASS | test_persistence (P8): restore + 8 == непрерывные 16 тиков |
| save → fork создаёт связанную отдельную историю | PASS | test_persistence; test_final_polygon_e2e S17 (после ремонта fork-env-patch, см. §5) |
| Replay исходной ветки совпадает | PASS | test_persistence; test_final_polygon_e2e S18 (identical hash) |
| Visualization не меняет simulation state | PASS | test_portability §27 (52 checks): OFF / LOW / HIGH / inspector open / closed → одинаковый hash; test_generic_realizer, test_organization_profile |
| `VISUAL_ONLY` profile не меняет canonical ecology/BodyGraph hash | PASS | test_organization_profile (P9); test_final_polygon_e2e S19 |
| `FREE` работает без обязательных archetype labels | PASS | test_final_polygon_e2e S1; test_organization_profile |
| Неизвестная BodyGraph topology имеет Generic Realizer fallback | PASS | test_generic_realizer (P6, 94); test_final_polygon_e2e S12 (all-roles программа + invented unknown role) |
| Specialized Realizer не является условием validity | PASS | test_generic_realizer: universal adapter fallback для любых примитивов |
| `DEVELOPMENT_BIAS` явно в manifest/provenance, детерминирован при seed | IMPLEMENTED R2 (exact pending) | A3 `genome_mutation_v1` принимает versioned operator reweighting только над закрытым `OPERATORS`; SOFT/EARTH_LIKE/NMS_LIKE исполняются через shared runtime + A5 mutation receipt; неизвестный оператор fail-closed |
| Смена organization profile не маскируется под genome/environment | PASS | profile — отдельное manifest-поле; blocked-статусы не трогают canonical state (нет state hashes) |
| Morphotype labels не пишутся в genotype и не влияют на reproduction | PASS | test_observatory (P10, 207 checks): analytics-only toggle |
| Batch comparison сохраняет все seeds, без скрытого winner | PASS | test_batch_compare (P11, 106); test_final_polygon_e2e S20 |
| Resource/material balances не ломаются | PASS | test_world_compat E (matter accounting == LAB totals); test_batch_compare |
| WORLD-COMPAT не обходит owner/epoch/Region/Matter правила | PASS | test_world_compat (P12, 110): ACTIVE-only, fail-closed, explicit-only mapping, dual-truth rejection, handoff seam, damage overlay |
| Экспортированный experiment пригоден для simulator integration | PASS | test_portability (§26): тот же workbench в двух host-композициях; WORLD_COMPAT route в test_world_compat/test_final_polygon_e2e S21 |
| Fresh independent review: нет polygon-only biological truth | PENDING (вне P13-исполнителя) | реализация + сьют чисты по owner map; independent review — отдельная роль по harness-процессу |

### Минимальный пользовательский сценарий (§31, roadmap §7) — R2

`test_final_polygon_e2e.gd`: FREE experiment → несколько founders → structural variant через canonical A3 → WET/DRY/DARK → placement → run/growth/resource consumption → **реальное reproduction + receipt-backed inherited mutation** → **реальная starvation death в Polygon controller → corpse return → decomposition/mineralization** → unknown topology через Generic Realizer → inspector → caller-anchored checkpoint/restore/fork/replay → canonical DEVELOPMENT_BIAS → batch seeds → WORLD-COMPAT handoff + persistent damage overlay.

## 5. Известные канонические ограничения и gaps (сводка из P-отчётов)

1. ~~**A5 witness / mutated-genome fallback** (P2, наблюдается в P10/P13)~~ — **ИСПРАВЛЕНО в REPAIR R1** (`repair/eco-arch2-a10-5-polygon-r1`): мутированный геном входит в линию ТОЛЬКО через canonical sealed mutation receipt (`genome_mutation_receipt_v1.gd`) + canonical A5 admission; fallback на родительский геном удалён (fail-closed). Durable provenance хранится в состоянии ребёнка (`mutation_receipt`) и перепроверяется при каждой валидации. См. `ECO_ARCH2_A10_5_OWNER_MAP_RU.md` §4.
2. ~~**A6 `MAX_STEPS=64` и O(n²) рост**~~ — **снято с controller-пути в REPAIR R1**: полигон исполняется через shared `EcologyRuntimeV1` (per-step conservation + integrity seal вместо полного replay-доказательства на каждом шаге); старый public `Feedback.advance` сохранён для прежних callers без изменений. Batch-горизонт 32 остаётся политикой runner'а, не каноническим пределом.
3. ~~**DEVELOPMENT_BIAS profile blocked**~~ — **ИСПРАВЛЕНО R2**: A3 получил versioned bias contract, который только перевзвешивает уже разрешённые `OPERATORS`; A5 принимает реально мутированный child только через sealed mutation receipt. Polygon не содержит отдельного mutation engine.
4. **ROLES — закрытый canonical список ролей** (A1/A2): workbench только
   проецирует роли (`MorphologyDescriptor.ROLE_CLASSES`); неизвестные роли
   отображаются нейтральным цветом (`unknown`), новые роли требуют
   canonical-расширения.
5. **Matter→signal mapping отсутствует** (P12): в WORLD_COMPAT сигналы
   (light/temperature) остаются явными декларациями manifest; только stocks
   приходят из matter mapping (fail-closed, zero zone stocks).
6. ~~**Workbench-owned persistence / snapshot gap**~~ — **ИСПРАВЛЕНО R2**: добавлен shared `ecology_runtime_checkpoint_v1.gd` поверх единого `EcologyRuntimeV1`. Он использует A8-style external-anchor admission и не принадлежит workbench biological truth. WORLD-COMPAT authority state переносится отдельным opaque, hash-bound payload (Region/cursor/Matter/site/damage). Исторический `snapshot_seam_v1` не переписывается.
7. ~~**Death недостижим в Polygon LAB**~~ — **ИСПРАВЛЕНО R2**: manifest получил опциональный canonical input `genesis.founder_endowment`. P13 запускает zero-water/energy founder с corpse material, наблюдает starvation death, A6 corpse registration/return и mineralization на том же single canonical field.
8. ~~**Manifest/A4 stock bounds mismatch**~~ — **ИСПРАВЛЕНО R2**: controller использует `FieldContract.MAX_CELL_STOCK`; значения больше одного `MAX_REQUEST` детерминированно режутся на bounded effects, а genesis коммитится per-cell, чтобы не превышать A4 `MAX_BATCH`. P4 имеет high-stock regression.
9. ~~**P9 DEVELOPMENT_BIAS extension doc**~~ — **РЕАЛИЗОВАНО R2**; документ сохранён как design/implementation record и обновлён до фактического API.
10. **Batch runner не принимает founder registry** (P13): batch-манифесты
    должны быть self-contained (inline genomes); registry-ссылки разрешаются
    только в интерактивном controller-пути.

### Ремонт в P13

- **fork() env-patch дефект** (`experiment_branch_v1.gd`): раньше branch
  контроллер инициализировался уже патченным манифестом, поэтому
  `apply_field_patch` считал stock-дельты против патченных значений (дельта 0)
  — stock-патчи молча не доходили до live field (P8-сьют покрывал только
  signal-патчи, которые идут через `set_cell_signals` без дельт). Исправлено:
  initialize по исходному манифесту, `apply_field_patch` сам выполняет
  immutable-переключение манифеста + канонические дельты. Регрессия
  test_persistence PASS; новый кейс — test_final_polygon_e2e S17.

## 6. Что не покрыто и почему

- **Independent fresh review** — по harness-процессу выполняется отдельной
  ролью (Verifier/Reviewer), не самим исполнителем P13.
- **GUI-ручные шаги сценария §31** (визуальный осмотр роста/морфологии) —
  автоматизированы headless-эквиваленты (§27 изоляция презентации);
  ручная проверка — через `RUN_ECO_A10_5_POLYGON.ps1` (GUI lab-сцена).
- **Миллионные популяции / бесконечная эволюция** — осознанно вне scope A10.5
  (roadmap §9).
