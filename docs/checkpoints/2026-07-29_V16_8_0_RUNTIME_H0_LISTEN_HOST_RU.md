# Checkpoint v16.8.0 — H0 listen-host runtime

**Build ID:** `h0-single-process-network-first-host`
**Base:** `v16.7.1-architecture-a0-distributed-runtime`
**Branch:** `feature/h0-listen-host-runtime`

## Результат

Создан первый однопроцессный network-first runtime: authority и client расположены в одном процессе, но взаимодействуют через DTO/serialization boundary. Существующий item command проходит через ClientRuntime, loopback transport и ClientReplicaStore, а не через прямую ссылку UI на domain state.

## Acceptance scenario

```text
H0 loopback host final checksum
==
N1.2 two-process ENet final checksum
```

Дополнительно подтверждены exact replay, duplicate delta fencing, stale revision rejection, одна authoritative mutation, одна ledger-запись и отсутствие mutable snapshot alias между client и server.

## Новые тесты

- `tests/runtime/test_h0_listen_host_contracts.gd`;
- `tests/runtime/test_h0_listen_host_processes.gd`;
- `RUN_H0_LISTEN_HOST_TESTS.ps1`;
- `RUN_H0_LISTEN_HOST_TESTS.sh`.


## Локальная validation

```text
H0 contracts:                 71/71 PASS
H0 process equivalence:       24/24 PASS
Network/runtime profile:      25/25 suites, 2136/2136 assertions
World test scripts:           68/68 PASS
Equivalent runner steps:      71/71 PASS
Main scene offline:           6 PASS, 0 FAIL
Main scene listen-host:       6 PASS, 0 FAIL
Simulation-server lifecycle:  PASS
```

Эквивалентность подтверждена точным checksum:

```text
64820794148e9e8b8d7e73d95b39f57347011da054cd2523712b46e63ce66b17
```

## Ограничение checkpoint

H0 не объявляет весь существующий UI сетевым. `listen-host` является opt-in composition и foundation для последовательного переноса gameplay вертикалей. Default F5 остаётся `offline` до отдельного приёмочного checkpoint UI/runtime migration.

## Следующий checkpoint

`A1 — Generic Aggregate Foundation`.
