# V0 P6 R3 — находки world/core regression прогона (fence и унаследованный RED)

Дата: 2026-08-24 (UTC+10)

Ветка: `repair/v0-p6-persistence-exactly-once-r1` (HEAD на момент находок: `dc7ac584`)

Контекст WO `V0-P6-R3-WO-001`: предикат `FULL_WORLD_CORE_REGRESSION_PASS`.
Прогон выполнялся инлайн-репликацией канонического
`RUN_WORLD_REGRESSION_TESTS.ps1` на Ubuntu headless (pwsh на машине нет):
editor-import + все standalone `test_*.gd` (202 curated + auto-discovery,
fail-fast в первом прогоне, census во втором) + `main_scene_cli_all`.

## Находка 1 — PRE_EXISTING_MAIN_RED: test_nx2_realtime_traffic_separation

```text
тест:      res://tests/network/test_nx2_realtime_traffic_separation.gd
результат: 131 assertions, 8 failures (exit 1)
примеры:   "Compact network-tick movement snapshot is absent",
           "Item Graph explicit resync is not wired",
           "Committed Item Graph mutation has no full-resync fallback",
           "Redundant movement batches do not request authoritative snapshot retransmission",
           "Movement snapshot dirty state is cleared before all target queues accept the acknowledgement"
```

**Доказательство наследования:** тот же тест на БЕЗУПРЕЧНОМ `origin/main`
(`9ade3233`, merge PR #212, проверено в отдельном detached-worktree, worktree
удалён после проверки) даёт идентичный результат — exit 1, «131 assertions,
8 failures». Ветка R3 не меняет ни одного файла вне
`scripts/runtime/networked_gameplay/p6/**`, `tests/runtime/test_v0_p6_*`,
`tests/runtime/support/p6_*`, `RUN_V0_P6_*` и evidence/control-путей WO.

Вывод: RED **не вызван** P6 R3 repair. Это отдельный дефект сетевой линии
(`scripts/network/**` — forbidden_paths данного WO). Маршрутизация: отдельный
defect/Work Order вне этого ремонта; до его закрытия
`FULL_WORLD_CORE_REGRESSION_PASS` остаётся недостижим НИ НА ОДНОЙ ветке,
включая main.

## Находка 2 — environment fence: 5 display-зависимых тестов

На этой машине нет Xvfb (`/usr/bin/Xvfb` отсутствует) и графического дисплея;
установка пакетов без approval невозможна. Следующие standalone-тесты сами
требуют `/usr/bin/Xvfb` и исключены из локального прогона с явной пометкой:

```text
tests/runtime/test_m2_dedicated_graphical_processes.gd
tests/runtime/test_m3_graphical_multiplayer_processes.gd
tests/runtime/test_m4_graphical_shared_gameplay_processes.gd
tests/runtime/test_m5_graphical_multiplayer_acceptance.gd
tests/runtime/test_m7_playable_networked_processes.gd
```

Их каноническое покрытие — Windows-прогон `RUN_WORLD_REGRESSION_TESTS.ps1`
(исторический путь принятых checkpoint'ов) либо Xvfb-совместимая среда.
Эти 5 тестов НЕ считаются здесь PASS или FAIL — они FENCED/PENDING.

## Находка 3 — предполагаемый флак под нагрузкой: test_m6_dedicated_recovery_processes

В census-прогоне, исполнявшемся параллельно с коротким smoke-прогоном soak
(два Godot-процессных набора одновременно), `test_m6_dedicated_recovery_processes`
дал FAIL; в первом (fail-fast) прогоне той же сессии тот же тест был PASS (56 s)
без каких-либо изменений runtime-кода между прогонами. Классификация
«flake под CPU/порт-конкуренцией vs реальная нестабильность» будет зафиксирована
изолированным повторным прогоном после завершения census. До тех пор находка
классифицируется как UNCLASSIFIED_FLAKE_SUSPECT, а не как продуктовый дефект.

## Находка 4 — коррекция census: 6 фантомных записей инструментария

Первичная сводка census назвала провальными также:

```text
test_environment_cell_adapter
test_environment_cell_aggregate
test_growth_compute_handler
test_item_location_conservation_validator
test_transaction_aggregate_adapter
test_transaction_snapshot_factory
```

Все шесть лежат в `tests/simulation/fixtures/**`. Канонический ps1 явно
исключает любой путь-сегмент `fixtures` («support types ... must not be
executed as SceneTree entry points»), инлайн-репликация этот фильтр
первоначально упустила и попыталась запустить support-скрипты как точки входа.
Godot детерминированно отказал: «Can't load the script ... doesn't inherit
from SceneTree or MainLoop». Это **TOOLING_ARTIFACT репликации**, а не
тестовые провалы и не продуктовые дефекты; на предикаты WO они не влияют и
в блокеры не заносятся. Фильтр исправлен для последующих прогонов.

## Итоговый честный реестр census

```text
выполнено шагов ............. 293 (editor-import + 287 standalone + main_scene_cli_all*)
реальные тестовые провалы ... 4:
    test_m6_dedicated_recovery_processes .... FLAKE_SUSPECT -> изолированный реран
    test_eg45_synthetic_journal ............. FLAKE_SUSPECT -> изолированный реран
    test_v0_p1_live_reconnect_convergence ... FLAKE_SUSPECT -> изолированный реран
    test_nx2_realtime_traffic_separation .... PRE_EXISTING_MAIN_RED (Находка 1)
ожидаемый таймаут по дизайну . 1:
    test_v0_p6_thirty_minute_soak ........... литеральный 30-мин гейт не помещается
                                              в per-test окно 600s; канонический
                                              прогон - RUN_V0_P6_R3_SOAK.sh
tooling-artifact ............ 6 записей fixtures (Находка 4)
display-fenced (не запускались) 5 (Находка 2)
```

*main_scene_cli_all выполняется последним шагом census; его результат
фиксируется отдельно при закрытии миссии.

## Находка 5 — изолированные рераны и финальная классификация

Ночная цепочка после тишины машины (внешняя параллельная сессия завершила
прогоны в 13:54 UTC+10) дала окончательную классификацию:

```text
test_m6_dedicated_recovery_processes .... ISOLATED_RERUN_PASS -> нагрузочный флак
test_v0_p1_live_reconnect_convergence ... ISOLATED_RERUN_PASS -> нагрузочный флак
test_eg45_synthetic_journal ............. ISOLATED_RERUN_FAIL -> РЕАЛЬНЫЙ дефект;
    воспроизводится идентично на БЕЗУПРЕЧНОМ origin/main 9ade3233
    («replay result must equal the stored prior result verbatim»,
    25 assertions / 1 failure) => ВТОРОЙ PRE_EXISTING_MAIN_RED
```

Итог: оба нагрузочных подозреваемых сняты, реальных дефектов на ветке
ремонта НЕТ; оба реальных RED (nx2, eg45) унаследованы от main и требуют
отдельных линий ремонта вне scope данного WO (`scripts/network/**` —
forbidden_paths).

## Находка 6 — NX lane: фокусная верификация заблокирована parse-ошибкой

Первая же фаза NX-кампании (`RUN_H0_2_NX_C1_TESTS.sh` на ветке
`feature/h0-2-nx-c1-owner-authority-r3`, head `1a56fe0e`) упала на первом
фокусном тесте: `tests/network/test_nx_owner_movement_authority.gd`
содержит GDScript parse-ошибки («Cannot infer the type of ... variable»,
11 мест). Оставшиеся 4 фокусных теста не исполнялись (раннер fail-fast).
Вывод для NX lane: источник не проходит даже парсинг под каноническим
Godot 4.7.1 double — предикат
EXACT_GODOT_FOCUSED_RUNTIME_VERIFICATION требует предварительного
тестового ремонта на самой NX-ветке (её собственным порядком, вне данного
WO). Артефакт: `artifacts/test-results/p6-r3-night-chain-20260824-132416/nx-focused.log`.

## Позитивный итог цепочки — литеральный soak доказан

```text
V0_P6_THIRTY_MINUTE_TWO_CLIENT_SOAK_PASS_REAL_TIME
elapsed ....... 1800013 ms (30.00 real-time minutes)
checkpoints ... 29 периодических delegated checkpoint'ов (каждые ~60s)
reconnects .... alice x2, bob x2 (registry rebind_on_transport_change)
assertions .... 51/51 PASS
маркер раннера  V0_P6_R3_SOAK_SUITE_PASS
артефакты ..... artifacts/test-results/p6-r3-soak-suite-410928/
                artifacts/test-results/p6-r3-night-chain-20260824-132416/
```

## Влияние на предикаты WO

```text
FULL_WORLD_CORE_REGRESSION_PASS ......... ОТКРЫТ (честно):
    блокер A - унаследованный NX2 RED на main (Находка 1);
    блокер B - 5 display-fenced тестов (Находка 2).
V0_P6_R3_* core-fix предикаты ........... не затронуты находками;
    подтверждены независимым focused suite 16/16 PASS.
```

PASS-маркер полного regression НЕ выдаётся и не будет выдан, пока блокеры A/B
не сняты в их собственных линиях. Это соответствует stop-conditions WO
(«не фабриковать PASS»).
