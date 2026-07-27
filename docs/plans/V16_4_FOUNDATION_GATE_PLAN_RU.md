# План v16.4 — Foundation Gate

# Статус реализации

Checkpoint `v16.3.2-foundation-lifecycle-part2-fix2`:

- [x] pure-domain runtime roles;
- [x] launch option parser;
- [x] runtime descriptor;
- [x] launch context передаётся runtime;
- [x] authority transfer сохраняет monotonic revision;
- [x] LifecycleCoordinator процесса;
- [x] graceful shutdown и command fencing;
- [x] terrain stop/drain barrier;
- [x] synchronous world-runtime disposal;
- [x] isolated process user data в Python harness;
- [x] simulation-server без активных UI, камер и local input;
- [ ] физическое разделение SimulationKernel/PresentationHost;
- [ ] WorldEntityAggregate;
- [ ] entity/chunk lifecycle Dormant/Warm/Active/Unloading.

Foundation Gate остаётся незавершённым. Lifecycle Part 2 fix2 закрывает terminal world-load fence после failed shutdown; следующий core-блок — canonical WorldEntityAggregate и формальная граница SimulationKernel/PresentationHost.

## Цель

Подготовить локальную архитектуру PlanetSimulator к выделенному simulation server,
не включая настоящий сетевой transport.

Foundation Gate закрывает разрыв между работающим offline-клиентом и переносимым
canonical simulation kernel.

## 1. Runtime roles

Добавить pure-domain значения:

```text
offline
client
simulation-server
bot-client
```

Параметры запуска:

```text
--role=<role>
--node-id=<id>
--instance-id=<id>
--user-data-dir=<path>
```

На этом этапе `listen-port` и `connect` могут быть объявлены, но transport не
обязан открывать сокеты.

## 2. SimulationKernel

Выделить headless-safe orchestration:

```text
SimulationKernel
├── SimulationClock
├── CommandGateway
├── EntityRegistry
├── ItemDomain
├── WorldStateRepository
├── PartitionRuntime
├── GravityField
└── LifecycleCoordinator
```

Запрещённые зависимости kernel:

- `Control` и UI;
- активная камера;
- обязательный `MeshInstance3D`;
- editor-only API;
- прямой network peer;
- input events как доменные команды.

## 3. PresentationHost

Presentation становится подключаемым adapter:

```text
PresentationHost
├── camera/input
├── terrain meshes
├── entity visuals
├── inventory UI
├── audio
└── debug overlays
```

Offline mode создаёт `SimulationKernel + PresentationHost`.
Simulation-server создаёт только kernel.

## 4. Shutdown barrier

Добавить lifecycle состояния процесса:

```text
STARTING
READY
STOPPING
STOPPED
FAILED
```

Последовательность остановки:

1. запретить новые команды;
2. прекратить новые terrain jobs;
3. пометить выполняемые jobs отменёнными;
4. дождаться WorkerThreadPool tasks;
5. завершить pending commits;
6. сохранить authoritative state;
7. закрыть transport adapters;
8. записать JSONL `node_stopped`;
9. завершить процесс кодом 0.

## 5. Entity и Chunk Lifecycle

Формализовать:

```text
Dormant
Warm
Active
Unloading
```

Минимальные правила:

- `Dormant`: только persisted snapshot;
- `Warm`: canonical state в памяти, без physics/presentation nodes;
- `Active`: canonical state + simulation activation;
- `Unloading`: новые мутации fenced, snapshot flush, presentation release.

Presentation activation не должна определять canonical lifecycle.

## 6. WorldEntityAggregate

Целевая модель:

```text
WorldEntityAggregate
├── entity_id
├── entity_type
├── authority_owner_id
├── authority_epoch
├── state_revision
├── SpatialRef
├── PartitionAddress
├── physics_state
└── domain_components
    └── item_graph_root / cargo / attachments
```

WORLD relation предмета не должна хранить вторую независимую spatial truth.
Допустимы:

- ссылка на `entity_id`;
- embedded snapshot только как transport/persistence representation одного aggregate.

## 7. Revision semantics

Изменить transfer authority:

```text
authority_epoch := authority_epoch + 1
state_revision := state_revision или state_revision + 1
```

Запрещено:

```text
state_revision := 0
```

Owner-local counters при необходимости выделяются отдельно.

## 8. Persistence ports

Разделить:

```text
WorldStateStore
WorldStateRepository
EntityActivationService
PresentationAdapter
```

Repository не должен быть обязан создавать `Node3D`.

## 9. Тесты

Обязательные новые тесты:

1. `test_runtime_role_contract`;
2. `test_simulation_kernel_headless_boot`;
3. `test_shutdown_during_terrain_generation`;
4. `test_entity_lifecycle_state_machine`;
5. `test_world_entity_aggregate_roundtrip`;
6. `test_authority_transfer_revision_monotonicity`;
7. `test_presentation_disabled_server_boot`;
8. `test_isolated_user_data`.

## 10. Критерий выхода

Foundation Gate принят, когда:

- simulation-server boot не создаёт UI и камеры;
- процесс завершается кодом 0 при активном terrain worker;
- старые offline tests остаются зелёными;
- `WorldEntityAggregate` имеет canonical round-trip;
- authority transfer не уменьшает revision;
- presentation можно отключить конфигурацией;
- каждый test process использует отдельный user data path.

## 11. Не входит в v16.4

- ENet connection;
- snapshot replication между процессами;
- World Directory;
- lease renewal;
- authority handoff;
- player prediction;
- ghosts.
