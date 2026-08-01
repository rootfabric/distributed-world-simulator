# Наглядная карта строительной линии PlanetSimulator

**Статус документа:** каноническая карта строительного трека
**База проекта:** `main @ 2879fdb7134032f645ffc5c98c0535aecfc09caf`
**C1:** `c2b9404`, ACCEPTED
**C2A:** `68cf8b2`, ACCEPTED
**C2B:** `d5c9187`, ACCEPTED
**C3:** ACCEPTED вместе с fix1; reviewed delivery SHA-256 `2296f48f0f31c8d4feb9290e0973d27dd4b4f85ed9c7f29361f28156b82ac256`
**C4:** ACCEPTED вместе с fix1
**C5:** ACCEPTED вместе с fix1; база C4 `b985cde`
**C6:** `2837835`, ACCEPTED
**C7:** ACCEPTED; reviewed delivery SHA-256 `5a4cebb21587ed8c4b54852145b6a018445438866bc1908d5cf9bcc4fe9aee87`
**C8:** ACCEPTED
**C9:** ACCEPTED
**C10:** ACCEPTED; base C9 `8d8bf77`
**C11:** `6d26f69`, ACCEPTED
**C12:** ACCEPTED; reviewed delivery SHA-256 `85c455c72dc1d5651f86672dc3d20e851e3c650bfa575c5643883f1da78c7f29`
**C13:** ACCEPTED
**C14:** ACCEPTED
**C15:** ACCEPTED
**C16:** `a4376cd`, ACCEPTED
**Рабочая ветка C17:** `feature/c17-distributed-construction-authority`
**Текущая позиция:** `C17 — Distributed Construction Authority, IMPLEMENTED CANDIDATE`

Подробная карта после C12: `docs/plans/CONSTRUCTION_POST_C12_ROADMAP_RU.md`.

## Парадигма всей линии

PlanetSimulator создаёт не очередной редактор блоков, а **конструктор нового уровня**:

> семантический масштаб + составные предметы + компиляция facets + capability-based поведение.

Это попытка сделать стройку нового уровня и превратить её в парадигму всей линии симуляции. Игрок действует намерениями и стадиями, а система сохраняет реальный состав, identity деталей, материалы, связи, сетевую authority и возможность раскрыть объект до инженерного уровня.

## Карта движения

```mermaid
flowchart TD
    C0["C0 Paradigm — ACCEPTED"] --> C1["C1 Kernel — ACCEPTED"]
    C1 --> C2["C2A/C2B Item Authority — ACCEPTED"]
    C2 --> C3["C3 BuildPlan — ACCEPTED"]
    C3 --> C4["C4 CompositeDefinition — ACCEPTED"]
    C4 --> C5["C5 Capabilities — ACCEPTED"]
    C5 --> C6["C6 Mobile — ACCEPTED"]
    C6 --> C7["C7 Spatial — ACCEPTED"]
    C7 --> C8["C8 Fabrication — ACCEPTED"]
    C8 --> C9["C9 Damage/Split/Repair — ACCEPTED"]
    C9 --> C10["C10 Parametric Members — ACCEPTED"]
    C10 --> C11["C11 Local Geometry — ACCEPTED"]
    C11 --> C12["C12 Multiplayer Acceptance — ACCEPTED"]
    C12 --> C13["C13 Runtime Geometry/Physics — ACCEPTED"]
    C13 --> C14["C14 Structural Integrity — ACCEPTED"]
    C14 --> C15["C15 Executable Utilities — ACCEPTED"]
    C15 --> C16["C16 Construction UX — ACCEPTED"]
    C16 --> C17["C17 Distributed Authority — CURRENT CANDIDATE"]
    C17 --> C18["C18 Streaming/LOD"]
    C18 --> C19["C19 Agent Automation"]
    C19 --> C20["C20 Logistics/Economy"]
    C20 --> C21["C21 Scale Acceptance"]
    C21 --> C22["C22 Production Hardening"]
```

```text
C0 accepted: paradigm
  ↓
C1 accepted: semantic construct kernel
  ↓
C2A accepted: transaction contracts
  ↓
C2B accepted: production Item Graph + M0 authority
  ↓
C3 accepted: immutable BuildPlan + weightless ghost + resumable stages
  ↓
C4 accepted: reusable semantic definitions + deterministic late binding
  ↓
C5 accepted: typed behavior profiles + part/port affordances + semantic queries
  ↓
C6 accepted: mobile subsystem graph + dynamic degradation + checksum-pinned commands
  ↓
C7 accepted: sections + Space Graph + enclosure + utilities + activation
  ↓
C8 current: recipes + machine capabilities + queue + authoritative material flow
  ↓ acceptance gate
C9 damage → C10 parametric construction → C11 local geometry
  ↓
C12 multiplayer construction → C13 federated constructs
```

## Статусы

| Этап | Результат | Контрольный объект | Статус |
|---|---|---|---|
| C0 | парадигма, границы доменов, roadmap | вся линия | **ACCEPTED** |
| C1 | parts, bonds, snapshots, revisions, facet compiler | стол | **ACCEPTED** |
| C2A | item projections, mutations, atomic plans | стол | **ACCEPTED — 68cf8b2** |
| C2B | production registries, shared ledger, M0 authority и recovery | стол | **ACCEPTED** |
| C3 | immutable BuildPlan, ghost projection, stages, requirements, resume и builder executor | стадийный стол | **ACCEPTED — fix1** |
| C4 | semantic slots, typed parameters, exposed ports, reusable definitions и deterministic BuildPlan compilation | два параметризованных экземпляра стола | **ACCEPTED — fix1** |
| C5 | typed capabilities, concrete affordances, semantic query и rebuildable profiles | агент использует неизвестный стол | **ACCEPTED — fix1** |
| C6 | power/control/drive/sensor subsystems, quorum, dependency cascade и mobile commands | наземный робот | **ACCEPTED** |
| C7 | sections, spaces, enclosure, openings, utilities и activation LOD | дом | **ACCEPTED** |
| C8 | recipes, machine profiles, work queue, atomic material reservation/consumption и fabricated outputs | производственная ячейка | **ACCEPTED** |
| C9 | damage, split, repair, salvage | стол/робот/секция | **ACCEPTED** |
| C10 | beams, panels, pipes, cables, profiles | строение/корабль | ACCEPTED |
| C11 | constrained local geometry and control-point edits | параметрическая деталь | **ACCEPTED** |
| C12 | contention, permissions, reconnect, replay и convergence | два клиента | **ACCEPTED** |
| C13 | runtime mesh/collision/physics projection | runtime construct | **ACCEPTED** |
| C14 | load paths и progressive collapse | несущая конструкция | **ACCEPTED** |
| C15 | executable utilities и machine leases | utility network / fabrication cell | **ACCEPTED** |
| C16 | placement, snapping, gizmos и overlays | graphical client | **ACCEPTED — a4376cd** |
| C17 | owner routing, migration, replicas и takeover | три spatial servers | **IMPLEMENTED CANDIDATE** |
| C18–C22 | streaming, agents, economy, scale и hardening | мир проекта | PLANNED |

## C2A — Item Graph Contracts

Статус: **ACCEPTED**. Этап зафиксировал строгие планы сборки и разборки, item-backed identity, транзакционные preconditions и тестовый adapter без изменения production Item Graph.

## C2B — Authoritative Item Graph Integration

Статус: **ACCEPTED**. Этап подключил реальные `ItemRegistry`/`ContainerRegistry`, общий `OperationLedger` и M0-first authoritative commit/recovery. C3 выполняет расход и перемещение предметов только через эту границу.

## C3 — BuildPlan and Ghost Construction

Статус: **ACCEPTED вместе с fix1**. Этап зафиксировал resumable execution plan, невесомый ghost, staged partial constructs и recovery после authoritative commit.

## C3: что появилось

```text
immutable BuildPlan
├── target ConstructSnapshot
├── exact source Item projections
├── ordered BuildStages
├── material allocations
├── required tool capabilities
└── ghost world relation
        ↓
weightless GhostState
        ↓ execute stage
C2A ConstructionItemTransactionPlan
        ↓
C2B authoritative Item Graph + shared ledger + M0
        ↓
partial ConstructSnapshot
        ↓ next stage / crash recovery / exact replay
        ↓
OPERATIONAL ConstructSnapshot
```

### Ключевой принцип ghost

Ghost до первой стадии:

- не является `ItemInstance`;
- не имеет массы;
- не имеет collision/physics authority;
- не имеет capabilities;
- не создаёт construct root;
- является только persisted intention/projection BuildPlan.

После первой стадии физическим становится **частично построенный construct**, а не ghost. Ghost продолжает показывать план и прогресс, но не дублирует массу и поведение объекта.

### Стадии контрольного стола

```text
0 FOUNDATION
  top + two supports + 2 fasteners
  ConstructSnapshot = PARTIAL
  capabilities = []

1 FRAME
  remaining two supports + 2 fasteners
  ConstructSnapshot = PARTIAL
  capabilities = []

2 COMMISSIONING
  sealant + inspection capability
  ConstructSnapshot = OPERATIONAL
  capabilities = PLACE_ITEMS / SUPPORT_SURFACE / WORK_SURFACE
```

### Recovery C3

```text
stage transaction committed in C2B
→ process crashes before GhostState update
→ ConstructSnapshot and shared ledger remain authoritative
→ C3 reconcile identifies matching deterministic stage snapshot
→ ghost progress advances without repeating material consumption
→ repeated operation ID returns exact replay
```

BuildPlan хранит исходные item projections и точные allocations. Поэтому transaction plan каждой стадии детерминирован и может быть восстановлен после перезапуска с тем же checksum.


## C4: CompositeDefinition

**Статус:** ACCEPTED вместе с fix1.

```text
completed operational construct + accepted C3 BuildPlan
        ↓ promotion
CompositeDefinition v1
├── semantic part slots (no item IDs)
├── bond templates (slot-to-slot topology)
├── stage templates
├── material requirements by definition
├── typed parameter definitions
├── exposed ports bound to semantic slots
├── version + checksum + provenance
└── no concrete construct/build-plan/container identity
        ↓ deterministic late binding
available Item projections
        ↓
concrete C3 BuildPlan + CompositeInstantiation record
        ↓
unchanged C3 → C2A → C2B execution path
```

Ключевой результат: один пользовательский тип создаёт несколько независимых constructs с разными реальными предметами. `CompositeDefinition` не является prefab: каноническими остаются реальные parts, bonds и Item Graph identity каждого экземпляра.

C4 v1 использует точное `definition_id` и optional component subset для part slots. Typed parameters имеют строгий тип/default и pin-ятся в каждом instantiation. Exposed ports компилируются semantic slot → concrete part ID и публикуются по мере установки частей. Материалы выбираются детерминированно по item ID, могут распределяться между несколькими stacks и не исчерпывают stack из-за текущего C2A/C3 ограничения. Concrete binding сохраняется отдельным checksum-защищённым `CompositeInstantiation`, поэтому версия определения и происхождение каждого BuildPlan остаются проверяемыми.

Partial и final snapshots несут pinned provenance:

```text
composite_definition_id
composite_definition_version
composite_definition_checksum
composite_instantiation_id
composite_parameters
composite_exposed_ports
```


## C5: Capability and Affordance Compilation

**Статус:** ACCEPTED вместе с fix1.

```text
Authoritative ConstructSnapshot
        ↓ deterministic behavior compiler
ConstructionBehaviorProfile
├── typed capabilities
├── concrete provider parts
├── concrete exposed ports
└── action affordances + actor requirements
        ↓ semantic query
unknown-object agent action selection
```

Ключевые правила:

- profile является rebuildable projection, а не новым authoritative aggregate;
- partial и damaged constructs не публикуют operational actions;
- affordance обязан ссылаться на provider part/port собственного capability;
- C4 parameter values становятся queryable properties;
- resolver не использует prefab/display name;
- равные запросы детерминированно сортируют кандидатов;
- stale и same-revision profile mutation отклоняются.

Контрольный объект: два неизвестных параметризованных стола. Generic agent выбирает `PLACE_ITEM` по `load_rating_kg`, `finish` и своим actor capabilities, затем теряет действие после structural damage.

## Сквозные архитектурные линии

```text
Item identity       C1 ─ C2A ─ C2B ─ C3 ─ C4 ────────────────────► C13
Authority/replay    C1 ─ C2A ─ C2B ─ C3 ─ C4 ────────────────────► C13
Build intent        C0 ────────────── C3 ─ C4 ─ C8 ──────────────► C13
Reusable types      C0 ───────────────── C4 ─ C5 ─ C8 ───────────► C13
Facet compilation   C1 ───────── C3 ─ C5 ─ C6 ─ C7 ─ C9 ─ C11 ─► C13
Capabilities        C1 ───────── C3 ─ C5 ─ C6 ─ C7 ─ C8 ────────► C13
Semantic scale      C0 ───────────────── C7 ─ C10 ─ C11 ─────────► C13
Spatial partition   C0 ───────────────── C7 ───────── C12 ─ C13
```

Новый этап не принимается, если он:

1. создаёт вторую identity предмета;
2. меняет Item Graph вне C2B authority boundary;
3. делает ghost физическим источником истины;
4. выдаёт capabilities частичной конструкции как operational;
5. повторно расходует материал после replay/recovery;
6. делает progress state сильнее authoritative construct/ledger;
7. превращает mesh или Node3D в каноническое состояние;
8. сохраняет конкретные item/construct/build-plan IDs внутри reusable definition;
9. связывает CompositeDefinition с отдельным execution path в обход C3/C2B.

## Контрольные вертикальные объекты

- **Стол:** identity, parts, bonds, materials, stages, rollback, capabilities.
- **Робот:** rigid islands, joints, power, control, sensors, container, partial failure.
- **Дом:** sections, rooms, enclosure, utilities, semantic activation.
- **Сборщик:** input/output, tooling и исполнение того же BuildPlan.
- **Корабельная секция:** pressure topology, damage, leaks, split and authority transfer.

## Правило фиксации движения

Каждое продвижение обновляет одновременно:

1. `CONSTRUCTION_MAP_RU.md`;
2. `CONSTRUCTION_ROADMAP_RU.md`;
3. `CONSTRUCTION_PROGRESS_LOG_RU.md`;
4. checkpoint этапа;
5. delivery manifest;
6. validation JSON;
7. focused runner;
8. обязательный world-regression manifest.

Статус `ACCEPTED` назначается только после внешней проверки focused, network и полного world regression.


## C6: Mobile Construct

**Статус:** ACCEPTED.

```text
Authoritative ConstructSnapshot
├── concrete mobile parts
├── bond states
└── compiled_facets.mobile_subsystems
        ↓ deterministic subsystem compiler
ConstructionMobileProfile
├── POWER / CONTROL / DRIVE / SENSOR states
├── provider quorum
├── dependency cascade
├── MOBILE / DEGRADED / IMMOBILE
├── C5 capability descriptors
└── concrete mobile affordances
        ↓ checksum-pinned command
ConstructionMobileCommandAuthorizer
```

Ключевые правила C6:

- profile остаётся rebuildable projection authoritative `ConstructSnapshot`;
- health subsystem вычисляется из состояния конкретных parts, обязательных bonds и dependency graph;
- quorum позволяет потерять часть однотипных providers без полного отказа;
- `DAMAGED` больше не означает автоматический ноль всех возможностей: сохраняются только реально работоспособные подсистемы;
- потеря sensor не лишает робота движения;
- потеря power/control каскадно отключает drive и sensor;
- команда pin-ит checksum профиля и не исполняется против устаревшей конфигурации;
- физическое движение, network endpoint и graphical control остаются за следующим runtime-интеграционным слоем.

Контрольный объект: восьмикомпонентный колёсный rover. Потеря одного колеса снижает максимальную скорость `8 → 6 м/с`, потеря трёх колёс опускает drive ниже quorum и делает rover `IMMOBILE`, sensor failure сохраняет движение, battery/controller failure каскадно отключает зависимые подсистемы, а ремонт возвращает полный профиль.


## C7: Spatial Construct

**Статус:** ACCEPTED.

```text
Authoritative ConstructSnapshot
├── structural sections
├── exterior/interior openings
├── closure parts and bond states
├── semantic spaces
└── utility dependency graph
        ↓ deterministic spatial compiler
ConstructionSpatialProfile
├── section states
├── opening states
├── HABITABLE / DEGRADED / EXPOSED / INACTIVE spaces
├── POWER / DATA / WATER / AIR / HEAT utilities
├── ACTIVE / DEGRADED / INACTIVE building state
├── DORMANT / SUMMARY / FUNCTIONAL activation level
├── C5 capabilities
└── concrete spatial affordances
        ↓ checksum-pinned command
ConstructionSpatialCommandAuthorizer
```

Ключевые правила C7:

- Space Graph является семантическим DTO и не выводится из mesh/Node3D;
- enclosure зависит от section quorum, bonds и состояния exterior openings;
- открытая исправная дверь деградирует герметичность, но не уничтожает помещение;
- разрушенная стена, окно или door bond переводят room в `EXPOSED`;
- utility failure деградирует функциональность независимо от enclosure;
- зависимость DATA → POWER отключает data при потере power;
- partial construct остаётся `DORMANT` и не публикует spatial behavior;
- profile является rebuildable projection и pin-ит authoritative construct checksum.

Контрольный объект: однокомнатный дом с шестью boundary sections, дверью, окном, power panel и data router.


## C8: Fabrication Cell

**Статус:** ACCEPTED.

```text
Versioned FabricationRecipe
        ↓ deterministic allocation
FabricationJob + exact item bindings
        ↓ reserve
C2A FABRICATION_RESERVE plan
        ↓ C2B authority
inputs in machine input container
machine ConstructSnapshot pins active job
        ↓ idempotent work progress
C2A FABRICATION_COMPLETE plan
├── consume exact/partial input stacks
├── create fabricated ItemInstance outputs
└── update machine ConstructSnapshot
        ↓
normal Item Graph + output container + C3 BuildPlan
```

Ключевые правила C8:

- recipe version неизменяема и закрепляется checksum в каждом job;
- очередь не хранит альтернативные предметы: input/output bindings ссылаются на реальные item identities;
- reservation, completion и release проходят через расширенный C2A plan и общий C2B authoritative adapter;
- machine availability выводится из concrete parts/bonds, C5 behavior capabilities и C7 utilities;
- progress operation идемпотентна по operation ID;
- crash после authoritative completion восстанавливается по `fabrication_runtime.last_completed_job_id`;
- exact replay не расходует материал повторно и не создаёт второй продукт;
- fabricated item содержит `fabrication_origin` и возвращается в обычный Item Graph;
- изготовленная балка используется как source projection обычного C3 BuildPlan;
- анимация станка, tick-based power/heat/tool wear и UI остаются вне C8.

Контрольный объект: CNC-cell, которая при наличии WORKSTATION capability и POWER utility резервирует coolant и steel, выполняет десять work units и выпускает structural beam.


## C9: Damage, Split, Repair

**Статус:** ACCEPTED.

```text
DamageRequest + source checksum
        ↓ deterministic topology update
connected components
├── retained source aggregate
├── split child aggregate(s)
└── salvage ItemInstance(s)
        ↓ one authoritative transaction
Item Graph + multiple ConstructSnapshots + shared ledger
        ↓ pinned RepairPlan
inverse transaction restores original topology
```

Ключевые правила C9:

- broken bonds и destroyed parts исключаются из connectivity graph;
- retained component выбирается explicit `retained_part_id`;
- split identity задаётся до commit, а не генерируется внутри adapter;
- parts никогда не копируются между outcomes;
- source update, child create/delete и item relation changes атомарны;
- salvage policy задаёт минимальный размер нового construct и конечную relation;
- repair ghost проверяет наличие реальных item identities;
- exact damage/repair replay не меняет generation;
- terminal operation conflict отклоняет другой payload с тем же ID;
- C5–C8 profiles после damage/repair должны перестраиваться из новых snapshots.

Контрольный объект: bridge-arm из шести parts, который после двух broken bonds разделяется на source, двухкомпонентный child construct и одиночный salvage sensor, а затем полностью собирается обратно.


## C10: Parametric Members

**Статус:** IMPLEMENTED CANDIDATE.

```text
material + versioned definition + parameters
        ↓ deterministic metric compiler
ParametricMemberInstance
├── geometry / bounding box
├── mass and per-material usage
├── stock requirements
├── item identity and provenance
└── checksum
        ↓
C8 fabrication → Item Graph → C3 BuildPlan
        ↓
C9 conservative segmentation and repair
```

Ключевые правила C10:

- поддержаны beam, panel, pipe, cable и layered wall;
- exact parameter sets и limits являются частью versioned definition;
- density и stock-unit mass закреплены versioned material definition;
- material usage, volume и mass вычисляются, а не задаются вручную;
- output C8 остаётся обычным item-backed projection;
- C5 capability выводится из member kind и concrete part ID;
- segmentation сохраняет массу, объём и расход каждого материала;
- repair требует все pinned segment checksums и восстанавливает исходный parent instance;
- mesh/collision и local CSG остаются производными и переходят в C11.

Контрольный vertical slice: S355 beam компилируется из размеров, производится C8-станком из рассчитанного steel stock, входит в C3 BuildPlan, переживает C9 split/repair и режется на три консервативных сегмента.


## C11: Local Geometry Editing

**Статус:** IMPLEMENTED CANDIDATE.

```text
C10 instance + edit request + constraints
        ↓
semantic control-point path / parameter update
        ↓ C10 recompilation
new geometry, mass and material usage
        ↓ one authoritative transaction
ItemProjection + PartRecord + ConstructSnapshot
```

Ключевые правила C11:

- control points и constraints являются canonical DTO, а не editor-only state;
- C10 definition/material provenance сохраняется;
- relation, quantity и item identity edit не меняет;
- effective path length управляет C10 mass/material recomputation;
- part mass и parametric checksum синхронизируются с item projection;
- exact replay не выполняет второй commit;
- failure/constraint rejection не оставляет частичного состояния;
- C5/C8 downstream projections перестраиваются из нового checksum;
- mesh и collision остаются derived projections.


## C13: Runtime Geometry and Physics Projection

**Статус:** ACCEPTED.

```text
authoritative ConstructSnapshot + C6/C7/C10/C11 projections
        ↓ JSON-safe runtime descriptor
MeshInstance3D + CollisionShape3D + StaticBody3D/RigidBody3D
        ↓ checksum incremental synchronization
C9 split/removal + streaming rebuild
```

Ключевые правила C13:

- Node, Resource, RID и Transform3D никогда не входят в domain DTO;
- descriptor pin-ит source construct checksum и revision;
- неизменившиеся parts не перестраиваются;
- collision shapes создаются под единым physics body конструкции;
- C11 path становится набором детерминированных mesh/collision segments;
- C7 opening status управляет runtime transform closure part;
- C6 mobility state выбирает RigidBody3D и freeze;
- runtime tree полностью удаляем и восстанавливаем из derived descriptor store;
- C9 split сохраняет item identity и переносит presentation между construct roots.


## C14: Structural Integrity and Load Paths

**Статус:** ACCEPTED.

```text
part mass + gravity + external load
+ supports + part/bond capacities
        ↓
deterministic shortest support paths
        ↓
reactions and utilization
        ↓
progressive collapse
        ↓
C9 damage / split / repair
```

Ключевые правила C14:

- load case закрепляет checksum authoritative snapshot;
- part capacity и buckling limits находятся в semantic metadata;
- bond strength и degraded factor определяют effective capacity;
- profile и dormant summary полностью перестраиваемы;
- каскад каждый шаг пересчитывает после одного детерминированного отказа;
- ни structural profile, ни C13 physics nodes не изменяют authority напрямую;
- окончательное повреждение выполняется только через C9 multi-aggregate transaction.


## C15: Executable Utilities and Machines

**Статус:** ACCEPTED.

```text
C7 semantic utility topology
+ sources / links / consumers / storage
        ↓
deterministic tick allocation
        ↓
losses / priorities / load shedding
        ↓
checksum-pinned C8 machine lease
```

Ключевые правила C15:

- POWER/WATER/AIR/HEAT/DATA используют один strict generic flow contract;
- demand ниже minimum не получает скрытый частичный расход, а атомарно shed;
- source dispatch, link losses и storage deltas входят в execution profile;
- profile является rebuildable projection и не изменяет C7 authority;
- C8 progress разрешён только при фактически выделенном ресурсе;
- lease pin-ит machine, recipe, tick, profiles и allocations;
- work units ограничены delivered resource;
- exact replay не дублирует progress.


## C16 — Construction Interaction and Editing UX

**Статус:** ACCEPTED @ `a4376cd`.

Реализованы: semantic snapping, placement ghost, C11 gizmos, build/repair material overlays и C12-only command submission. Подробности: `docs/checkpoints/2026-08-01_C16_CONSTRUCTION_INTERACTION_AND_EDITING_UX_RU.md`.


## C17 — Distributed Construction Authority

Один aggregate имеет одного writer. Authority record закрепляет owner server/cell, epoch, lease и replicas. Команды C12 маршрутизируются к owner; migration включает fence и terminal-operation handoff; split child может получить owner в другой зоне; takeover разрешён только после lease expiry и из checksum-verified replica.


## C18 — Streaming, LOD and Dormant Constructs

**Статус:** ACCEPTED.

```text
interest + authority + budgets
→ DORMANT / SUMMARY / SIMULATED / PRESENTED
→ NONE / IMPOSTOR / SIMPLIFIED / FULL
```

C18 сохраняет authoritative snapshot checksums, C8 job IDs и pending operations, но удаляет derived summaries и C13 SceneTree по budget/interest policy. Owner выполняет bounded deterministic catch-up; read-only C17 replica может представляться, но не симулируется локально.


## C19 — Agent Construction and Automation API

**Статус:** IMPLEMENTED CANDIDATE.

```text
semantic goal
→ BOM / fabrication / reservation
→ work queue
→ C12 command
→ C17 owner
→ C3/C9 authoritative process
```

C19 поддерживает build, repair и salvage goals. Агент не получает прямого доступа к Item Graph или domain process: он создаёт проверяемый план, резервирует конкретные ресурсы, использует C8 для недостающих компонентов и выполняет mutation только через C12/C17. Exact replay и persistence исключают повторную фабрикацию и двойной commit после restart.
