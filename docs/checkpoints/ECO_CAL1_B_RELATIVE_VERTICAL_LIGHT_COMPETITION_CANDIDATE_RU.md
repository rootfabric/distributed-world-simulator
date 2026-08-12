# ECO.CAL1-B — Relative Vertical Light Competition — CANDIDATE

Статус: `IMPLEMENTED / RESEARCH_ONLY / EXACT WINDOWS CANONICAL GATE PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head:

`561daee4cd9fa48bcef5c78e6f2b0d050451f3b9`.

Parent:

`ECO.CAL1-A ACCEPTED` with canonical baseline

`280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`.

## Why this mechanism exists

CAL1-A established that:

- `HEIGHT_LOW` wins REFERENCE, SHADE, SUN and DRY;
- `HEIGHT_HIGH` ranks seventh in all four;
- `structural_cost` is the strongest HEIGHT_LOW-vs-HEIGHT_HIGH score driver in every environment;
- current PH3 has no neighbour-relative height/light payoff.

CAL1-B does **not** lower structural cost and does not add an unconditional `tall_bonus`.

It tests the missing causal path:

> expensive height can become useful when a canopy overlaps shorter competitors and gains a larger fraction of contested light.

## Mechanism

Source:

`scripts/research/ecology/plant_relative_vertical_light_competition_v1.gd`.

For a pair of realized phenotypes:

```text
competition_intensity
  = canopy_overlap * local_density

relative_height_bias
  = (height_a - height_b) / (height_a + height_b)

contested_light_pool
  = accepted_PH3_height_light_access_gain
    * sunlight
    * competition_intensity

a_light_delta
  = contested_light_pool * relative_height_bias

b_light_delta
  = -a_light_delta
```

Therefore:

```text
no neighbours / no overlap
→ zero pool
→ zero delta

equal height
→ zero relative bias
→ zero delta

tall over short with dense overlap
→ tall positive delta
→ short equal negative delta
```

The pair mechanism is intentionally zero-sum. It redistributes a bounded contested-light contribution and does not invent unlimited energy.

The accepted PH3 morphology profile is read only through `MorphologyProfile.create_default()`. CAL1-B does not create or tune a custom PH3 profile.

## Controlled experiment

`scripts/research/ecology/plant_vertical_light_competition_experiment_v1.gd`.

Cases:

1. `NO_NEIGHBOURS`;
2. `EQUAL_HEIGHT_DENSE`;
3. `TALL_SHORT_DENSE`;
4. `TALL_SHORT_SPARSE`;
5. `DRY_TALL_SHORT_DENSE`;
6. `TALL_SHORT_DENSE_SWAP`.

All morphology comparisons reuse PH3C common Genome/IndividualSeed isolation.

## Acceptance requirements

### No-neighbour control

Competition intensity, contested pool and both deltas must be zero.

### Equal-height control

Relative-height bias must be zero, access shares 0.5/0.5 and no fake winner may be created.

### Dense tall-vs-short

Tall phenotype must receive positive relative-light delta and short phenotype an equal negative delta.

This is not required to reverse the full existing PH3 winner. The proof is causal, not calibration-driven.

### Sparse control

Dense effect must be more than an order of magnitude larger than sparse effect with the selected controlled contexts.

### Dry control

Tall must still gain relative access under dense overlap, but existing structure/water economics must remain strong enough that CAL1-B does not automatically make tall universally superior.

### Swap symmetry

Swapping focal A/B must swap heights, phenotype hashes and light deltas exactly.

### Conservation

`a_light_delta + b_light_delta == 0` within numerical tolerance.

### Determinism

Same-process and fresh-process aggregate hashes must match.

### Parent invariants

CAL1-A baseline hash and accepted PH3C hash must remain unchanged.

## Test surface

- `tests/research/ecology/eco_cal1_b_relative_vertical_light_competition_acceptance.gd`;
- `tests/research/ecology/eco_cal1_b_restart_replay_probe.gd`;
- `RUN_ECO_CAL1_B_TESTS.ps1`.

The runner first executes the complete accepted CAL1-A runner, then CAL1-B acceptance, then two independent CAL1-B fresh-process probes.

## Diff boundary

`6934d726... -> 561daee4...` changes exactly five ECO research/test/runner files.

No accepted PH3/PH3C source and no production runtime path was modified.

## Exact Windows gate

```powershell
cd C:\Godot\lunar-world-eco-evolutionary-ecology

git pull

$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_ECO_CAL1_B_TESTS.ps1 -GodotPath $Godot
```

Need to record:

```text
ECO.CAL1-B Relative Vertical Light Competition: PASS (...)
ECO.CAL1-B aggregate_hash=<64 hex>
ECO.CAL1-B dense_delta=...
ECO.CAL1-B sparse_delta=...
ECO.CAL1-B dense_to_sparse=...
ECO.CAL1-B reference_gap_before=...
ECO.CAL1-B reference_gap_after=...
ECO.CAL1-B dry_gap_before=...
ECO.CAL1-B dry_gap_after=...
ECO.CAL1-B candidate automated gates: PASS
```

Until this exact gate passes:

```text
CAL1-B = IMPLEMENTED_CANDIDATE
CAL1-B != ACCEPTED
CAL1-C = BLOCKED
```
