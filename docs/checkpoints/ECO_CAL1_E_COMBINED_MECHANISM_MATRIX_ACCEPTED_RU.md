# ECO.CAL1-E — Combined Mechanism Matrix — ACCEPTED

Статус: `ACCEPTED / EXACT WINDOWS CANONICAL / RESEARCH_ONLY / NO CALIBRATION`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `69a6f569d3a0f6ecbad641fb45b21340323f118e`.

Canonical gate executed on exact Windows checkout with Godot `4.7.1.stable.double.custom_build.a13da4feb`.

## Parent preservation

`ECO.CAL1-D` remained exact:

`c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`.

The full PH3 -> PH3C -> CAL1-A -> B -> C -> D chain passed before CAL1-E.

## Canonical evidence

```text
aggregate_hash = 6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814
rows = 192
contexts = 24
dense_nonzero = 96
sparse_nonzero = 0
multiobjective_contexts = 24
multi_member_pareto_contexts = 24
distinct_pareto_signatures = 2
```

Fresh-process A and B reproduced the same aggregate hash exactly.

## Main finding

CAL1-E successfully composed accepted resource, vertical-light, crown/root spatial and lifecycle/disturbance mechanisms without creating a weighted composite fitness scalar.

`SPARSE` remained a strict no-overlap anchor: all 96 sparse rows had zero neighbour interaction. `DENSE` activated neighbour interaction in all 96 dense rows.

Every one of the 24 ecological contexts had multiple metric objectives and a multi-member Pareto front. This is evidence that the repaired causal model exposes genuine trade-offs instead of merely replacing one universal winner with another.

### Reference dense examples

`REFERENCE/DENSE/NONE`:

```text
pareto = [HEIGHT_LOW, HEIGHT_HIGH, BRANCH_LOW, GIANT_DENSE]
resource winner = HEIGHT_LOW
seed winner = HEIGHT_LOW
dispersal winner = GIANT_DENSE
```

`REFERENCE/DENSE/SEVERE`:

```text
pareto = [HEIGHT_LOW, HEIGHT_HIGH, BRANCH_LOW, GIANT_DENSE]
survival winner = HEIGHT_LOW
recovery winner = HEIGHT_LOW
```

Thus `HEIGHT_LOW` still has strong advantages on several objectives, but it is not universally dominant across the accepted objective vector: expensive/tall morphology retains causal value, notably dispersal, and remains non-dominated in relevant contexts.

## Acceptance decision

`ECO.CAL1-E = ACCEPTED`.

CAL1-F is now allowed to perform the first explicit calibration/perturbation/full-pool robustness stage.

CAL1-F must not tune toward a preferred strategy. It must test whether conclusions survive reasonable parameter, environment, density, deterministic-seed and strategy-pool perturbations, and must report fragility if they do not.

After CAL1-F acceptance, `ECO.EVO0 / CAL1` may close and the branch can move to `ECO.EVO1 Plant World Proof`.
