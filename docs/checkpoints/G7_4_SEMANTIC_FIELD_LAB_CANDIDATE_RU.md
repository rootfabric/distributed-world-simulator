# G7.4 Semantic Field Lab — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-10-R2`
**Branch:** `feature/g7-semantic-field-fabric`
**G7.3 tested head:** `910899a906e684d6793cd74ba898d68c457a37b4`

## Цель

G7.4 — первый официальный graphical/debug milestone Semantic Field Fabric.

Он не создаёт новые canonical semantics. Lab читает уже принятые G7 fields и переводит их в derived color/mesh presentation.

```text
canonical semantic samples
       ↓ read only
presentation patch / colors / HUD
```

## Визуализируемые поля

Только реально доступные через accepted provider/adapter chain:

```text
1  geo/surface-height-m
2  geo/valley-influence
3  geo/river-distance-m
4  geo/river-width-m
5  geo/fluid-surface-distance-m
```

### Поля, которые lab специально НЕ имитирует

```text
geo/slope
geo/curvature
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

Они остаются `VOCABULARY_ONLY_G7_0`. Их наличие в registry означает contract vocabulary, а не готовую truth-generating implementation.

Это защищает G8/G9/environment stages от скрытого захвата ownership presentation-кодом.

## Semantic patch

Deterministic patch:

```text
body: accepted G6 continuity fixture
latitude:   0..10 deg
longitude: 30..62 deg
segments: 16 x 32
semantic vertices: 561
visual proof faces: PX + PZ
```

Каждый vertex строится из настоящего query/composition pipeline:

```text
SemanticFieldQuery
  ├─ G3 surface adapter
  ├─ G5 valley-bounds adapter
  └─ G6 river/fluid adapter
          ↓
SemanticFieldComposerV1
          ↓
SemanticFieldBundle
SemanticFieldCompositionReceipt
```

Для G5 используется deterministic lab-only valley fixture на том же body/frame, чтобы визуально показать уже принятый `FEATURE_BOUNDS_FALLOFF_V1`. Этот fixture не является production terrain feature и не переносит geomorphology ownership в G7.4.

## Presentation

Geometry shape использует только accepted `geo/surface-height-m`.

Переключение `1..5` не перестраивает canonical query и не меняет geometry — меняется только vertex color mapping.

Дополнительная white line — accepted G6 canonical river centerline overlay.

HUD показывает:

```text
selected field id
unit
registry availability
min/max values
sample count
grid dimensions
observed cube faces
center bundle checksum prefix
center provenance checksum prefix
presentation-only manifest hash
vocabulary-only fields NOT faked
```

## Controls

```text
1..5  field mode
F     river centerline overlay
W/S   zoom
A/D   yaw
Q/E   pitch
Space auto orbit
R     reset
```

## P0 boundary

```text
field mode != canonical query mutation
color != semantic value
camera != world truth
mesh density != canonical identity
patch topology != SurfaceCell identity
presentation hash != world identity
river overlay != FluidRegion owner
lab valley fixture != production geomorphology
```

G7.4 не владеет:

```text
WorldQuery Fabric
Spatial Domain Fabric
Authority / Interest
Persistence
Network
Material Ontology
Scheduler / Cache
Geomorphology
renderer foundation
```

## Automated acceptance

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_4_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Automated gate включает:

```text
active GLOBAL config/roadmap == main
G7.3 ACCEPTED ancestor
strict G7.4 file allowlist
git diff --check
PowerShell AST parsing
G7.0..G7.4 focused regressions
headless scene smoke
561 sample proof
5 backed fields
6 vocabulary-only fields not faked
PX/PZ coverage
full world/core regression
safe Microsoft/ cleanup
final clean worktree
```

Ожидаемый конец:

```text
G7.4 AUTOMATED ACCEPTANCE: PASS
MANUAL GRAPHICAL OBSERVATION: REQUIRED before G7.4 ACCEPTED
```

## Manual graphical acceptance

```powershell
.\START_G7_4_SEMANTIC_FIELD_LAB.ps1 -GodotPath $Godot
```

Нужно подтвердить:

```text
[ ] semantic patch виден на сфере около river fixture
[ ] 1 surface-height показывает макро-рельеф цветом
[ ] 2 valley-influence показывает широкое bounds/falloff поле
[ ] 3 river-distance выделяет коридор около centerline
[ ] 4 river-width читается как отдельное G6 semantic field
[ ] 5 fluid-surface-distance меняет картину независимо от field 3
[ ] F действительно скрывает/показывает river centerline
[ ] переключение 1..5 не изменяет форму patch, только цвет
[ ] camera/orbit controls работают
[ ] HUD явно пишет vocabulary-only fields as NOT faked
[ ] нет визуальных seam-разрывов при переходе PX/PZ
```

Только после automated PASS + manual observation G7.4 можно перевести в `ACCEPTED`.

## Следующий checkpoint

```text
G7 Full Acceptance
```
