# Локальное тестирование нескольких сетевых узлов

## Цель

Любой агент должен уметь одной командой:

1. запустить World Directory;
2. запустить два Godot headless simulation server;
3. запустить одного или нескольких bot clients;
4. дождаться готовности;
5. выполнить сценарий;
6. собрать JSONL и JUnit;
7. завершить все процессы даже после падения теста.

## Планируемая структура

```text
tools/network_lab/
├── network_lab.py
├── process_manager.py
├── port_allocator.py
├── jsonl_probe.py
├── reports.py
├── scenarios/
│   ├── single_authority.py
│   ├── duplicate_commands.py
│   ├── object_handoff.py
│   ├── player_handoff.py
│   └── crash_matrix.py
└── README_RU.md

tests/network_py/
├── conftest.py
├── test_single_authority.py
├── test_object_handoff.py
├── test_player_handoff.py
├── test_network_faults.py
└── test_soak.py
```

## Контракт процесса Godot

Каждый процесс принимает:

```text
--role=<directory|simulation|client-bot|observer>
--node-id=<stable-test-id>
--instance-id=<isolated-instance>
--space-id=<space>
--region-id=<region>
--listen-host=127.0.0.1
--listen-port=<port>
--directory-url=<url>
--scenario=<scenario-id>
--report-path=<absolute-path>
--exit-after-scenario
```

## Изоляция user data

Нельзя запускать несколько тестовых узлов с общим `user://`.

Harness создаёт:

```text
artifacts/network-runs/<run-id>/
├── directory/user-data/
├── sim-a/user-data/
├── sim-b/user-data/
├── client-1/user-data/
├── logs/
├── reports/
└── topology.json
```

На Linux используются отдельные `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME` и `HOME`. На Windows каждому процессу передаётся собственный путь через проектный adapter для test user data.

Это также устраняет влияние старого `moon-experiment-001/world.json` на сетевые прогоны.

## JSONL readiness protocol

Каждый процесс обязан напечатать:

```json
{"event":"node_starting","node_id":"sim-a","role":"simulation"}
{"event":"network_listening","host":"127.0.0.1","port":19001}
{"event":"directory_registered","node_id":"sim-a"}
{"event":"node_ready","node_id":"sim-a","server_tick":0}
```

Harness не использует фиксированный `sleep(5)`. Он ждёт конкретное событие с timeout.

## Health contract

Минимальный health snapshot:

```json
{
  "schema": "planet_simulator.network_node_health.v1",
  "node_id": "sim-a",
  "role": "simulation",
  "ready": true,
  "authority_regions": ["region/space-a"],
  "connected_peers": 2,
  "server_tick": 180,
  "last_tick_duration_ms": 1.42,
  "entity_count": 14,
  "ghost_count": 3,
  "active_handoffs": 0
}
```

## Команды запуска, к которым должна прийти реализация

### Самый быстрый smoke

```bash
python tools/network_lab/network_lab.py run single-authority
```

### Все локальные network-тесты

```bash
python -m pytest tests/network_py -m network
```

### Два сервера и клиент для ручного просмотра

```bash
python tools/network_lab/network_lab.py up \
  --topology config/network/local-lab.example.json \
  --with-visible-client
```

### Остановка

```bash
python tools/network_lab/network_lab.py down --run-id latest
```

## Уровни тестирования

### L0 — pure GDScript contracts

Без сети и процессов:

- DTO;
- state machine;
- lease;
- handoff validation;
- snapshot checksum.

### L1 — in-process Godot

Один процесс, несколько `MultiplayerAPI` на поддеревьях:

- server peer;
- client peer;
- message routing;
- быстрый тест RPC/packet adapter.

Не считается доказательством process isolation.

### L2 — multi-process local

Несколько реальных Godot-процессов:

- порт;
- reconnect;
- crash;
- разные `user://`;
- реальные UDP sockets.

Это основной acceptance layer.

### L3 — Docker Compose

- повторяемые образы;
- healthchecks;
- NATS/PostgreSQL;
- Linux production-like окружение.

### L4 — fault injection

- `tc netem` для ENet UDP;
- Toxiproxy для HTTP/WebSocket/TCP control plane;
- delay, jitter, loss, reorder, disconnect.

### L5 — soak

- 1–24 часа;
- тысячи handoff;
- bounded memory;
- отсутствие entity duplication;
- отсутствие epoch regression.

## Правила process manager

1. Все процессы стартуют в собственной process group.
2. stdout/stderr всегда пишутся в файл.
3. После timeout отправляется graceful shutdown.
4. Затем `SIGTERM`, после grace period `SIGKILL`.
5. Teardown выполняется в `finally`/pytest fixture yield.
6. Порт считается занятым до фактического завершения процесса.
7. Report сохраняется даже при первом падении.

## Артефакты каждого теста

```text
scenario.json
processes.json
combined-events.jsonl
network-summary.json
junit.xml
sim-a.stdout.log
sim-b.stdout.log
client-1.stdout.log
snapshots/
```

## Обязательные поля итогового отчёта

```text
checkpoint
engine_version
protocol_version
topology
seed
started_at_utc
finished_at_utc
process_exit_codes
assertion_count
entity_conservation
handoff_count
failed_handoff_count
max_position_discontinuity_m
max_velocity_discontinuity_mps
max_authority_overlap_ticks
network_fault_profile
passed
```
