# ECO.P1C-S4 — Competition Robustness + Aggregate Acceptance — ACCEPTED

Exact-Windows confirmation received on Godot `4.7.1.stable.double.custom_build.a13da4feb`.

Accepted evidence:

- six heterogeneous seeds × 18 cycles: `6 × 30 assertions`, all PASS;
- uniform negative control: `27 assertions`, PASS;
- 24-cycle deep horizon: `30 assertions`, PASS;
- aggregate contract: `15/15`;
- fresh-process restart replay: `6/6`;
- aggregate hash `0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112`;
- default case `431c4b6c0683b692c9fe88fbc912f49c3659db122c8fdf2715f525ea712dc43b`;
- uniform case `8f27fb89d87d7b92911efcb80ae461d2d0f32ff169ed8f3efbdf73a296d67d47`;
- deep horizon `ca49a238f82303ac6ad7e36d10f849baff07442873ab3b20c22d2d32f9f34411`.

Failure matrix: `GLOBAL_TAKEOVER`, `DIVERSITY_COLLAPSE`, `CLUSTER_COLLAPSE`, `FALSE_NICHE_UNIFORM`, `REPLAY_DIVERGENCE` PASS; `RUNAWAY_TRAIT=PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS`.

S4 introduces no new ecology equations and accepts the robustness of the already-accepted P1C competition model.
