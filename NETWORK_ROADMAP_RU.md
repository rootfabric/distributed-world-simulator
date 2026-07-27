# Дорожная карта сетевой бесшовности PlanetSimulator

Этот файл — точка входа в отдельную сетевую программу проекта.

Текущий статус: `v16.3.0-r2-inventory-ux`. Фактическая сеть находится **до N0**.
Следующее принятое направление: `v16.4 Foundation Gate + N0 Network Contracts`.

## Основные документы

1. [`docs/checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md`](docs/checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md) — принятое архитектурное решение и следующий gate.
2. [`docs/architecture/audits/2026-07-27_V16_3_ARCHITECTURE_AND_NETWORK_AUDIT_RU.md`](docs/architecture/audits/2026-07-27_V16_3_ARCHITECTURE_AND_NETWORK_AUDIT_RU.md) — полный аудит фактического кода, документов и тестов.
3. [`docs/network/NETWORK_READINESS_CHECKPOINT_RU.md`](docs/network/NETWORK_READINESS_CHECKPOINT_RU.md) — текущая готовность проекта к сети.
4. [`docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`](docs/plans/V16_4_FOUNDATION_GATE_PLAN_RU.md) — отделение canonical simulation от presentation и server-safe lifecycle.
5. [`docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md`](docs/network/N0_NETWORK_CONTRACTS_PLAN_RU.md) — первый исполняемый сетевой этап без сокетов.
6. [`docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`](docs/network/SEAMLESS_WORLD_ROADMAP_RU.md) — последовательность N0–N11.
7. [`docs/network/NETWORK_STACK_RESEARCH_RU.md`](docs/network/NETWORK_STACK_RESEARCH_RU.md) — исследование Godot-библиотек и инфраструктурных компонентов.
8. [`docs/network/LOCAL_MULTI_PROCESS_TESTING_RU.md`](docs/network/LOCAL_MULTI_PROCESS_TESTING_RU.md) — локальный стенд нескольких Godot-процессов и fault injection.
9. [`docs/network/NETWORK_TEST_MATRIX_RU.md`](docs/network/NETWORK_TEST_MATRIX_RU.md) — обязательная матрица автоматических проверок.
10. [`docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md`](docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md) — правила параллельной разработки core, network и gameplay.
11. [`docs/network/AGENT_TASK_CARDS_RU.md`](docs/network/AGENT_TASK_CARDS_RU.md) — небольшие самостоятельные задачи для агентской разработки.
12. [`docs/network/NETWORK_PROTOCOL_GLOSSARY_RU.md`](docs/network/NETWORK_PROTOCOL_GLOSSARY_RU.md) — единая терминология.

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
