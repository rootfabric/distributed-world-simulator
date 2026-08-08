# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/g6-hydrology-fluid-surface-v0`  
**Local role:** hydrology/fluid semantic layer above G5 World Feature Graph  
**Current stage:** `G6.1 CasualRiverProviderV1 — IMPLEMENTED CANDIDATE`  
**Next stage after acceptance:** `G6.2 cross-cell / cross-LOD continuity`

## Назначение

G6 развивает гидрологию как semantic/provider layer поверх G5, не создавая отдельный spatial, authority, persistence или material foundation.

Каноническая цепочка:

```text
G5 WorldFeature / FeatureId
        ↓
G6 fluid semantic provider
        ↓
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
        ↓
representation/query adapters
```

Главный invariant:

```text
FluidRegion != SurfaceCell
FluidRegion != AuthorityRegion
FluidRegion != InterestRegion
FluidRegion != renderer object
Fluid identity != LOD / quality / observer state
```

## P0-2 Spatial Domain Fabric

До появления общего `WorldAddress` G6 использует существующие G5 body/reference-frame/feature semantics и не объявляет `SurfaceCellKey` владельцем canonical fluid identity.

Одна река может пересекать много generation/representation cells. Разбиение по cell, LOD или streaming budget является производным представлением одной semantic river identity.

Будущая интеграция должна маппировать canonical fluid bounds/anchors к Spatial Domain Fabric, а не заменять его собственным `RiverChunkId`.

## P0-3 Unified Material Ontology

G6.0 `FluidType` остаётся semantic fluid namespace baseline и не считается полной material ontology.

Когда P0 Unified Material Ontology будет введена, fluid semantics должны проецироваться на общий `MaterialDefinitionId` для density/phase/composition/thermal/resource meaning.

Запрещено превращать rendering material/shader name в canonical fluid material identity.

## P0-4 Cross-Domain World Transaction Model

G6.1–G6.4 являются procedural/representation baseline и не владеют authoritative mutation commit.

Будущие операции, меняющие воду, лёд, Matter, Item или Construction, должны проходить через общий `WorldOperation / WorldTransactionPlan` либо соответствующий durable authority path.

Запрещён сценарий:

```text
fluid mutation
 -> best-effort Matter RPC
 -> best-effort Item/Construction RPC
```

## P0-5 NX7 / NX8 / NX9

G6 не создаёт собственный authority registry.

NX7 — policy над существующей authority foundation.

NX8 может запрашивать различные fluid representations по interest/budget, но:

```text
interest region / LOD / ribbon segment / mesh patch != FluidRegionId
```

NX9 может менять I/O scheduling/cache path, но не canonical fluid semantics и не durability ownership.

## G6.1 boundary

`CasualRiverProviderV1` реализован как deterministic compiler из stable G5 river/valley semantics в принятые G6.0 data contracts.

Зафиксировано:

- вход строится из stable G5 river/valley semantics;
- существующий G5 `River FeatureId` остаётся semantic owner и provider не создаёт второй `WorldFeature`;
- `FluidRegionId` не зависит от representation cell;
- `RiverSpline.spline_id` не зависит от текущего LOD или camera;
- channel profile deterministic и versioned;
- один source feature даёт одну semantic river identity независимо от query order;
- geometry revision может менять checksums без reroll canonical identities;
- provider не пишет canonical world state;
- provider не владеет persistence/authority/network transport;
- renderer/SceneTree не требуется для deterministic generation.

До Windows focused acceptance G6.1 остаётся `IMPLEMENTED CANDIDATE`, а не `ACCEPTED`.

## G6.2 boundary

Следующий checkpoint после G6.1 acceptance должен доказать, что одна canonical river geography адресуется через меняющиеся G2 representation cells/LOD без изменения `FeatureId`, `FluidRegionId`, `spline_id` и canonical provider result.

G6.2 может использовать `SurfaceCellKey` только как representation addressing для доказательства continuity. Cell не становится входом G6.1 provider identity.

## Stop conditions

G6 должен остановиться и потребовать global architecture review, если для следующего шага требуется:

- сделать `SurfaceCellKey` permanent river identity;
- создать private fluid authority registry;
- создать private global material ontology;
- сделать visual river mesh источником canonical truth;
- хранить durable mutation только в procedural cache;
- связывать river identity с camera/LOD/query order;
- реализовать cross-domain mutation через best-effort RPC chain.

## Merge / composition gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 или более новая синхронная revision
[PASS] global roadmap blob byte-equivalent main
[PASS] global architecture ledger blob byte-equivalent main
[PASS] network roadmap / NX7-NX9 boundaries byte-equivalent main
[PASS] G5 parent branch behind = 0 at synchronization point
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] renderer is derived presentation
[PENDING] G6.1 Windows focused acceptance
[PASS] G6.0 post-P0 focused regression remains in G6.1 runner
```

Канонический общий план: `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
