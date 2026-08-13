# ECO / OBS1 — Read-only Low-poly Ecology Observer — TARGETED PASS

Статус: `IMPLEMENTED / NON_GATING / TARGETED LINUX PASS / VISUAL OBSERVER ONLY`.

Ветка: `feature/eco-evolutionary-ecology`.

Parent implementation head: `a208d0c2670754b46f9e475d6cba11fedac6a119` (`P3.2 CANDIDATE / targeted Linux PASS`).

OBS1 не меняет статусы P3.1/P3.2 и не открывает P3.3. Это отдельная read-only observer lane, разрешённая roadmap после появления P3.2 implementation surface.

## Цель

Дать маленькую casual low-poly сцену, в которой можно глазами наблюдать уже вычисленные ecology snapshots:

- ground patch;
- low-poly plant proxies;
- `Play / Pause / Step`;
- текущий year/frame;
- biomass и next biomass;
- effective carrying capacity `K`;
- density ratio / feedback;
- resource support / pressure;
- limiting resource;
- active plant count;
- exact source/snapshot hashes.

OBS1 не является симулятором и не владеет canonical state.

## Архитектурная граница

```text
P3.1/P3.2 canonical simulation state
        |
        v
immutable deterministic result dictionaries
        |
        v
eco_obs1_snapshot_v1.gd
        |
        v
read-only display snapshot
        |
        v
eco_obs1_patch_observer_lab.gd
        |
        v
visual nodes / labels / Play-Pause-Step index
```

Observer не имеет API записи обратно в P3.1/P3.2 state.

`current_snapshot()` возвращает defensive deep copy. UI controls изменяют только `frame_index`, `playing` и local presentation accumulator.

## Новые surfaces

```text
scripts/research/ecology/eco_obs1_snapshot_v1.gd
scripts/research/ecology/eco_obs1_demo_timeline_v1.gd
scripts/labs/ecology/eco_obs1_patch_observer_lab.gd
scenes/labs/ecology/eco_obs1_patch_observer_lab.tscn
tests/research/ecology/eco_obs1_read_only_acceptance.gd
tests/research/ecology/eco_obs1_scene_smoke.gd
RUN_ECO_OBS1_TESTS.ps1
OPEN_ECO_OBS1_LAB.ps1
```

`eco_obs1_demo_timeline_v1.gd` — только deterministic lab fixture producer. Он строит фиксированный набор P3.2 results для визуального просмотра и не является production timeline или новым ecology checkpoint.

## Read-only invariants

Проверяются следующие свойства:

```text
source P3.2 validates before snapshot conversion
source result_hash unchanged after conversion
source dictionary deep-equal before/after conversion
snapshot contains scalars/copies only
snapshot source_result_hash pins exact P3.2 result
same source + step + year -> same snapshot_hash
snapshot adapter consumes no global RNG
malformed/tampered source -> fail closed
tampered observer snapshot -> validation FAIL
timeline build is deterministic across fresh processes
scene Step changes observer frame only
scene current_snapshot() returns defensive copy
```

Отдельный global-RNG probe использует seeded `randi()` sequence до/после snapshot conversion; sequence не сдвигается.

## Low-poly presentation

Plant proxy строится только из presentation data:

- position = canonical plant index grid;
- height/radius = bounded transform от displayed biomass;
- color = fixed canonical-index palette + bounded resource-growth tint;
- meshes = low-segment `CylinderMesh` + `SphereMesh`;
- visual layout не использует simulation RNG.

Это renderer-only representation. Его mesh/layout/material state не входит в P3.1/P3.2 hashes.

## Targeted Linux evidence

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Parser/preload:

```text
eco_obs1_read_only_acceptance.gd = PASS
eco_obs1_scene_smoke.gd = PASS
```

Fresh process A/B/C дали идентичные результаты:

```text
ECO.OBS1 Read-only Snapshot Boundary: PASS (49 assertions)
snapshot_hash=1a71d293354516adfb0c07752623d5b1cb80b5d1f7674feb06dfa76e2efb8e57
timeline_hash=0d5d35e7b04fa6921dc3d0f8f1827055f68aeb5e91e46c17db3e5b4572f21031
source_p3_2=9667aba9cd8d33668abcaf7b1123e1ceb846dc59f48a646de91c7cc7bec35dac
```

Actual scene instantiate/smoke:

```text
ECO.OBS1 Scene Smoke: PASS (9 assertions)
initial_source_hash=cea41ca41890e8456c640ff40be70f89460a74b1be7a02359bc1d58df8e7fd9d
```

Demo trajectory checkpoints:

```text
frame 0:  biomass=12.600000  K=7.965517  density=1.581818  pressure=0.517241  limiting=WATER
frame 5:  biomass=8.198764   K=7.965517  density=1.029282  pressure=0.517241  limiting=WATER
frame 10: biomass=7.977256   K=7.965517  density=1.001474  pressure=0.517241  limiting=WATER
frame 15: biomass=7.966108   K=7.965517  density=1.000074  pressure=0.517241  limiting=WATER
```

То есть observer показывает мягкое приближение P3.2 trajectory к resource-coupled `K`, но сам эту trajectory не изменяет.

## Gate semantics

OBS1 намеренно `NON_GATING`.

```text
OBS1 PASS != P3.1 ACCEPTED
OBS1 PASS != P3.2 ACCEPTED
OBS1 PASS != permission to open P3.3
```

Canonical P3 sequence остаётся:

```text
P3.1 exact Windows canonical -> ACCEPTED
P3.2 exact Windows canonical -> ACCEPTED
P3.3 Spatial Dispersal
```

Для локального OBS1 запуска:

```powershell
.\RUN_ECO_OBS1_TESTS.ps1 -GodotPath $Godot
.\OPEN_ECO_OBS1_LAB.ps1 -GodotPath $Godot
```
