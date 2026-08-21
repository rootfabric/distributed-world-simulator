# ECO.CAL1-B — Relative Vertical Light Competition — ACCEPTED

Статус: `ACCEPTED / EXACT WINDOWS CANONICAL / RESEARCH_ONLY`.

Implementation head: `561daee4cd9fa48bcef5c78e6f2b0d050451f3b9`.

Exact Windows Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

Canonical evidence:

- CAL1-A baseline preserved: `280980c13b2545e66af94d10cc35f707c506365c65df9efeddb07b037588cb0f`;
- PH3C aggregate preserved: `294ebcd81db924421a916ad599711146c4047f0e295fe76f715fff11e548b7fb`;
- CAL1-B: `PASS (109 assertions)`;
- aggregate: `c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c`;
- dense delta: `0.099556363636`;
- sparse delta: `0.002765454545`;
- dense/sparse: `36.000000`;
- reference gap: `-0.577805307483 -> -0.378692580210`;
- dry gap: `-0.455052978213 -> -0.255940250941`;
- fresh-process A/B hashes exact.

The pair-gap shift is approximately `0.199112727273 = 2 × dense_delta`, matching the zero-sum contract: tall receives `+delta`, short receives `-delta`.

Accepted causal properties:

- no neighbours -> zero delta;
- equal height -> symmetric zero relative-height delta;
- dense tall-vs-short -> tall gains / short loses;
- sparse overlap -> effect 36× smaller;
- dry context retains structural/water tradeoffs;
- A/B swap symmetry;
- contested-light delta conservation;
- deterministic restart/replay;
- no PH3 coefficient changes.

Decision: `ECO.CAL1-B ACCEPTED_EXACT_WINDOWS_CANONICAL`.

Next: `ECO.CAL1-C Crown + Root Spatial Competition`.

Calibration remains forbidden until CAL1-E mechanism acceptance.
