# ECO.EVO7 — Ремонт MINOR/NOTE-замечаний линии: команды, коды выхода, логи (2026-08-24)

**Роль:** реализатор (implementer), продолжение работ по аудиту `docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md` (MINOR-1, NOTE-2, автоматизация кросс-seed батареи, Linux-близнец цепочки).
**Ветка:** `feature/eco-evo7-fff-r1`, базовый HEAD `43f225e2c1751c5f04245d3742f8fa22cc2fc674`.
**Среда:** Ubuntu Linux; `Godot 4.7.1.stable.double.custom_build.a13da4feb` (`~/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64`); python 3.14.4.
**Сопутствующий чекпоинт:** `docs/checkpoints/2026-08-24_ECO_EVO7_FFF6_R2_MINORS_RU.md`.
**Статус работы:** CANDIDATE (реализаторская сессия; самопринятия нет).

Все прогоны выполнялись с изолированным HOME/APPDATA/XDG на каждый запуск и `BREAKPOINT_RUNTIME_DISABLED=1`; логи сохранялись под `artifacts/test-results/<имя>-<pid>/` (gitignored, поэтому ключевые хвосты процитированы здесь дословно — durable-запись живёт в этом документе).

## 1. Сводка команд и кодов выхода

| # | Команда (сокращённо) | Код выхода | Результат / маркер |
|---|---|---|---|
| 1 | `$GODOT_BIN --headless --editor --import --path <worktree>` (preflight) | **0** | без parse-ошибок вообще (`grep -c "Parse Error"` → 0) |
| 2 | `--script res://tests/research/ecology/eco_evo7_fff6_succession_lab_acceptance.gd` (ДО перекалибровки) | **0** | `PASS (171 assertions)`, `result_hash=52995cf4bcd03578`, 176 c |
| 3 | `--script res://tests/research/ecology/eco_evo6_water_evolution_acceptance.gd` | **0** | `PASS (24 assertions)`, полный `result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` |
| 4 | `python3 tests/research/ecology/test_evo5_rule_compiler.py` | **0** | ok-строки, отказов нет |
| 5 | `python3 tests/research/ecology/test_evo6_water_rules.py` | **0** | ok-строки, отказов нет |
| 6 | `--script res://tests/research/ecology/eco_evo7_fff6_pinning_calibration_probe.gd` (калибровка NOTE-2) | **0** | таблица ниже; `total runtime_ms=186405` |
| 7 | повтор `#2` ПОСЛЕ перекалибровки | **0** | `PASS (173 assertions)` (+2 потолочных ассерта), хэш не изменился |
| 8 | `RUN_ECO_EVO7_FFF6_TESTS.sh` — ПРОГОН 1 | **1** | fail-closed: 18 pass / 2 FAIL — мои python-стадии использовали относительный путь (см. §5); научные стадии зелёные |
| 9 | `RUN_ECO_EVO7_FFF6_TESTS.sh` — ПРОГОН 2 (после фикса путей) | **0** | `passed: 20 failed: 0`, финальный маркер `[stage] ECO_EVO7_FFF6_REPAIR_SUITE_PASS`, 601 c |
| 10 | `RUN_ECO_EVO7_FFF6_TESTS.sh` — ПРОГОН 3 (сертификация итоговых байтов файла после явного комментария-зеркала MINOR-1) | **0** | `passed: 20 failed: 0`, тот же финальный маркер, 586 c, профиль `eco-evo7-fff6-suite-308714` |

Прогоны #1–#3 выполнены до правок (базовая линия), #6–#9 после соответствующих правок; порядок честно отражает «сначала данные — потом порог».

## 1а. Верификация закрытия MINOR-1 (без повторной реализации)

По уточнению центральной сессии MINOR-1 уже закрыт на ветке: коммит **`c0a70efcf3d79b8dff999de042f25c281cec58e5`** («test(eco): fold EVO6-WATER determinism regression into FFF6 chain») добавил в хвост `RUN_ECO_EVO7_FFF6_TESTS.ps1` шаг `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline`. Повторная реализация НЕ выполнялась. Проверка наличия и когерентности в рабочем дереве (HEAD `43f225e2…`, затем собственные коммиты):

- `git show c0a70efc --stat`: ровно 1 файл, +3 строки — вызов sub-runner с `-SkipBaseline`, проверка `$LASTEXITCODE`, throw при отказе; блок стоит ПОСЛЕ основного списка тестов и перед финальным PASS-сообщением — когерентно.
- Исполнительная верификация: полный зелёный прогон Linux-цепочки (§3) содержит эквивалентный финальный EVO6-WATER блок + `EVO6_WATER_BASELINE_HASH_GUARD_PASS (7010e30707613e28... bit-identical)`.
- `.sh`-близнец зеркалирует семантику `.ps1`-хвоста: прямой `.sh`-эквивалент `RUN_ECO_EVO6_WATER_SELECTION.ps1` отсутствует, поэтому исполняются ТЕ ЖЕ обёрнутые стадии (два python rule-pack теста, water fitness, water-driven evolution acceptance, visual observatory adapter под `EVO6_WATER_LAB_AUTOCAP=1`) с сохранением guard'а замороженного хэша.

## 2. Калибровочная проба NOTE-2 (кросс-seed pinning)

Команда (#6): `godot --headless --path <worktree> --script res://tests/research/ecology/eco_evo7_fff6_pinning_calibration_probe.gd`, exit 0.

```text
STABILITY seed=20260823 zone=MESIC_LOAM cycles=108 max_pinning=0.040 finite_means=true means_bounded=true fully_pinned=true runtime_ms=15766
STABILITY seed=20260823 zone=DRY_SAND   cycles=108 max_pinning=0.080 finite_means=true means_bounded=true fully_pinned=true runtime_ms=15721
STABILITY seed=20260824 zone=MESIC_LOAM cycles=108 max_pinning=0.040 finite_means=true means_bounded=true fully_pinned=true runtime_ms=17506
STABILITY seed=20260824 zone=DRY_SAND   cycles=108 max_pinning=0.040 finite_means=true means_bounded=true fully_pinned=true runtime_ms=16518
STABILITY seed=20260825 zone=MESIC_LOAM cycles=108 max_pinning=0.000 finite_means=true means_bounded=true fully_pinned=true runtime_ms=16686
STABILITY seed=20260825 zone=DRY_SAND   cycles=108 max_pinning=0.080 finite_means=true means_bounded=true fully_pinned=true runtime_ms=16991
```

Наблюдаемый меж-seed максимум = **0.080** ⇒ потолок **0.25** даёт запас **3.125×** (требование ≥2× выполнено). Ни один seed порог 0.25 не превысил — наука не ослаблялась. Контекст: полный 16-поколенческий `run_all` дал pinning 0.000 во всех 12 комбинациях зона×режим на всех трёх seed'ах; `result_hash` (16 симв.) при этом `52995cf4bcd03578` / `28414a1831f26475` / `876ecd4f96e258a2` — побитово равны Windows-значениям из R1-чекпоинта и wave-2 evidence (в пределах печатаемых префиксов).

Повторный прогон acceptance после перекалибровки (#7):

```text
ECO.EVO7 FFF6 result_hash=52995cf4bcd03578
ECO.EVO7 FFF6 Succession Lab: PASS (173 assertions)
```

## 3. Полный прогон отремонтированной Linux-цепочки (#9, сертификационный повтор #10)

`RUN_ECO_EVO7_FFF6_TESTS.sh` — editor-preflight первым шагом, изолированный HOME на стадию, timeout на вызов, fail-closed, агрегат под `artifacts/test-results/eco-evo7-fff6-suite-236849`. Хвост журнала (exit 0, 601 c; сертификационный прогон #10 итогового файла завершился идентично — exit 0, `passed: 20 failed: 0`, профиль `artifacts/test-results/eco-evo7-fff6-suite-308714`, 586 c):

```text
[eco-evo7-fff6-suite][stage] EDITOR_PREFLIGHT_OK
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF6_SUCCESSION_LAB_ACCEPTANCE_PASS (ECO.EVO7 FFF6 Succession Lab: PASS (173 assertions))
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF5_SOIL_MEMORY_ACCEPTANCE_PASS (ECO.EVO7 FFF5 Soil Memory: PASS (91 assertions))
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF4_WATER_FEEDBACK_ACCEPTANCE_PASS (ECO.EVO7 FFF4 Water Feedback: PASS (101 assertions))
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF3_LIGHT_FEEDBACK_ACCEPTANCE_PASS (ECO.EVO7 FFF3 Light Feedback: PASS (51 assertions))
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF2_MORPHOLOGY_EVOLUTION_ACCEPTANCE_PASS (ECO.EVO7 FFF2 Morphology Evolution: PASS (56 assertions))
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF1_FUNCTIONAL_PHENOTYPE_ACCEPTANCE_PASS (ECO.EVO7 FFF1 PlantFunctionalPhenotype: PASS (110 assertions))
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF0_CONTRACT_MAPPING_ACCEPTANCE_PASS (ECO.EVO7 FFF0 Contract Mapping: PASS (112 assertions))
[eco-evo7-fff6-suite][stage] ECO_P1B_S1_MUTATION_LINEAGE_ACCEPTANCE_PASS (Lineage: PASS (5834 assertions))
[eco-evo7-fff6-suite][stage] ECO_PH2_ENVIRONMENT_COUPLED_DEVELOPMENT_ACCEPTANCE_PASS (ECO.PH2 Environment-Coupled Development: PASS (107 assertions))
[eco-evo7-fff6-suite][stage] ECO_P1A_S1_ENVIRONMENT_ACCEPTANCE_PASS (ECO.P1A-S1 Environment Baseline: PASS (109 assertions))
[eco-evo7-fff6-suite][stage] ECO_P1A_S2_SINGLE_PLANT_RESOURCE_ACCEPTANCE_PASS (ECO.P1A-S2 Single-Plant Resource Model: PASS (235 assertions))
[eco-evo7-fff6-suite][stage] ECO_P1C_S4_AGGREGATE_CONTRACT_PASS (ECO.P1C-S4 Aggregate Contract: PASS (15 assertions))
[eco-evo7-fff6-suite][stage] ECO_PH0_DEVELOPMENT_CONTRACT_ACCEPTANCE_PASS (ECO.PH0 Development Trait Contract: PASS (63 assertions))
[eco-evo7-fff6-suite] wiring in the canonical multiseed wave-2 battery

[eco-evo7-fff6-suite][stage] MULTISEED_WAVE2_BATTERY_PASS
[eco-evo7-fff6-suite] EVO6-WATER rule pack + numeric predicates
[eco-evo7-fff6-suite][stage] TEST_EVO5_RULE_COMPILER_PASS
[eco-evo7-fff6-suite][stage] TEST_EVO6_WATER_RULES_PASS
[eco-evo7-fff6-suite][stage] ECO_EVO6_WATER_FITNESS_ACCEPTANCE_PASS (ECO.EVO6-WATER fitness: PASS (5 assertions))
[eco-evo7-fff6-suite][stage] ECO_EVO6_WATER_EVOLUTION_ACCEPTANCE_PASS (ECO.EVO6-WATER evolution: PASS (24 assertions))
[eco-evo7-fff6-suite][stage] EVO6_WATER_BASELINE_HASH_GUARD_PASS (7010e30707613e28... bit-identical)
[eco-evo7-fff6-suite] EVO6-WATER visual observatory adapter
[eco-evo7-fff6-suite][stage] EVO6_WATER_VISUAL_ADAPTER_PASS (ECO.EVO6-WATER-VIS: PASS plants=72)
[eco-evo7-fff6-suite] passed: 20 failed: 0 (logs: .../artifacts/test-results/eco-evo7-fff6-suite-236849)
[eco-evo7-fff6-suite][stage] ECO_EVO7_FFF6_REPAIR_SUITE_PASS
```

Примечание: P1B-S1 (5834 assertions — ядро мутаций/lineage) исполнен зелёным В СОСТАВЕ цепочки, отдельный 15-минутный бюджет не понадобился. Дополнительное совпадение с базовой линией: `ECO.P1A-S1 environment_hash=b862c4fc529b5fd8…` — тот же хэш, что зафиксирован в FFF*_VERIFICATION документах.

## 4. Мультисид-батарея внутри цепочки

Внутренний журнал стадии (`artifacts/test-results/eco-evo7-multiseed-wave2-…/…log`, тот же прогон #9):

```text
WATER strict double run seed=20260824 twice_identical=true
LITTER strict double run seed=20260824 twice_identical=true
SUCCESSION seed=20260824 divergent=6/6 zones=[FLOODED|RIPARIAN|MESIC_LOAM|DRY_SAND|UNDER_CANOPY|CANOPY_GAP] finite_bounded_means=true result_hash=28414a1831f26475
SUCCESSION seed=20260825 divergent=6/6 … result_hash=876ecd4f96e258a2
SUCCESSION seed=20260826 divergent=6/6 … result_hash=c047378faadb898f
SUCCESSION strict double run seed=20260824 twice_identical=true
ECO.EVO7 multiseed wave2: PASS (15 assertions)
total runtime_ms=246604
```

Все три SUCCESSION-хэша побитово совпали с Windows-значениями волны-2 (`docs/evidence/2026-08-23_ECO_EVO7_MULTISEED_WAVE2_RU.md`) — платформенная воспроизводимость детерминизма подтверждена ещё раз.

## 5. Честная фиксация дефекта первого прогона цепочки

ПРОГОН 1 (#8) упал по моему же дефекту: python-стадии получали ОТНОСИТЕЛЬНЫЙ путь к rule-pack тестам, а cwd раннера — не worktree:

```text
[eco-evo7-fff6-suite] FAIL test_evo5_rule_compiler (exit code 2)
/usr/bin/python3: can't open file '/home/yurig/distributed-world-simulator/tests/research/ecology/test_evo5_rule_compiler.py': [Errno 2] No such file or directory
```

Fail-closed механика сработала как задумано (ненулевой код ⇒ FAIL ⇒ агрегат exit 1, финальный PASS-маркер не напечатан). Пути заменены на абсолютные (`$ROOT/tests/...`), выполнен ПОЛНЫЙ повторный прогон (#9) — зелёный. Научных последствий нет: godot-стадии прогона 1 были зелёными (абсолютные пути), ошибка была чисто навигационной.

## 6. Ограничения и что НЕ сделано (честно)

1. `.ps1`-правки этой сессии (guard в `RUN_ECO_EVO6_WATER_SELECTION.ps1`; встраивание wave-2 в `RUN_ECO_EVO7_FFF6_TESTS.ps1`; новый `RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.ps1`) **не исполнялись**: PowerShell/pwsh на Ubuntu-машине отсутствует. Их логика зеркально реализована и исполнена зелёным в `.sh`; сами `.ps1` прошли только ручной синтаксический обзор. Требуется Windows-исполнение при ближайшей возможности.
2. Статусы чекпоинтов остаются CANDIDATE; независимый review/verification ремонта не проводился (роль реализатора).
3. Anti-runaway stability-покрытие осталось 2 зоны из 6 (MESIC_LOAM, DRY_SAND) — расширение зон не входило в объём MINOR-ремонта (хвост E-6 аудита остаётся открытым, теперь с кросс-seed обоснованием потолка).
4. Наследованный BOM-дефект `eco_evo4*/eco_evo5*.tscn` не трогался (вне компетенции). Наблюдение: в данной среде import-preflight завершился с exit 0 и НУЛЁМ parse-ошибок — известные сообщения «Parse Error: Expected '['» здесь не воспроизвелись; толерантность к ним в preflight-стадии `.sh` оставлена как страховка согласно инструкции линии.
5. Артефакты под `artifacts/test-results/` gitignored и в коммиты не входят; durable-копии ключевых выводов — этот документ и чекпоинт.
