# G8 — Full Acceptance — ACCEPTED

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

## Решение

G8 полностью принят и переведён в `FREEZE_ACCEPTED_EVIDENCE`.

Aggregate exact-Windows tested checkout:

```text
31c0d4eef30544d4d5090b14721585047a97b979
```

Runtime-tested G8.6 checkout остаётся:

```text
a9ca1f8b723e4edc5ebff40db26e41283d464597
```

Manual graphical observation checkout:

```text
b91ed3eb8664ec1aee28453947a84c6a56acb95b
```

Engine:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## Принятая цепочка

```text
G8.0 Geomorphology Contracts                          ACCEPTED
G8.1 Valley Incision Baseline                         ACCEPTED
G8.2 River Channel Incision                           ACCEPTED
G8.3 Banks / Floodplain Shaping                       ACCEPTED
G8.4 Erosion / Deposition Baseline                    ACCEPTED
G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance  ACCEPTED
G8.6 Geomorphology Visual Lab                         ACCEPTED
G8 Full Acceptance                                    ACCEPTED
```

## G8.6 graphical evidence

User-observed graphical PASS был выполнен на `b91ed3eb...`:

```text
G       source G3 <-> resolved G8; Truth hash stable
1..7    all seven diagnostic views observed
W/S     presentation LOD: 33x17 / 17x9 / 9x5 / 5x3
        Canonical samples=561 stable
        Truth hash=36c87791f25bbd0b stable
X       PX/PZ seam without visible crack/discontinuity
F       canonical river overlay coherent with channel/bank/floodplain
```

## Aggregate acceptance evidence

Final runner output on `31c0d4ee...`:

```text
G8 FULL ACCEPTANCE: PASS
Architecture revision: GLOBAL-P0-2026-08-10-R2
Project Control revision: PC0-2026-08-10-R1
G8.0-G8.6 accepted chain: PASS
G8.6 manual graphical acceptance: PASS @ b91ed3eb8664ec1aee28453947a84c6a56acb95b
G8.6 fresh focused/headless regression: PASS
PC0 G health: NON_RED
World/core regression: PASS
Working tree: CLEAN
```

The world/core regression completed through NX4 client prediction and reconciliation. `main_scene_cli_all` reported `6 PASS / 0 FAIL`, and the final lifecycle state was `STOPPED` with exit code 0.

An earlier aggregate attempt on `796cc4df...` stopped before runtime execution because `git diff --check` found two Markdown trailing spaces in the newly added candidate checkpoint. That was a metadata-hygiene failure only; the whitespace was corrected in `31c0d4ee...` and no runtime, scene or test behavior changed.

## Architectural result

G8 now provides accepted evidence for deterministic geomorphology derived from canonical semantic inputs, including valley incision, river channel, banks/floodplain, erosion/deposition, cross-cell/cross-LOD invariance and a presentation-only visual lab.

Canonical geomorphology truth remains independent from `SurfaceCellKey`, cube face, presentation LOD, camera, mesh density and diagnostic overlays. G8 does not take ownership of Matter mutation, material ontology, authority, persistence or networking.

## Freeze rule

The existing G8 branch is now frozen accepted evidence. Do not continue runtime development on it.

The next generation stage is not opened automatically:

```text
G9 BLOCKED
  requires CANONICAL GLOBAL-P0 R3
  requires MAT0 CANONICAL MATERIAL IDENTITY
```

When those dependencies become canonical, G9 must start as a fresh current-canonical frontier rather than by extending the frozen G8 evidence branch.
