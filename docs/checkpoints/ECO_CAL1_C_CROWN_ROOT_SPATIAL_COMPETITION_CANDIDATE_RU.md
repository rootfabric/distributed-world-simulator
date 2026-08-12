# ECO.CAL1-C — Crown + Root Spatial Competition — CANDIDATE

Статус: `IMPLEMENTED_CANDIDATE / RESEARCH_ONLY / EXACT WINDOWS GATE REQUIRED`.

Parent: `ECO.CAL1-B ACCEPTED_EXACT_WINDOWS_CANONICAL`.

Parent hash: `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`.

## Goal

Introduce explicit spatial neighbour competition above and below ground without changing accepted PH3/P1 coefficients.

## Crown mechanism

`plant_spatial_crown_root_competition_v1.gd::evaluate_crown_pair` computes exact 2D circle intersection from realized crown spread and positions.

For each focal plant:

- overlap fraction = overlap area / own crown area;
- neighbour shading pressure = own overlap fraction × neighbour realized branch probability;
- accepted PH3 saturating crown-light potential is reused read-only;
- crown overlap loss = accepted crown-light potential × neighbour shading pressure.

No-overlap is neutral. Moving crowns closer must increase overlap/loss. A denser-branching neighbour must shade the same focal crown more strongly at equal geometry. Wide/narrow A/B swap must be symmetric.

## Root mechanism

`evaluate_root_pair` uses a controlled research geometry proxy:

`root_zone_radius_m = genome.root_depth_m`.

This is not a canonical botanical invariant; it is a CAL1-C spatial proxy until/if a separate root-spread trait is introduced.

Within the geometric shared root zone:

`uptake_capacity = root_depth × growth_rate`.

The two plants divide the shared claim by normalized capacity. The competitor can remove only its claim from the focal plant's overlapping resource fraction. The resulting effective local soil moisture/nutrients are then evaluated through the existing accepted `plant_resource_model_v1.gd`.

Thus CAL1-C does not create a second water/nutrient fitness equation.

## Controlled cases

Crown:

- NO_OVERLAP;
- EQUAL_CLOSE;
- EQUAL_FAR;
- HIGH_BRANCH_NEIGHBOUR;
- LOW_BRANCH_NEIGHBOUR;
- WIDE_NARROW;
- WIDE_NARROW_SWAP.

Root:

- NO_OVERLAP;
- EQUAL_DENSE;
- DEEP_SHALLOW_DENSE;
- DEEP_SHALLOW_SPARSE;
- DRY_DEEP_SHALLOW_DENSE;
- DEEP_SHALLOW_SWAP.

## Acceptance

Required:

- exact parent CAL1-B hash preservation;
- deterministic same-process and fresh-process aggregate hash;
- crown no-overlap neutrality;
- closer crown geometry produces greater overlap and loss than farther geometry;
- high-branch neighbour produces greater focal crown loss than low-branch neighbour at equal geometry;
- crown A/B swap symmetry;
- root no-overlap neutrality;
- equal root pair gets 0.5/0.5 shared claims and symmetric competition;
- shared claims conserve one;
- deep root gets a larger shared claim than shallow root under the controlled pair;
- dense overlap produces stronger shallow-root resource impact than sparse overlap;
- root A/B swap symmetry;
- dry context remains finite/causal;
- no accepted PH3/P1 source changes;
- no coefficient calibration.

## Test surface

- `scripts/research/ecology/plant_spatial_crown_root_competition_v1.gd`;
- `scripts/research/ecology/plant_crown_root_competition_experiment_v1.gd`;
- `tests/research/ecology/eco_cal1_c_crown_root_spatial_competition_acceptance.gd`;
- `tests/research/ecology/eco_cal1_c_restart_replay_probe.gd`;
- `RUN_ECO_CAL1_C_TESTS.ps1`.

Until exact Windows PASS:

`CAL1-C != ACCEPTED` and `CAL1-D = BLOCKED`.
