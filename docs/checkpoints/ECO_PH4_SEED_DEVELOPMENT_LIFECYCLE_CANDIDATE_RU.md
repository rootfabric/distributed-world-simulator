# ECO.PH4 — Seed Development Lifecycle — CANDIDATE

Статус: `LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

PH4 проводит наследуемую программу через полный ранний жизненный цикл:

`seed payload -> germination/dormancy -> juvenile -> adult -> reproductive -> offspring seed payloads`.

## Truth boundary

Семя переносит только наследуемую информацию и identity metadata:

- полный `PlantGenome`;
- inherited `DevelopmentTraits`;
- принятый PH0 seed envelope;
- lineage id / generation / parent IndividualSeed;
- deterministic payload hash.

Семя **не переносит** `GrowthGraph`, realized phenotype, mesh, renderer profile или LOD. При прорастании PH2 заново реализует фенотип из локального `EnvironmentSample`, а PH3 даёт morphology/resource viability ledger.

PH4 намеренно не включает morphology mutation: full-pool PH3C diagnostic всё ещё показывает broad `HEIGHT_LOW` advantage. Mutation остаётся fail-closed до отдельной calibration задачи.

## Локальное evidence

- PH0 regression: `PASS (63)`;
- PH1 regression: `PASS (128)`;
- PH2 regression: `PASS (107)`;
- PH3 regression: `PASS (217)`;
- PH4 focused: `PASS (718 assertions)`;
- PH4 fresh-process restart: `PASS (5 assertions)`.

Exact hashes:

- lifecycle profile: `d8c8b9ff56ec630b832c4b6bdbb49d39147586f4d97e6535dcc6fbd37c29a795`;
- founder payload: `1b5ff858fc57fdf98d75eb796cc6d7e6aa68b0b0e51e8321611e13b024cdc396`;
- lifecycle run: `88d8b3f53a5233d675eb75f1fe94c017b4f435ca91c34ce145d9b93f3c72d6d1`;
- offspring batch: `48d1ba23151ad5cf02f4d0de2ebbf9559da99612c852c6ec97029254159ee5ce`.

Reference timeline:

`SEED -> GERMINATED -> JUVENILE -> ADULT -> REPRODUCTIVE`.

Default genome yields `80` unique offspring seed payloads in this bounded research fixture. This is acceptance evidence only and does not redefine production ecology from population truth to planet-wide individual truth.

## Dormancy and plasticity

Under controlled DRY conditions the same seed remains dormant for ten 0.1-year steps: chronological age advances while development age stays exactly zero. After moving the unchanged payload to REFERENCE conditions it germinates without inheriting prior failed phenotype growth.

The first offspring payload is also realized independently in SHADE and SUN. Genome checksum, inherited development checksum and payload identity stay the same, while PH2 phenotype hashes differ. Thus the offspring inherits a development program, not a finished plant model.

## Infrastructure guard

`RUN_ECO_PH4_TESTS.ps1` now checks the current branch and fails immediately with `WRONG_BRANCH` unless the worktree is on `feature/eco-evolutionary-ecology`. This closes the exact failure mode previously observed when the ECO folder had been switched to the FPE research branch.

Execution-critical published blobs exactly match the locally tested bytes.

Следующий gate: exact Windows `RUN_ECO_PH4_TESTS.ps1`.
