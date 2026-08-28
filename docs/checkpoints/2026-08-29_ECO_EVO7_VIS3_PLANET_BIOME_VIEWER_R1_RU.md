# ECO EVO7 / ECO-VIS3 — Planet Patch / Biome Viewer R1

## Статус маршрута

Принятый predecessor: ECO-VIS2 R2.1 `dd6304eb28434666a401f888b583d7b17c1474c5`.

```text
LS3.0–LS3.FINAL                 CLOSED
ECO-VIS1 Spatial World Viewer  CLOSED
ECO-VIS2 Procedural Plants     CLOSED / ACCEPTED dd6304e
        ↓
ECO-VIS3 Planet/Biome Viewer   IMPLEMENTATION CANDIDATE
        ↓
LS4
```

## Цель VIS3

Перевести наблюдение ecology из режима «32×32 диагностическая матрица» в режим наблюдаемого физического участка планеты, не создавая нового ecology authority.

VIS3 сохраняет accepted VIS2 procedural plants и добавляет поверх публичного LS3.6 Workbench:

- 2.5D topographic hillshade из accepted LS3.0 Planet Patch elevation/slope/aspect;
- topographic contour lines;
- реальные post-hoc LS3.5 biome boundaries;
- multi-scale `REGION / PATCH / PLANT` camera/LOD;
- bounded presentation-only history наблюдённых поколений;
- history scrub без rewind/mutation Workbench;
- performance HUD для обнаружения фактического bottleneck.

## Data flow

```text
LS3.0 physical patch
      +
LS3.5 classification
      +
LS3.6 public Workbench snapshots/history
      +
accepted VIS2 phenotype descriptors
             ↓
VIS3 presentation cache / terrain renderer
             ↓
terrain + biome boundaries + LOD + timeline + telemetry
             ↓
pixels only
```

## Multi-scale LOD

### REGION

- широкая камера (`0.55x` preset);
- индивидуальная plant geometry скрывается;
- population показывается агрегированно по coarse blocks;
- biome regions используют dominant label coarse block;
- уменьшает render cost при просмотре всей patch.

### PATCH

- стандартный обзор (`1.15x` preset);
- terrain contours + biome boundaries;
- procedural plants видимы;
- основной режим наблюдения распространения популяции.

### PLANT

- morphology zoom (`3.0x` preset) с центрированием выбранной клетки;
- individual VIS2 plants видимы;
- root debug допускается только на этом масштабе.

`AUTO` выбирает LOD по фактическому zoom. LOD/camera не входят в ecology identity.

## History contract

VIS3 хранит максимум 64 наблюдённых render frames. Frame содержит только компактные read-only summaries:

- generation;
- ecology/workbench/classification hashes;
- population count / occupied cells;
- 1024 per-cell population counts;
- 1024 biome labels;
- accepted spatial observatory summary.

Полные genomes/records/phenotype descriptors в timeline не копируются.

History scrub:

```text
live Workbench generation N   — НЕ МЕНЯЕТСЯ
            +
selected VIS3 frame K
            ↓
historical terrain/biome/population presentation
```

Во время historical scrub current individual plants скрыты, чтобы не смешивать live plant geometry с historical summary.

## Performance telemetry

VIS3 измеряет отдельно:

- generation advance вокруг Workbench (`last_step_ms`);
- VIS3 refresh (`last_refresh_ms`);
- history capture (`last_history_capture_ms`);
- FPS;
- population;
- visible plant count;
- effective LOD;
- history frame count.

Это observability, а не performance acceptance threshold. Известный VIS2 CPU/performance debt остаётся non-blocking до отдельного PERF checkpoint; VIS3 должен сначала показать фактический источник затрат.

## Дополнительный repair

VIS3 исправляет только display-side inherited VIS1 lineage lookup:

```text
legacy:    hereditary_bundle.lineage_record
canonical: hereditary_bundle.lineage
```

Это не меняет lineage model; только корректно показывает уже существующий canonical lineage ID.

## Authority boundary

- terrain renderer не импортирует Workbench/ecology implementation;
- VIS3 viewer не обращается напрямую к LS3.3/LS3.4/LS3.5 implementations;
- используются только public `get_patch()`, `get_classification()`, `get_spatial_history()`, ecology/render facade VIS2;
- no genome write;
- no population/fitness authority;
- no mutation/reproduction/dispersal authority;
- no persistence/network authority;
- history cache не является simulation truth и не умеет rewind ecology.

## Acceptance R1

Focused exact-double acceptance проверяет:

1. точную VIS3 runtime identity;
2. terrain/hillshade/contour/biome-boundary contracts;
3. физические 32×32 / 16m / 512m patch dimensions;
4. non-flat real elevation span;
5. REGION/PATCH/PLANT LOD и camera presets;
6. REGION скрывает individual plant geometry;
7. LOD/camera не меняют ecology/workbench hashes;
8. generation advance создаёт source-bound history frames;
9. per-cell counts суммируются в exact population;
10. emergent biome labels входят в observed history;
11. history scrub не rewinds live Workbench;
12. historical mode не смешивает current plant geometry;
13. return-to-live восстанавливает procedural plants;
14. canonical lineage field отображается корректно;
15. performance telemetry связана с текущей ecology;
16. source guards сохраняют presentation-only boundary.

Локальный exact-double R1: `PASS (107 assertions)` на `4.7.1.stable.double.custom_build.a13da4feb`.

Graphical smoke: VIS3 scene стартует под X11, печатает `ECO.EVO7 VIS3 READY ...`, scene/GDScript/resource ошибок нет. В virtual X11 ожидаемы только VSync/llvmpipe/audio infrastructure warnings.

## Windows

```powershell
.\RUN_ECO_EVO7_VIS3_TESTS.ps1 `
  -GodotBin 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'

.\OPEN_ECO_EVO7_VIS3_PLANET_BIOME_VIEWER.ps1 `
  -GodotBin 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
```

Правильный runtime marker:

```text
ECO.EVO7 VIS3 READY scene=EcoEvo7VIS3PlanetBiomeViewer revision=ECO.EVO7-VIS3.R1
```
