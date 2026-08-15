# V0-SM0 — автоматическая проверка двухсерверного handoff и evidence contract

**Branch:** `feature/sm0-two-authority-seamless-handoff-lab`  
**Checkpoint:** `V0-SM0-TWO-AUTHORITY-SEAMLESS-HANDOFF-LAB`  
**Product base:** `d66378b98b69756fab6c2a93b80b74db9ccd1980`  
**Status:** REQUIRED TEST/EVIDENCE CONTRACT FOR SM0

## 1. Главный приоритет первого SM0

Первый перенос игрока между Server A и Server B проверяет прежде всего **сетевую и authority-корректность**, а не визуальную плавность.

На первом рабочем checkpoint допустимы:

- короткая заметная пауза во время freeze/activate;
- видимая коррекция позиции после активации target;
- временно грубый переход presentation;
- отсутствие ghosts/overlap interpolation;
- отсутствие production-grade latency hiding.

Это НЕ является причиной отклонять первый SM0, если canonical/network state корректен.

Первый checkpoint обязан доказать:

```text
same logical_player_id
same player_entity_id
same graphical/headless client process during one run
exactly one active authoritative writer
authority epoch increments monotonically
source loses write permission after commit
target becomes the only writer after commit
input sequence does not reset/replay incorrectly
client route changes A -> B -> A
both servers remain alive and synchronized
no unexpected ERROR or persistent network error code
```

Плавность становится отдельным post-correctness этапом только после стабильного 20-handoff test.

## 2. Что считать PASS и что не считать PASS

### PASS для первого SM0

Handoff может визуально быть грубым, но весь transfer должен завершиться правильной state-machine последовательностью:

```text
ACTIVE_SOURCE
-> TARGET_ROUTE_WARM
-> SOURCE_FROZEN
-> TARGET_PREPARED_SHADOW
-> DIRECTORY_COMMITTED
-> TARGET_ACTIVE
-> SOURCE_RETIRED_READ_ONLY
```

После commit:

```text
writer_count == 1
directory.owner == target
directory.epoch == previous_epoch + 1
source mutation == rejected
target mutation == accepted
```

### FAIL независимо от того, что "на экране всё выглядит нормально"

```text
writer_count > 1
player identity changed
second player entity appeared
source accepted mutation after commit
target accepted mutation before commit
authority epoch did not increment or moved backward
directory A/B disagree after convergence timeout
input sequence reset or stale source input was accepted
client silently respawned instead of handoff
server process crashed/restarted
handoff state machine skipped mandatory phase
unexpected ERROR / assertion / persistent last_error_code
```

### Диагностика, но НЕ hard acceptance gate первого SM0

```text
total_handoff_ms
freeze_duration_ms
position_gap_m
prediction_correction_m
frames_without_authoritative_update
visible presentation jump
```

Собирать эти показатели обязательно, оптимизировать — после correctness gate.

## 3. Три уровня тестирования

SM0 должен иметь три независимых уровня.

### T1 — pure contract tests

Без процессов и sockets:

```text
test_sm0_zone_directory.gd
test_sm0_handoff_contracts.gd
test_sm0_handoff_state_machine.gd
```

Проверяют:

- exact-field DTO validation;
- checksums;
- unknown zone/authority rejection;
- stale directory revision;
- monotonic authority epoch;
- replay-safe transfer ID;
- duplicate PREPARE/COMMIT/ACTIVATE;
- abort before commit;
- no source reactivation after commit.

### T2 — real multi-process network test

Главный correctness test SM0.

Запускаются реальные процессы:

```text
Dedicated Server A :24580 / control :24680
Dedicated Server B :24581 / control :24681
Automated Client Driver
```

Client Driver обязан использовать тот же transport/handshake/player-input/handoff путь, который использует реальный клиент. Запрещено проверять handoff прямым вызовом server methods в одном процессе.

Для T2 graphical rendering не является обязательным. Цель — реальная межпроцессная сеть и authority transfer.

### T3 — real graphical process test

После T2 PASS запускается настоящий graphical client с тем же automated movement driver.

T3 подтверждает:

- реальный game-client composition;
- окно/PID клиента не перезапускаются;
- Earth/player presentation переживают route switch;
- network state совпадает с T2.

T3 не должен использовать OS-level эмуляцию клавиатуры как основной механизм теста. Детерминированный acceptance driver должен подавать movement intent внутрь обычного client input/prediction path.

## 4. Детерминированный automated crossing driver

Новый bounded acceptance component:

```text
scripts/runtime/seamless/sm0/sm0_automated_crossing_driver.gd
```

Он НЕ вызывает server mutation напрямую.

Он формирует тот же локальный movement intent, который затем проходит через обычный client pipeline:

```text
automated intent
-> client prediction/input path
-> realtime input transport
-> active authority server
-> authoritative movement
-> snapshots/reconciliation
```

### Первый deterministic scenario

Стартовая позиция:

```text
Zone A
east_offset_m = -20
```

Фаза A->B:

```text
send EAST movement intent
wait until warm route B == READY
continue EAST
wait until directory owner == B
wait until client active route == B
wait until authoritative east_offset_m >= +5
```

Фаза B->A:

```text
send WEST movement intent
wait until warm route A == READY
continue WEST
wait until directory owner == A
wait until client active route == A
wait until authoritative east_offset_m <= -5
```

Один round-trip = два handoff.

### Нельзя управлять сценарием только таймерами

Переход к следующему шагу должен происходить по наблюдаемому canonical/network state:

```text
zone
directory owner
authority epoch
active route
authoritative position
handoff state
```

Timeout используется только как fail-closed guard.

Это позволяет тесту работать и при медленном CI/локальном компьютере.

## 5. Автоматический process runner

Целевой runner:

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1
```

Минимальные параметры:

```text
-Handoffs 4        # быстрый developer gate
-Final             # 20 handoffs
-Graphical         # T3 graphical process test
-FaultCase <name>  # отдельный fault scenario
-Restart
-GodotExe <path>
```

### Developer gate

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Handoffs 4 -Restart
```

### Final checkpoint gate

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Final -Restart
```

`-Final` означает:

```text
10 round-trips = 20 authority handoffs.
```

### Graphical confirmation

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Final -Graphical -Restart
```

## 6. Обязательная структура логов

Каждый запуск создаёт отдельную immutable session-directory:

```text
%LOCALAPPDATA%\DistributedWorldSimulator\SM0Seamless\logs\<session-id>\

  server-a.log
  server-b.log
  client.log
  control.jsonl
  handoffs.jsonl
  harness.log
  summary.json
```

Для graphical test дополнительно допускаются:

```text
client-engine.log
screenshots/
```

Runner всегда печатает exact log directory в конце PASS и FAIL.

Логи не удаляются автоматически при FAIL.

## 7. Structured events

Помимо обычного Godot текста, SM0 должен писать machine-readable JSONL events.

Минимальный envelope:

```json
{
  "schema": "distributed_world_simulator.sm0_event.v1",
  "session_id": "...",
  "event": "SM0_HANDOFF_PREPARED",
  "severity": "INFO",
  "process_role": "server-b",
  "process_id": 1234,
  "time_msec": 123456,
  "transfer_id": "handoff/...",
  "logical_player_id": "a",
  "player_entity_id": "player/a",
  "source_authority_id": "authority/sm0/a",
  "target_authority_id": "authority/sm0/b",
  "authority_epoch": 2,
  "directory_revision": 8
}
```

Required event families:

```text
SM0_SERVER_READY
SM0_AUTHORITY_PEER_SYNCED
SM0_DIRECTORY_READY
SM0_CLIENT_ROUTE_ACTIVE
SM0_CLIENT_ROUTE_STANDBY_READY

SM0_HANDOFF_BEGIN
SM0_SOURCE_FROZEN
SM0_HANDOFF_PACKAGE_EXPORTED
SM0_HANDOFF_PREPARED
SM0_DIRECTORY_COMMITTED
SM0_TARGET_ACTIVATED
SM0_SOURCE_RETIRED
SM0_HANDOFF_ABORTED

SM0_CROSSING_COMPLETED
SM0_INVARIANT_VIOLATION
SM0_PROCESS_EXIT
SM0_ACCEPTANCE_RESULT
```

## 8. Correlation по transfer_id

Каждый handoff получает unique `transfer_id`.

Анализатор обязан собрать события A, B и client в одну timeline:

```text
transfer_id = H17

A: BEGIN
A: SOURCE_FROZEN
A: PACKAGE_EXPORTED
B: PREPARED
A/directory: COMMITTED epoch 7 -> 8
B: TARGET_ACTIVATED
A: SOURCE_RETIRED
CLIENT: ACTIVE_ROUTE B
HARNESS: CROSSING_COMPLETED
```

Если обязательного события нет или порядок нарушен — FAIL, даже если клиент физически оказался по другую сторону границы.

## 9. Snapshot/invariant telemetry на каждом crossing

После каждого commit analyzer должен иметь снимок:

```text
handoff_index
transfer_id
logical_player_id
player_entity_id
source_zone
target_zone
source_epoch
target_epoch
directory_revision
directory_owner
server_a_writer_count
server_b_writer_count
last_source_input_sequence
first_target_input_sequence
authoritative_position_before
authoritative_position_after
inventory_fingerprint_if_enabled
```

Hard invariant:

```text
server_a_writer_count + server_b_writer_count == 1
```

Во время PREPARE допустимо временно:

```text
writer_count == 0
```

но никогда:

```text
writer_count > 1
```

## 10. Автоматический log analyzer

Целевой analyzer:

```powershell
.\ANALYZE_V0_SM0_LOGS.ps1 -LogDirectory <path>
```

Runner вызывает его автоматически после завершения процессов.

Analyzer также можно запускать отдельно на логах ручного теста.

### Что analyzer считает hard FAIL

Любое совпадение или structured equivalent:

```text
ERROR:
SCRIPT ERROR
CRASH
ASSERTION FAILED
SM0_INVARIANT_VIOLATION
MULTIPLAYER_SAME_REVISION_MUTATION
persistent last_error_code != ""
process exit_code != 0
```

Плюс semantic failures:

```text
missing SERVER_READY
missing PEER_SYNCED
missing DIRECTORY_READY
missing mandatory handoff phase
non-monotonic authority epoch
directory divergence between A and B
different player_entity_id across handoff
writer_count > 1
source accepted movement after commit
target accepted movement before commit
duplicate active player entity
client process restarted during a run
handoff timeout
```

Не надо просто grep-ать слово `WARNING`: warnings классифицируются отдельно и не являются FAIL без явного denylist/invariant impact.

## 11. summary.json

Каждый process run заканчивается machine-readable report:

```json
{
  "schema": "distributed_world_simulator.sm0_acceptance_result.v1",
  "session_id": "...",
  "result": "PASS",
  "handoffs_requested": 20,
  "handoffs_completed": 20,
  "round_trips_completed": 10,
  "server_a_exit_code": 0,
  "server_b_exit_code": 0,
  "client_exit_code": 0,
  "unexpected_error_count": 0,
  "invariant_violation_count": 0,
  "max_observed_writer_count": 1,
  "player_identity_changes": 0,
  "authority_epoch_start": 1,
  "authority_epoch_end": 21,
  "stale_source_mutation_accepts": 0,
  "duplicate_active_player_count": 0,
  "diagnostics": {
    "max_handoff_ms": 0,
    "max_position_gap_m": 0.0,
    "max_prediction_correction_m": 0.0
  }
}
```

`diagnostics` записываются, но для первого SM0 их numerical thresholds не являются hard gate.

## 12. Exit-code contract

Runner должен быть пригоден для локального запуска и CI.

```text
0   PASS
1   acceptance/invariant FAIL
2   invalid configuration / missing dependency
3   startup synchronization FAIL
4   process crashed/exited early
124 timeout
```

Любой non-zero означает, что checkpoint не принят.

## 13. Fault tests

Fault tests выполняются отдельно от happy-path 20 handoffs, чтобы причина сбоя была однозначной.

Минимальный набор:

```text
TARGET_UNAVAILABLE_BEFORE_PREPARE
TARGET_DIES_DURING_PREPARE
DUPLICATE_PREPARE
DUPLICATE_COMMIT
STALE_TICKET
STALE_SOURCE_INPUT_AFTER_COMMIT
CLIENT_STANDBY_ROUTE_LOST
TARGET_ACTIVATION_ACK_LOST
```

Каждый fault case создаёт свой `summary.json` и обязан доказать ожидаемое конечное ownership state.

## 14. Regression после SM0 test

SM0 runner не заменяет обычный V0 regression.

После SM0 happy-path/fault acceptance обязательно запустить текущий single-server baseline:

```powershell
.\RUN_V0_MVP_AUTO.ps1 -Clients 2 -Restart
```

И проверить отсутствие новых startup/network ошибок.

На CI/acceptance это должно стать отдельным последним gate.

## 15. Минимальный порядок реализации тестов

Тестирование создаётся вместе с production code, не в конце.

```text
SM0.1 contracts
  + T1 tests сразу

SM0.2 two-server launcher/control link
  + startup process test сразу
  + logs/session structure сразу

SM0.3 headless authority handoff
  + deterministic automated crossing driver
  + structured handoff.jsonl
  + analyzer invariants

SM0.4/SM0.5 client routing/graphical crossing
  + тот же driver через real client input path
  + client PID/route assertions

SM0.7
  + fault matrix
  + 20-handoff final run
  + summary.json
```

Нельзя откладывать автоматизацию до момента, когда ручной переход уже "работает".

## 16. Final SM0 evidence package

Для независимой проверки checkpoint должен быть достаточен один каталог логов плюс exact Git SHA:

```text
HEAD SHA
Godot build ID
zone manifest hash
protocol hash
server-a.log
server-b.log
client.log
control.jsonl
handoffs.jsonl
summary.json
```

Reviewer не должен быть обязан смотреть видео, вручную водить персонажа или доверять текстовому отчёту implementer.

Видео/скриншот может быть дополнительным presentation evidence, но source of truth для первого SM0 — machine-readable network/authority evidence.
