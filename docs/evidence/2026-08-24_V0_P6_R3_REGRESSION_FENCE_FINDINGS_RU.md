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
