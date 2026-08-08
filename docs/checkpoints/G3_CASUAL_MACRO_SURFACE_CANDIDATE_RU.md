# G3 — Mega Casual Macro Surface — candidate

**Дата:** 2026-08-08  
**Ветка:** `feature/g3-casual-macro-surface`  
**Base:** `feature/g2-planetary-cells-lod @ 6319e1e312c7c663d5d05c0806f5a42cf68ad441`  
**Статус:** `IMPLEMENTED CANDIDATE`

## Dependency state

Пользователь сообщил успешный полный G2 checkout gate. В текущем program ledger G2 поэтому считается `ACCEPTED` для начала G3. Production terrain/world runtime по-прежнему не заменяется.

## Цель G3

Первая настоящая процедурная форма поверхности без рек, геологии, эрозии и локальной детализации:

```text
body-fixed unit direction
        ↓
deterministic low-frequency 3D field
        ↓
geo/surface-height-m
        ↓
radial displacement for representation
```

Главный инвариант:

```text
macro form != cell content
macro form != LOD artifact
macro form = canonical Geo field sampled at body-fixed position
```

## Provider

`CasualMacroTerrainProviderV1`

```text
provider_id        geo-provider/casual-macro-terrain-v1
contract_version   1.0.0
generator_version  1.0.0
requires           []
provides           [geo/surface-height-m]
deterministic      true
```

Default lab parameters:

```text
seed                2026080801
nominal_radius_m    6000000
amplitude_m         900
base_wavelength_m   600000
octaves             4
persistence         0.5
base_height_m       0
```

Все параметры входят в provider descriptor/provenance.

## Почему noise не привязан к cube-face

Provider не получает `SurfaceCellKey`, face UV, chunk id или LOD. Он нормализует `body_fixed_position_m` и семплирует непрерывное 3D value-noise поле в едином body-fixed direction domain.

Это даёт:

```text
одна координата → одна высота
тот же shared edge point → та же высота
coarse/fine shared vertex → та же высота
LOD0/LOD14 → та же world truth
```

Cube-sphere cells используются только representation layer из G2.

## Noise v1

Использован intentionally simple deterministic 3D value noise:

```text
integer lattice hash
quintic fade
trilinear interpolation
4-octave fBm
```

Никакого `RandomNumberGenerator`, `randf/randi` или per-cell seed нет.

G3 не утверждает физическую правдоподобность рельефа. Его задача — доказать глобальную непрерывную macro-form, которую позже можно заменить в G4.

## Exact-engine isolated validation

Engine:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
```

Result:

```text
cold editor import:           PASS
G3 macro surface acceptance:  PASS — 14,275 assertions
G3 fly-in macro continuity:   PASS — 99 assertions
G3 visual lab headless:       PASS
```

Macro acceptance проверяет:

```text
same seed exact deterministic
different seed changes macro form
height bounded by configured amplitude
radial query distance does not alter height
local continuity at 1 / 10 / 100 / 1000 m arc offsets
global visible relief span
cross-face seam continuity through LOD3
coarse/fine shared vertex stability
GeoKernel integration
resolution independence
LOD0/2/5/9/14 world-truth invariance
provider source has no cell/renderer/random coupling
```

Fly-in/out:

```text
50,000 km → surface → 50,000 km
```

At each step:

```text
G2 adaptive cover remains bounded
fixed ground point has exactly one leaf owner in representation cover
25-point regional macro profile hash stays identical
GeoKernel height stays finite and canonical
near approach reaches finer LOD
fly-out does not mutate macro geography
```

## Visual lab

```text
res://scenes/labs/procedural/g3_casual_macro_surface_lab.tscn
```

Controls:

```text
W/S altitude
A/D longitude
Q/E latitude
```

The lab renders adaptive G2 cube-sphere cells as a radially displaced terrain mesh. Surface color is height-based; grid color indicates LOD. Renderer code is confined to `scripts/labs/procedural`.

## Architecture boundary

Production provider:

```text
NO Node / SceneTree
NO Mesh / ImmediateMesh
NO Camera3D / RenderingServer
NO SurfaceCellKey
NO CubeSphereAddressing
NO face UV / cell UV
NO RandomNumberGenerator
```

Thus:

```text
Geo provider → canonical height field
G2 cells     → representation scope
G3 lab       → derived mesh only
```

## Full checkout acceptance

Run:

```powershell
.\RUN_G3_FULL_ACCEPTANCE.ps1
```

It requires:

```text
G2 dependency focused PASS
G3 focused PASS
full world/core regression PASS
git diff --check vs feature/g2-planetary-cells-lod PASS
```

Until that full checkout gate is confirmed, G3 remains `IMPLEMENTED CANDIDATE`.

## Next

After `G3 ACCEPTED`:

```text
G4 — Provider Composition / Replacement
```

G4 must split composition and prove that `CasualMacroTerrainProviderV1` can be replaced without changing GeoKernel call sites, G2 cells, streaming policy or renderer contract.
