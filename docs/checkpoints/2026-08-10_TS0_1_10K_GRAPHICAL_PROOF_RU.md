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

Добавлен `scripts/labs/t1/ts0/ts0_large_structural_proxy_adapter.gd`.

Adapter берёт только принятый TS0 fixture builder, создаёт обычные RuntimeProjection/Compile/Interest contracts, работает в `READ_ONLY`, сохраняет `section_size_m = 8.0` как derived presentation policy и не вводит новый authority/storage слой.

```text
NEAR → LOCAL_EXTERIOR
MID  → SECTION_HLOD
FAR  → DISTANT_SHELL
```

Thresholds: local 80 m, section 250 m, shell 1000 m. Near/Mid ограничены 12 section artifacts; Far — один shell artifact.

### Graphical lab

Добавлены сцена, presentation script и launch runners. Управление:

```text
1 — CUBE_10K
2 — PYRAMID_10K
3 — NEAR
4 — MID
5 — FAR
W/A/S/D + Q/E — free flight
Shift — fast flight
RMB — mouse look
R — reset camera
H — HUD
```

Для масштаба есть presentation-only 1.8 m human reference, 10 m mast и 240 m ground plane; они не входят в Construction canonical state.

HUD показывает canonical identity, C22 mode/sections, bounded runtime nodes, vertices/triangles/surfaces, compile/presentation time и C22/C24 cache telemetry. `presentation_materialize_ms` не выдаётся за чистый GPU upload time: C24 пока не разделяет CPU materialization и driver upload instrumentation.

## Acceptance contracts

`tests/construction/ts0/ts0_graphical_proxy_acceptance.gd` прогоняет `CUBE_10K` и `PYRAMID_10K` через настоящий `ConstructionProxyStreamingController` и требует:

- internal-face culling;
- multiple compiled sections при section count << part count;
- greedy shell geometry;
- NEAR/MID/FAR → LOCAL_EXTERIOR/SECTION_HLOD/DISTANT_SHELL;
- не более 12 near/mid proxy meshes;
- ровно один far shell mesh и ноль far collision proxies;
- каждый proxy mesh — C24 `ArrayMesh`;
- runtime node count далеко ниже semantic part count;
- canonical checksum invariant across HLOD modes;
- отсутствие роста C22 artifact cache от простого mode switching;
- C24 mesh-cache hit при повторном Far;
- соблюдение C24 entry/byte budgets.

`RUN_TS0_GRAPHICAL_TESTS.ps1` дополнительно повторяет существующие C22/C24 graphical regression tests.

## Что TS0.1 намеренно не делает

100k остаётся TS0.2; true local incremental rebuild — TS0.3; 1M — TS0.4. Этап не создаёт WorldAddress/Geodesy/Authority ownership, network replication owner, новый renderer backend или Item Graph semantics.

## Validation

Локальный Linux parse/smoke harness на `Godot 4.7.1.stable.double.custom_build.a13da4feb`:

```text
editor import / script parse                 PASS
scene construction                           PASS
CUBE_10K synthetic adapter control flow      PASS
NEAR → LOCAL_EXTERIOR                        PASS
MID  → SECTION_HLOD                          PASS
```

Harness проверяет новый TS0 slice, но использует stubbed C22/C24 pipeline. Полный production pipeline должен быть подтверждён в реальном Windows worktree.

## Критерий SOURCE_ACCEPTED

```text
RUN_TS0_GRAPHICAL_TESTS.ps1              PASS
manual graphical observation             PASS
CUBE_10K near/mid/far                    visually observable
PYRAMID_10K near/mid/far                 visually observable
RUN_WORLD_REGRESSION_TESTS.ps1           PASS
```

До этого статус — `IMPLEMENTED_CANDIDATE`.

## Запуск Windows worktree

```powershell
cd C:\Godot\lunar-world-double-godot-ts0
git pull --ff-only
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$env:GODOT_BIN = $Godot
.\RUN_TS0_GRAPHICAL_TESTS.ps1 -GodotPath $Godot
.\RUN_TS0_GRAPHICAL_LAB.ps1 -GodotPath $Godot -Profile CUBE_10K -Mode NEAR
```
