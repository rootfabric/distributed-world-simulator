# Checkpoint v17.3.0 — MW3 local meshing

## Решение

```text
checkpoint: v17.3.0-simulation-mw3-local-meshing
build_id: mw3-local-meshing
base: v17.2.0-simulation-mw2-sparse-bricks
base_delivery: fix1
branch: feature/mw3-local-meshing
status: CANDIDATE FOR INDEPENDENT REVIEW
```

MW3 добавляет первую Godot presentation-проекцию Dynamic Matter Fabric: детерминированный локальный mesh, static concave collision и camera-local laboratory над принятыми MW1/MW2 contracts.

## Реализовано

```text
scripts/world/matter/meshing/matter_brick_mesh_data.gd
scripts/world/matter/meshing/matter_tetrahedral_mesher.gd
scripts/world/matter/meshing/matter_mesh_resource_factory.gd
scripts/world/matter/meshing/matter_mesh_seam_validator.gd
scripts/world/matter/lab/matter_local_mesh_streamer.gd
scripts/world/matter/lab/matter_asteroid_meshing_lab.gd
scripts/world/matter/lab/matter_lab_fly_camera.gd
scenes/labs/matter_asteroid_meshing_lab.tscn
```

Mesher использует Freudenthal decomposition `6 tetrahedra/cell`, SDF iso-level `0`, central gradients из ghost samples, Godot-clockwise triangle winding и cell-center-relative vertex coordinates.

## Архитектурные гарантии

- `MatterBrickSnapshot` остаётся единственным входом mesher;
- mesh и collision не входят в canonical state;
- общая грань соседей сравнивается по vertices, normals и segments;
- empty brick не создаёт Godot mesh/collision resources;
- streamer ограничивает builds за кадр, отклоняет stale generation requests и отдельно считает failed builds;
- Moon runtime и `config/worlds/catalog.json` не изменены;
- лаборатория запускается только прямым открытием `.tscn`.

## Проверка поставки до независимой runtime-приёмки

```text
JSON parse: PASS
UTF-8: PASS
preload targets: PASS
GDScript delimiter scan: PASS
presentation/domain direction: PASS
synthetic Freudenthal seam model: PASS
real MW1 +X surface topology model: PASS
empty interior/vacuum model: PASS
shell/bash syntax: PASS
git diff --check equivalent whitespace audit: PASS
Godot 4.7.1 double runtime: NOT RUN IN DELIVERY ENVIRONMENT
```

## Независимая приёмка

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_MW3_LOCAL_MESHING_TESTS.ps1 -GodotPath $godot
.\RUN_MW2_SPARSE_BRICKS_TESTS.ps1 -GodotPath $godot
.\RUN_MW1_FIXED_SEED_ASTEROID_TESTS.ps1 -GodotPath $godot
.\RUN_MW0_MATTER_CONTRACTS_TESTS.ps1
.\RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1 -GodotPath $godot
.\RUN_M6_DEDICATED_RECOVERY_TESTS.ps1 -GodotPath $godot

git diff --check
```

Дополнительно открыть:

```text
res://scenes/labs/matter_asteroid_meshing_lab.tscn
```

и подтвердить:

- surface bricks появляются постепенно;
- при перемещении camera desired region меняется;
- между соседними bricks нет видимых щелей;
- collision соответствует поверхности;
- Moon/main scene не изменены.

## Gate

Checkpoint принимается только после `MW3 focused PASS` с ожидаемой топологией `7518 assertions`, всех MW0–MW2/A3/M6 regression PASS и отсутствия parser/preload errors.

Все review-fix остаются в `feature/mw3-local-meshing`.
