# ECO.PH4 — Seed Development Lifecycle — ACCEPTED

Статус: `ACCEPTED / EXACT WINDOWS PASS`.

PH4 проводит наследуемую программу растения через жизненный цикл:

`seed payload -> germination/dormancy -> juvenile -> adult -> reproductive -> offspring seed payloads`.

## Exact Windows evidence

Engine:

`Godot Engine v4.7.1.stable.double.custom_build.a13da4feb (2026-07-13 21:00:28 UTC)`

Parent regressions:

- P1C-S4 aggregate: `PASS (15)`;
- PH0: `PASS (63)`;
- PH1: `PASS (128)`;
- PH2: `PASS (107)`;
- PH3: `PASS (217)`;
- PH3C focused: `PASS (97)`;
- PH3C fresh-process replay: `PASS (6)`.

PH4:

- focused acceptance: `PASS (718 assertions)`;
- fresh-process replay: `PASS (5 assertions)`;
- failures: `0`.

Canonical exact hashes:

- lifecycle profile: `d8c8b9ff56ec630b832c4b6bdbb49d39147586f4d97e6535dcc6fbd37c29a795`;
- founder payload: `1b5ff858fc57fdf98d75eb796cc6d7e6aa68b0b0e51e8321611e13b024cdc396`;
- lifecycle run: `88d8b3f53a5233d675eb75f1fe94c017b4f435ca91c34ce145d9b93f3c72d6d1`;
- offspring batch: `48d1ba23151ad5cf02f4d0de2ebbf9559da99612c852c6ec97029254159ee5ce`.

Reference timeline:

`SEED -> GERMINATED -> JUVENILE -> ADULT -> REPRODUCTIVE`.

Default P1 genome produced `80` unique deterministic offspring seed payloads in the bounded research fixture.

## Accepted truth boundary

Seed payload carries heredity and identity metadata only:

- `PlantGenome`;
- inherited `DevelopmentTraits`;
- PH0 seed envelope;
- lineage id / generation / parent IndividualSeed;
- deterministic payload hash.

Seed payload does **not** carry:

- `GrowthGraph`;
- realized phenotype;
- mesh;
- renderer profile;
- LOD.

At germination PH2 derives a new realized phenotype from inherited program + local `EnvironmentSample`; PH3 supplies morphology/resource consequences. The same offspring payload therefore may realize different phenotype hashes in SHADE and SUN while preserving genome, inherited development and payload identity.

Dormancy is also accepted: chronological age may advance while development age remains zero; the unchanged dormant seed may later germinate after environmental recovery.

## Explicit fail-closed boundary

PH4 does not enable unconstrained morphology mutation. The PH3C full-pool diagnostic still shows broad `HEIGHT_LOW` advantage. Calibration remains required before morphology mutation/evolution or species-emergence claims.

Production ecology remains population-canonical; this research fixture does not establish planet-wide individual GrowthGraph truth.

## Decision

`ECO.PH4 ACCEPTED`.

Следующий этап: `ECO.PH5 — Extensible Procedural Visual Materialization`, strictly presentation-derived from accepted GrowthGraph/phenotype truth.
