# FABRIC HOLDOUT-R4 G2 — Repair R3

## Subject / trigger

Parent product subject:

```text
HEAD = 8fe54a498a9a055b232cfe34bfc379088ec4a627
TREE = 1607ed1c82ea92c11ad26800c3d559d455f26492
```

Fresh independent review of that exact subject completed on PR #592 and returned `FIX_REQUIRED`.
Current finding:

```text
review = 5188851698
inline finding = 3998177168
severity = P2
path = scripts/research/fabric_bake0/fabric_composition_r3_general_event_step_v1.gd
```

Repair R2 aligned generalized system integration and `observe()` with the declared G2-B signed effort convention:

```text
effort = k * (q_a - q_b) + c * (v_a - v_b)
```

but the generalized event bracketing/localization helper `_effort()` still used the historical opposite sign:

```text
k * (q_b - q_a) + c * (v_b - v_a)
```

Because both positive and negative guard transitions exist, event time / physical trajectory can remain unchanged while the opposite signed transition is selected and persisted into event/replay history. This makes signed causal evidence incorrect.

## Independent negative control

On the exact parent subject with the canonical double Godot, the existing generalized delimiter/failure E2E fixture was instrumented only for observation and reproduced the defect:

```text
declared effort = -0.35000000000871 N
recorded event  = failure|bond/g2|weak|support|1.0
parsed sign     = +1.0
result          = FAIL
```

The negative control is not committed as product evidence; its durable purpose is to establish that the review finding is executable, not merely stylistic.

## Bounded repair

Allowed product scope:

1. `scripts/research/fabric_bake0/fabric_composition_r3_general_event_step_v1.gd`
   - align event bracketing/localization `_effort()` with the already-declared G2-B sign convention only;
2. `tests/research/fabric1/fabric_holdout_r4_g2_bond_id_acceptance.gd`
   - extend the already-existing generalized runtime failure E2E with assertions that the persisted failure transition sign matches the declared observed support effort at the event;
3. this Repair Map.

No algorithm redesign is authorized.

## Forbidden scope

Do not change:

- failure/guard capacities or thresholds;
- event localization tolerances, work budgets, time-step limits, or golden hashes;
- physical internal-force application convention already fixed in Repair R2;
- lossless replay transport;
- NetworkUtils / canonical legacy serialization;
- COMPLEX2-PERF code or budget;
- frozen G1 cases, provenance, author response, probes, or historical verdict;
- authority / canonical commit fencing.

G1 remains `FALSIFIED`.

## Acceptance

Before calling this repair ready for fresh review:

1. prove the focused generalized runtime failure sign assertion FAILS on parent `8fe54a...`;
2. after the one-line sign alignment, prove the same E2E PASSes and records a sign consistent with `supports[].effort_n`;
3. run full exact `RUN_FABRIC_HOLDOUT_R4_G2_TESTS.sh` on the final product HEAD;
4. rerun inherited R3/R2/R1 gates through that runner;
5. obtain new exact-head CI because any product mutation makes all `8fe54a...` evidence stale;
6. rebuild qualification evidence in a new R3 control epoch; do not overwrite R1/R2 evidence;
7. request a new independent exact-head review.

`B0.6-CLOSE` / `COMPLEX2-PERF` baseline-performance classification remains a separate Reviewer/Director decision and must not be converted to PASS by this repair.

Production freeze, unseen holdout, R4 acceptance and SCALE-R5 remain locked.
