# G7–G13 — P0-aligned roadmap Universal World Generation Fabric

**Global revision:** `GLOBAL-P0-2026-08-10-R2`
**Branch:** `feature/g7-semantic-field-fabric`
**Current frontier:** `G7.3 — Cross-Cell / Cross-LOD Invariance`
**Upstream accepted:** `G6 Hydrology / Fluid Surface v0 — SOURCE_ACCEPTED`

## 1. Цель линии

G7–G13 превращает принятые G3/G5/G6 semantics в универсальный набор composable fields, затем в geomorphology, geology, volume и разные типы celestial bodies.

Главная граница остаётся:

```text
canonical procedural semantics
        != representation cells / LOD
        != renderer
        != authority routing
        != persistence backend
        != network transport
```

И:

```text
Geo baseline + sparse authoritative Matter mutations = current world truth
```

## 2. P0 guards

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldId != AuthorityRegionId
SemanticFieldId != InterestRegionId
SemanticFieldQuery != universal WorldQuery Fabric
FluidTypeId != MaterialDefinitionId
Geo provider != persistence owner
Geo provider != network owner
Geo provider != authority owner
```

G7 остаётся domain semantic fabric. Scheduler/cache ownership — G12; shared Work/Budget vocabulary — future P1 foundation.

## 3. Текущий G7 progression

```text
G7.0 Semantic Field Contracts            ACCEPTED
G7.1 Upstream Adapters                    completed upstream step
G7.2 Composition / Provenance              completed upstream step
G7.3 Cross-Cell / Cross-LOD Invariance    CURRENT
G7.4 Semantic Field Lab                   NEXT VISUAL MILESTONE
```

### G7.3 — Cross-Cell / Cross-LOD Invariance

Acceptance должен доказать:

- один world point даёт одинаковые canonical semantic values независимо от `SurfaceCellKey`;
- LOD меняет только sampling/representation density;
- cube-sphere seams не меняют semantic value;
- один river/valley feature пересекает много cells без смены identity;
- query order не влияет на result/provenance;
- renderer/camera не участвуют в canonical checksum.

G7.3 не должен вводить новый spatial mapping foundation. Он доказывает invariance уже существующих domain identities.

### G7.4 — Semantic Field Lab

После G7.3 делается derived graphical lab с переключением:

```text
height
slope
curvature
river distance
moisture proxy
continentalness
```

Lab colors, mesh density, patch layout и camera не входят в canonical truth.

G7.4 — первый официальный visual milestone после текущего G7.3.

## 4. G8 — Geomorphology

G8 является **первым natural terrain showcase milestone**.

Ownership:

```text
valley incision
river channel incision
banks
floodplain shaping
ridge/valley response
erosion/deposition baseline
```

Не ownership:

```text
player excavation
persistent terrain damage
Matter transactions
material ontology
```

Целевая композиция:

```text
G3 macro height
 + G7 drainage / river / slope fields
 -> G8 geomorphology modifiers
 -> canonical procedural surface baseline
```

Главный visual proof: river из G6 реально формирует channel/valley/banks/floodplain, а не лежит поверх terrain как presentation mesh.

## 5. G9 — Layered Geology

G9 добавляет:

```text
strata / layers
lithology topology
fault influence
ore/resource potential
porosity
hardness/fracture projections
thermal/geochemical hooks
```

Formal material truth требует P0 Unified Material Ontology.

```text
G9 topology can proceed
G9 material truth requires P0 MaterialDefinitionId bridge
```

## 6. G10 — GeoVolume / SDF

G10 — **first true 3D geo/volume showcase**.

```text
caves
arches
overhangs
floating islands
asteroid voids
subsurface chambers
true volumetric cliffs
```

```text
GeoVolume != Matter storage
GeoVolume != authoritative excavation state
```

## 7. G11 — Heterogeneous Body Lab

G11 — **universal body showcase**.

Минимальная matrix:

```text
Earth-like sphere
small irregular asteroid
floating-island body/field
water-dominant world
ice/methane-like body
body with non-default gravity/environment parameters
```

Замена recipe/providers должна менять world composition без `if earth / if asteroid` в generic kernel.

## 8. G12 — Scheduler / Cache / Provenance

G12 владеет execution layer:

```text
generation work scheduling
provider dependency execution
cache keys
cache invalidation
provenance manifests
budget accounting adapters
```

Но не владеет:

```text
authority
persistence semantics
world identity
network ownership
canonical transaction commit
```

G12 обязан оставаться совместимым с NX8 и future World Work / Budget Fabric, а не создавать private global scheduler identity.

## 9. G13 — Detail Contract Freeze

G13 фиксирует contract boundary для:

```text
surface
features
fluids
semantic fields
geomorphology
geology
volume/SDF
provenance
representation requests
```

После G13 production detail/content generators могут масштабироваться без диктовки новых core interfaces.

## 10. Визуальные milestones G

Начиная с P0 R2 они фиксируются явно:

```text
G7.4
  semantic/debug visualization

G8
  FIRST NATURAL TERRAIN SHOWCASE

G10
  FIRST TRUE 3D GEO/VOLUME SHOWCASE

G11
  UNIVERSAL BODY SHOWCASE
```

Это не новые canonical stages и не перенос ownership в renderer; это обязательные observable evidence points.

## 11. Параллельность с T / TS

Сейчас одновременно развивается:

```text
G7.3  World Generation correctness
T1A.4 Construction composition
TS0   planned Construction scale/visual proof
```

G не должен зависеть от TS0, а TS0 не должен использовать G cells как Construction section identity.

Позднее разрешён composition consumer:

```text
G8 accepted natural terrain
+
usable T1 D1 outpost
+
usable character presentation
        ↓
V0 Planet + Outpost Showcase
```

V0 не является owner G/T/CH foundations.

## 12. Merge / composition gates

Каждый G7+ checkpoint перед SOURCE_ACCEPTED подтверждает:

```text
GLOBAL revision == main
GLOBAL config byte-equivalent
GLOBAL roadmap byte-equivalent
local P0 alignment current
no duplicate foundation ownership
identity independent from cell/LOD/rendering/network
headless semantic execution possible
focused contracts PASS
parent G-stage regression PASS
world/core regression PASS
clean worktree
git diff --check PASS
status dimensions remain distinct
```

Дополнительные gates:

```text
G9  -> Material Ontology composition gate
G10 -> Geo/Matter ownership audit
G12 -> Authority/Persistence/Work-Budget ownership audit
```

## 13. Stop conditions

G stage должен остановиться и вынести вопрос в P0, если требуется:

```text
SurfaceCellKey as global WorldAddress
LOD/camera in canonical identity
private material ontology
private authority registry
private persistence ownership
private global Work/Budget foundation
second Matter implementation
renderer artifact as canonical source
```

## 14. Ближайшая последовательность

```text
G7.3 CURRENT
  ↓
G7.4 visual semantic field lab
  ↓
G8 natural terrain showcase
```

Это текущая ближайшая G-линия после `GLOBAL-P0-2026-08-10-R2`.
