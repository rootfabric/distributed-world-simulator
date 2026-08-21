# ECO.CAL1-D — Lifecycle / Reproduction / Dispersal / Disturbance Payoffs — ACCEPTED

Статус: `ACCEPTED / EXACT WINDOWS CANONICAL / RESEARCH_ONLY`.

Ветка: `feature/eco-evolutionary-ecology`.

Implementation head: `88adcc609fdfbc5511dc2aa0a4b779edc9a114e0`.

Canonical gate executed on the exact Windows checkout with Godot `4.7.1.stable.double.custom_build.a13da4feb`.

## Parent preservation

`ECO.CAL1-C` remained exact:

`d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a`.

The complete PH3 -> PH3C -> CAL1-A -> CAL1-B -> CAL1-C chain passed before CAL1-D.

## Canonical result

`aggregate_hash = c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6`.

Both independent fresh-process probes reproduced that hash exactly.

Canonical causal observations:

- mature / immature seed output ratio: `4.000000000000`;
- high / low reserve seed output ratio: `3.333333333333`;
- high / low release-height dispersal ratio: `2.000000000000`;
- fast maturity index: `2.500000000000`;
- slow maturity index: `8.000000000000`;
- short-life annual structural amortization: `0.043650537490`;
- long-life annual structural amortization: `0.007275089582`;
- shallow-root survival at matched severe disturbance: `0.412244897959`;
- deep-root survival: `0.800000000000`;
- fast recovery index: `0.446428571429`;
- slow recovery index: `1.428571428571`;
- mild post-disturbance seed potential: `462.357351103707`;
- severe post-disturbance seed potential: `268.807788421491`.

## Accepted interpretation

CAL1-D proves that morphology/life-history consequences are not reducible to instantaneous resource balance:

- maturity gates realized reproduction;
- reserve state gates realized seed output;
- release height changes dispersal through explicit geometry;
- larger target size delays maturity when growth rate is held fixed;
- lifespan amortizes structural investment over time;
- root depth changes mechanical anchoring and disturbance survival;
- growth rate changes recovery time;
- disturbance severity reduces surviving reproductive opportunity.

CAL1-D deliberately does not define one hidden lifecycle-fitness scalar. It exposes independent observables for the combined-mechanism stage.

## Boundary

No accepted P1/PH3/CAL1-B/C source was modified. No runtime path was modified. No generic `tall_bonus` and no coefficient calibration were introduced.

## Decision

`ECO.CAL1-D = ACCEPTED_EXACT_WINDOWS_CANONICAL`.

Next: `ECO.CAL1-E Combined Mechanism Matrix`, still without coefficient calibration. CAL1-F remains the first calibration/robustness stage.
