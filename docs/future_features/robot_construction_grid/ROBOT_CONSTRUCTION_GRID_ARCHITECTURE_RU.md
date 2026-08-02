# Robot Construction Grid — архитектура локальных гридов роботов и машин

**Статус:** будущая функция; реализация ещё не начата.
**Серия:** `RCG0–RCG8`.
**Целевая база первой реализации:** объединённый checkpoint `C23 + RL1`.
**Главное правило:** robot grid является канонической частью item-backed construct, но не является мировым spatial grid и не хранится как SceneTree.

---

## 1. Задача

PlanetSimulator должен поддерживать роботов, роверы, корабли, промышленные машины и другие составные объекты, в которых:

- десятки, тысячи или десятки тысяч блоков принадлежат одной конструкции;
- блоки размещены в локальной дискретной системе координат;
- часть блоков занимает несколько ячеек;
- соседство не тождественно структурному, электрическому или информационному соединению;
- конструкция может иметь шарниры и несколько жёстких сегментов;
- блок можно демонтировать и вернуть в `Item Graph` как тот же физический экземпляр;
- повреждение может разделить конструкцию на несколько aggregates;
- сервер остаётся единственным authoritative writer;
- клиент не обязан создавать по `Node3D` на каждый блок;
- AI-агент управляет устройствами и подсистемами, а не редактирует каноническое состояние напрямую.

Типичный пример:

```text
robot/miner-001
├── 2 400 конструктивных частей
├── 12 батарей
├── 8 приводов
├── 6 колёс
├── 14 датчиков
├── 3 вычислительных контроллера
├── 1 грузовой контейнер
└── 2 манипулятора с шарнирами
```

На уровне мира это один логический робот. На уровне локальной конструкции это набор частей, grid segments и графов связности.

---

## 2. Текущее основание проекта

К моменту фиксации документа проект уже располагает необходимыми нижними слоями:

- item-backed identities и relations;
- canonical `Item Graph`;
- generic aggregates и multi-aggregate transactions;
- construction parts, bonds, damage, split и repair;
- runtime geometry/physics projection;
- structural summaries;
- utility и machine semantics;
- distributed construction authority;
- activity levels и логические construction LOD tiers;
- agent construction boundary;
- large-scale и production-hardening тестовыми профилями;
- `SimulationCell` и aggregate shards для мирового пространства;
- общими Representation LOD contracts и matter summary pyramid;
- fixed-tick authoritative network simulation.

Robot grid не должен создавать параллельные identity, transaction, authority, persistence или representation системы. Он расширяет существующий construction domain.

---

## 3. Два разных понятия grid

### 3.1. Мировой spatial grid

Существующий `SimulationCell` отвечает за:

- адрес пространства;
- spatial interest;
- server routing;
- aggregate shards;
- streaming регионов;
- границы distributed authority.

Пример:

```text
SimulationCell: moon/surface/region-42
└── AggregateShard: robot/miner-001/main
```

Мировой grid не должен содержать запись на каждый блок робота.

### 3.2. Локальный construction grid

`RobotConstructionGrid` отвечает за:

- локальную lattice внутри rigid segment;
- занятость ячеек;
- размещение и ориентацию parts;
- быстрые запросы по локальной координате;
- поиск геометрических соседей;
- атомарную проверку установки и демонтажа;
- deterministic serialization и checksum.

```text
RobotAggregate
└── RigidGridSegment: chassis
    └── RobotConstructionGrid
        ├── cell (0, 0, 0) → frame/001
        ├── cell (1, 0, 0) → frame/002
        ├── cell (2, 0, 0) → battery/004
        └── cell (3, 0, 0) → battery/004
```

`SimulationCellAddress` и `RobotGridCellAddress` не взаимозаменяемы.

---

## 4. Каноническая модель aggregate

Первая версия использует один authoritative aggregate на небольшого или среднего робота:

```text
RobotConstructAggregate
├── aggregate identity
├── world spatial state
├── authority owner + epoch
├── construction revision
├── Array[RobotRigidGridSegment]
├── EntityPartGraph / construct parts
├── StructuralConnectionGraph
├── JointGraph
├── UtilityGraphs
├── device states
├── mass properties source data
└── operation/replay state
```

### 4.1. Один робот — не один обязательный rigid body

Робот может содержать несколько жёстких сегментов:

```text
torso grid segment
├── shoulder joint
│   └── upper-arm grid segment
│       └── elbow joint
│           └── forearm grid segment
└── wheel suspension joints
```

Каждый `RobotRigidGridSegment` имеет:

- стабильный `segment_id`;
- локальный frame относительно aggregate root;
- собственный `RobotConstructionGrid`;
- собственные mass/collision dirty summaries;
- список joints к другим сегментам.

Это позволяет моделировать руки, подвеску, двери, турели, поршни и складывающиеся механизмы без попытки поместить подвижные части в одну неподвижную lattice.

---

## 5. Идентичность блока

Установленный блок остаётся тем же item-backed экземпляром.

```text
item_instance_id: item/motor/7f2a...
part_instance_id: part/motor/7f2a...
```

Один стабильный ID связывает:

- Item Graph identity;
- placement в robot grid;
- part graph;
- structural connections;
- utility ports;
- device state;
- damage/wear;
- persistence и replay.

Запрещено создавать отдельные несовместимые IDs для:

- inventory item;
- установленного блока;
- physics node;
- mesh node;
- network replica.

Presentation может иметь ephemeral runtime handle, но он не является domain identity.

---

## 6. Дескриптор установленной части

Концептуальный контракт:

```text
RobotGridPartPlacement
├── schema
├── part_instance_id
├── part_definition_id
├── segment_id
├── anchor_cell: Vector3i
├── orientation_id
├── occupied_cells: sorted Array[Vector3i]
├── placement_revision
├── structural_port_bindings
├── utility_port_bindings
├── state_reference
└── checksum
```

### 6.1. Multi-cell parts

Размер и форма определяются immutable definition, а placement хранит конкретные занятые cells после применения ориентации.

Пример батареи `2 × 1 × 1`:

```text
anchor = (4, 2, 1)
orientation = ROT_Y_90
occupied:
- (4, 2, 1)
- (4, 2, 2)
```

`occupied_cells` сортируются канонически. Duplicate cells, cell вне bounds и расхождение с definition отклоняются fail-closed.

### 6.2. Два индекса

Grid хранит минимум:

```text
placements_by_part_id
cell_to_part_id
```

Это обеспечивает:

- `O(1)` поиск части по cell;
- проверку пересечения;
- удаление multi-cell части;
- локальный neighbor query;
- region dirty marking.

Каноническое состояние не должно зависеть от порядка вставки в Dictionary.

---

## 7. Ориентации

Первая версия должна использовать конечный дискретный набор ортонормальных ориентаций, а не произвольный quaternion.

Для кубической lattice допустимы 24 proper rotations куба:

```text
orientation_id: 0..23
```

Definition хранит local footprint и local ports. Placement применяет выбранную ориентацию и получает:

- transformed occupied cells;
- transformed port faces;
- transformed local attachment transforms.

Произвольные углы допускаются только между rigid segments через joints или в отдельном freeform construction subsystem.

---

## 8. Геометрическое соседство и графы

Главный инвариант:

> Соседние cells не означают автоматическое структурное, электрическое, механическое или data-соединение.

### 8.1. Structural graph

Определяет, является ли конструкция физически связной.

Ребро содержит:

```text
connection_id
part_a
port_a
part_b
port_b
connection_kind
strength profile
damage state
revision
```

После удаления части или разрушения connection выполняется connected-components analysis.

### 8.2. Joint graph

Связывает rigid segments:

- hinge;
- slider/piston;
- ball joint;
- wheel axle;
- fixed docking joint;
- soft/tow connection.

Joint state хранится в domain, а Godot joint является производной physics projection.

### 8.3. Utility graphs

Отдельно существуют:

- `PowerGraph`;
- `DataGraph`;
- `FluidGraph`;
- `ThermalGraph`;
- `MechanicalTransmissionGraph`.

Один pair parts может иметь несколько связей разных типов или не иметь ни одной.

---

## 9. Порты

Part definition объявляет типизированные порты:

```text
port_id
port_kind
local_cell
local_face
connector_profile
flow_direction
capacity
required_tags
```

При установке grid только находит потенциальных геометрических соседей. Отдельный topology compiler:

1. трансформирует ports по orientation;
2. сопоставляет противоположные faces;
3. проверяет connector compatibility;
4. создаёт или удаляет graph edges;
5. маркирует затронутые summaries dirty.

Wireless data connection, flexible cable или hose могут создавать edge без face adjacency, но только через отдельную authoritative command.

---

## 10. Установка и демонтаж

### 10.1. Установка

```text
item in inventory/world
→ PlaceRobotGridPart command
→ validate authority/permission/revision
→ validate definition and footprint
→ reserve target cells
→ validate attachment rules
→ stage Item Graph relation change
→ stage placement and topology changes
→ atomic commit
→ emit deltas/invalidation
```

После commit item перестаёт быть свободным предметом и становится установленной частью того же construct.

### 10.2. Демонтаж

```text
installed part
→ RemoveRobotGridPart command
→ validate no forbidden active dependency
→ stage graph edge removal
→ stage placement removal
→ stage Item Graph relation to inventory/world
→ atomic commit
→ emit deltas/invalidation
```

При недостатке места в target container операция отклоняется целиком. Нельзя удалить part из grid и потерять item.

---

## 11. Split и merge

### 11.1. Split

После structural mutation:

1. пересчитать connected components затронутого structural graph;
2. определить primary component;
3. создать child aggregates для остальных components;
4. перенести parts, placements, graph edges и device states;
5. пересчитать segment roots, mass и bounds;
6. создать world spatial state новых aggregates;
7. атомарно опубликовать split через существующий construction damage/split boundary.

Primary identity остаётся component, содержащей declared core/root part. При отсутствии core используется deterministic policy, например максимальная масса, затем минимальный canonical part ID.

### 11.2. Merge и docking

Нужно различать:

- soft docking — два aggregates и relation/joint между ними;
- fixed assembly — один aggregate с несколькими grid segments;
- true grid merge — перенос placements в одну lattice, только если scale, orientation и cell alignment совместимы.

По умолчанию предпочтителен fixed assembly с несколькими segments. Это избегает destructive coordinate remap.

---

## 12. Масса и физика

Канонический робот не содержит `RigidBody3D`, `CollisionShape3D`, `RID` или `Joint3D`.

Derived physics projection строится из snapshot:

```text
segment parts
→ mass and center-of-mass summary
→ inertia approximation
→ compound/generated collision
→ one RigidBody3D per active rigid segment
→ Godot joints between segments
```

Запрещено создавать отдельный active `RigidBody3D` для каждого из тысяч блоков.

Dirty categories:

```text
MASS
INERTIA
COLLISION
STRUCTURE
JOINTS
POWER
DATA
MESH
HLOD
CAPABILITIES
```

Изменение одной части должно иметь bounded rebuild fan-out.

---

## 13. Сетевой authority и replication

Первая production-модель:

```text
one RobotConstructAggregate
→ one authoritative writer
→ clients are replicas
```

Частые данные:

- root transform;
- velocity;
- joint positions/velocities;
- actuator targets;
- short-lived device telemetry.

Редкие structural deltas:

- part placed;
- part removed;
- part damaged;
- connection changed;
- segment split/merged;
- device configuration changed.

Late join получает versioned snapshot, затем monotonic deltas.

Для небольшого робота не допускается несколько writers внутри одного aggregate. Cross-server section ownership относится к позднему этапу после durable handoff и cross-region transaction protocols.

---

## 14. Представление и LOD

Robot grid не определяет, сколько nodes создаёт клиент.

```text
canonical placements and graphs
→ section/cluster summaries
→ detail mesh near observer
→ simplified segment mesh
→ whole-robot proxy/impostor
```

Representation artifacts:

- content-addressed;
- связаны с exact source revision;
- могут быть удалены и перестроены;
- не меняют item/part identities;
- не входят в authoritative mutation.

Interactive semantic anchors — seat, connector, hatch, gripper, service port — должны храниться отдельно от merged mesh.

---

## 15. API для агента

AI не получает право напрямую менять dictionaries grid.

Уровни API:

```text
Task API
  move_to / dock / pick_up / repair

Subsystem API
  mobility / manipulation / power / sensing

Device API
  motor / camera / lidar / battery / switch

Engineering query API
  query parts / topology / damage / mass / free cells

Construction command API
  plan placement / place / remove / connect / disconnect
```

Все mutations проходят через те же authoritative commands, permissions и transaction boundary, что и действия игрока.

Агенту не следует передавать полный список из 10 000 parts каждый tick. Он получает summaries и запрашивает detail по необходимости.

---

## 16. Persistence и replay

Snapshot обязан включать:

- aggregate identity;
- segment descriptors;
- placements;
- structural/joint/utility graph revisions;
- item relation bindings;
- device persistent state;
- deterministic checksums.

Replay command обязан быть idempotent по `operation_id`.

Same revision:

- exact same payload/checksum → idempotent replay;
- different payload/checksum → conflict and fail-closed.

Presentation cache, generated mesh и physics nodes в snapshot не входят.

---

## 17. Масштабирование

Начальные целевые profiles:

```text
small robot:       50–500 parts
industrial rover:  500–5 000 parts
large vehicle:     5 000–25 000 parts
station section:   25 000+ parts, partitioned
```

Для первых двух profiles достаточно одного aggregate и одного writer.

Большие конструкции используют:

- stable section topology;
- bounded dirty propagation;
- activity levels;
- representation HLOD;
- optional aggregate shards;
- позднее — distributed section coordination.

---

## 18. Обязательные инварианты

1. World `SimulationCell` и local robot cell имеют разные schemas и IDs.
2. Part identity сохраняется при `inventory ↔ installed ↔ detached` переходах.
3. Одна local cell принадлежит не более чем одной placement.
4. Multi-cell placement добавляется и удаляется атомарно.
5. Orientation и footprint детерминированы definition version.
6. Geometry adjacency не создаёт произвольные graph edges.
7. Любая mutation проходит через authority и transaction boundary.
8. Structural split не теряет и не дублирует parts или material.
9. Godot objects не попадают в canonical payload.
10. Mesh/collision/HLOD являются derived cache.
11. Client replica не может самостоятельно изменить grid.
12. Rebuild одной части ограничен её cluster/section ancestor chain.
13. Несовместимая schema/version отклоняется до изменения состояния.
14. Смена authority требует нового epoch/fencing token.
15. Полное удаление presentation cache не меняет checksum робота.

---

## 19. Антицели первой версии

`RCG0–RCG2` не должны включать:

- production UI-конструктор;
- полноценную rigid-body физику;
- электрический solver;
- несколько server writers одного робота;
- arbitrary-angle blocks внутри одной lattice;
- mesh merging или HLOD;
- agent autonomy;
- Moon/planet integration;
- migration существующих construction fixtures;
- сохранение `Node`, `Resource`, `Mesh`, `RID`, `Callable` или `NodePath` в domain.

---

## 20. Итоговая схема

```text
WORLD
└── SimulationCell / AggregateShard
    └── RobotConstructAggregate
        ├── world spatial state
        ├── authority + revisions
        ├── Item-backed parts
        ├── RigidGridSegment A
        │   └── RobotConstructionGrid A
        ├── RigidGridSegment B
        │   └── RobotConstructionGrid B
        ├── StructuralGraph
        ├── JointGraph
        ├── UtilityGraphs
        └── DeviceState

DERIVED
├── physics projection
├── detailed meshes
├── simplified segment meshes
├── robot proxy/impostor
└── UI and agent summaries
```

Такой слой делает robot grid естественным расширением текущей construction architecture и не превращает мировой spatial grid в контейнер тысяч внутренних блоков.
