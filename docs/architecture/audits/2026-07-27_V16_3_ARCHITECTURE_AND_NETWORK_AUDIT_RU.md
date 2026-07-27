# PlanetSimulator — архитектурная ревизия после v16.3.0

Дата: 27 июля 2026 года
Проверяемый архив: `lunar-world-double-godot(3).zip`
Движок: `Godot 4.7.1.stable.double.custom_build.a13da4feb`

## 1. Проверенный checkpoint

- Текущая версия кода: `v16.3.0-r2-inventory-ux`.
- Git HEAD: `35cb5da` — документация дорожной карты сети.
- 97 GDScript-файлов в `scripts/`.
- 36 файлов тестов, из них 34 обязательных `test_*.gd` в regression manifest.
- 5 runtime-миров: `moon`, `earth`, `earth_moon`, `item_lab`, `playground`.
- Editor import/parse на приложенной double-сборке: PASS, зарегистрировано 133 global classes.
- Все 34 обязательных test scripts достигли собственного результата PASS.
- `test_world_switch_during_generation` завершился кодом 0.
- `test_unified_runtime_boot` и `test_world_boot_matrix` напечатали PASS, но Linux-процесс не завершился автоматически из-за фонового terrain worker.

Источники в проекте:

- `scripts/app/lunar_app.gd:34-35`
- `RUN_WORLD_REGRESSION_TESTS.ps1:42-80`
- `config/worlds/catalog.json`
- `README_RU.md`

## 2. Что фактически построено

### Simulator Core

- единый `SimulatorApp`;
- versioned `WorldCatalog`;
- runtime contract;
- общий `CommandRegistry` и `RuntimeTestRegistry`;
- загрузка и выгрузка пяти миров;
- консоль и системное меню;
- world-switch fencing для terrain generation.

### Координаты и распределённый фундамент

- double precision;
- `SimulationClock`;
- `SpatialRef`;
- `FrameGraph` и motion providers;
- `PartitionAddress v2`;
- cube-sphere grid;
- universe / instance / space / frame / partition разделены;
- authority owner и epoch уже присутствуют в EntityRecord/EntityRegistry.

### Планеты и физика

- процедурная Луна;
- процедурная Земля;
- единое Earth–Moon simulation space;
- атмосфера Земли;
- асинхронный streaming Луны;
- gravity field Солнца, Земли и Луны;
- test-particle trajectory integrator;
- рекурсивная физическая масса контейнеров.

### Предметный домен

- UUID предметов;
- versioned Item Registry;
- relation `WORLD / CONTAINER / ATTACHMENT`;
- полный item graph snapshot;
- BULK и SLOTS контейнеры;
- operation ledger;
- optimistic revisions;
- canonical payload hash;
- inventory, hotbar, pickup/drop/mount;
- placeable beacon mount;
- stack merge/split;
- fail-closed persistence.

### Тестовый фундамент

- editor import/parse barrier;
- double precision contract;
- 34 обязательных headless tests;
- main-scene smoke tests;
- отдельные item, terrain, persistence и runtime tests;
- JSON regression report.

## 3. Состояние сетевой дорожной карты

Сетевая программа хорошо описана документально:

- `NETWORK_ROADMAP_RU.md`;
- `docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`;
- `docs/network/NETWORK_READINESS_CHECKPOINT_RU.md`;
- `docs/network/NETWORK_TEST_MATRIX_RU.md`;
- ADR-005 и ADR-006;
- конфигурация local network lab.

Но commit `35cb5da` добавил только документацию и примеры конфигурации. В коде отсутствуют:

- `NetworkCommandEnvelope`;
- `EntitySnapshotEnvelope`;
- `AuthorityLease`;
- `AuthorityRoute`;
- `HandoffTicket`;
- `ENetMultiplayerPeer` adapter;
- simulation-server/client roles;
- Python process harness;
- network test suite;
- World Directory.

Следовательно, фактическая сетевой стадия — **до N0**.

## 4. Что уже можно повторно использовать для сети

1. UUID и стабильная идентичность.
2. `SpatialRef` как canonical spatial state.
3. `PartitionAddress v2` как постоянный адрес данных.
4. `expected_revision` и operation ledger.
5. `authority_owner_id` и `authority_epoch`.
6. Transactional item graph snapshot.
7. Command Registry как вход в доменные действия.
8. JSONL logging и regression infrastructure.
9. World runtime lifecycle.
10. Gravity/velocity state для передачи движущихся объектов.

## 5. Главные архитектурные разрывы

### 5.1 Simulation и presentation ещё смешаны

`SimulatorApp` всегда создаёт `DeveloperConsole`, `SystemMenu` и `Node3D WorldHost` (`scripts/app/simulator_app.gd:74-88`).

`LunarWorldRepository` одновременно:

- читает/пишет состояние;
- создаёт `Node3D` roots;
- создаёт runtime nodes;
- создаёт landmark markers;
- обновляет render transforms.

Для dedicated server это нужно разделить на:

- canonical repository;
- activation/lifecycle service;
- presentation adapter.

### 5.2 Нет server role и чистого shutdown

Нет `--role=simulation-server`, `--node-id`, `--listen-port`.

Два теста достигают PASS, но процесс продолжает жить после результата. Для multi-process harness это блокер: process manager не сможет надёжно отличать завершённый узел от зависшего worker.

### 5.3 Item Graph и Entity Registry пока два независимых мира

WORLD-item хранит spatial state в item relation. `EntityRecord` отдельно хранит `SpatialRef`, partition и authority.

Перед handoff нельзя иметь две потенциальные canonical spatial truths. Нужно выбрать единый aggregate:

```text
WorldEntityAggregate
  entity identity + authority + spatial + partition
  item graph root / cargo / attachments
  physics state
```

Рекомендуется: `EntityRecord` хранит canonical WORLD spatial state, а item relation WORLD ссылается на `entity_id`, а не дублирует независимую истину.

### 5.4 Authority существует, lease отсутствует

`EntityRegistry` проверяет owner/epoch, но отсутствуют:

- lease ID;
- срок действия;
- renew-after;
- heartbeat;
- route lookup;
- durable commit record;
- recovery после node restart.

### 5.5 Revision при authority transfer сбрасывается

`EntityRecord.transfer_authority()` сбрасывает `state_revision` и `revision` в ноль (`scripts/simulation/entities/entity_record.gd:266-273`).

Это конфликтует с сетевым инвариантом монотонной revision и может сделать старую команду визуально «новой» после handoff.

Правильнее:

- `authority_epoch` увеличивается;
- global state revision не уменьшается;
- при необходимости owner-local sequence хранится отдельным полем.

### 5.6 Chunk lifecycle пока не формализован

В roadmap уже отмечены состояния `Dormant / Warm / Active / Unloading`, но в коде они не являются единым контрактом.

Без этого нельзя корректно реализовать:

- interest management;
- ghosts;
- server memory budget;
- activation queue;
- безопасную передачу region authority.

### 5.7 Legacy persistence мешает тестовой изоляции

`moon-experiment-001/world.json` продолжает давать identity mismatch. Тесты проходят, но multi-process network lab обязан получать отдельный чистый `user://` и deterministic world ID на каждый процесс.

### 5.8 Большие монолиты

Крупнейшие файлы:

- `procedural_moon_terrain.gd` — ~117 KB;
- `lunar_app.gd` — ~60 KB;
- `lunar_world_repository.gd` — ~53 KB;
- `terrain_streaming_manager.gd` — ~45 KB;
- `simulator_app.gd` — ~41 KB;
- `item_gameplay_controller.gd` — ~39 KB.

Перед параллельной разработкой желательно выделять сервисы по контрактам, а не продолжать наращивать эти orchestration-файлы.

## 6. Рекомендуемое направление

Не переходить сразу к N4 handoff или большой энергетике. Следующий главный пакет должен быть **Foundation Gate v16.4 / Network N0**.

### Поток C — Core Foundation

1. `RuntimeRole`:
   - client;
   - offline;
   - simulation-server;
   - bot-client.
2. `SimulationKernel` без UI.
3. `PresentationHost` как подключаемый adapter.
4. Явный async shutdown barrier:
   - stop accepting work;
   - cancel;
   - await workers;
   - flush persistence;
   - emit node_stopped;
   - quit.
5. Формализованный chunk/entity lifecycle.
6. `WorldEntityAggregate` и единая spatial authority.

### Поток N — Network

Реализовать N0:

- versioned DTO;
- canonical JSON;
- protocol fixtures;
- authority epoch fencing;
- handoff state machine как pure domain;
- network contract lint;
- `RUN_NETWORK_CONTRACT_TESTS`.

После N0 — N1:

- один headless simulation server;
- один bot client;
- ENet transport adapter;
- initial snapshot;
- одна команда `item.move_to_container`;
- checksum server/client.

### Поток G — Gameplay / R3

Строительство можно делать параллельно, но только через новые правила:

- `PlaceStructureCommand`;
- UUID каждого foundation/module;
- versioned construction aggregate;
- sockets;
- placement validation;
- structure snapshot;
- interaction island descriptor;
- тест без UI;
- presentation только слушает canonical state.

Первый вертикальный срез R3:

```text
Foundation
→ Beacon Mount
→ Solar Panel
→ Battery
→ simple power graph
→ save/restart
→ remote command-ready
```

### Поток T — Test Infrastructure

1. Linux/Windows runner parity.
2. Process cleanup test.
3. Python multi-process harness.
4. Отдельный user data dir на процесс.
5. JSON/JUnit report.
6. Duplicate delivery/reconnect/fault profiles.

## 7. Приоритетная последовательность

### Итерация A — v16.4 Foundation Gate

- server-safe kernel;
- presentation split;
- shutdown barrier;
- aggregate unification;
- revision semantics fix;
- lifecycle contract;
- update network checkpoint to v16.3+.

### Итерация B — N0

- network DTO;
- fixtures;
- state machines;
- contract tests.

A и B можно вести параллельно.

### Итерация C — N1 + R3.1

Параллельно:

- N1 server/bot item command;
- R3.1 foundation + placement preview.

Оба используют один Command Gateway и один aggregate serializer.

### Итерация D — N2

- Python multi-process lab;
- 1 server + 2 clients;
- restart/reconnect;
- duplicate command.

### Итерация E — N3

- World Directory;
- leases;
- epoch renewal;
- two static authority regions.

### Итерация F — N4

- handoff одного камня или маяка;
- без player handoff;
- pause до 500 ms допустима;
- no duplicate authority.

## 8. Что пока отложить

- Kubernetes/Agones;
- NATS control plane;
- player make-before-break handoff;
- ghosts и distributed collision;
- динамический split Земли;
- полноценную распределённую N-body физику;
- сложный корабль с интерьером;
- большой power grid.

## 9. Решение ревизии

Проект уже имеет правильный локальный фундамент и может начать сетевую ветку сейчас. Однако следующий шаг должен быть не «добавить сокеты», а отделить canonical simulation от presentation и реализовать N0 contracts.

Рекомендуемый основной checkpoint:

```text
v16.4-foundation
+ N0 network contracts
```

После него можно безопасно вести параллельно:

```text
R3 construction
N1 single authority networking
N2 multi-process test infrastructure
```
