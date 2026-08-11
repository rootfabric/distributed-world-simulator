# G8.6 — Geomorphology Visual Lab — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Project Control:** `PC0-2026-08-10-R1`  
**Branch:** `feature/g8-geomorphology`

## Решение

G8.6 принят после автоматического exact-Windows acceptance и отдельного user-observed graphical PASS.

Автоматически проверенный checkout:

```text
a9ca1f8b723e4edc5ebff40db26e41283d464597
```

Графически наблюдавшийся checkout:

```text
b91ed3eb8664ec1aee28453947a84c6a56acb95b
```

Engine:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## Automated evidence

```text
G8.6 AUTOMATED ACCEPTANCE: PASS
G8.5 parent ACCEPTED: PASS
G8.6 headless local corridor lab: PASS
Derived presentation LOD / truth separation: PASS
PX/PZ seam diagnostic corridor: PASS
World/core regression through NX4: PASS
main_scene_cli_all: 6 PASS / 0 FAIL
lifecycle: STOPPED
working tree: CLEAN
```

## Manual graphical evidence

Explicit human decision:

```text
G8.6 MANUAL PASS
```

Observed invariants:

```text
G       source G3 <-> resolved G8 geometry: PASS
        canonical Truth hash remains stable

1..7    resolved / total / valley / channel / bank /
        floodplain / erosion-deposition: PASS

W/S     presentation LOD0  33x17 stride 1: PASS
        presentation LOD1  17x9  stride 2: PASS
        presentation LOD2   9x5   stride 4: PASS
        presentation LOD3   5x3   stride 8: PASS

        Canonical samples=561: STABLE
        Truth hash=36c87791f25bbd0b: STABLE

X       PX/PZ seam: PASS, no visible crack/discontinuity
        faces=PX,PZ, seam-edges=34

F       canonical river overlay agrees with visible
        channel/bank/floodplain structure: PASS
```

## Architecture result

G8.6 подтверждает presentation boundary:

- camera distance не является geomorphology truth;
- presentation mesh density / LOD не является geomorphology truth;
- cube-sphere face и `SurfaceCellKey` не являются geomorphology identity;
- diagnostic colors/overlays не являются canonical world state;
- один canonical source set из 561 samples сохраняет один truth hash на всех четырёх presentation LOD;
- PX/PZ representation seam не требует отдельной seam-owned canonical geometry;
- visual lab не создаёт Matter mutation, authority, persistence или network ownership.

## FIX history

- First Windows attempt: harness-only JSON numeric array type-sensitivity failure; FIX1 corrected acceptance harness only.
- Second Windows attempt: presentation corridor was forced to body reference radius while accepted G6 river spline carried radial elevation; FIX2 preserved upstream G6 centerline radius in the visual wrapper.
- Accepted G8.1–G8.5 runtime/formulas were not changed by FIX2.

## Следующий gate

G8.6 acceptance **не является G8 aggregate acceptance**.

Следующий обязательный шаг:

```text
G8 FULL ACCEPTANCE
```

Он должен на одном clean exact-Windows checkout подтвердить принятую цепочку G8.0–G8.6, Project Control non-RED, focused G8.6 regression, полный world/core regression и финальную repository hygiene.

До этого G health остаётся YELLOW. PR #60 остаётся Draft и не merge-ится автоматически.
