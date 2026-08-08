# G5 World Feature Graph — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/g5-world-feature-graph`  
**Local role:** Universal World Generation Fabric, accepted G5 frontier

## Зачем добавлен этот документ

G5 уже правильно отделяет Feature identity от SurfaceCell, LOD и renderer. Следующие G6–G13 стадии начинают пересекаться с Matter, materials, authority, interest и scheduling, поэтому необходимо заранее закрепить, какие contracts принадлежат Generation, а какие являются общими foundation проекта.

## Локальная линия Generation

```text
G5 World Feature Graph              ACCEPTED
 ↓
G6 Hydrology / Fluid Surface v0
 ↓
G7 Semantic Field Fabric
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

Эта последовательность сохраняется.

## P0 dependencies

### Spatial Domain Fabric

G2 `SurfaceCellKey` остаётся representation/generation addressing. G5 `FeatureId` остаётся semantic identity.

Generation не вводит единый global ChunkId и не превращает surface cells в authority/interest regions.

Будущие surface/volume/space providers должны подключаться через mapping к общему `WorldAddress`.

### Unified Material Ontology

G9 не создаёт автономный глобальный namespace материалов.

```text
Lithology / hardness / fracture / geology fields
    -> projection shared MaterialDefinitionId
```

Generator может хранить provider-specific parameters, но canonical material meaning должен быть общим с MW, Item, Construction, Fluid и Fabrication.

### Geo/Matter boundary

Будущая `GM` линия трактуется исключительно как:

```text
Geo <-> Matter Integration
```

Не допускается новая параллельная Matter implementation.

Canonical composition:

```text
procedural baseline
+ authoritative sparse Matter mutations
= current world truth
```

### Transactions

Mining/excavation, которые создают Item/Material output, в будущем используют общий `WorldOperation / WorldTransactionPlan`, а не `Geo RPC -> Matter RPC -> Item RPC`.

### NX8 / representation

G representation/detail может быть provider NX8 interest/budget, но:

```text
LOD / patch / billboard / MultiMesh != canonical identity
```

### G12 scheduler

G12 владеет scheduling generation jobs и caches. Он не получает право:

- становиться authority owner;
- определять durable canonical commit;
- заменять S1 compute boundary;
- создавать отдельный persistence truth.

## Локальные задачи, разрешённые без P0 block

- G6 hydrology contracts/features;
- G7 semantic fields;
- GR representation experiments;
- GE environment contracts;
- deterministic scatter research;
- G8 geomorphology research до material freeze;
- G10 SDF backend research при сохранении shared identity boundaries.

G9 material contract freeze должен учитывать P0 Material Ontology.

## Stop conditions

Generation stage останавливается и требует global architecture revision, если требуется:

- использовать SurfaceCellKey как Feature/authority permanent identity;
- создать новый global material namespace;
- создать GM Matter runtime, параллельный MW;
- считать renderer/shader единственным источником terrain truth;
- сделать G12 scheduler authoritative writer;
- связывать canonical geography с camera/LOD/query order.

## Merge gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 или более новая синхронная revision
[PASS] global config byte-equivalent main
[PASS] network NX7-NX9 boundaries синхронизированы
[PASS] G local roadmap сохраняет Feature != Cell
[PASS] GM boundary определена как Geo/Matter integration
[PASS] G9 не замораживает private material ontology
[PASS] G5/G6+ relevant regressions
```

Канонический общий план: `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
