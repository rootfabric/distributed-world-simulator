# G8.5 — Cross-Cell / Cross-LOD Geomorphology Invariance — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

## Решение

G8.5 принят после exact-Windows focused + full acceptance на Godot `4.7.1.stable.double.custom_build.a13da4feb`.

Tested head:

```text
6cc0c2b5ff1bc21a5b488a8492ef8cce28fa4736
```

## Доказано

- G8.4 parent ACCEPTED — PASS.
- G7.3 semantic cross-cell / cross-LOD parent proof — PASS.
- Один body-fixed point получает разные presentation `SurfaceCellKey` на LOD 2/4/8/12, но canonical semantic query/bundle и final geomorphology deformation остаются идентичными.
- Все пять `component_deltas_m` независимы от presentation LOD.
- Внешний `SurfaceCellKey` и cube-face label не могут изменить canonical deformation.
- Порядок requested semantic fields не меняет query/bundle/deformation checksum.
- Canonical G6 river проходит через несколько representation cells и PX/PZ seam; full accepted G8.4 deformation корректно вычисляется на обеих сторонах seam.
- `SurfaceCellKey`, cube face, LOD, camera и representation не входят в canonical geomorphology identity.

## Regression evidence

```text
G8.5 FULL ACCEPTANCE: PASS
G8.4 parent ACCEPTED: PASS
G7.3 semantic cross-cell/cross-LOD parent proof: PASS
G8.5 geomorphology cross-cell/cross-LOD invariance: PASS
SurfaceCellKey / cube face / LOD excluded from canonical deformation identity: PASS
World/core regression: PASS
main_scene_cli_all: 6 PASS / 0 FAIL
lifecycle: STOPPED
working tree: CLEAN
```

Первый Windows attempt на `00de94e2...` остановился до исполнения G8.5 proof из-за type-inference parse error в acceptance harness. FIX1 `fa841b3b...` изменил только локальную типизацию трёх результатов `direction_to_cell()` и не менял runtime, semantic inputs или смысл proof.

## Следующий этап

`G8.6 — Geomorphology Visual Lab`.

Visual Lab обязан оставаться derived presentation: он может менять camera, mesh density, color map и diagnostic overlays, но не canonical semantic/deformation truth и не identity.
