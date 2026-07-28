# Дорожная карта сетевой бесшовности PlanetSimulator

Этот файл — точка входа в отдельную сетевую программу проекта.

Текущий статус: `v16.7.0-repository-r3.1-authoritative-recovery` (candidate). N2 принят. R3.1 добавляет атомарные authoritative checkpoints, restart recovery и сохранение command/replay dedup без повторной item mutation. Следующий этап — N3 World Directory и authority leases.

## Основные документы

1. [`docs/checkpoints/2026-07-29_V16_7_0_REPOSITORY_R3_1_AUTHORITATIVE_RECOVERY_RU.md`](docs/checkpoints/2026-07-29_V16_7_0_REPOSITORY_R3_1_AUTHORITATIVE_RECOVERY_RU.md) — текущий R3.1 candidate.
2. [`docs/persistence/R3_1_AUTHORITATIVE_RECOVERY_RU.md`](docs/persistence/R3_1_AUTHORITATIVE_RECOVERY_RU.md) — authoritative checkpoint, crash/restart и fail-closed recovery.
3. [`docs/checkpoints/2026-07-29_V16_6_0_NETWORK_N2_PROCESS_HARNESS_RU.md`](docs/checkpoints/2026-07-29_V16_6_0_NETWORK_N2_PROCESS_HARNESS_RU.md) — принятый N2 harness.
2. [`docs/checkpoints/2026-07-28_V16_5_2_FOUNDATION_NETWORK_N1_RU.md`](docs/checkpoints/2026-07-28_V16_5_2_FOUNDATION_NETWORK_N1_RU.md) — принятый полный N1.
2. [`docs/checkpoints/2026-07-28_V16_5_1_NETWORK_N1_REMOTE_ITEM_COMMAND_RU.md`](docs/checkpoints/2026-07-28_V16_5_1_NETWORK_N1_REMOTE_ITEM_COMMAND_RU.md) — принятый N1.2 authoritative command.
3. [`docs/checkpoints/2026-07-28_V16_5_0_NETWORK_N1_SNAPSHOT_RU.md`](docs/checkpoints/2026-07-28_V16_5_0_NETWORK_N1_SNAPSHOT_RU.md) — принятый N1.1 ENet snapshot path.
3. [`docs/network/N1_NETWORK_IMPLEMENTATION_PLAN_RU.md`](docs/network/N1_NETWORK_IMPLEMENTATION_PLAN_RU.md) — точный план N1.0–N5 и checkpoint gates.
4. [`docs/checkpoints/2026-07-28_V16_4_2_NETWORK_TRANSPORT_BOUNDARY_RU.md`](docs/checkpoints/2026-07-28_V16_4_2_NETWORK_TRANSPORT_BOUNDARY_RU.md) — принятый N1.0.
5. [`docs/checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md`](docs/checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md) — закрытие найденных N0 boundary bypasses.
6. [`docs/checkpoints/2026-07-27_V16_4_0_FOUNDATION_N0_RU.md`](docs/checkpoints/2026-07-27_V16_4_0_FOUNDATION_N0_RU.md) — исходный Foundation/N0 checkpoint.
7. [`docs/contracts/N0_NETWORK_CONTRACTS_V1_RU.md`](docs/contracts/N0_NETWORK_CONTRACTS_V1_RU.md) — точные DTO, checksums, handoff и loopback.
8. [`docs/checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_FIX2_RU.md`](docs/checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_FIX2_RU.md) — принятый canonical WORLD aggregate.
9. [`docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md`](docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md) — terminal lifecycle fence.
10. [`docs/network/NETWORK_READINESS_CHECKPOINT_RU.md`](docs/network/NETWORK_READINESS_CHECKPOINT_RU.md) — текущая готовность к N1.
11. [`docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`](docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md) — план и acceptance Foundation.
12. [`docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md`](docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md) — план и acceptance N0.
13. [`docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`](docs/network/SEAMLESS_WORLD_ROADMAP_RU.md) — последовательность N0–N11.
14. [`docs/network/NETWORK_TEST_MATRIX_RU.md`](docs/network/NETWORK_TEST_MATRIX_RU.md) — обязательная матрица проверок.
15. [`docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md`](docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md) — правила параллельной разработки.

## Машиночитаемые файлы

- [`config/network/network-roadmap.v1.json`](config/network/network-roadmap.v1.json);
- [`config/network/local-lab.example.json`](config/network/local-lab.example.json).

## Главное решение

> Сетевой слой развивается поверх существующих доменных команд, UUID,
> `SpatialRef`, revisions, operation ledger и authority epoch. Серверы не владеют
> идентичностью и координатами мира навсегда. Они получают временную аренду права
> изменять конкретные сущности и interaction islands.

Перед настоящим transport и handoff необходимо закрепить границу:

```text
canonical simulation ≠ presentation ≠ transport
```
