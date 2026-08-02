# Robot Construction Grid — инструкция и план реализации RCG0–RCG8

**Статус:** инструкция для будущей feature-ветки.
**Первая ветка:** `feature/rcg0-robot-construction-grid-contracts`.
**Первый checkpoint:** определить при старте от фактической объединённой базы; логический ID `RCG0` неизменяем.
**Код до выполнения start gate:** не добавлять в production runtime.

---

## 1. Текущий срез проекта на 3 августа 2026 года

Разработка находится не в одном линейном `main`, а в нескольких зрелых feature-линиях. Для Robot Construction Grid важны три среза.

### Construction

```text
branch: feature/c23-production-hardening
delivery: fix1
state: construction vertical slice through production hardening
```

Последняя проверка C23 фиксирует:

```text
C23 focused:       4/4 profiles, 4187/4187 assertions, PASS
C22 regression:    191/191 assertions, PASS
C2B regression:    258/258 assertions, PASS
C9 regression:     204/204 assertions, PASS
network:           54/54 tests, 55/55 steps, PASS
world regression:  152/152 tests, 155/155 steps, PASS
```

Это означает, что item-backed construction, damage/split, runtime projection, utilities, authority, activity/LOD и hardening уже достаточно зрелы для нового специализированного domain layer.

### Representation and Matter

```text
checkpoint: v17.10.0-simulation-rl1-matter-summary-pyramid
branch: feature/rl1-matter-summary-pyramid
state: accepted in project history
```

RL1 включает общий RL0 lifecycle контрактов representation и добавляет summary pyramid/dirty propagation для Matter. Для RCG0 нужен прежде всего общий RL0 слой; matter-specific summary implementation не используется как robot grid storage.

### Network

```text
checkpoint: v16.13.0-network-nx3-fixed-tick-authoritative-simulation
branch: feature/nx3-fixed-tick-authoritative-simulation
state: accepted in project history
```

NX3 уже даёт fixed-tick authoritative foundation. Он не нужен для pure-domain RCG0, но должен быть включён до RCG4, где появятся движущиеся rigid segments, joints и сетевое управление роботом.

### Главный риск текущего среза

Эти линии ещё не следует считать одним доказанным production checkpoint только потому, что каждая прошла собственную приёмку. Перед RCG0 нужно создать воспроизводимую композицию, разрешить пересечения manifests/docs/runtime metadata и повторно прогнать общую регрессию.

---

## 2. Ответ: когда начинать

### 2.1. Pure-domain robot grid

`RCG0` можно начинать **сразу после одного объединяющего integration checkpoint**, в котором доказано совместное существование:

```text
C23 Production Hardening fix1
+
RL1 Matter Summary Pyramid
  └── содержит общий RL0 Representation contract layer
+
текущих Item Graph / aggregate transaction / authority boundaries
```

Практически это означает:

1. выбрать C23 как construction source of truth;
2. перенести или слить RL0/RL1 без создания второго representation contract layer;
3. разрешить конфликты документации, manifests и runtime metadata;
4. прогнать construction, representation, network и world regression;
5. зафиксировать integration commit/tag;
6. от него создать `feature/rcg0-robot-construction-grid-contracts`.

### 2.2. Что не блокирует RCG0

Для pure-domain occupancy и placement contracts не нужно ждать:

- MW9 durable distributed handoff;
- MW10 cross-region matter transactions;
- RL2 matter multiresolution meshing;
- RL3 artifact streaming;
- RL4 construction HLOD;
- RL5 cache scheduler;
- RL6 scale acceptance;
- Moon/planet matter integration;
- agent runtime;
- client prediction для робота.

### 2.3. Что блокирует поздние части

| Возможность | Минимальный prerequisite |
|---|---|
| локальный deterministic grid | unified `C23 + RL0/RL1` integration checkpoint |
| structural split/merge | RCG0 + существующие construction damage/split contracts |
| item install/demount | RCG0 + Item Graph/M0 transaction boundary |
| active rigid segments и joints | RCG1–RCG3 + C13 physics projection + integrated fixed-tick runtime |
| power/data/mechanical networks | RCG2 + C15 utility/machine runtime |
| сетевые construction deltas | RCG2 + текущий authoritative gameplay boundary |
| progressive artifact streaming | RL3 |
| robot/vehicle HLOD | RL4 + RL5 |
| один гигантский construct через несколько authority regions | MW9 + MW10 и соответствующий durable construction authority gate |
| массовые autonomous robot builders | RCG5 + agent API + scale acceptance |

### 2.4. Рекомендация

Не откладывать весь robot grid до конца RL-roadmap. Это создаст ненужную задержку и заставит HLOD проектироваться без реального grid source.

Правильный порядок:

```text
integration checkpoint C23 + RL1
↓
RCG0 contracts and occupancy
↓
RCG1 topology
↓
RCG2 item-backed transactions
↓
RCG3 split/merge
↓
параллельно завершаются MW9/MW10/RL2/RL3
↓
RCG4 physics and joints
↓
RCG5 utility/device networks
↓
RCG6 network and activity integration
↓
RL4/RL5
↓
RCG7 HLOD and large robots
↓
RCG8 agent/scale/production acceptance
```

---

## 3. Integration start gate

Перед созданием RCG0 обязательны следующие проверки.

### 3.1. Source composition

В одной рабочей tree должны существовать:

- C23 production-hardening construction code и tests;
- C2B item-backed construction identities;
- C9 damage/split/repair;
- C13 runtime projection boundary;
- C15 utility semantics/runtime;
- C17 authority ownership model;
- C18 activity/LOD policies;
- RL0 representation contracts;
- RL1 summary dependency/dirty semantics;
- текущий generic aggregate/M0 transaction boundary;
- текущий authoritative network runtime.

### 3.2. Нельзя начинать от устаревшего main

Если `main` не содержит C23 и RL1, RCG0 не создаётся напрямую от `main`.

Сначала создаётся короткоживущая integration-ветка, например:

```text
integration/c23-rl1-robot-grid-base
```

После зелёной проверки она фиксируется отдельным checkpoint и становится единственной базой RCG0.

### 3.3. Mandatory regression gate

На объединённой базе должны пройти:

```text
C23 focused profiles
C22 construction proxy/HLOD contracts currently present in construction line
C2B item-backed construction
C9 damage/split/repair
RL0 representation contracts
RL1 matter summary pyramid
current network contract/runtime profile
full world regression
editor import/parse
git diff --check
```

Точные runner names берутся из объединённой tree. Нельзя объявлять integration base принятой только по статическому merge.

---

## 4. Серия этапов

## RCG0 — Contracts, orientations and sparse occupancy

### Цель

Создать чистый domain grid без SceneTree, physics, devices и network transport.

### Ветка

```text
feature/rcg0-robot-construction-grid-contracts
```

### Предлагаемые файлы

```text
config/robot_grid/rcg0-robot-construction-grid.v1.json

scripts/construction/robot_grid/contracts/
├── robot_grid_contract_utils.gd
├── robot_grid_cell_address.gd
├── robot_grid_orientation.gd
├── robot_grid_part_placement.gd
├── robot_grid_segment_descriptor.gd
├── robot_grid_snapshot.gd
└── robot_grid_operation_result.gd

scripts/construction/robot_grid/domain/
├── robot_construction_grid.gd
├── robot_grid_placement_validator.gd
└── robot_grid_snapshot_codec.gd

tests/construction/robot_grid/
├── rcg0_test_fixture.gd
└── test_rcg0_robot_construction_grid_contracts.gd

RUN_RCG0_ROBOT_CONSTRUCTION_GRID_TESTS.ps1
RUN_RCG0_ROBOT_CONSTRUCTION_GRID_TESTS.sh
```

### API первой версии

```text
can_place(part_definition, anchor_cell, orientation_id)
place(placement, expected_revision, operation_id)
can_remove(part_instance_id)
remove(part_instance_id, expected_revision, operation_id)
get_part_at(cell)
get_placement(part_instance_id)
query_placements_in_bounds(min_cell, max_cell)
to_snapshot()
load_snapshot(snapshot)
canonical_checksum()
```

### Обязательные свойства

- sparse storage, без выделения полного кубического массива;
- `Vector3i` coordinates с явно заданными bounds;
- 24 дискретные cube orientations;
- multi-cell footprint;
- exact overlap rejection;
- atomic placement/removal;
- monotonic grid revision;
- idempotent exact replay;
- fail-closed same-revision conflict;
- deterministic sorted serialization;
- runtime Godot object rejection;
- отсутствие изменений production scenes/world catalog.

### Acceptance

```text
empty grid allocates no occupied cells
same operation replay changes nothing
multi-cell overlap is rejected atomically
remove releases every occupied cell
orientation round-trip is exact
snapshot load produces identical checksum
random insertion order produces identical snapshot/hash
invalid DTO leaves revision and state unchanged
```

---

## RCG1 — Structural ports and connectivity

### Цель

Связать placements с типизированными structural ports и получить deterministic connected components.

### Добавить

```text
robot_grid_port_definition.gd
robot_grid_port_binding.gd
robot_structural_connection.gd
robot_structural_graph.gd
robot_grid_topology_compiler.gd
robot_connected_component_summary.gd
```

### Scope

- transformed port positions/faces;
- compatible connector profiles;
- explicit structural edges;
- incremental neighbor recompilation;
- component detection;
- deterministic root/core policy;
- dirty region output для C14/C22/RL layers.

### Не делать

RCG1 только обнаруживает split candidate. Он ещё не создаёт новые aggregates.

---

## RCG2 — Item-backed installation transactions

### Цель

Сделать переходы предмета между inventory/world и robot grid без смены identity.

### Commands

```text
PlaceRobotGridPart
RemoveRobotGridPart
MoveRobotGridPart
RotateRobotGridPart
ConnectRobotGridPorts
DisconnectRobotGridPorts
```

### Transaction

Одна operation должна атомарно изменять:

- Item Graph relation;
- construct part membership;
- grid placement;
- structural/utility edges;
- revisions;
- transactional outbox.

### Gate

Fault injection на каждом staged step не оставляет orphan item, ghost placement или duplicate membership.

---

## RCG3 — Aggregate split, merge and docking

### Цель

Превратить component split в реальные authoritative aggregate transitions.

### Scope

- primary component selection;
- child aggregate identity generation;
- part/grid/graph transfer;
- world transform derivation;
- mass/bounds summaries;
- soft docking;
- fixed multi-segment assembly;
- optional compatible-grid merge;
- replay and rollback.

### Gate

```text
1 robot → break bridge part → 2 aggregates
all part IDs preserved exactly once
mass/item counts conserved
replay creates no extra aggregate
rollback restores original checksums
```

---

## RCG4 — Runtime physics projection and joints

### Цель

Создать active physics representation без one-body-per-block.

### Scope

- one `RigidBody3D` per active rigid segment;
- derived compound/generated collision;
- mass, center of mass and inertia summaries;
- hinge/slider/wheel/fixed joint projections;
- bounded incremental rebuild;
- headless operation without nodes;
- fixed-tick authoritative stepping integration;
- sleep/dormancy transitions.

### Gate

Удаление всей physics projection и rebuild из того же snapshot дают эквивалентные source-linked summaries. Physics nodes не могут изменить domain напрямую.

---

## RCG5 — Utility, devices and control facade

### Цель

Сделать установленную конструкцию функциональным роботом.

### Scope

- power graph;
- data bus graph;
- mechanical transmission;
- fluid/thermal networks по необходимости;
- battery, generator, controller, motor, sensor fixtures;
- device registry;
- capability compilation;
- `RobotControlFacade` для player и AI;
- deterministic allocation и load shedding.

### Gate

Одинаковый snapshot и commands дают одинаковые utility allocations и actuator outputs. Агент не получает прямой mutable reference на grid.

---

## RCG6 — Network snapshots, deltas and activity levels

### Цель

Реплицировать структуру и runtime state без полного snapshot на каждый tick.

### Scope

- versioned `RobotGridSnapshot`;
- monotonic structural deltas;
- late join/reconnect;
- command result/rejection;
- owner-only and observer views;
- activity levels `DORMANT/SUMMARY/SIMULATED/PRESENTED`;
- per-client interest and bandwidth budgets;
- frequent transform/joint channel отдельно от durable structural channel;
- checksum convergence.

### Gate

Потеря, duplicate, reorder, reconnect и stale baseline не создают duplicate parts или divergent grid.

---

## RCG7 — Representation HLOD and large robots

### Prerequisite

```text
RL3 artifact streaming accepted
RL4 Construction HLOD backend accepted
RL5 shared cache/scheduler accepted
```

### Scope

- stable grid clusters/sections;
- internal-face removal;
- material batching;
- segment simplified meshes;
- whole-robot proxy/impostor;
- semantic anchors outside merged mesh;
- local detail promotion;
- content-addressed cache;
- one-part bounded rebuild fan-out.

### Scale fixture

```text
25 000 parts
0 individual part nodes at distance
bounded draw calls
local service area promoted to full detail
one-part edit rebuilds one cluster and ancestor chain
```

---

## RCG8 — Agents, tools and production acceptance

### Scope

- build/repair/salvage planning API;
- multi-agent reservations;
- robot self-diagnostics;
- tool requirements;
- deterministic construction jobs;
- permission and ownership security;
- corruption recovery;
- chaos and soak;
- server migration during active robot operation;
- large fleet tests.

### Profiles

```text
100 small robots
20 industrial rovers
5 large articulated machines
1 25k-part vehicle
network reconnect storm
mass damage/split
cache loss and rebuild
server handoff
12–24 h soak
```

---

## 5. Детальный порядок выполнения RCG0

### Шаг 1. Freeze schema

Зафиксировать JSON config:

```text
schema version
grid coordinate bounds
maximum cells per part
maximum placements per segment
orientation table version
payload size limits
snapshot limits
error codes
```

### Шаг 2. Orientation table

Сгенерировать и зафиксировать 24 unique proper rotations. Tests обязаны доказать:

- determinant `+1`;
- orthogonality;
- unique basis transforms;
- inverse для каждой orientation;
- composition closure;
- exact integer cell transform.

### Шаг 3. Placement contract

Проверить:

- exact fields;
- canonical IDs;
- sorted unique occupied cells;
- footprint соответствует definition;
- anchor входит в occupied cells по принятой convention;
- checksum;
- отсутствие Object/Resource/RID/Callable/NodePath.

### Шаг 4. Sparse grid state

Внутреннее состояние:

```text
placements_by_part_id: Dictionary
cell_to_part_id: Dictionary
revision: int
operation replay ledger: bounded/domain-approved structure
```

Никаких `Node3D` и mesh references.

### Шаг 5. Atomic operations

`place()` сначала полностью валидирует и строит mutation plan, затем применяет изменения. При любой ошибке state и revision остаются прежними.

`remove()` проверяет всю reverse occupancy до mutation.

### Шаг 6. Snapshot codec

Snapshot сортирует:

1. segments по `segment_id`;
2. placements по `part_instance_id`;
3. cells лексикографически `(x, y, z)`;
4. metadata keys канонически.

### Шаг 7. Property tests

Минимум:

- random non-overlapping placements;
- random insertion order;
- random removals;
- 24 orientations;
- multi-cell concave footprints;
- negative coordinates;
- bounds edges;
- duplicate operation IDs;
- stale revisions;
- malformed payloads;
- snapshot round-trip;
- hash convergence.

### Шаг 8. Integration proof

Создать test adapter, который связывает один existing item-backed construct fixture с grid snapshot, но не меняет production runtime.

---

## 6. Error model первой версии

Рекомендуемые стабильные error codes:

```text
INVALID_SCHEMA
UNKNOWN_SCHEMA_VERSION
INVALID_GRID_ID
INVALID_SEGMENT_ID
INVALID_PART_ID
INVALID_DEFINITION_ID
INVALID_ORIENTATION
INVALID_FOOTPRINT
CELL_OUT_OF_BOUNDS
CELL_OCCUPIED
PART_ALREADY_PLACED
PART_NOT_FOUND
STALE_REVISION
REVISION_CONFLICT
OPERATION_REPLAY_CONFLICT
PAYLOAD_TOO_LARGE
RUNTIME_OBJECT_REJECTED
CHECKSUM_MISMATCH
INTERNAL_INVARIANT_BROKEN
```

UI-текст не входит в domain error payload.

---

## 7. Test pyramid

### Contract/unit

- serializers;
- orientations;
- footprint transforms;
- occupancy;
- checksums;
- negative cases.

### Property/fuzz

- random operation sequences;
- arbitrary dictionary order;
- malformed arrays and integer bounds;
- duplicate cells/IDs;
- revision and replay races.

### Domain integration

- Item Graph install/remove;
- transaction rollback;
- structural topology;
- split/merge;
- persistence.

### Runtime integration

- physics projection rebuild;
- joints;
- devices;
- activity transitions.

### Network/process

- dedicated authority;
- two clients;
- late join;
- disconnect/reconnect;
- stale delta;
- checksum convergence.

### Scale/soak

- thousands of parts;
- repeated edits;
- mass split;
- cache loss;
- memory/node leak checks.

---

## 8. Definition of Done RCG0

RCG0 считается принятым только если:

1. чистый grid domain работает без SceneTree;
2. empty grid не materializes полный cell volume;
3. все 24 orientations доказаны tests;
4. multi-cell placement атомарен;
5. overlap и bounds errors fail-closed;
6. snapshot/hash не зависит от insertion order;
7. stale revision и conflicting replay отклоняются;
8. runtime objects rejected recursively, включая Dictionary keys и nested metadata;
9. Item Graph, construction, representation, network и world regression не изменились;
10. production scenes, world catalog и save format не изменены;
11. focused runner работает одной командой на Windows и Linux;
12. independent Godot 4.7.1 double acceptance пройдена.

---

## 9. Инструкция применения этого документационного overlay

Архив содержит только новые файлы в исходных project-relative paths.

Из каталога над `lunar-world-double-godot`:

### Windows PowerShell

```powershell
Expand-Archive `
  .\planet-simulator-robot-construction-grid-future-feature-docs.zip `
  -DestinationPath . `
  -Force

cd .\lunar-world-double-godot

git diff --check
git status --short

Get-Item .\docs\future_features\robot_construction_grid\README_RU.md
Get-Item .\docs\future_features\robot_construction_grid\ROBOT_CONSTRUCTION_GRID_ARCHITECTURE_RU.md
Get-Item .\docs\future_features\robot_construction_grid\ROBOT_CONSTRUCTION_GRID_IMPLEMENTATION_GUIDE_RU.md
```

### Linux

```bash
unzip -o planet-simulator-robot-construction-grid-future-feature-docs.zip
cd lunar-world-double-godot
git diff --check
git status --short

test -f docs/future_features/robot_construction_grid/README_RU.md
test -f docs/future_features/robot_construction_grid/ROBOT_CONSTRUCTION_GRID_ARCHITECTURE_RU.md
test -f docs/future_features/robot_construction_grid/ROBOT_CONSTRUCTION_GRID_IMPLEMENTATION_GUIDE_RU.md
```

Godot tests для этого overlay не требуются: он не содержит `.gd`, `.tscn`, `.tres`, config или runtime changes. После применения достаточно UTF-8, archive path safety и `git diff --check`.

---

## 10. Следующее действие после документации

Когда будет подготовлен объединённый `C23 + RL1` checkpoint:

```text
create feature/rcg0-robot-construction-grid-contracts
→ freeze RCG0 config and DTO
→ implement sparse occupancy
→ add property/negative tests
→ prove Item Graph adapter without production wiring
→ independent acceptance
```

До этого момента документация остаётся каноническим future-feature intent и не считается разрешением на добавление параллельного experimental runtime в production worlds.
