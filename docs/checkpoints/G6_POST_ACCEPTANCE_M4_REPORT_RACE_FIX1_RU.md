# G6 post-acceptance M4 report race fix1

**Дата:** 2026-08-09
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`

## Trigger

Во время G7.0 full world regression M4 graphical shared gameplay завершил client-side gameplay успешно, но четыре server-report assertions получили пустой `item_graph_snapshot`:

```text
A/B gameplay complete              PASS
A/B client Item Graph convergence  PASS
server canonical graph             FAIL
server snapshot checksum           FAIL
server/client convergence          FAIL
```

## Root cause

Dedicated server пишет `server.json` через `AtomicJsonFile`: existing target временно переименовывается в backup, затем verified temporary file становится новым target. M4 test после завершения клиентов читал `server.json` один раз обычным `FileAccess` одновременно с server disconnect/report write.

На Windows допустимо попасть в короткое окно, когда target временно отсутствует. `_read()` тогда возвращает `{}`, хотя canonical server Item Graph исправен. Это объясняет одновременный FAIL всех server-snapshot assertions при уже зелёном A/B checksum convergence.

## Fix

`test_m4_graphical_shared_gameplay_processes.gd` теперь ожидает валидный server Item Graph report до 10 секунд. Он:

- игнорирует временно отсутствующий/невалидный report;
- запоминает последний report с 64-character Item Graph checksum;
- возвращается сразу, когда server checksum совпадает с уже полученным A client checksum;
- при реальном semantic mismatch по timeout возвращает последний валидный server snapshot, поэтому существующая convergence assertion всё равно падает.

Таким образом fix устраняет только report-read race и не маскирует настоящий server/client divergence.

## Scope

```text
production runtime changes   NONE
Item Graph semantics         UNCHANGED
network protocol             UNCHANGED
M4 process test              FIXED
```

Assistant-side exact Godot smoke на `4.7.1.stable.double.custom_build.a13da4feb` воспроизвёл sequence `stale report -> target missing -> final report` и завершился:

```text
M4_REPORT_RACE_SMOKE: PASS
```

Полный M4 graphical process validation остаётся частью следующего Windows `RUN_G7_0_FULL_ACCEPTANCE.ps1`.
