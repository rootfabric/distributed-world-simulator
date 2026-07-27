# Checkpoint v16.3 — готовность архитектурного фундамента и сетевой ветки

Дата фиксации: 27 июля 2026 года
Проверенный checkpoint кода: `v16.3.0-r2-inventory-ux`
Проверенный архив: `lunar-world-double-godot(3).zip`
Целевая сборка: `Godot 4.7.1 stable double custom build a13da4feb`

## 1. Назначение checkpoint

Этот документ фиксирует решение после завершения R1–R2 и архитектурной ревизии проекта.
Он определяет:

- что уже считается устойчивым фундаментом;
- что пока существует только в документации;
- какие разрывы необходимо закрыть перед настоящим сетевым handoff;
- как параллельно развивать core, network, gameplay и test infrastructure;
- какой следующий крупный этап считается обязательным.

Полный аудит:
`docs/architecture/audits/2026-07-27_V16_3_ARCHITECTURE_AND_NETWORK_AUDIT_RU.md`.

## 2. Что принято как существующий фундамент

### 2.1 Simulator Core

Приняты:

- единый `SimulatorApp`;
- versioned `WorldCatalog`;
- runtime lifecycle пяти миров;
- общий `CommandRegistry`;
- общий `RuntimeTestRegistry`;
- developer console и system menu;
- world-switch fencing для terrain generation.

Миры:

```text
moon
earth
earth_moon
item_lab
playground
```

### 2.2 Координаты и пространство

Приняты:

- double precision;
- `SimulationClock`;
- `SpatialRef`;
- `FrameGraph`;
- motion providers;
- `PartitionAddress v2`;
- cube-sphere addressing;
- разделение `Universe / Instance / Space / Frame / Partition / Render Frame`;
- `authority_owner_id` и `authority_epoch` в локальном entity domain.

### 2.3 Планеты и физика

Приняты:

- процедурная Луна;
- процедурная Земля;
- общее Earth–Moon simulation space;
- атмосфера Земли;
- асинхронный lunar terrain streaming;
- gravity field Солнца, Земли и Луны;
- test-particle trajectory integrator;
- рекурсивная физическая масса контейнеров.

### 2.4 Предметный домен

Приняты:

- глобальные UUID;
- versioned Item Registry;
- relation `WORLD / CONTAINER / ATTACHMENT`;
- полный transactional Item Graph snapshot;
- `BULK` и `SLOTS` containers;
- operation ledger;
- optimistic revisions;
- canonical payload hash;
- inventory, hotbar, pickup, drop, mount и placement;
- stack merge/split;
- fail-closed persistence.

### 2.5 Тестовый фундамент

Зафиксированы:

- editor import/parse barrier;
- double-precision contract;
- 34 обязательных headless test scripts;
- main-scene smoke tests;
- JSON regression report;
- отдельные item, persistence, terrain и runtime tests.

Два тяжёлых Linux-теста достигают `PASS`, но процесс может оставаться живым из-за
фонового terrain worker. Это не отменяет функциональный результат, но является
обязательным lifecycle-блокером для многопроцессной сетевой лаборатории.

## 3. Фактическое состояние сетевого слоя

Документация сетевой программы уже существует:

- `NETWORK_ROADMAP_RU.md`;
- `docs/network/SEAMLESS_WORLD_ROADMAP_RU.md`;
- `docs/network/NETWORK_READINESS_CHECKPOINT_RU.md`;
- `docs/network/NETWORK_TEST_MATRIX_RU.md`;
- ADR-005 и ADR-006;
- примеры конфигурации local network lab.

Но в коде пока отсутствуют:

- `NetworkCommandEnvelope`;
- `EntitySnapshotEnvelope`;
- `AuthorityLease`;
- `AuthorityRoute`;
- `HandoffTicket`;
- transport adapter;
- simulation-server/client roles;
- Python multi-process harness;
- World Directory;
- network regression suite.

Следовательно, фактическая стадия сети: **до N0**.

## 4. Главные архитектурные разрывы

### 4.1 Simulation и presentation смешаны

Dedicated server пока нельзя запустить без обязательных UI, камер, scene roots и
presentation orchestration. Требуется разделение:

```text
SimulationKernel
PresentationHost
TransportAdapter
```

### 4.2 Нет server-safe shutdown

Нужен явный barrier:

```text
stop accepting work
→ cancel background jobs
→ await workers
→ flush persistence
→ emit node_stopped
→ quit code 0
```

### 4.3 WORLD item и EntityRecord могут стать двумя spatial truths

Перед handoff требуется единый `WorldEntityAggregate`, который объединяет:

```text
identity
authority
SpatialRef
PartitionAddress
physics state
item/container/attachment graph
```

### 4.4 Authority epoch есть, lease отсутствует

Нужны lease ID, expiration, renew, heartbeat, route lookup и recovery semantics.

### 4.5 Revision не должна сбрасываться при authority transfer

Инвариант следующего слоя:

```text
authority_epoch увеличивается
state_revision никогда не уменьшается
```

### 4.6 Chunk lifecycle не формализован

Нужен исполняемый контракт:

```text
Dormant
Warm
Active
Unloading
```

### 4.7 Test user data не изолированы

Каждый server/client process должен получать отдельный `user://` и deterministic
world ID. Legacy `moon-experiment-001/world.json` не должен влиять на сетевой стенд.

## 5. Решение по следующему этапу

Следующий обязательный пакет:

```text
v16.4 Foundation Gate
+
N0 Network Contracts
```

Эти два потока разрешено вести параллельно.

### Core Foundation

- runtime roles;
- `SimulationKernel` без presentation;
- подключаемый `PresentationHost`;
- shutdown barrier;
- entity/chunk lifecycle;
- единый `WorldEntityAggregate`;
- монотонная revision при authority transfer.

### Network N0

- versioned DTO;
- canonical JSON fixtures;
- authority epoch fencing;
- pure-domain handoff state machine;
- network contract lint;
- отдельный `RUN_NETWORK_CONTRACT_TESTS`.

### Gameplay R3

Можно развивать параллельно только через доменные команды и snapshots:

```text
Foundation
→ Beacon Mount
→ Solar Panel
→ Battery
→ Charging Dock
→ simple Power Graph
```

### Test Infrastructure

- process cleanup test;
- isolated user data;
- Linux/Windows runner parity;
- Python multi-process harness после N1;
- JSON/JUnit reports.

## 6. Порядок последующих этапов

1. `v16.4 Foundation Gate` и `N0` параллельно.
2. `N1` authoritative server + bot client и `R3.1` foundation параллельно.
3. `N2` local multi-process network lab.
4. `N3` World Directory и leases.
5. `N4` handoff одного камня или маяка.
6. Только затем player handoff, ghosts, child spaces и dynamic region split.

## 7. Что намеренно отложено

До N4 не начинать как основной трек:

- Kubernetes/Agones;
- NATS control plane;
- WAN player handoff;
- distributed collision;
- dynamic split Земли;
- distributed N-body;
- большой корабль с интерьером;
- сложный энергетический граф.

## 8. Архитектурный инвариант

Следующие изменения обязаны сохранять границу:

```text
canonical simulation
≠ presentation
≠ transport
```

Offline-клиент может собирать все три слоя в одном процессе, но доменная логика не
должна зависеть от UI, SceneTree transport или конкретного сетевого протокола.

## 9. Следующий acceptance checkpoint

Следующая архитектурная приёмка должна подтвердить:

- headless simulation role без UI;
- корректный shutdown при активном terrain worker;
- монотонные revisions при transfer authority;
- единый canonical WORLD aggregate;
- versioned N0 DTO и fixtures;
- отсутствие Godot runtime types в network contracts;
- полный старый offline regression без изменений.
