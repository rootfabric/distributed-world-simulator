# ECO.EVO7 — Ремонт MINOR/NOTE-замечаний аудита линии (FFF6 R2) — CANDIDATE

**Дата:** 2026-08-24
**Ветка:** `feature/eco-evo7-fff-r1`, базовый HEAD `43f225e2c1751c5f04245d3742f8fa22cc2fc674`
**Роль:** реализатор (implementer) в рамках продолжения работы по замечаниям аудита `docs/evidence/2026-08-23_ECO_EVO7_LINE_AUDIT_GATES_RU.md`
**Статус:** CANDIDATE (реализаторская роль; самопринятия нет; независимые review/verification для R2 не проводились)
**Среда исполнения:** Ubuntu Linux, Godot 4.7.1.stable.double.custom_build.a13da4feb (double-precision), python 3.14.4. Все числа ниже — из реальных прогонов ЭТОЙ сессии (логи перечислены в `docs/evidence/2026-08-24_ECO_EVO7_LINE_MINORS_REPAIR_RU.md`).

## Что изменилось (по пунктам аудита)

### MINOR-1: EVO6-WATER-регрессия в цепочке FFF6 + бит-идентичный guard

- **Фактическое состояние на базовом HEAD:** свёртка `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline` в хвост `RUN_ECO_EVO7_FFF6_TESTS.ps1` уже присутствует и ЗАКРЫВАЕТ MINOR-1 — коммит `c0a70efcf3d79b8dff999de042f25c281cec58e5` («test(eco): fold EVO6-WATER determinism regression into FFF6 chain»), выполненный ПОСЛЕ текста аудита (аудит смотрел HEAD `d129b0ba`); закрытие подтверждено центральной сессией, повторная реализация не выполнялась. Текст MINOR-1 устарел наполовину: включение есть, но guard базового хэша отсутствовал.
- **Добавлен недостающий guard:** `RUN_ECO_EVO6_WATER_SELECTION.ps1` теперь захватывает stdout evolution-acceptance (`eco_evo6_water_evolution_acceptance.gd`) и требует точного вхождения строки `result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e`; любое расхождение — `throw` (дрейф базовой линии трактуется как регрессия, а не как «перекалибровка»). Эквивалентный grep-guard добавлен в Linux-цепочку `RUN_ECO_EVO7_FFF6_TESTS.sh` (стадия `EVO6_WATER_BASELINE_HASH_GUARD_PASS`).
- **Исполнительная проверка:** Linux-прогон evolution-acceptance в этой сессии дал полный хэш `7010e307…aa6e` (exit 0, PASS 24 assertions) — бит-идентично Windows-базе линии; guard-логика фактически исполнена в составе полного `.sh`-прогона цепочки (см. evidence-док).
- **Честное ограничение:** сами `.ps1`-правки в этой сессии НЕ исполнялись — на машине нет PowerShell (`pwsh` отсутствует). Их корректность подтверждена синтаксическим обзором и зеркальным исполнением той же логики в `.sh`.

### NOTE-2: перекалибровка anti-runaway потолка связывания осей (bound-pinning)

Было: ассерт stability-блока опирался только на слишком мягкий флаг `no_axis_fully_pinned` (= max_pinning < 1.0, «ни одна ось не связана всей популяцией»). Аудит наблюдал pin_max ≈ 0.08 и предложил жёсткий потолок ≤ 0.25 с обязательной кросс-seed верификацией ДО коммита порога.

Калибровочная проба `tests/research/ecology/eco_evo7_fff6_pinning_calibration_probe.gd` (новый файл, observability-only, ничего не гейтит): `Simulation.run_zone_stability(zone, seed, 108)` для ОБОИХ гейтящихся stability-зон на трёх seed'ах (канонический `20260823` + волновые `20260824`, `20260825`). Прогон: exit 0, `total runtime_ms=186405`.

**Таблица калибровки (108 циклов, feedback ON, наблюдаемое):**

| Seed | Зона | `max_bound_pinning_fraction` | finite/bounded means |
|---|---|---|---|
| 20260823 | MESIC_LOAM | 0.040 | да / да |
| 20260823 | DRY_SAND | **0.080** | да / да |
| 20260824 | MESIC_LOAM | 0.040 | да / да |
| 20260824 | DRY_SAND | 0.040 | да / да |
| 20260825 | MESIC_LOAM | 0.000 | да / да |
| 20260825 | DRY_SAND | **0.080** | да / да |

- Наблюдаемый меж-seed максимум = **0.080** (совпадает с наблюдением аудита).
- Ни один seed не превысил 0.25, поэтому научное содержание гейта НЕ ослаблялось: выбран потолок **`STABILITY_PINNING_CEILING := 0.25`** — запас **3.125×** к наблюдаемому максимуму (требование ≥2× выполнено с запасом).
- В `eco_evo7_fff6_succession_lab_acceptance.gd` добавлены два жёстких ассерта: «G11: `<зона>` max bound-pinning `<x>` stays under the calibrated ceiling 0.25». Счётчик ассертов 171 → 173; повторный прогон: exit 0, PASS (173 assertions), `result_hash=52995cf4bcd03578` НЕ изменился (правка уровня теста; модуль `evo7_succession_simulation_v1.gd` не тронут ни одной строкой).
- Контекстные наблюдения той же пробы (не гейтятся): полный 16-поколенческий `run_all` даёт pinning 0.000 во ВСЕХ 12 комбинациях зона×режим на всех трёх seed'ах; поэтому качественный preview-ассерт Experiment A (`<1.0` для canopy-сообществ) оставлен как был — он гейтит другое состояние (конец 16 поколений, а не 108-цикловый дрейф), где наблюдаемый уровень нулевой.

### Кросс-seed батарея: автоматизация и встраивание в цепочку

- Новые канонические раннеры `RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.ps1` и `RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.sh` вокруг `tests/research/ecology/eco_evo7_multiseed_wave2_acceptance.gd` (WATER/LITTER/SUCCESSION на свежих seed'ах 20260824–20260826, направления/причинность 3/3 + строгий детерминизм двойных прогонов seed 20260824). Сам пробник не изменён.
- Батарея встроена в FFF6-цепочку явно: в `.ps1` — шагом перед EVO6-WATER-блоком; в `.sh` — стадией `MULTISEED_WAVE2_BATTERY_PASS` (вызов канонического `.sh`-раннера).

### Linux-близнец полной цепочки FFF6

`RUN_ECO_EVO7_FFF6_TESTS.sh` (новый) по каноническому паттерну `RUN_V0_P6_R3_TESTS.sh`: editor-preflight первым шагом (`--headless --editor --import --path`, ожидание exit 0), изолированный HOME/APPDATA/XDG на каждый запуск, `timeout` на каждый godot/python-вызов, литеральные `[stage]`-маркеры прохождения, fail-closed на ненулевой код / FAIL-маркеры / SCRIPT ERROR / Parse Error / Compile Error, агрегатный маркер `[stage] ECO_EVO7_FFF6_REPAIR_SUITE_PASS`, временные выходы ТОЛЬКО под `artifacts/test-results/<имя>-<pid>/` (gitignored). Унаследованный BOM-дефект `eco_evo4*/eco_evo5*.tscn` терпится ТОЛЬКО на стадии preflight (по инструкции линии); любые другие parse-ошибки роняют прогон.

## Точные головы и хэши

| Величина | Значение | Источник этой сессии |
|---|---|---|
| Базовый HEAD | `43f225e2c1751c5f04245d3742f8fa22cc2fc674` | `git rev-parse HEAD` до правок |
| FFF6 succession `result_hash` (seed 20260823, Linux) | `52995cf4bcd03578` (16-симв. префикс, печатается тестом) | префикс побитово совпадает с R1-чекпоинтом (Windows) |
| EVO6-WATER `result_hash` (Linux, полный) | `7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` | evolution-acceptance, exit 0 |
| SUCCESSION `run_all` seed 20260824 | `28414a1831f26475` | калибровочная проба; совпадает с wave-2 evidence (Windows) |
| SUCCESSION `run_all` seed 20260825 | `876ecd4f96e258a2` | калибровочная проба; совпадает с wave-2 evidence (Windows) |
| Счётчик ассертов FFF6 acceptance | 171 → **173** | до/после перекалибровки |

Совпадение Linux/Windows-хэшей (в пределах публикуемых префиксов) — дополнительное свидетельство платформенной устойчивости детерминизма двойной арифметики линии.

## Осознанные ограничения R2 (честно)

1. Статусы всех чекпоинтов линии остаются **CANDIDATE**: реализатор не может самопринять ремонт; нужен свежий review + clean-checkout verification.
2. `.ps1`-правки (guard в `RUN_ECO_EVO6_WATER_SELECTION.ps1`, встраивание wave-2 в `RUN_ECO_EVO7_FFF6_TESTS.ps1`, новый `RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.ps1`) не исполнялись в этой сессии — нет PowerShell на Ubuntu-машине; их зеркальная логика исполнена зелёно в `.sh`.
3. Stability-покрытие anti-runaway осталось 2 зоны из 6 (MESIC_LOAM, DRY_SAND) — хвост E-6 аудита не закрыт расширением зон, но обе гейтуемые зоны теперь имеют кросс-seed численное обоснование потолка.
4. Наследованный BOM-дефект `eco_evo5_*.tscn`/части `eco_evo4_*.tscn` не исправлялся (вне компетенции роли); в этой сессии import-preflight дал exit 0 при нуле parse-ошибок.
5. Калибровочный потолок обоснован на трёх seed'ах; появление seed'а с pinning > 0.25 должно трактоваться как сигнал о беглом дрейфе, а не как повод автоматически поднять потолок (перекалибровка — отдельное решение с новой таблицей).

## Следующий шаг

Свежие роли review/verification над новым HEAD; затем line-level final checkpoint EVO7 (сводка G1–G15, GUI-скриншот C-режима, решение candidate→accepted — human gate на merge остаётся).
