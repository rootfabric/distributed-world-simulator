# ECO.EVO1 / P2.6 — Long-Horizon Biogeography — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `9aa4678e9be99556fb54057f6580f219325c0126`.
Candidate/control head: `3d754e7f27dace3d469dce78e1999676c8f3b7c2`.
Parent P2.5 aggregate: `292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696`.

## Exact Windows canonical evidence

Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

Runner:

`RUN_ECO_EVO1_P2_6_TESTS.ps1`

Result:

```text
ECO.EVO1-P2.6 Long-Horizon Biogeography: PASS (223 assertions)
aggregate_hash=3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
p2_5=292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696
```

Diagnostics:

```text
colonized=1
extinct=18
recolonized=19
control_extinction=-1
long_patch_years=90
short_patch_years=61
far_long=29
far_short=0
long_max_range=3
short_max_range=2
event_absence=1
control_absence=0
control_far_years=30
final_reoccupied=true
regional_persist=true
```

Fresh-process replay A and B reproduced exactly:

`3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c`.

## Accepted meaning

The research metapopulation layer now demonstrates a causal full cycle:

`colonization -> local adult extinction -> regional persistence -> recolonization`.

The no-disturbance control with the same transport chronology has no matching FAR extinction. Broad dispersal produces more regional and FAR patch-years than short dispersal. P2.4 migration conservation, P2.5 disturbance conservation, bounded cohort truth and deterministic replay all remain intact.

No biome/species placement table participates. Patch geometry, year index and transport history remain research inputs rather than claims over canonical Spatial/Time/Environment foundations.

## Next

`ECO.EVO1/P2.7 Lineage Divergence / Speciation Candidate Diagnostics` is now executable.

P2.7 may diagnose ancestry/genomic/ecological/geographic divergence and loss of connectivity, but must not declare a canonical species identity or introduce a biome->species lookup.
