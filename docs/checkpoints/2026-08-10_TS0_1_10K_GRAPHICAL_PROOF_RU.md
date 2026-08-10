# TS0.1 — 10k Graphical Proof through C22/C24

**Дата:** 2026-08-10  
**Ветка:** `feature/ts0-large-structural-visual-lab`  
**База:** `TS0.0 SOURCE_ACCEPTED @ 3861fc7b511491439acf5a2d51a57372a951dc4d`  
**Global revision:** `GLOBAL-P0-2026-08-10-R2`  
**Статус:** `IMPLEMENTED CANDIDATE — WINDOWS GRAPHICAL/FOCUSED + FULL REGRESSION PENDING`

## Цель

TS0.1 впервые материализует принятые TS0 canonical fixtures как реальную графическую Construction presentation, не создавая отдельный TS0 renderer.

```text
TS0 ConstructSnapshot
        ↓
ConstructionRuntimeProjectionRequest
        ↓
ConstructionProxyCompileRequest
        ↓
C22 topology + exposed-surface culling + greedy artifacts
        ↓
C22 streaming planner
        ↓
C24 ArrayMesh materialization/cache
        ↓
ConstructionProxyRuntimeNode
        ↓
TS0 graphical lab
```

Production C22/C24 код этим этапом не изменяется.

## Реализовано

### TS0 → C22 adapter

Добавлен:

```text
scripts/labs/t1/ts0/ts0_large_structural_proxy_adapter.gd
```

Adapter:

- берёт только принятый `TS0LargeStructuralFixtureBuilder`;
- создаёт обычный `ConstructionRuntimeProjectionRequest`;
- создаёт обычный `ConstructionProxyCompileRequest` в `READ_ONLY` режиме;
- сохраняет `section_size_m = 8.0` как derived presentation policy;
- не вводит network owner, persistence или новый canonical DTO;
- создаёт стандартные C22 interest requests для `NEAR`, `MID`, `FAR`.

Mapping:

```text
NEAR → LOCAL_EXTERIOR
MID  → SECTION_HLOD
FAR  → DISTANT_SHELL
```

Distance policy:

```text
local threshold   80 m
section threshold 250 m
shell threshold   1000 m
```

Near/Mid ограничены максимум 12 section artifacts; Far обязан содержать ровно один shell artifact.

Для сплошных structural fixtures interest focus намеренно ставится на внешнюю поверхность `+Z`, а не в геометрический центр. При `section_size_m = 8 m` центральная секция большого сплошного куба может быть полностью внутренней и не иметь exposed faces; exterior focus гарантирует, что Near/Mid демонстрируют реальную видимую оболочку, не меняя C22 planner. Стартовый visual mode — `FAR`, поэтому при первом запуске сразу показывается вся compiled конструкция.

### Graphical lab

Добавлены:

```text
scenes/labs/construction/ts0_large_structural_visual_lab.tscn
scripts/labs/t1/ts0/ts0_large_structural_visual_lab.gd
RUN_TS0_GRAPHICAL_LAB.ps1
RUN_TS0_GRAPHICAL_LAB.sh
```

Лаборатория умеет без перезапуска менять:

```text
1 — CUBE_10K
2 — PYRAMID_10K
3 — NEAR
4 — MID
5 — FAR
```

Камера:

```text
W/A/S/D — horizontal free flight
Q/E     — down/up
Shift   — fast flight
RMB     — mouse look
R       — reset camera around current construct
H       — HUD on/off
```

Для масштаба в сцене есть отдельные presentation-only reference objects:

- 1.8 m human reference;
- 10 m mast;
- 240 m reference ground plane.

Они не входят в Construction canonical state.

### HUD

HUD показывает:

- profile;
- canonical part count / revision / checksum;
- actual C22 detail mode;
- observer distance;
- total / visible section count;
- proxy mesh / collision / interactive node count;
- total bounded runtime node count;
- vertices / triangles / material surfaces (draw-call proxy);
- C22 compile time;
- C24 presentation/materialization time;
- C22 artifact-cache entries/bytes;
- C24 mesh-cache entries/GPU bytes/hits/misses/evictions.

`presentation_materialize_ms` не выдаётся за чистый GPU upload time: существующий C24 backend пока не разделяет CPU descriptor/materialization и driver upload instrumentation.

## Acceptance contracts

Добавлен:

```text
tests/construction/ts0/ts0_graphical_proxy_acceptance.gd
RUN_TS0_GRAPHICAL_TESTS.ps1
RUN_TS0_GRAPHICAL_TESTS.sh
```

Focused test обязан провести оба профиля:

```text
CUBE_10K       10 648 canonical parts
PYRAMID_10K    10 416 canonical parts
```

через настоящий `ConstructionProxyStreamingController` и проверить:

1. C22 реально выполняет internal-face culling;
2. section count меньше semantic part count;
3. shell содержит greedy geometry;
4. NEAR даёт `LOCAL_EXTERIOR`;
5. MID даёт `SECTION_HLOD`;
6. FAR даёт `DISTANT_SHELL`;
7. Near/Mid имеют не более 12 proxy meshes;
8. Far имеет ровно один proxy mesh и ноль collision proxies;
9. каждый proxy mesh — `ArrayMesh`, а не `BoxMesh` substitute;
10. runtime nodes остаются далеко ниже semantic part count;
11. canonical checksum не меняется при HLOD transitions;
12. C22 artifact cache не растёт при простом переключении detail mode;
13. повторный Far presentation даёт C24 mesh-cache hit;
14. C24 entry/byte budgets соблюдаются.

Runner также повторяет существующие C22 и C24 graphical regression tests.

## Что TS0.1 намеренно не делает

- не материализует 100k profile — это TS0.2;
- не исправляет pseudo-incremental C22 rebuild — это TS0.3;
- не создаёт block/section debug nodes в количестве semantic parts;
- не вводит WorldAddress/Geodesy/Authority ownership;
- не добавляет сетевой replication owner;
- не изменяет Item Graph semantics;
- не делает 1M runtime probe.

## Критерий SOURCE_ACCEPTED

TS0.1 можно перевести в `SOURCE_ACCEPTED` только после:

```text
RUN_TS0_GRAPHICAL_TESTS.ps1              PASS
manual graphical observation             PASS
CUBE_10K near/mid/far                    visually observable
PYRAMID_10K near/mid/far                 visually observable
RUN_WORLD_REGRESSION_TESTS.ps1           PASS
```

До этого текущий статус — `IMPLEMENTED_CANDIDATE`.

## Запуск Windows worktree

```powershell
cd C:\Godot\lunar-world-double-godot-ts0
git pull --ff-only

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$env:GODOT_BIN = $Godot

.\RUN_TS0_GRAPHICAL_TESTS.ps1 -GodotPath $Godot
.\RUN_TS0_GRAPHICAL_LAB.ps1 -GodotPath $Godot -Profile CUBE_10K -Mode FAR
```

В открытой сцене профили и detail mode можно переключать клавишами `1..5`.
