# ECO ARCH2 A10.5 / ECO-POLYGON-1 — Acceptance Report (P13, финальная фаза)

Статус: FINAL ACCEPTANCE (P13). Дата: 2026-09-21.
Ветка: `feature/eco-arch2-a10-5-polygon-r1`. Base: `origin/main` = `e200a61cb55930378d11c39dcc5950cf49db603c`.

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

## 3. Итоговая таблица регрессии (полный сьют, 14 тестов)

| Тест | Фаза | Checks | Статус |
|---|---|---|---|
| test_manifest | P1 | 36 | PASS |
| test_controller_equivalence | P2 | 26 | PASS (тяжёлый, ~400s) |
| test_lab_scene | P3 | 453 | PASS |
| test_placement_environment | P4 | 54 | PASS |
| test_time_controls | P5 | 57 | PASS (тяжёлый, ~580s) |
| test_generic_realizer | P6 | 94 | PASS |
| test_editor | P7 | 78 | PASS |
| test_persistence | P8 | 49 | PASS |
| test_organization_profile | P9 | 72 | PASS |
| test_observatory | P10 | 207 | PASS |
| test_batch_compare | P11 | 106 | PASS |
| test_world_compat | P12 | 110 | PASS |
| test_portability | P13 (§26+§27) | 52 | PASS |
| test_final_polygon_e2e | P13 (§31) | 103 | PASS |
| **ИТОГО** | | **1497** | **14 PASS / 0 FAIL** |

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
| `DEVELOPMENT_BIAS` явно в manifest/provenance, детерминирован при seed | PARTIAL — BLOCKED (canonical) | SOFT/EARTH_LIKE/NMS_LIKE → `BLOCKED_CANONICAL_EXTENSION_REQUIRED` + required hook (test_batch_compare e; test_final_polygon_e2e S19); proposal: `ECO_ARCH2_A10_5_P9_DEVELOPMENT_BIAS_EXTENSION_RU.md` |
| Смена organization profile не маскируется под genome/environment | PASS | profile — отдельное manifest-поле; blocked-статусы не трогают canonical state (нет state hashes) |
| Morphotype labels не пишутся в genotype и не влияют на reproduction | PASS | test_observatory (P10, 207 checks): analytics-only toggle |
| Batch comparison сохраняет все seeds, без скрытого winner | PASS | test_batch_compare (P11, 106); test_final_polygon_e2e S20 |
| Resource/material balances не ломаются | PASS | test_world_compat E (matter accounting == LAB totals); test_batch_compare |
| WORLD-COMPAT не обходит owner/epoch/Region/Matter правила | PASS | test_world_compat (P12, 110): ACTIVE-only, fail-closed, explicit-only mapping, dual-truth rejection, handoff seam, damage overlay |
| Экспортированный experiment пригоден для simulator integration | PASS | test_portability (§26): тот же workbench в двух host-композициях; WORLD_COMPAT route в test_world_compat/test_final_polygon_e2e S21 |
| Fresh independent review: нет polygon-only biological truth | PENDING (вне P13-исполнителя) | реализация + сьют чисты по owner map; independent review — отдельная роль по harness-процессу |

### Минимальный пользовательский сценарий (§31, roadmap §7) — автоматизирован

`test_final_polygon_e2e.gd` (103 checks): S1 FREE experiment → S2 два founder'а →
S3 structural variant через genome editor → S4 WET/DRY/DARK → S5 placement
generators (same→разные зоны, разные→одна зона) → S6 run → S7 growth →
S8 потребление ресурсов → S9 reproduction (birth event) → S10 mutation attempt
(+fallback-статус) → S11 death/decomposition (см. §5) → S12 unknown topology
через generic realizer → S13 полный inspector → S14 checkpoint → S15 branch A →
S16 restore → S17 branch B (env patch) → S18 replay identical → S19 SOFT BLOCKED
+ VISUAL_ONLY non-causal → S20 batch 3 seeds полный отчёт → S21 WORLD-COMPAT
handoff + damage overlay.

## 5. Известные канонические ограничения и gaps (сводка из P-отчётов)

1. ~~**A5 witness / mutated-genome fallback** (P2, наблюдается в P10/P13)~~ — **ИСПРАВЛЕНО в REPAIR R1** (`repair/eco-arch2-a10-5-polygon-r1`): мутированный геном входит в линию ТОЛЬКО через canonical sealed mutation receipt (`genome_mutation_receipt_v1.gd`) + canonical A5 admission; fallback на родительский геном удалён (fail-closed). Durable provenance хранится в состоянии ребёнка (`mutation_receipt`) и перепроверяется при каждой валидации. См. `ECO_ARCH2_A10_5_OWNER_MAP_RU.md` §4.
2. ~~**A6 `MAX_STEPS=64` и O(n²) рост**~~ — **снято с controller-пути в REPAIR R1**: полигон исполняется через shared `EcologyRuntimeV1` (per-step conservation + integrity seal вместо полного replay-доказательства на каждом шаге); старый public `Feedback.advance` сохранён для прежних callers без изменений. Batch-горизонт 32 остаётся политикой runner'а, не каноническим пределом.
3. **DEVELOPMENT_BIAS profile**: закрытый список OPERATORS в A3 + A5 witness ⇒
   SOFT/EARTH_LIKE/NMS_LIKE BLOCKED; формальное предложение расширения —
   `ECO_ARCH2_A10_5_P9_DEVELOPMENT_BIAS_EXTENSION_RU.md`.
4. **ROLES — закрытый canonical список ролей** (A1/A2): workbench только
   проецирует роли (`MorphologyDescriptor.ROLE_CLASSES`); неизвестные роли
   отображаются нейтральным цветом (`unknown`), новые роли требуют
   canonical-расширения.
5. **Matter→signal mapping отсутствует** (P12): в WORLD_COMPAT сигналы
   (light/temperature) остаются явными декларациями manifest; только stocks
   приходят из matter mapping (fail-closed, zero zone stocks).
6. **snapshot_seam payload** (P12): A8 `snapshot_seam_v1` ecology payload
   привязан к A7 observatory treatment model и не может нести
   controller field+population+feedback — используется
   `ExperimentController.serialize_state` (P8 envelope) как канонический fit.
7. **Death недостижим в LAB-границах** (P13, зафиксировано в
   `test_final_polygon_e2e.gd` S11): единственные причины смерти — A5
   starvation (maintenance unpaid ≥ 3 тиков) и жёсткий A5_AGE_LIMIT (10⁶);
   founder endowment контроллера (200000 на резерв) покрывает maintenance на
   ~2000+ тиков ≫ MAX_STEPS 64; genome `max_age` останавливает только
   development, не убивает. Decomposition-половина цикла (organic→nutrient
   mineralization) измеряется на ЕДИНОМ canonical field (repair R1);
   реальная смерть + corpse return через canonical runtime API покрыты в
   `test_runtime_single_state.gd` S4; corpse-ветка также покрыта каноническим
   A6-сьютом.
8. **Bounds-расхождение** (P1/P4, зафиксировано): manifest валидирует zone
   stocks по `FieldContract.MAX_CELL_STOCK` (10⁹), а controller genesis — по
   `CELL_CAPACITY_MG` (10⁶): manifest с zone stock 2·10⁶ проходит manifest-
   validate, но FAIL-CLOSED падает в `CONTROLLER_ZONE_STOCK` при initialize.
   Границы не совпадают численно; безопасны, но требуют выравнивания в
   каноническом слое (A4 contract vs controller-константа).
9. **P9 DEVELOPMENT_BIAS extension doc**: требуется canonical hook в A3
   (именованный versioned bias над ALLOWED-операторами) + допуск A5 witness
   (см. п.3).
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
- **Corpse decomposition через смерть организма** — см. §5 п.7 (недостижимо в
  LAB-границах; канонически покрыто A6).
