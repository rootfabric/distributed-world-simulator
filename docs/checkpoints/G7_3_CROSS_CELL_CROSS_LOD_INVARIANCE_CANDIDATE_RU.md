# G7.3 Cross-Cell / Cross-LOD Invariance — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-10-R2`
**Branch:** `feature/g7-semantic-field-fabric`
**G7.2 accepted baseline:** `68c4f90dbdac0e2d9968b4461207713f5661521b`

## P0 frontier rule

`GLOBAL-P0-2026-08-10-R2` изменил program ledger так, что active frontier должен byte-exact совпадать с `main`, а исторические accepted/frozen branches не переписываются только ради нового global revision.

Для G7.3:

```text
active G7 global config/docs == main R2
historical accepted G6 may remain R1
G6 ancestry still required
G6 global byte equality is not required
```

Verified active GLOBAL blobs:

```text
config/architecture/global-program-roadmap.v1.json
  dd18f720cd4ce6493618efe270311605aea9bbbf

docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md
  3eb52a69cef73da8a784dfce7acc6a0c38185cf9
```

## Цель

G7.3 не добавляет новый procedural runtime. Он доказывает, что уже принятые G7.0–G7.2 contracts/adapters/composer независимы от representation partitioning.

Главный инвариант:

```text
canonical world point + canonical SemanticFieldQuery
    -> same semantic values/checksums/provenance
       regardless of SurfaceCellKey / LOD representation path
```

## Proof matrix

Проверяются LOD:

```text
2
4
8
12
```

Одна и та же world position адресуется в разные `SurfaceCellKey` на разных LOD. После каждого representation-addressing шага повторяется та же canonical semantic composition.

Должны оставаться неизменными:

```text
SemanticFieldQuery checksum
SemanticFieldBundle checksum
SemanticFieldCompositionReceipt checksum
per-field SemanticFieldSample checksum
per-field SemanticFieldProvenance checksum
G5 FeatureId
G6 FluidRegionId
```

При этом representation resolution/cell identity обязаны реально меняться.

## SurfaceCell boundary

`SemanticFieldQuery` не содержит:

```text
surface_cell
surface_cell_key
lod
representation
```

Тест дополнительно создаёт другой валидный external `SurfaceCellKey` рядом с фактической LOD8 cell и доказывает, что такая representation label не может изменить canonical bundle, потому что не входит в semantic API.

Это не означает, что world point физически принадлежит двум cells. Это proof ownership boundary: representation address не является semantic input.

## Cube seam

Используется принятый G6 cross-cell river fixture, проходящий через PX/PZ seam.

Для river spline control points на LOD8 проверяется:

```text
one river -> multiple SurfaceCellKey values
faces include PX and PZ
source FeatureId remains one
FluidRegionId remains one
river-distance-m on centerline stays approximately zero on both seam sides
```

Таким образом cube face не становится semantic branch condition.

## Query-order invariance

Один и тот же набор field ids подаётся в прямом и обратном порядке.

`SemanticFieldQuery.create()` должен нормализовать порядок, поэтому совпадают:

```text
requested_field_ids
query checksum
bundle checksum
composition receipt checksum
```

## Representation density

LOD увеличивает side resolution `2^lod`, но canonical semantic result для shared world point не меняется.

```text
LOD -> representation density/addressing only
LOD != semantic identity
```

## P0 boundaries

G7.3 не вводит production runtime helper для cell-aware semantics.

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
composer != representation scheduler
G7.3 != scheduler/cache
G7.3 != authority/interest
G7.3 != persistence/network
```

Stage состоит из proof tests/runners/manifest/docs; accepted G7.0–G7.2 semantic runtime не изменяется.

## Scope

От accepted G7.2 baseline допускаются только:

```text
G7.3 test/runners/manifest/validation/docs
active GLOBAL-P0 R2 config + roadmap sync from main
local G7-G13 R2 alignment docs/config
```

Любой G3/G5/G6 adapter, composer, Hydrology, Matter или Network runtime change должен остановить gate.

## Focused acceptance

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_TESTS.ps1 `
  -GodotPath $Godot
```

Focused runner повторно прогоняет G7.0, G7.1, G7.2 и затем G7.3 invariance test.

## Full acceptance

```powershell
.\RUN_G7_3_FULL_ACCEPTANCE.ps1 `
  -GodotPath $Godot
```

Full runner проверяет:

```text
current G6 ancestry
G7.2 ACCEPTED ancestry
active GLOBAL-P0 config/docs == main R2
historical G6 is not required to equal R2
strict G7.3 proof + P0-sync changed-file scope
git diff --check
G7.0/G7.1/G7.2 regressions
G7.3 focused invariance
full world/core regression
Windows transient cleanup
final clean worktree
```

## Следующий checkpoint после acceptance

```text
G7.4 — Semantic Field Lab
```
