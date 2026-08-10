# Global Program Architecture Roadmap — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-10-R2`  
**Status:** canonical program-level architecture plan  
**Canonical branch:** `main`  
**Date:** 2026-08-10

---

## 1. Назначение global plan

Проект развивается несколькими параллельными программами:

```text
Distributed Runtime / S1
Network / NX
Construction / C + T
Matter / MW + RL
World Generation / G
Character / CH
World Building Doctrine
```

Global P0 plan не заменяет branch-local roadmap. Он задаёт общие ownership boundaries, синхронизацию активных heads и composition gates.

```text
GLOBAL PROGRAM PLAN
        ↓
branch-local roadmap
        ↓
implementation checkpoint
```

Локальная ветка может расширять свою область, но не может создавать конкурирующий global foundation.

---

## 2. Каноническая формула архитектуры

```text
CANONICAL WORLD
    != PRESENTATION
    != TRANSPORT
    != COMPUTE
```

Обязательные инварианты:

```text
identity != LOD
feature != cell
spatial location != authority route
authority ownership != compute assignment
transport semantics != gameplay semantics
procedural baseline != mutable world state
representation artifact != canonical state
```

Для природного и построенного мира действует один принцип:

```text
Canonical natural world
    -> disposable terrain/detail/proxy representation

Canonical construct graph
    -> disposable C22/C24/HLOD representation
```

Representation можно кэшировать, удалять и перестраивать. Она не является canonical truth.

---

## 3. Статусы программы

Каждый крупный stage отслеживается раздельно:

```text
SOURCE_ACCEPTED
MAIN_INTEGRATED
COMPOSITION_VERIFIED
PRODUCTION_READY
```

- `SOURCE_ACCEPTED` — stage принят в своей исходной ветке;
- `MAIN_INTEGRATED` — stage реально присутствует в `main`;
- `COMPOSITION_VERIFIED` — проверен совместно с соседними подсистемами;
- `PRODUCTION_READY` — закрыты эксплуатационные budgets, recovery/soak и production constraints.

Один статус не подразумевает остальные.

---

## 4. P0-1 — Global Program / Architecture Ledger

`main` является владельцем глобального ledger.

Machine-readable companion:

```text
config/architecture/global-program-roadmap.v1.json
```

Активные ветки обязаны иметь byte-equivalent:

```text
docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md
config/architecture/global-program-roadmap.v1.json
```

### R2: правило active frontier

Начиная с R2 каждая активная программа имеет **одну объявленную frontier branch**.

```text
PROGRAM
   ↓
ACTIVE FRONTIER
   ↓ acceptance / handoff
NEXT ACTIVE FRONTIER
```

Accepted/frozen ancestor не переписывается новой global revision только ради синхронизации.

Переход frontier фиксируется сначала в `main`, затем один и тот же global change-set переносится в новые активные heads.

### Текущий active sync set R2

```text
main
feature/t1a4-interactive-fixture-binding
feature/g7-semantic-field-fabric
feature/ch7-8-skinned-garment
feature/world-building-doctrine
```

Текущие важные frontier stages:

```text
T: T1A.4 Interactive Fixture Binding
G: G7.3 Cross-Cell / Cross-LOD Invariance
```

---

## 5. P0-2 — Spatial Domain Fabric

Проект уже использует разные корректные spatial identities:

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

Они не должны быть сведены к одному `ChunkId`.

Целевой mapping:

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

Инварианты:

```text
SurfaceCellKey != FeatureId
MatterRegionId != AuthorityRegionId
InterestRegionId != canonical identity
LOD address != authoritative identity
reference frame != server owner
Construction section != WorldAddress
```

---

## 6. P0-3 — Unified Material Ontology

Material semantics встречаются одновременно в:

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

Будущий общий owner:

```text
MaterialDefinitionId
MaterialDefinition
```

Domain projections могут различаться, identity материала — общая.

```text
render material != canonical material
presentation material_family != MaterialDefinitionId
```

G9 не имеет права вводить отдельные canonical `rock/iron/water` identities; Construction также не получает private material ontology.

---

## 7. P0-4 — Cross-Domain World Transaction Model

Будущие операции пересекают Item / Construction / Matter:

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

Целевая модель:

```text
WorldOperation
    ↓ validation / authority plan
WorldTransactionPlan
    ├── Item mutations
    ├── Construction mutations
    ├── Matter mutations
    ├── events/outbox
    └── compensation/recovery policy
```

Запрещён correctness вида:

```text
Item commit -> best-effort Construction RPC
Matter commit -> best-effort Item RPC
```

Транспортный порядок не определяет canonical outcome.

---

## 8. P0-5 — NX7/NX8/NX9 reconciliation

### NX7

Physics Authority Profiles являются policy поверх существующего authority foundation, а не новым owner registry.

### NX8

Interest Management / Replication Budget является общим contract + domain adapters.

Consumers:

```text
players/entities
items
construction C22/C24
Matter/RL
Geo/detail representation
future AI/population
```

### NX9

Async Persistence / Hardening удаляет blocking I/O, но переиспользует существующие durability semantics R3/M0/MW.

---

## 9. Geo / Matter boundary

```text
procedural Geo baseline
        +
authoritative sparse Matter mutations
        ↓
current world truth
```

Будущий `GM` означает:

```text
Geo <-> Matter Integration
```

а не вторую Matter implementation.

---

## 10. P1 foundations, которые нельзя заблокировать

Текущие решения обязаны оставлять место для:

```text
Time Fabric / multi-rate deterministic simulation
Reference Frame + Geodesy integration
World Query Fabric
Promotion / Dormancy / Demotion lifecycle
World Work / Budget Fabric
Hierarchical Navigation / AI
```

Особенно важно для scale/render labs: локальный lab budget не должен превращаться в новый global scheduler.

---

# 11. Активная программа T — Construction

Текущий frontier:

```text
T1A.4 Interactive Fixture Binding
```

T1A.4 продолжает gameplay composition и не должен блокироваться визуальным scale research.

Начиная с R2 T делится на две параллельные линии после принятого Construction baseline:

```text
                         accepted T1A.3
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
       T COMPOSITION                     TS SCALE/VISUAL
              │                               │
       T1A.4 Binding                    TS0.0 Fixtures
              │                               │
       T1A.5 Runtime                    TS0.1 10k
              │                               │
       T1A.6 Inspector                  TS0.2 100k
              │                               │
       T1B Composition                  TS0.3 local mutation
              │                               │
              │                         TS0.4 1M probe
              │                               │
              └───────────────┬───────────────┘
                              ▼
                            T2.0+
```

TS означает Construction scale/visual research и остаётся внутри T family.

---

## 12. TS0 — Large Structural Visual Lab

### Роль

TS0 является **pre-T2 evidence**, а не новым production foundation и не T2 acceptance.

Главный вопрос:

> Может ли один canonical construct из большого количества простых одинаковых строительных блоков выглядеть и масштабироваться как один большой объект, не превращаясь в десятки/сотни тысяч тяжёлых SceneTree nodes и draw calls?

### Текущая база для ветки

TS0 не должен наследоваться от незавершённого T1A.4 candidate.

Предпочтительная база:

```text
T1A.3 SOURCE_ACCEPTED
commit: 5e051f67bf6987a354de5b565da1448be6b0b4db
+
GLOBAL-P0-2026-08-10-R2 sync change-set
```

T1A.4 и TS0 после этого развиваются параллельно.

### TS0.0 — Deterministic Large Structural Fixtures

Минимальные профили:

```text
CUBE_10K
PYRAMID_10K
CUBE_100K
PYRAMID_100K
CUBE_1M_RESEARCH
```

Примеры:

```text
22 x 22 x 22 = 10 648 blocks
46 x 46 x 46 = 97 336 blocks
100 x 100 x 100 = 1 000 000 blocks
```

Ступенчатые пирамиды должны иметь deterministic dimensions и stable IDs.

Fixture contract должен содержать минимум:

```text
fixture_id
shape
block_size_m
dimensions / levels
expected_part_count
construct_id
part_identity_policy
expected canonical checksum
```

### TS0.1 — 10k Visual Proof

Доказать реальный graphical observation:

```text
walk around object
free-flight camera
near block visibility
mid section representation
far compiled/HLOD representation
```

### TS0.2 — 100k Visual Scale Gate

Это основной TS0 gate.

Нужно доказать:

```text
~100k canonical semantic parts
        !=
~100k Node3D
~100k MeshInstance3D
~100k draw calls
```

HUD/telemetry:

```text
canonical_part_count
active_runtime_nodes
visible_sections
triangles
draw_calls
mesh_artifact_count
mesh_build_ms
GPU/resource bytes
current representation level
observer distance
```

### TS0.3 — Local Mutation / Dirty Section

На 100k fixture удалить локальную область, например `10x10x10` blocks.

Acceptance:

```text
canonical revision changes
only affected sections become dirty
whole construct is not recompiled
near/mid/far artifacts converge
construct and unaffected part identities remain stable
```

### TS0.4 — 1M Research Ceiling Probe

```text
1 000 000 semantic parts
```

Это research/ceiling probe, не обязательный production gate.

### TS0 representation modes

Полезный visual debug:

```text
SOLID
BLOCK_BOUNDARIES
SECTION_BOUNDARIES
HLOD_LEVELS
DIRTY_REBUILD_REGIONS
STATISTICS
```

Все debug modes — presentation-only.

### TS0 P0 non-ownership

TS0 не владеет и не создаёт:

```text
WorldAddress
Spatial Domain Fabric
AuthorityRegionId
InterestRegionId
MaterialDefinitionId
WorldOperation / WorldTransactionPlan
network replication policy
persistence semantics
global Work/Budget scheduler
```

Дополнительные guards:

```text
section_id != WorldAddress
section_id != AuthorityRegionId
section_id != InterestRegionId
HLOD != canonical construct state
visual material != MaterialDefinitionId
lab budget knob != global Work Budget contract
```

TS0 переиспользует C21/C22/C24 и существующую Construction canonical truth.

---

## 13. T2 после появления TS0

TS0 не заменяет T2.0.

Правильный переход:

```text
TS0 synthetic 10k/100k scale evidence
             ↓
T2.0 real large construct
```

T2.0 должен заменить синтетический cube/pyramid реальной сложной базой или станцией с разными semantic sections, а не повторять тот же synthetic benchmark.

Профили T2 остаются:

```text
S0  10 000+ semantic parts
S1  100 000 semantic parts
S2  1 000 000 research ceiling
```

Но после TS0 основной риск T2.0 смещается с raw rendering scale на composition scale.

---

# 14. Активная программа G — World Generation

Текущий frontier:

```text
G7.3 Cross-Cell / Cross-LOD Invariance
```

Текущий порядок сохраняется:

```text
G7.3 Cross-Cell / Cross-LOD Invariance
    ↓
G7.4 Semantic Field Lab
    ↓
G8 Geomorphology
    ↓
G9 Layered Geology
    ↓
G10 GeoVolume / SDF
    ↓
G11 Heterogeneous Body Lab
    ↓
G12 Scheduler / Cache / Provenance
    ↓
G13 Detail Contract Freeze
```

P0 ownership G не меняется.

### Визуальные milestones G

Чтобы инфраструктурная разработка регулярно давала наблюдаемый результат, фиксируются отдельные visual milestones:

```text
G7.4
    semantic/debug visualization

G8
    FIRST NATURAL TERRAIN SHOWCASE
    river actually shapes valley/channel/banks/floodplain

G10
    FIRST TRUE 3D GEO/VOLUME SHOWCASE
    caves / overhangs / arches / floating islands / asteroid voids

G11
    UNIVERSAL BODY SHOWCASE
    Earth-like / asteroid / floating-island / water-dominant / unusual body recipes
```

Эти labs являются derived presentation и не меняют canonical semantics.

---

## 15. Future V0 — Planet + Outpost Showcase

После того как одновременно доступны:

```text
G8 accepted natural terrain baseline
+
usable T1 D1 outpost composition
+
usable character presentation
```

разрешается отдельный composition consumer:

```text
V0 Planet + Outpost Showcase
```

Цель:

```text
procedural terrain
+ river/valley
+ real Construction outpost
+ character
= first integrated visible world slice
```

V0 не является owner ни G, ни T, ни CH foundation.

Если showcase требует нового global identity/authority/material/transaction понятия, работа останавливается и вопрос возвращается в P0.

---

## 16. Character / Doctrine responsibilities

### CH

Character остаётся presentation/domain-adapter track:

```text
avatar rig/model != player identity
equipment presentation != Item/Material truth
physics authority -> NX7 policy
local frames -> future Spatial/Reference Frame mapping
```

### World Building Doctrine

Doctrine задаёт design intent, но не technical authority.

```text
world-state progression -> persistent canonical mutations
infrastructure           -> Construction / Item / Matter
automation               -> WorldOperations + AI/compute
large world              -> Spatial / Interest / Authority separation
```

---

## 17. Merge / composition gate

Перед merge active branch:

```text
[ ] GLOBAL revision == main
[ ] global config byte-equivalent main
[ ] global roadmap byte-equivalent main
[ ] local alignment doc present/current
[ ] no duplicate global foundation ownership
[ ] identity independent from LOD/render/network route
[ ] status dimensions remain distinct
[ ] focused tests PASS
[ ] branch/world regression PASS where required
```

Для TS0 дополнительно:

```text
[ ] branch based on accepted Construction checkpoint, not T1A.4 candidate
[ ] C21/C22/C24 reused rather than duplicated
[ ] section/HLOD identity remains derived
[ ] laboratory build budgets are not promoted to global scheduler contracts
[ ] 100k visual gate records runtime-node/draw-call/resource telemetry
[ ] 1M result classified as research only
```

---

## 18. Stop conditions

Любая ветка останавливает локальную реализацию и поднимает global architecture revision, если требуется:

```text
new canonical authority registry
new global material namespace
new generic chunk identity replacing domain identities
RPC ordering as canonical transaction guarantee
renderer/HLOD as canonical source
private persistence model conflicting with R3/M0/MW durability
second Matter implementation
camera/LOD influencing canonical identity
server route embedded in permanent world identity
private scale-lab scheduler pretending to be global Work Budget Fabric
```

---

## 19. Целевая общая модель

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
  -> representation/work budget
  -> disposable local artifacts
```

R2 добавляет к этой модели не новый foundation, а дисциплину развития:

```text
one declared active frontier per program
+
regular visual evidence tracks
+
strict separation of synthetic scale proof from real composition acceptance
```

Это является общей архитектурной точкой для всех активных roadmap начиная с `GLOBAL-P0-2026-08-10-R2`.
