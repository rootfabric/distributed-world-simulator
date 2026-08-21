# ECO / OBS1.2 — Read-only Spatial Ecology Observer — TARGETED PASS

Статус: `IMPLEMENTED / NON_GATING / TARGETED LINUX PASS / P3.3 READ-ONLY PRESENTATION`.

Ветка: `feature/eco-evolutionary-ecology`.

## Что добавлено

OBS1.2 расширяет работающий OBS1.1 с одного локального patch до read-only просмотра P3.3 spatial graph:

- несколько patch/cell площадок;
- plant proxies внутри каждого patch;
- directed flow lines между patch;
- толщина flow зависит только от уже вычисленного transfer biomass;
- `Play / Pause / Step` переключают deterministic snapshot fixture;
- UI показывает dispersal fraction, source/final biomass, internal transfer, boundary export и conservation error;
- patch labels показывают локальную final biomass.

## Архитектурная граница

```text
P3.3 deterministic result
        |
        v
validate P3.3 result
        |
        v
eco_obs1_spatial_snapshot_v1.gd
        |
        v
immutable defensive display snapshot
        |
        v
eco_obs1_spatial_observer_lab.gd
        |
        v
patch meshes / plant proxies / flow meshes / labels
```

Observer не владеет topology, edge shares, transfer decisions или canonical simulation state.

## Snapshot contract

Snapshot содержит только display-safe копии:

```text
source P3.3 result hash
accepted P3.2 parent aggregate
dispersal fraction
canonical patch order
per-patch source/incoming/final totals
per-plant source/incoming/final biomass
canonical directed edges + normalized shares + aggregate transfer biomass
per-patch boundary export
global source/transfer/export/final/conservation totals
```

Validator независимо сверяет арифметические связи snapshot:

```text
sum patch source == total source
sum plant source == patch source
sum plant incoming == patch incoming
sum plant final == patch final
sum patch incoming == total internal transfer
sum edge transfers == total internal transfer
outgoing shares per source == 1
sum boundary exports == total boundary export
sum patch final == total final
source == final + boundary export
```

## Presentation determinism

Patch positions вычисляются только из canonical patch index через deterministic grid.

Plant colors используют global canonical plant order. Plant position внутри patch использует local canonical plant index.

Flow geometry строится из canonical edge endpoints и already-computed transfer biomass.

Никакой visual/simulation randomness не используется.

## Demo timeline

Deterministic lab fixture использует три patch:

```text
A: alpha + beta, 10 kg source
B: beta, 2 kg source
C: initially empty
```

Topology:

```text
A -> B weight 3
A -> C weight 1
B -> C weight 1
```

A имеет explicit `boundary_export_fraction = 0.25`.

Viewer переключает фиксированные dispersal fractions:

```text
0.00
0.08
0.16
0.24
0.32
0.40
```

Это не simulation clock и не production scenario. Каждая frame — independently reproducible P3.3 result, затем defensive observer snapshot.

## Targeted exact-Godot evidence

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Fresh processes A/B/C дали byte-identical logs:

```text
ECO.OBS1.2 Spatial Read-only Boundary: PASS (47 assertions)
snapshot_hash=ced399dbe56336d00953f9f369c462178b457b846a1c219de396d6724d77cc87
timeline_hash=7a686275024912134b758c19c42040507b97a696a06ad178111dd06c884c00e8
source_p3_3=84c802032740c23e65714c2e3c2c7e5679c3b51e95b8f61b4a6ca64408925779
parent_p3_2=172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
```

Actual scene instantiate:

```text
ECO.OBS1.2 Spatial Scene Smoke: PASS (12 assertions)
initial_source_hash=c3e3a7005d8e2bb39bf09ac62d49e48d888c1523c40be48fb52ef7aec58654f6
```

Scene smoke дополнительно анализировался на engine output: после исправления UI formatter нет строк `ERROR:` при zero exit code.

## Fail-closed / read-only checks

Проверены:

- P3.3 source validation до conversion;
- source deep equality до/после snapshot conversion;
- source `result_hash` unchanged;
- global RNG sequence unchanged;
- malformed/tampered P3.3 source rejected;
- tampered edge transfer rejected;
- tampered patch totals rejected;
- invalid source hash/parent pin rejected;
- non-canonical patch order rejected;
- deterministic repeated snapshot hash;
- deterministic repeated timeline hash;
- `current_snapshot()` returns defensive copy;
- scene Step меняет только observer frame selection;
- Play/Pause меняют только presentation playback state.

## Surfaces

```text
scripts/research/ecology/eco_obs1_spatial_snapshot_v1.gd
scripts/research/ecology/eco_obs1_spatial_demo_timeline_v1.gd
scripts/labs/ecology/eco_obs1_spatial_observer_lab.gd
scenes/labs/ecology/eco_obs1_spatial_observer_lab.tscn
tests/research/ecology/eco_obs1_spatial_read_only_acceptance.gd
tests/research/ecology/eco_obs1_spatial_scene_smoke.gd
RUN_ECO_OBS1_SPATIAL_TESTS.ps1
OPEN_ECO_OBS1_SPATIAL_LAB.ps1
validation/ecology/eco-obs1-2-spatial-observer-validation.json
```

## Gate semantics

```text
OBS1.2 PASS != P3.3 ACCEPTED
OBS1.2 PASS != permission to open P3.4
```

Mainline remains:

```text
P3.3 exact Windows canonical
-> separate P3.3 acceptance lifecycle update
-> P3.4 Environmental Gradient
```
