# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`
**Local role:** hydrology/fluid semantic layer above G5 World Feature Graph
**Current stage:** `G6.2 cross-cell / cross-LOD continuity — IMPLEMENTED CANDIDATE`
**Next after acceptance:** `G6.3 runtime WaterSurfaceQuery resolver`

## Canonical boundary

```text
G5 WorldFeature / FeatureId
        ↓
G6 deterministic fluid provider
        ↓
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
        ↓
representation/query adapters
```

Обязательные инварианты:

```text
FluidRegion != SurfaceCell
FluidRegion != AuthorityRegion
FluidRegion != InterestRegion
FluidRegion != renderer object
Fluid identity != LOD / quality / observer state
G5 River FeatureId remains semantic owner
```

## P0-2 Spatial Domain Fabric

До появления общего `WorldAddress` G6 использует G5 body/reference-frame/feature semantics. Одна река может пересекать много generation/representation cells; cell/LOD являются производным addressing, а не identity.

Будущая интеграция должна маппировать canonical fluid bounds/anchors в Spatial Domain Fabric, а не вводить `RiverChunkId`.

G6.2 теперь формально проверяет эту границу на seam-river, проходящей через `PX/PZ` и LOD `2 / 4 / 8 / 12`.

## P0-3 Unified Material Ontology

G6 `FluidType` остаётся baseline semantic vocabulary, а не полной material ontology. Future fluid semantics должны проецироваться на общий `MaterialDefinitionId`. Rendering material/shader name не является canonical fluid identity.

## P0-4 Cross-Domain World Transaction Model

G6.1–G6.4 не владеют authoritative mutation commit. Будущие изменения воды/льда/Matter/Item/Construction проходят через общий `WorldOperation / WorldTransactionPlan` или соответствующий durable authority path.

Запрещено:

```text
fluid mutation
 -> best-effort Matter RPC
 -> best-effort Item/Construction RPC
```

## P0-5 NX7 / NX8 / NX9

G6 не создаёт authority registry. NX8 может выбирать fluid representation по interest/budget, но `interest region / LOD / ribbon / mesh patch != FluidRegionId`. NX9 может менять I/O scheduling/cache, но не canonical fluid semantics.

## G6.1 accepted boundary

`CasualRiverProviderV1` принят как deterministic compiler из stable G5 river/valley semantics в принятые G6.0 data contracts.

Зафиксировано:

- G5 `River FeatureId` остаётся semantic owner; provider не создаёт второй `WorldFeature`;
- `FluidRegionId` и `RiverSpline.spline_id` не зависят от cell/LOD/camera/query order;
- channel profile deterministic и versioned;
- geometry revision может менять checksums без reroll canonical identities;
- linked valley влияет на derived geometry, но не владеет river identity;
- provider не пишет canonical world state;
- provider не владеет persistence/authority/network transport;
- renderer/SceneTree/runtime random не требуются.

Windows focused acceptance на tested head `b8f36d17dc8ba138e6b215968aa0e651eec9ccd1`:

```text
G5 World Feature Graph: PASS (249 assertions)
G5 feature/cell identity: PASS (94 assertions)
G6.0 fluid contracts: PASS (169 assertions)
G6.1 CasualRiverProviderV1: PASS (74 assertions)
git diff --check: PASS
working tree: clean
```

Canonical acceptance record: `docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md`.

## G6.2 implemented boundary

G6.2 добавляет только deterministic fixture + acceptance proof. Принятый G6.1 provider и G6.0 contracts не изменяются.

Proof matrix:

```text
source longitude: 34°
mouth longitude:  58°
cube faces:        PX / PZ
LOD:               2 / 4 / 8 / 12
```

Для одной canonical river geography проверяется:

```text
representation cell set changes
FeatureId stays stable
FluidRegionId stays stable
RiverSpline.spline_id stays stable
RiverChannelProfile.profile_id stays stable
provider manifest stays stable
canonical spline/surface checksums stay stable
```

`SurfaceCellKey` и `CubeSphereAddressing` используются только как representation addressing. G6.2 не создаёт `RiverChunkId`, runtime query resolver, renderer, authority или persistence.

Focused Windows gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_2_CROSS_CELL_CONTINUITY_TESTS.ps1
```

До этого прогона:

```text
G6.2 = IMPLEMENTED CANDIDATE
```

## Stop conditions

Требуется global architecture review, если G6 понадобится:

- permanent river identity из `SurfaceCellKey`;
- private fluid authority registry;
- private global material ontology;
- visual mesh как canonical truth;
- durable mutation только в procedural cache;
- identity, зависящая от camera/LOD/query order;
- cross-domain mutation через best-effort RPC chain.

## Merge / composition gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1
[PASS] canonical global/network files byte-equivalent main
[PASS] G5 parent synchronized
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] renderer remains derived presentation
[PASS] G6.0 post-P0 dependency regression
[PASS] G6.1 Windows focused acceptance — 74 assertions
[PENDING WINDOWS] G6.2 cross-cell / cross-LOD continuity
```

Канонический общий план: `docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md`.
