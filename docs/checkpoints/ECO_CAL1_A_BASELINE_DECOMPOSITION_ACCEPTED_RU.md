# ECO.CAL1-A — Baseline Decomposition / Mechanism Audit — ACCEPTED

Статус: `ACCEPTED / EXACT WINDOWS CANONICAL / RESEARCH_ONLY`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head:

`20e083d32d8dc9ff1f4a5f3f600a49a53f7a076e`.

Canonical evidence was produced on the exact Windows checkout with:

`Godot Engine v4.7.1.stable.double.custom_build.a13da4feb`.

## Decision

`ECO.CAL1-A ACCEPTED`.

CAL1-A did not change morphology economics. It measured the accepted PH3/PH3C model under a controlled common-Genome/common-IndividualSeed 4x8 matrix and established the deterministic causal baseline required before adding new mechanisms.

## Parent regression evidence

PH3:

- `PASS (217 assertions)`;
- `profile_hash=1051df16a4718a3bc33be99b8394da400bc8bd7d1b8e1f86a8d190229b59a67a`;
- `reference_hash=58161227616f083ab29426931ce91e24f6354f5b3d96d9020af6f8b60b72a43e`;
- `giant_hash=eaa6b1d6b452adb7ee8549baecc06c99cbb26cbce86cb34f364e36c0c152d704`.

PH3 restart:

- `PASS (5 assertions)`;
- accepted reference/shade/dry hashes unchanged.

PH3C:

- `PASS (97 assertions)`;
- `aggregate_hash=294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- `height_low_share=0.88312054209733`;
- `giant_dense_share=0.00014414428813`.

PH3C restart:

- `PASS (6 assertions)`;
- same aggregate hash.

Therefore CAL1-A did not invalidate the accepted parent evidence.

## CAL1-A canonical evidence

`ECO.CAL1-A Baseline Decomposition / Mechanism Audit: PASS (1094 assertions)`.

Canonical baseline:

`280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`.

Legacy PH3C pairwise hash recorded by CAL1-A:

`294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`.

Fresh-process replay A and B both reproduced the same baseline hash exactly.

Classification:

`HEIGHT_LOW_BROAD_FULL_POOL_WINNER`.

`HEIGHT_LOW` wins all four controlled environments and is top-2 in all four.

## Exact environment findings

```text
REFERENCE
winner=HEIGHT_LOW
runner=BRANCH_LOW
winner_margin=0.028264166
winner_driver=structural_cost
winner_driver_delta=0.071206790
HEIGHT_LOW rank=1
HEIGHT_HIGH rank=7
HEIGHT_LOW-HEIGHT_HIGH score delta=0.577805307
height_pair_driver=structural_cost

SHADE
winner=HEIGHT_LOW
runner=BRANCH_LOW
winner_margin=0.004685816
winner_driver=structural_cost
winner_driver_delta=0.079952795
HEIGHT_LOW rank=1
HEIGHT_HIGH rank=7
HEIGHT_LOW-HEIGHT_HIGH score delta=0.545990845
height_pair_driver=structural_cost

SUN
winner=HEIGHT_LOW
runner=CROWN_WIDE
winner_margin=0.043289224
winner_driver=structural_cost
winner_driver_delta=0.071206790
HEIGHT_LOW rank=1
HEIGHT_HIGH rank=7
HEIGHT_LOW-HEIGHT_HIGH score delta=0.614010029
height_pair_driver=structural_cost

DRY
winner=HEIGHT_LOW
runner=BRANCH_LOW
winner_margin=0.022911560
winner_driver=structural_cost
winner_driver_delta=0.057786857
HEIGHT_LOW rank=1
HEIGHT_HIGH rank=7
HEIGHT_LOW-HEIGHT_HIGH score delta=0.455052978
height_pair_driver=structural_cost
```

## Interpretation

The finding is stronger than the earlier qualitative suspicion.

Current height economics has a broad asymmetry:

```text
HEIGHT_HIGH
  pays large super-linear structural cost
        ↓
  receives only absolute-environment height benefit
        ↓
  has no neighbour-relative canopy-position payoff
```

The result is not a single-environment anomaly. `HEIGHT_HIGH` is seventh in REFERENCE, SHADE, SUN and DRY; `structural_cost` is the strongest HEIGHT_LOW-vs-HEIGHT_HIGH driver in every environment.

This does **not** prove that the structural cost coefficient is wrong. It proves that the existing model lacks the primary ecological context in which expensive height can pay: competition for light against shorter neighbours.

Therefore coefficient tuning remains forbidden.

## Next checkpoint

`ECO.CAL1-B — Relative Vertical Light Competition`.

CAL1-B must be implemented as a separate research mechanism over accepted PH3/PH3C semantics.

Required causal properties:

1. no neighbours -> near-zero competition effect;
2. equal-height competitors -> symmetric result / no fake height advantage;
3. tall vs short with strong canopy overlap -> tall receives additional relative light access and short is correspondingly suppressed;
4. sparse/no-overlap competition -> effect collapses strongly;
5. dry conditions do not make tall universally win: existing water/structure costs remain active;
6. swapping A/B must swap outputs exactly;
7. deterministic/restart hash;
8. no accepted PH3 coefficient changes.

CAL1-B is not required to make `HEIGHT_HIGH` the global winner. It only has to prove the missing causal path:

> height can become valuable because neighbouring competitors exist.

After CAL1-B acceptance, proceed to crown/root competition rather than coefficient calibration.
