# Дорожная карта сетевой бесшовности PlanetSimulator

Этот файл — точка входа в отдельную сетевую программу проекта.

Текущий статус: `v16.5.0-network-n1-snapshot` (candidate). N1.0 принят. N1.1 реализует настоящий ENet handshake и initial snapshot между отдельными headless Godot-процессами. Следующий этап — N1.2 remote authoritative item command.

## Основные документы

1. [`docs/checkpoints/2026-07-28_V16_5_0_NETWORK_N1_SNAPSHOT_RU.md`](docs/checkpoints/2026-07-28_V16_5_0_NETWORK_N1_SNAPSHOT_RU.md) — текущий N1.1 candidate.
2. [`docs/network/N1_NETWORK_IMPLEMENTATION_PLAN_RU.md`](docs/network/N1_NETWORK_IMPLEMENTATION_PLAN_RU.md) — точный план N1.0–N5 и checkpoint gates.
3. [`docs/checkpoints/2026-07-28_V16_4_2_NETWORK_TRANSPORT_BOUNDARY_RU.md`](docs/checkpoints/2026-07-28_V16_4_2_NETWORK_TRANSPORT_BOUNDARY_RU.md) — принятый N1.0.
3. [`docs/checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md`](docs/checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md) — закрытие найденных N0 boundary bypasses.
4. [`docs/checkpoints/2026-07-27_V16_4_0_FOUNDATION_N0_RU.md`](docs/checkpoints/2026-07-27_V16_4_0_FOUNDATION_N0_RU.md) — исходный Foundation/N0 checkpoint.
5. [`docs/contracts/N0_NETWORK_CONTRACTS_V1_RU.md`](docs/contracts/N0_NETWORK_CONTRACTS_V1_RU.md) — точные DTO, checksums, handoff и loopback.
6. [`docs/checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_FIX2_RU.md`](docs/checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_FIX2_RU.md) — принятый canonical WORLD aggregate.
7. [`docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md`](docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md) — terminal lifecycle fence.
8. [`docs/network/NETWORK_READINESS_CHECKPOINT_RU.md`](docs/network/NETWORK_READINESS_CHECKPOINT_RU.md) — текущая готовность к N1.
9. [`docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`](docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md) — план и acceptance Foundation.
10. [`docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md`](docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md) — план и acceptance N0.
11. [`docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`](docs/network/SEAMLESS_WORLD_ROADMAP_RU.md) — последовательность N0–N11.
12. [`docs/network/NETWORK_TEST_MATRIX_RU.md`](docs/network/NETWORK_TEST_MATRIX_RU.md) — обязательная матрица проверок.
13. [`docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md`](docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md) — правила параллельной разработки.

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
