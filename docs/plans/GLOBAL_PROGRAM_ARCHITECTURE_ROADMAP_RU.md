# Global Program Architecture Roadmap — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Status:** canonical program-level architecture plan  
**Canonical branch:** `main`  
**Date:** 2026-08-08

## 1. Зачем вводится эта правка

Проект вырос из одной последовательной дорожной карты в несколько зрелых параллельных программ:

```text
Distributed Runtime / S1
Network / NX
Construction / C + T1
Matter / MW + RL
World Generation / G
Character / CH
World Building Doctrine
```

Каждая программа по отдельности сохраняет правильные архитектурные принципы, но появилась новая системная опасность: разные ветки могут независимо начать реализовывать одинаковые фундаментальные понятия — spatial addressing, authority, material semantics, cross-domain transactions, interest и persistence.

Цель этого документа — не заменить локальные roadmap. Он вводит общий уровень над ними:

```text
GLOBAL PROGRAM PLAN
    ↓
branch-local roadmap
    ↓
implementation checkpoint
```

Локальная ветка может расширять свой план, но не может переопределять глобальные инварианты.

## 2. Каноническая формула архитектуры

```text
CANONICAL WORLD
    != PRESENTATION
    != TRANSPORT
    != COMPUTE
```

Дополнительные обязательные инварианты:

```text
identity != LOD
feature != cell
spatial location != authority route
authority ownership != compute assignment
transport semantics != gameplay semantics
procedural baseline != mutable world state
representation artifact != canonical state
```

Эти границы уже подтверждены существующими foundation:

- S1: worker предлагает mutation, authority проверяет и commit-ит;
- C22/C24: proxy/ArrayMesh/HLOD являются derived presentation;
- G2/G5: SurfaceCell/LOD не задают Feature identity;
- MW8–MW10: authority lease/fence и durable transaction не зависят от presentation;
- NX3–NX6: realtime networking не определяет domain semantics.

## 3. Статусные уровни программы

С этого revision запрещено использовать одно слово `DONE` для разных состояний.

Каждый крупный stage отслеживается минимум в четырёх измерениях:

```text
SOURCE_ACCEPTED
MAIN_INTEGRATED
COMPOSITION_VERIFIED
PRODUCTION_READY
```

Определения:

- `SOURCE_ACCEPTED` — stage принят в своей исходной ветке;
- `MAIN_INTEGRATED` — stage реально присутствует в `main`;
- `COMPOSITION_VERIFIED` — stage проверен совместно с соседними подсистемами;
- `PRODUCTION_READY` — подтверждены эксплуатационные бюджеты, recovery/soak и production constraints.

Пример: принятый stage не обязан быть уже production-ready; принятая ветка не обязана быть ещё интегрирована в `main`.

## 4. P0-1 — Global Program / Architecture Ledger

### Проблема

Существуют несколько локальных roadmap, и некоторые из них описывают исторически правильный, но уже не полный порядок развития.

### Решение

`main` является каноническим владельцем глобального program ledger.

Machine-readable companion:

```text
config/architecture/global-program-roadmap.v1.json
```

Активные параллельные ветки обязаны содержать byte-equivalent копию глобального плана и global config той же revision.

Локальные документы добавляются отдельно и обязаны ссылаться на:

```text
global_revision = GLOBAL-P0-2026-08-08-R1
```

### Правило

```text
GLOBAL PLAN = одинаковый во всех активных heads
LOCAL PLAN  = специфичен для ветки
```

Локальная ветка не должна редактировать global plan в одиночку. Изменение глобальной архитектуры сначала фиксируется в `main`, затем синхронно переносится в активные heads новой global revision.

## 5. P0-2 — Spatial Domain Fabric

### Причина

Проект уже использует несколько корректных, но разных spatial identities:

```text
S0 hierarchical cells
G2 SurfaceCellKey
G5 FeatureBounds / FeatureAnchor
MW authority regions / bricks
Construction scopes
NX interest regions
Space population cells
body/geodetic coordinates
local/reference frames
```

Ошибка — заменить их одним универсальным `ChunkId`.

### Целевой контракт

Ввести общий semantic mapping layer:

```text
WorldAddress
├── body_id
├── reference_frame_id
├── canonical position / bounds
└── spatial_domain

WorldAddress
    ├──> SurfaceCellKey
    ├──> MatterRegionId
    ├──> AuthorityRegionId
    ├──> InterestRegionId
    ├──> FeatureBounds
    ├──> ConstructionScope
    └──> SpacePopulationCell
```

### Инварианты

```text
SurfaceCellKey != FeatureId
MatterRegionId != AuthorityRegionId
InterestRegionId != canonical identity
LOD address != authoritative identity
reference frame != server owner
```

Mapping может быть many-to-many и versioned.

### Что должен доказать будущий P0 spatial checkpoint

- одна canonical position адресуется в нужные domain regions;
- изменение LOD не меняет canonical object/feature identity;
- authority rebalancing не меняет world address;
- один feature может пересекать много surface/matter/interest regions;
- один construct может иметь собственный local frame и при этом корректно находиться в world address space;
- headless server может выполнять mapping без renderer.

## 6. P0-3 — Unified Material Ontology

### Причина

Материал уже появляется одновременно в:

```text
G9 geology
MW mass ledger
Item Graph
Construction
fabrication
fluids
gases/atmosphere
salvage/recycling
```

Нельзя допустить независимые значения `iron`, `rock`, `water`, `steel` с разными semantics.

### Целевой foundation

```text
MaterialDefinitionId

MaterialDefinition
├── stable identity
├── composition
├── allowed phases
├── density model
├── mechanical properties
├── thermal properties
├── chemical/resource tags
├── fabrication tags
└── schema/version
```

Domain-specific projections:

```text
Geology      -> hardness/fracture/lithology
Matter       -> mass/volume/composition
Fluid        -> phase/density/flow properties
Item         -> contained quantity/composition
Construction -> structural/material properties
Fabrication  -> transformation inputs/outputs
```

### Инварианты

- MW10 mass ledger использует canonical material identity;
- G9 не вводит конкурирующий material namespace;
- Item resource identity не обязана равняться MaterialDefinitionId;
- processed composite material может ссылаться на composition, а не маскироваться строковым item type;
- rendering material никогда не является canonical material definition.

## 7. P0-4 — Cross-Domain World Transaction Model

### Причина

M0 решает atomic multi-aggregate mutation в одной authority boundary. MW10 решает durable cross-region Matter transaction. Но будущие gameplay operations пересекают домены:

```text
mining:
Matter - mass
Item Graph + resource

construction:
Item Graph - materials
Construction + parts

salvage:
Construction - part
Item/Matter + recovered material
```

### Целевая модель

```text
WorldOperation
    ↓ validation / authority plan
WorldTransactionPlan
    ├── Item mutations
    ├── Construction mutations
    ├── Matter mutations
    ├── produced events/outbox
    └── compensation/recovery policy
```

Execution class выбирается по реальной boundary:

```text
single authority + M0-capable aggregates
    -> atomic M0 transaction

multiple Matter authority regions
    -> MW10-style durable coordinated transaction

long-running / cross-service workflow
    -> durable saga / intent / compensation
```

### Запрещено

```text
Matter commit -> затем best-effort Item RPC
Item decrement -> затем best-effort Construction RPC
```

Canonical gameplay result не может зависеть от случайного порядка сетевых сообщений.

### До T3/T5

До формального T3/T5 acceptance должны быть определены:

- common operation identity;
- durable decision ownership;
- retry/replay semantics;
- cross-domain revision/result envelope;
- compensation rules для non-atomic workflows;
- outbox/event publication boundary.

## 8. P0-5 — NX7/NX8/NX9 architectural reconciliation

Этапы NX7–NX9 остаются нужны, но им запрещено создавать вторую foundation поверх уже существующей.

### NX7 Physics Authority Profiles

NX7 = **policy layer над существующим authority foundation**.

Использует:

```text
A1 aggregate authority
S0 spatial scope
C17 authority migration where applicable
MW8/MW9 lease/fencing patterns where applicable
network ownership/session mapping
```

NX7 не создаёт новый canonical owner registry.

Profiles описывают runtime policy:

```text
SERVER_ONLY
OWNER_PREDICTED
OWNER_AUTHORITY_VALIDATED
PREDICTED_SPAWN
CLIENT_COSMETIC
```

### NX8 Interest Management / Replication Budget

NX8 = **общий Interest/Budget contract + domain adapters**.

Он не владеет world identity и не делает HLOD каноническим состоянием.

Consumers/providers:

```text
players/entities
items
construction C22/C24
Matter/RL representations
Geo/detail representation
future AI/population
```

Общий vocabulary должен включать минимум:

```text
interest subject
spatial bounds
priority
representation level
bandwidth budget
update age/staleness
enter/leave hysteresis
```

### NX9 Async Persistence / Hardening

NX9 = **удаление blocking I/O из realtime path**, а не новый persistence model.

Он обязан переиспользовать semantics существующих foundation:

```text
R3 recovery
M0 atomic transaction/outbox
operation replay/dedup
MW9/MW10 durable decision/recovery patterns
```

Разрешается менять scheduling/backend I/O. Запрещается менять canonical commit semantics ради производительности.

## 9. Geo/Matter boundary

Generation roadmap не должен создавать вторую Matter implementation.

Будущая `GM` линия трактуется как:

```text
Geo <-> Matter Integration
```

а не:

```text
GM Matter implementation || MW Matter implementation
```

Целевая композиция:

```text
procedural Geo baseline
        +
authoritative sparse Matter mutations
        ↓
current canonical material/volume truth
        ↓
GeoVolume / Matter / gameplay query
```

`procedural baseline + sparse authoritative mutations = current world truth` остаётся обязательным правилом.

## 10. Representation boundary

Одинаковая модель применяется к природному и построенному миру:

```text
Canonical natural world
 -> terrain/detail/proxy representation

Canonical construct graph
 -> C22/C24 proxy/HLOD representation
```

Representation artifacts:

- могут кэшироваться;
- могут удаляться;
- могут пересобираться;
- могут отличаться по клиентскому бюджету;
- не меняют checksum canonical world сами по себе.

## 11. Active branch synchronization policy

Активный head обязан содержать:

```text
docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md
config/architecture/global-program-roadmap.v1.json
```

с одной global revision.

Дополнительно branch-local plan обязан явно указать:

- local branch purpose;
- current local stage;
- dependencies on P0 foundations;
- что branch не имеет права переопределять;
- merge/composition gate.

### Текущий sync set R1

```text
main
feature/t1-complex-construct-demo-lab
feature/g5-world-feature-graph
feature/ch7-8-skinned-garment
feature/world-building-doctrine
```

Accepted/frozen historical checkpoint branches не переписываются задним числом.

## 12. Branch-local responsibilities

### T1 / Construction

T1 продолжает Complex Construct Demo и composition validation.

Дополнительные P0 требования:

- construction spatial scopes должны маппиться через Spatial Domain Fabric;
- construction materials в будущем используют Unified Material Ontology;
- consume/build/salvage flows не создают private cross-domain transaction bridge;
- C22/C24 representation остаётся derived;
- T1 может исследовать composition до завершения P0 implementations, но formal T5-like cross-domain acceptance требует соответствующих contracts.

### G5+ / World Generation

G5 остаётся accepted feature-identity foundation; G6 и далее продолжаются.

Дополнительные P0 требования:

- G surface cells не становятся authority regions;
- G9 использует shared MaterialDefinitionId;
- GM = Geo/Matter integration;
- G12 scheduler не становится authority/persistence owner;
- generation/representation budgets должны быть совместимы с будущим shared work/interest vocabulary.

### CH / Character

Character остаётся presentation/domain-adapter track.

Дополнительные P0 требования:

- avatar rig/model не становятся player canonical identity;
- equipment presentation не создаёт второй Item/Material truth;
- future physical authority profiles подключаются через NX7 policy;
- local character frames должны быть совместимы с общим spatial/reference-frame mapping.

### World Building Doctrine

Doctrine задаёт design intent, но не техническую authority.

Её technical mapping:

```text
world-state progression
 -> canonical persistent mutations
infrastructure
 -> Construction/Item/Matter
automation
 -> WorldOperations + AI/compute
large world
 -> Spatial/Interest/Authority separation
```

## 13. P1 foundations, которые должны быть защищены уже сейчас

Они не входят в P0 implementation gate, но текущие решения не должны их блокировать:

```text
Time Fabric / multi-rate deterministic simulation
Reference Frame + Geodesy integration
World Query Fabric
Promotion / Dormancy / Demotion lifecycle
World Work / Budget Fabric
Hierarchical Navigation / AI
```

Особенно запрещено жёстко привязывать canonical state к render frame, camera, one-server clock или one-rate simulation loop.

## 14. Stop conditions

Любая ветка должна остановить stage и вынести решение на global architecture revision, если для реализации требуется хотя бы одно:

```text
новый canonical authority registry при существующем authority foundation
новый global material namespace
новый generic chunk identity, заменяющий domain-specific identities
RPC chain как единственная гарантия cross-domain transaction
renderer/HLOD как canonical source
NX persistence model, несовместимый с M0/R3/MW durability
GM Matter implementation, параллельная MW
camera/LOD, влияющие на canonical identity
server route, встроенный в permanent world identity
```

## 15. Merge и composition gate

Перед merge активной параллельной ветки в `main` проверяется:

```text
[ ] global revision совпадает
[ ] global config совпадает
[ ] local alignment doc присутствует
[ ] local stage не нарушает P0 ownership boundaries
[ ] новые contracts не дублируют existing foundation
[ ] accepted source status отделён от main/composition status
[ ] branch-specific tests/regression проходят
```

Если global revision ветки устарел, сначала выполняется synchronization rebase/merge или документационная sync-поставка, и только затем functional acceptance.

## 16. Целевая общая модель

```text
WORLD =
    Stable Identity
  + Spatial Domain Fabric
  + Recipe / Providers / Features
  + Material Ontology
  + Environment / Volume truth
  + Sparse authoritative mutations
  + Items / Construction / Entities
  + Durable WorldOperations

AUTHORITY =
    temporary right to mutate part of WORLD

COMPUTE =
    proposal generation, never implicit authority

VIEW =
    WORLD
  -> interest
  -> representation budget
  -> disposable local artifacts
```

Именно эта модель является общей архитектурной точкой, которой должны подчиняться все локальные roadmap начиная с `GLOBAL-P0-2026-08-08-R1`.
