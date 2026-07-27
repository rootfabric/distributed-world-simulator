# Дорожная карта сетевой бесшовности PlanetSimulator

Этот файл — точка входа в отдельную сетевую программу проекта.

Текущий статус: `v16.3.3-foundation-world-aggregate-part3`. N0 находится в работе: строгие command/result/snapshot contracts и loopback реализованы, transport sockets ещё не начаты. Foundation теперь содержит lifecycle barrier, presentation-free SimulationKernel boundary, WorldEntityAggregate, Item Graph v2 и формальный Entity/Chunk Lifecycle.

## Основные документы

1. [`docs/checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_RU.md`](docs/checkpoints/2026-07-27_V16_3_3_FOUNDATION_WORLD_AGGREGATE_PART3_RU.md) — canonical WORLD aggregate и Item Graph v2.
2. [`docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md`](docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_FIX2_RU.md) — terminal lifecycle world-load fence после failed shutdown.
3. [`docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_RU.md`](docs/checkpoints/2026-07-27_V16_3_2_FOUNDATION_LIFECYCLE_PART2_RU.md) — принятый lifecycle/shutdown checkpoint.
4. [`docs/checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md`](docs/checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md) — принятое архитектурное решение и следующий gate.
5. [`docs/architecture/audits/2026-07-27_V16_3_ARCHITECTURE_AND_NETWORK_AUDIT_RU.md`](docs/architecture/audits/2026-07-27_V16_3_ARCHITECTURE_AND_NETWORK_AUDIT_RU.md) — полный аудит фактического кода, документов и тестов.
6. [`docs/network/NETWORK_READINESS_CHECKPOINT_RU.md`](docs/network/NETWORK_READINESS_CHECKPOINT_RU.md) — текущая готовность проекта к сети.
7. [`docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`](docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md) — отделение canonical simulation от presentation и server-safe lifecycle.
8. [`docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md`](docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md) — первый исполняемый сетевой этап без сокетов.
9. [`docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`](docs/network/SEAMLESS_WORLD_ROADMAP_RU.md) — последовательность N0–N11.
10. [`docs/network/NETWORK_STACK_RESEARCH_RU.md`](docs/network/NETWORK_STACK_RESEARCH_RU.md) — исследование Godot-библиотек и инфраструктурных компонентов.
11. [`docs/network/LOCAL_MULTI_PROCESS_TESTING_RU.md`](docs/network/LOCAL_MULTI_PROCESS_TESTING_RU.md) — локальный стенд нескольких Godot-процессов и fault injection.
12. [`docs/network/NETWORK_TEST_MATRIX_RU.md`](docs/network/NETWORK_TEST_MATRIX_RU.md) — обязательная матрица автоматических проверок.
13. [`docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md`](docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md) — правила параллельной разработки core, network и gameplay.
14. [`docs/network/AGENT_TASK_CARDS_RU.md`](docs/network/AGENT_TASK_CARDS_RU.md) — небольшие самостоятельные задачи для агентской разработки.
15. [`docs/network/NETWORK_PROTOCOL_GLOSSARY_RU.md`](docs/network/NETWORK_PROTOCOL_GLOSSARY_RU.md) — единая терминология.

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
