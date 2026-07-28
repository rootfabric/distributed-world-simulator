# Правила параллельной разработки сети и gameplay

## Текущий режим после v16.4.1-foundation-inventory-merge

Foundation Gate и N0 завершены. Одновременно разрешены три потока:

```text
Track N — N1 Authoritative Server + Bot Client
Track G — R3.1 Construction Vertical Slice
Track T — Multi-process Test Infrastructure
```

Track N подключает реальный transport к принятым N0 DTO и не меняет доменную
семантику без отдельной версии протокола. Track G использует те же commands,
revisions, aggregates и snapshots. Track T обеспечивает process isolation,
fault injection, reconnect и отчёты.

Рекомендуемые каталоги ответственности:

```text
Track N:
  scripts/network/transports/
  scripts/network/client/
  scripts/network/server/
  tests/network/
  tests/process/

Track G:
  scripts/construction/domain/
  scripts/construction/services/
  scripts/construction/presentation/
  tests/construction/

Track T:
  tests/process/
  tools/network/
  artifacts/test-results/
```

Общие файлы `CommandGateway`, `WorldEntityAggregate`, schema registry и N0 DTO
меняются только через versioned contract change и integration gate.

Связанные документы:

- `../checkpoints/2026-07-28_V16_4_1_FOUNDATION_INVENTORY_MERGE_RU.md`;
- `N0_NETWORK_CONTRACTS_PLAN_RU.md`;
- `../contracts/N0_NETWORK_CONTRACTS_V1_RU.md`;
- `../checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md`;
- `../checkpoints/2026-07-27_V16_4_0_FOUNDATION_N0_RU.md`.

## Базовые правила параллельной разработки

## 1. Можно ли вести сеть параллельно

Да. После N0 сетевой трек может развиваться независимо от:

- новых предметов;
- строительства;
- power/data/mechanical graph;
- новых планет и terrain;
- UI;
- роботов;
- транспорта.

Но обе ветки должны соблюдать единые доменные правила.

## 2. Три параллельных потока

### Track G — Gameplay

- предметы;
- строительство;
- энергетика;
- инструменты;
- базы;
- роботы;
- транспорт.

### Track N — Network

- DTO;
- transports;
- server roles;
- directory;
- authority;
- handoff;
- ghosts;
- routing.

### Track T — Test Infrastructure

- Python harness;
- process lifecycle;
- isolated user data;
- Docker Compose;
- fault injection;
- reports;
- soak tests.

Track N не должен блокировать Track G после завершения N0. Track T развивается вместе с каждым N-этапом.

## 3. Обязательный контракт новой игровой сущности

Любая изменяемая сущность должна иметь:

```text
stable entity_id
schema + schema_version
state_revision
authority_owner_id
authority_epoch
snapshot serializer
command handlers
validation
persistence adapter
network interest descriptor
```

Для мировой сущности дополнительно:

```text
SpatialRef
bounds
activation policy
physics island relation
```

## 4. Запрещённые паттерны

Нельзя:

- менять item/container state прямо из UI;
- хранить canonical position только в `Node3D`;
- использовать peer ID как entity ID;
- сохранять NodePath в network snapshot;
- считать server process постоянным владельцем пространства;
- отправлять полное SceneTree как сетевой контракт;
- запускать отдельную бизнес-логику для offline и online;
- добавлять клавишу, которая обходит `CommandRegistry`;
- делать сетевую репликацию до domain validation.

## 5. Правильный путь команды

```text
Input/UI/AI
→ CommandRegistry
→ Domain Command
→ validation + revision + authority
→ canonical state mutation
→ persistence/event
→ presentation update
→ network snapshot/delta
```

Offline mode использует local transport adapter:

```text
LocalLoopbackTransport
```

Online mode:

```text
ENetCommandTransport
```

Domain service не знает, откуда пришла команда.

## 6. Как параллельно делать строительство

Строительная система может развиваться до настоящей сети, если:

- placement оформлен командой;
- foundation/module получают UUID;
- socket graph имеет snapshot;
- power graph имеет versioned state;
- вся конструкция определяет interaction island;
- изменяемые chunks имеют owner token;
- тест может воспроизвести строительство без UI.

Когда появится handoff, целая связанная конструкция мигрирует одним aggregate/island, а не по одному блоку.

## 7. Как параллельно делать транспорт

Корабль или rover заранее должны иметь:

- control input DTO;
- authoritative motion state;
- `SpatialRef`;
- child space для интерьера при необходимости;
- список attached/contained entities;
- boundary crossing policy;
- promotion/demotion between analytical and local physics.

## 8. Merge gates

Каждый PR/патч Track G проходит:

```text
existing offline regression
snapshot round-trip
no direct presentation mutation
network contract lint
```

Каждый PR/патч Track N проходит:

```text
existing offline regression unchanged
network contract tests
multi-process scenario
process cleanup
JSON report
```

## 9. Версионирование

Изменение DTO:

- добавление optional поля — minor protocol revision;
- изменение семантики — новая schema version;
- удаление поля — новая schema version;
- server поддерживает текущую и предыдущую версию во время rolling upgrade;
- golden fixtures хранятся в репозитории.

## 10. Definition of Done для agent task

Агентская задача завершена только когда присутствуют:

1. изменённый код;
2. локальный test command;
3. acceptance assertions;
4. JSON report;
5. обновлённая документация контракта;
6. список изменённых файлов;
7. отсутствие ручных шагов для базовой проверки.
