# PC0 Project Convergence — MAIN_INTEGRATED

**Date:** 2026-08-11  
**Control plane:** `PC0-2026-08-10-R1`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Decision:** `ACCEPTED / MAIN_INTEGRATED`

## Canonical merge

Project-wide control convergence PR #63 was merged into `main` as:

```text
d931f8f9a336df8c507d0183fe0d32d792e49a03
```

The merged change-set contains no gameplay/domain runtime implementation. It makes `main` the canonical operational control center and adds directional watched-dependency auditing.

## Canonical control capabilities

```text
main-owned project registry
branch passports
standard dependency/validation auditor
directional producer -> consumer watched-path auditor
combined CONTROL_PROJECT.ps1 health handling
CI syntax/JSON/control validation
current convergence execution plan
```

Directional rule:

```text
producer changed path
    ∩ consumer watched_paths
        -> consumer YELLOW

producer changed path
    ∩ consumer critical_watched_paths
        -> consumer RED
```

`SOURCE_ACCEPTED_HANDOFF_COMPLETE` branches remain consumer evidence but are not treated as active producers.

## Operational consequence

The previous PC0-hardening blocker is closed.

The following work is now authorized in parallel, subject to each branch's own gates:

```text
G8.6 manual graphical acceptance
CH9.6 two-pass graphical/recovery acceptance
C22 current-main convergence refresh
fresh current-main NX.C1 creation and minimal owner-authority transfer
R3 current-main candidate refresh and revision-transition control work
```

Still blocked:

```text
G9 until canonical R3 + MAT0
TS0.4 until C22 MAIN_INTEGRATED
T2.0 until C22 + TS0.4 + PC0 convergence
R3 promotion until refreshed candidate + transition rule + PC0 non-RED
Wave A until canonical R3
```

## Canonical entry points

```text
PROJECT_CONTROL.md
config/control/project-program-registry.v1.json
docs/control/CURRENT_PROJECT_FRONTIERS_RU.md
docs/plans/PROJECT_CONVERGENCE_2026-08-11_RU.md
```

The next project-control snapshot is registry generation 62.
