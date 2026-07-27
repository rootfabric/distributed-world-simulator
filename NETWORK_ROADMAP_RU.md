# Дорожная карта сетевой бесшовности PlanetSimulator

Этот файл — точка входа в отдельное сетевое изыскание проекта.

Основные документы:

1. [`docs/network/NETWORK_READINESS_CHECKPOINT_RU.md`](docs/network/NETWORK_READINESS_CHECKPOINT_RU.md) — фактическая готовность текущего проекта к сети.
2. [`docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`](docs/network/SEAMLESS_WORLD_ROADMAP_RU.md) — пошаговая дорожная карта от локального сервера до распределённой бесшовности.
3. [`docs/network/NETWORK_STACK_RESEARCH_RU.md`](docs/network/NETWORK_STACK_RESEARCH_RU.md) — исследование Godot-библиотек и инфраструктурных компонентов.
4. [`docs/network/LOCAL_MULTI_PROCESS_TESTING_RU.md`](docs/network/LOCAL_MULTI_PROCESS_TESTING_RU.md) — локальный стенд с несколькими Godot-процессами, клиентами и fault injection.
5. [`docs/network/NETWORK_TEST_MATRIX_RU.md`](docs/network/NETWORK_TEST_MATRIX_RU.md) — обязательная матрица автоматических проверок.
6. [`docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md`](docs/network/PARALLEL_DEVELOPMENT_RULES_RU.md) — правила параллельной разработки сети, предметов, строительства и энергетики.
7. [`docs/network/AGENT_TASK_CARDS_RU.md`](docs/network/AGENT_TASK_CARDS_RU.md) — маленькие самостоятельные задачи для агентской разработки.
8. [`docs/network/NETWORK_PROTOCOL_GLOSSARY_RU.md`](docs/network/NETWORK_PROTOCOL_GLOSSARY_RU.md) — единая терминология.

Машиночитаемые файлы:

- [`config/network/network-roadmap.v1.json`](config/network/network-roadmap.v1.json);
- [`config/network/local-lab.example.json`](config/network/local-lab.example.json).

Главное решение:

> Сетевой слой развивается поверх существующих доменных команд, UUID, `SpatialRef`, revisions, operation ledger и authority epoch. Серверы не владеют идентичностью и координатами мира навсегда. Они получают временную аренду права изменять конкретные сущности и interaction islands.
