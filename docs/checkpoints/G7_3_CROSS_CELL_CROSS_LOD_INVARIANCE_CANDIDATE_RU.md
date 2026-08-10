# G7.3 Cross-Cell / Cross-LOD Invariance — FIX1 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-10-R2`
**Branch:** `feature/g7-semantic-field-fabric`
**G7.2 accepted baseline:** `68c4f90dbdac0e2d9968b4461207713f5661521b`

## Текущий результат

Focused Windows gate уже прошёл:

```text
G7.3 Cross-Cell / Cross-LOD Invariance: PASS (122 assertions)
G7.3 Cross-Cell / Cross-LOD Invariance focused gate passed.
```

Подтверждены FeatureId/FluidRegionId invariance, multi-cell river, PX/PZ seam и centerline river-distance continuity.

Первый full-gate run дошёл до P0/scope hygiene и остановился только на:

```text
docs/plans/GLOBAL_PROGRAM_ARCHITECTURE_ROADMAP_RU.md:3: trailing whitespace
```

Это не локальная G7.3 мутация: active G7 roadmap заранее проверяется byte-identical к `origin/main`, а R2 canonical Markdown использует trailing double-space как Markdown hard break.

## Fix1

`RUN_G7_3_FULL_ACCEPTANCE.ps1` теперь делает порядок строго таким:

```text
1. local GLOBAL config blob == origin/main blob
2. local GLOBAL roadmap blob == origin/main blob
3. GLOBAL revision == GLOBAL-P0-2026-08-10-R2
4. G7 is declared active world-generation frontier
5. run strict git diff --check over G7.3 delta
   EXCEPT the already-byte-verified canonical GLOBAL roadmap file
6. final hygiene repeats the same strict check
```

То есть inherited canonical Markdown bytes не маскируются произвольно: исключается ровно один файл и только после доказательства его byte-equivalence с main. Все остальные G7.3/P0-sync files остаются под `git diff --check`.

Fix1 commit:

```text
73ca4a0d356eb7ed18aa813c19f617b7b2c29137
```

Validation evidence commit:

```text
5710751f8d6ff9aaca5d718c50983e18c9d6ca71
```

## P0 frontier rule

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

## G7.3 semantic proof

LOD matrix:

```text
2
4
8
12
```

For the same canonical world position, the following must remain identical while representation SurfaceCellKey/resolution changes:

```text
SemanticFieldQuery checksum
SemanticFieldBundle checksum
SemanticFieldCompositionReceipt checksum
per-field SemanticFieldSample checksum
per-field SemanticFieldProvenance checksum
G5 FeatureId
G6 FluidRegionId
```

`SemanticFieldQuery` contains no:

```text
surface_cell
surface_cell_key
lod
representation
```

The accepted G6 seam fixture proves one river spans multiple cells and both PX/PZ cube faces without identity reroll.

## Scope

G7.3 remains proof-only. No accepted G7 semantic runtime, G3/G5/G6 adapter, composer, Hydrology, Matter or Network runtime file is changed.

## Re-run

Only the full gate needs to be repeated after Fix1:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_3_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Expected final marker:

```text
G7.3 FULL ACCEPTANCE: PASS
Global revision: GLOBAL-P0-2026-08-10-R2
Active GLOBAL-P0 main alignment: PASS
Canonical GLOBAL roadmap byte-match to main: PASS
G7.2 ACCEPTED ancestor: PASS
G7.3 invariance scope: PASS
Cross-cell / cross-LOD semantic invariance: PASS
World/core regression: PASS
Working tree: CLEAN
```

## Next

After full acceptance:

```text
G7.4 — Semantic Field Lab
```
