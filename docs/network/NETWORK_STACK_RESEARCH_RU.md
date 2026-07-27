# Исследование сетевого стека для PlanetSimulator

## 1. Критерии выбора

Для проекта важнее не максимальное количество функций библиотеки, а:

1. понятная документация;
2. стабильный CLI и headless-режим;
3. возможность запускать несколько узлов локально;
4. отсутствие скрытой магии над доменным состоянием;
5. читаемые контракты для агентов и LLM;
6. лёгкое создание автоматических тестов;
7. независимость канонического мира от конкретного транспорта.

## 2. Рекомендуемый базовый стек

```text
Godot client/server realtime:  ENetMultiplayerPeer + MultiplayerAPI
Domain protocol:               versioned DTO + canonical JSON fixtures
Multi-process test harness:    Python + pytest + subprocess
Local services:                Docker Compose
Control plane later:           NATS Core + JetStream
Fault injection:               tc/netem for UDP, Toxiproxy for TCP/WebSocket
Production allocation later:   Agones
Prediction later:              netfox, selectively
Accounts/lobbies optionally:   Nakama
```

### Сравнительная матрица

Оценка `1–5`, где 5 — максимально подходит текущей задаче.

| Компонент | Документация | Понятность агентам | Локальные тесты | Пригодность для seamless core | Решение |
|---|---:|---:|---:|---:|---|
| Godot ENet/MultiplayerAPI | 5 | 5 | 5 | 4 | основа N1–N6 |
| netfox | 4 | 4 | 4 | 2 для handoff, 4 для prediction | подключать выборочно после N5 |
| Nakama Godot SDK | 5 | 5 | 5 | 2 | аккаунты, lobby, initial routing |
| NATS Core/JetStream | 5 | 4 | 5 | 4 для control plane | после локального Directory |
| GdUnit4 | 4 | 4 | 4 | не транспорт | optional, не мигрировать текущие тесты |
| GUT | 4 | 4 | 4 | не транспорт | запасной вариант |
| Python/pytest | 5 | 5 | 5 | 5 для orchestration tests | обязательный harness |
| Docker Compose | 5 | 5 | 5 | 4 | с N2/N3 |
| Toxiproxy | 4 | 5 | 5 | 3 | TCP/WebSocket fault tests |
| tc/netem | 4 | 3 | 5 | 5 | ENet UDP fault tests |
| Agones | 5 | 4 | 4 | 3 | только после N9 |


## 3. Godot built-in MultiplayerAPI и ENet

### Решение

Использовать как первый транспорт:

```gdscript
ENetMultiplayerPeer
MultiplayerAPI
SceneMultiplayer
```

Но не использовать автоматическую SceneTree replication как каноническое хранилище мира.

### Почему подходит

- входит в Godot и не требует addon;
- одинаковый GDScript работает в клиенте и headless-сервере;
- сервер можно запускать через `--headless`;
- один процесс Godot может иметь разные `MultiplayerAPI` на разных поддеревьях, что полезно для быстрых in-process тестов;
- ENet использует UDP и поддерживает reliable/unreliable каналы;
- легко запускается агентом одной командой.

### Ограничение

Wire-протокол `SceneMultiplayer` является implementation detail Godot и не предназначен для сторонних серверов. Поэтому DTO PlanetSimulator должны существовать независимо от RPC и SceneTree.

### Правило

```text
Godot RPC = транспортная оболочка
Network DTO = контракт проекта
Domain command = источник изменения
Scene node = представление
```

## 4. netfox

### Сильные стороны

- сетевой tick;
- синхронизация времени;
- interpolation;
- client-side prediction;
- server reconciliation;
- rollback-синхронизаторы;
- latency simulation;
- документация и примеры.

### Почему не берём в N0

Текущая физика PlanetSimulator активно использует `RigidBody3D`. Документация netfox прямо указывает, что стандартный Godot не предоставляет ручной physics stepping; полноценный rollback rigid-body physics требует специального движка или fork.

### Рекомендуемая роль

Оценивать после появления обычного authoritative client/server:

- движение персонажа;
- interpolation удалённых игроков;
- projectiles без сложных rigid-body constraints;
- client prediction для rover/ship controls;
- не использовать для authority handoff и World Directory.

## 5. Nakama

### Сильные стороны

- официальный Godot 4 SDK;
- authentication;
- sessions;
- users, friends, groups, chat;
- matchmaking и lobby;
- authoritative и relayed matches;
- локальный запуск в Docker;
- документация имеет отдельные Markdown-представления для LLM.

### Ограничение

Nakama authoritative match по своей модели закрепляется за одним узлом. Он не решает бесшовную миграцию physics authority между двумя Godot simulation nodes.

### Рекомендуемая роль

Не использовать как ядро server mesh. Подключать позднее для:

- аккаунтов;
- токенов;
- presence;
- lobby;
- matchmaking;
- выбора или выдачи адреса initial simulation node;
- out-of-band подключения к выделенному Godot-серверу.

## 6. NATS Core и JetStream

### Рекомендуемое назначение

Control plane, но не поток каждого physics transform.

Подходящие события:

```text
node.register
node.heartbeat
region.assign
authority.lease.request
authority.lease.changed
handoff.prepare
handoff.commit
handoff.abort
entity.route.changed
snapshot.checkpoint.created
```

Core NATS подходит для request/reply и ephemeral notifications. JetStream нужен для durable handoff/event records, повторной доставки и replay.

### Подключение к Godot

На первом этапе не добавлять NATS GDExtension в игру. Предпочтителен local sidecar:

```text
Godot SimulationNode
    ↕ loopback WebSocket/HTTP
Node Agent (Python/Go)
    ↕ NATS
World Directory / Orchestrator
```

Так доменный GDScript остаётся простым, а библиотека NATS используется в языках с официальными клиентами и сильными тестовыми инструментами.

## 7. Python + pytest

Это основной orchestrator локальных сетевых тестов.

Причины:

- явные fixtures;
- простое создание временных каталогов;
- `subprocess` для нескольких Godot-процессов;
- удобные timeouts и teardown;
- JSON/JUnit-отчёты;
- агенты хорошо понимают Python;
- можно постепенно добавить Docker/Testcontainers.

Godot-тесты остаются внутри проекта. Python не заменяет GDScript unit tests; он управляет процессами и проверяет межпроцессные инварианты.

## 8. GdUnit4 и GUT

В проекте уже есть простой и успешно работающий headless test manifest. Немедленная миграция не нужна.

### GdUnit4

Плюсы:

- CLI;
- scene runner;
- assertions, mocks и parameterized tests;
- поддержка актуальных Godot 4.x.

### GUT

Плюсы:

- зрелый проект;
- CLI;
- большая история использования;
- editor и headless запуск.

### Решение

- текущий custom runner остаётся обязательным regression gate;
- GdUnit4 можно добавить экспериментально только для новых network adapter tests;
- не переписывать 32 существующих теста;
- внешний multi-process test harness всё равно должен быть Python-based.

## 9. Docker Compose и Testcontainers

Docker Compose нужен начиная с N2:

```text
world-directory
sim-space-a
sim-space-b
client-bot-1
client-bot-2
nats (позднее)
toxiproxy (позднее)
```

Каждый сервис обязан иметь healthcheck. `depends_on` без `service_healthy` недостаточен, потому что запущенный процесс ещё не обязательно готов принимать соединения.

Testcontainers можно применять для Python integration tests, когда появятся NATS, PostgreSQL или другие реальные сервисы.

## 10. Fault injection

### ENet/UDP

Использовать Linux `tc netem`:

- delay;
- jitter;
- loss;
- duplication;
- reorder;
- corruption;
- rate limiting.

### TCP/WebSocket control plane

Использовать Toxiproxy:

- latency;
- timeout;
- disconnect;
- bandwidth;
- slow close.

## 11. Agones

Agones нужен только после рабочего локального handoff и устойчивого node lifecycle.

Он решает:

- Fleet;
- health;
- allocation;
- scale up/down;
- multi-cluster allocation.

Он не решает:

- authority ownership;
- entity snapshot;
- ghost replication;
- client handoff;
- physics continuity.

## 12. Формат протокола

### N0–N4

Использовать:

- versioned `Dictionary` DTO;
- canonical JSON;
- JSON fixtures;
- schema name и schema version;
- SHA-256 payload fingerprint.

Это максимально понятно агентам и удобно для diff.

### После стабилизации

Возможен переход wire payload на Protobuf или FlatBuffers. JSON fixtures и golden tests должны остаться как человекочитаемое эталонное представление.

## 13. Итог выбора

### Обязательный минимум

```text
Godot ENet
versioned DTO
Python pytest launcher
Docker Compose
JSONL logs
```

### Подключать позднее

```text
netfox       — prediction/interpolation
Nakama       — аккаунты/lobby/match routing
NATS         — control plane и durable events
Agones       — production process orchestration
```

## 14. Основные источники

- Godot high-level multiplayer: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- Godot dedicated servers: https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_dedicated_servers.html
- Godot SceneMultiplayer: https://docs.godotengine.org/en/stable/classes/class_scenemultiplayer.html
- netfox: https://foxssake.github.io/netfox/latest/
- netfox rollback caveats: https://foxssake.github.io/netfox/latest/netfox/tutorials/rollback-caveats/
- Nakama Godot 4: https://heroiclabs.com/docs/nakama/client-libraries/godot/
- Nakama authoritative multiplayer: https://heroiclabs.com/docs/nakama/concepts/multiplayer/authoritative/
- GdUnit4: https://godot-gdunit-labs.github.io/gdUnit4/latest/
- GUT: https://gut.readthedocs.io/
- pytest fixtures: https://docs.pytest.org/en/latest/explanation/fixtures.html
- Docker Compose startup order: https://docs.docker.com/compose/how-tos/startup-order/
- NATS queue groups: https://docs.nats.io/nats-concepts/core-nats/queue
- NATS JetStream: https://docs.nats.io/nats-concepts/jetstream
- Agones allocation: https://agones.dev/site/docs/reference/gameserverallocation/
- Toxiproxy: https://github.com/Shopify/toxiproxy
- netem: https://man7.org/linux/man-pages/man8/tc-netem.8.html
