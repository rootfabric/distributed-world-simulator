# G6.4 — Casual Visual River Lab — FIX3 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Fix3 candidate head:** `77e99819c319e8ad924485414c56f3dc14748844`

Fix2 automated gate прошёл (`104 assertions`, headless scene PASS), а ручной прогон подтвердил, что `SurfaceLodSelector` действительно дробит сетку при приближении. Но он также выявил второй design gap: сама поверхность оставалась fixed `SphereMesh`, а увеличение river sample count только пересэмплировало ту же гладкую spline. Новая видимая геометрическая информация не появлялась. Поэтому Fix2 не принят.

Fix3 добавляет реальную representation-detail композицию:

```text
observer
  -> G2 SurfaceLodSelector
  -> adaptive SurfaceCellKey leaf cover
  -> G3 CasualMacroTerrainProviderV1 samples
  -> adaptive macro terrain triangles

accepted G6 river
  -> adaptive river sampling
  -> derived water ribbon
```

Новый presenter:

```text
res://scripts/labs/procedural/g6_4_adaptive_macro_surface_presenter.gd
```

Fixed `SphereMesh` оставлен в scene только как disposable fallback resource и скрыт. Видимая поверхность теперь строится из G2 leaves. Каждый новый terrain vertex получает `geo/surface-height-m` через accepted G3 provider в body-fixed direction space.

Чтобы 900 m macro relief был различим на 8-unit debug globe, используется display-only height exaggeration `x40`. Он не меняет canonical G3 sample и не влияет на G6 identities.

Automated Windows gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Кроме прежнего G6.4 marker, обязательный новый marker:

```text
G6.4 Adaptive Macro Surface: PASS (... far_triangles=... near_triangles=...)
```

Gate требует:

```text
near.max_lod > far.max_lod
near.macro_surface_triangles > far.macro_surface_triangles
near.selection_hash != far.selection_hash
```

Manual acceptance теперь должна подтвердить не только уменьшение LOD-grid, но и появление дополнительной macro-surface геометрии/рельефа при `W` refine.

При этом Fix3 сознательно **не** вырезает долину под реку и не деформирует terrain по hydrology. Это следующий причинный слой `G8 Geomorphology`, а не задача G6 visual proof.

До нового automated + graphical run:

```text
G6.4 = FIX3 IMPLEMENTED CANDIDATE
```

После green evidence: `G6 FULL ACCEPTANCE` с fresh main/G5/GLOBAL-P0/shared-baseline sync check.
