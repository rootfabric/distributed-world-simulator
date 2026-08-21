# ECO.EVO1 / P2.7 — Lineage Divergence / Speciation Candidate Diagnostics — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `8da9c039a8591d61a0d542aa4e4695a51a9d20d6`.
Candidate/control head: `238bc1053827114dd55649649d1339a97adc9d1b`.
Parent P2.6 aggregate: `3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c`.

## Exact Windows canonical evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Runner: `RUN_ECO_EVO1_P2_7_TESTS.ps1`.

```text
ECO.EVO1-P2.7 Lineage Divergence / Speciation Candidate Diagnostics: PASS (62 assertions)
aggregate_hash=7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe
p2_6=3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
```

Diagnostics:

```text
candidate=true
connected=false
similar=false
recent=false
split_age=25
isolation=1.000000000000
connection=0.000000000000
genome=0.473241998529
recruitment=0.575000000000
ecology=0.130666666667
connected_connection=1.000000000000
similar_genome=0.025410357504
similar_ecology=0.000000000000
recent_split_age=3
```

Fresh-process replay A and B reproduced exactly:

`7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe`.

## Accepted meaning

P2.7 proves a fail-closed **diagnostic** contract rather than a taxonomy engine. A positive research candidate requires convergent evidence from shared ancestry, sufficient split age, prolonged spatial isolation, low connection, genome divergence and ecological-history divergence.

The falsification controls are canonical evidence:

- same divergence while connected -> no candidate;
- long isolation with similar genome/ecology -> no candidate;
- recent split despite strong divergence/isolation -> no candidate.

Recruitment-trait distance remains an independently exposed diagnostic and is not used as a hidden weighted score.

`canonical_species_declared=false` remains mandatory. P2.7 assigns no `species_id`, creates no biome/species table and does not claim canonical taxonomy ownership.

## Next

`ECO.EVO1/P2.8 Deterministic Save/Restart Plant World Proof` is authorized.

P2.8 must prove that the same plant-world truth can be serialized, validated, restored in a fresh process and continued with absolute simulation time without changing future deterministic keys or ecological outcomes. It must compare uninterrupted execution with one or more save/restart cuts and preserve adult cohorts, seed banks, patch state/history, migration/disturbance accounting and lineage-divergence diagnostics.
