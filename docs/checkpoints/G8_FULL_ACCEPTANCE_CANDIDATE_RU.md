# G8 — Full Acceptance — CANDIDATE

**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Project Control:** `PC0-2026-08-10-R1`  
**Branch:** `feature/g8-geomorphology`

## Accepted chain

```text
G8.0 Geomorphology Contracts                         ACCEPTED
G8.1 Valley Incision Baseline                        ACCEPTED
G8.2 River Channel Incision                          ACCEPTED
G8.3 Banks / Floodplain Shaping                      ACCEPTED
G8.4 Erosion / Deposition Baseline                   ACCEPTED
G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance ACCEPTED
G8.6 Geomorphology Visual Lab                        ACCEPTED
```

G8.6 evidence anchors:

```text
automated tested head  a9ca1f8b723e4edc5ebff40db26e41283d464597
manual observed head   b91ed3eb8664ec1aee28453947a84c6a56acb95b
accepted metadata      f2c5b99ee3940e2515ab758ab3077ff09bf081fd
truth hash             36c87791f25bbd0b
canonical samples      561
```

## Purpose

Aggregate G8 acceptance does not add geomorphology behavior. It proves that the complete accepted G8 chain is still coherent on one clean executable checkout after the graphical G8.6 gate.

Required predicates:

1. current branch is exactly `feature/g8-geomorphology` and working tree is clean;
2. G8.6 accepted metadata, automated tested head and manual observed head are all ancestors;
3. only aggregate-control files changed after G8.6 acceptance;
4. all `validation/g8-0...g8-6` records are `ACCEPTED`;
5. G8.6 manifest and manual evidence are `ACCEPTED/PASS` with the exact observed truth hash/sample count;
6. no executable G8.6 or geomorphology runtime drift occurred after automated acceptance;
7. Project Control reports G `NON_RED`;
8. fresh G8.6 focused/headless gate passes;
9. complete world/core regression passes;
10. final repository hygiene remains clean.

## Exact Windows run

From the existing G worktree:

```powershell
cd C:\Godot\lunar-world-g6-fluid

git fetch origin --prune
git pull --ff-only

git branch --show-current
git status --short
git rev-parse HEAD

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G8_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

The terminal result required for acceptance is:

```text
G8 FULL ACCEPTANCE: PASS
G8.0-G8.6 accepted chain: PASS
G8.6 manual graphical acceptance: PASS
G8.6 fresh focused/headless regression: PASS
PC0 G health: NON_RED
World/core regression: PASS
Working tree: CLEAN
```

## Stop rule

Do not infer PASS from partial output. Do not merge PR #60 automatically.

Only a complete exact-Windows PASS permits:

```text
G8 FULL ACCEPTED
G8 branch -> FREEZE_ACCEPTED_EVIDENCE
```

After that G9 still does **not** open automatically. G9 requires canonical `GLOBAL-P0 R3` plus `MAT0` material identity.
