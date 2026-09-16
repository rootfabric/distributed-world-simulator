# FABRIC HOLDOUT-R4 — DIRECTOR R1

```text
ROLE             = DIRECTOR
SUBJECT_BRANCH   = repair/fabric-holdout-r4-g2-generalized-capabilities-r1
SUBJECT_HEAD     = e6228a39b6b3006a3d14ad0884c09266570fcd00
SUBJECT_TREE     = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
BASE             = b88004e77a9a424f1b23ba979f5ce8883a98f1a8
DIRECTOR_VERDICT = PASS
NEXT_GATE        = PRODUCTION_FREEZE
R4_ACCEPTED      = false
```

## Scope of this decision

This is a Director adjudication over the immutable product subject above. It consumes the completed exact-head product, Reviewer, Verifier and B0.6 closure evidence. It does **not** modify product/runtime/test thresholds, merge PR #592, freeze production by itself, reveal/design the unseen holdout, or mark R4 accepted.

Live PR #592 was re-resolved immediately before this decision and still pointed to exact `e6228a39b6b3006a3d14ad0884c09266570fcd00` on base `b88004e77a9a424f1b23ba979f5ce8883a98f1a8`; the exact product tree remains `1b84960369868aa6d5ec23c1eae3019250ff9a8f`.

## Evidence admitted

### Product exact-head execution

- G2 exact self-hosted run `34756624051` = `SUCCESS`, artifact `10323837160`.
- COMPLEX2-CLOSE run `34756626745` = `SUCCESS`.
- COMPLEX2-PERF run `34756626564` = `SUCCESS`; the fixed 12 s case budget was not weakened.
- B0.6 A/B/C/D/E current-head individual gates = `SUCCESS`.
- Canonical Linux double runtime:

```text
Godot  = 4.7.1.stable.double.custom_build.a13da4feb
SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

### Full B0.6 closure

The canonical 45-minute workflow cancellation is retained as an orchestration timeout and is not counted as a PASS.

The decisive isolated control run `34967889721` executed two serial clean jobs, each with a clean exact `e622` checkout, fresh import, one unmodified full B0.6 closure, the same expected closure hash and clean-source proof:

```text
repeat 1 job      = 104376646076 SUCCESS
repeat 1 artifact = 10397444837
repeat 1 digest   = 690f3ef6bdd16d25c39ee90155809b1aa34f55a08fa9258bf93957704fbccac4

repeat 2 job      = 104376646294 SUCCESS
repeat 2 artifact = 10399258711
repeat 2 digest   = cb8bd4d517eea7c4016a8fa824975b690042e2f6b75899b73ba1a33e25a8ccc9

B06_CLOSURE_HASH  = 892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584
```

Decision: `B0.6-CLOSE = VERIFIED`.

### Fresh Reviewer

Fresh Codex review request `#5696289944` was explicitly bound to exact `e622/1b849`. The completed Reviewer response `#5696356174` states that it did not find any major issues and records reviewed commit `e6228a39b6`.

Decision: `FRESH_REVIEWER = PASS` for the current immutable subject.

### Fresh independent Verifier

Verifier-owned branch:

```text
verify/fabric-holdout-r4-g2-fresh-independent-verifier-r1
```

Executable verifier head:

```text
VERIFIER_HEAD = 2c77c1db0f54385f56e91266352659371eb46e38
VERIFIER_TREE = 73db3d77b84f5565c8acfa137e20c9f6ef4f9604
parent        = e6228a39b6b3006a3d14ad0884c09266570fcd00
```

Primary verifier run:

```text
run      = 35089433455 SUCCESS
job      = 104771963647 SUCCESS
artifact = 10443333867
artifact digest = c3d5a7b7f9a09fd4862ebb32066f2a9b6ac5342ff67eea214f92cddf26b8088e
```

The artifact records exact product HEAD/TREE and canonical Godot identity. The verifier-owned analytic oracle produced:

```text
FABRIC_HOLDOUT_R4_G2_INDEPENDENT_VERIFIER_R1_ASSERTIONS=54
FABRIC-HOLDOUT-R4-G2-INDEPENDENT-VERIFIER-R1: PASS
```

The detached exact-subject replay also contains:

```text
FABRIC-HOLDOUT-R4-G2: PASS
FABRIC-COMPOSITION-R3: PASS
FABRIC-PHYSICS-R2: PASS
FABRIC-REPAIR-R1 INTEGRITY: PASS (42 assertions)
```

The durable verifier report was then updated in a report-only commit:

```text
STATUS_HEAD = fcd5748b895a7b35e568727f2600055d1e022ed5
```

Final status-head integrity replay:

```text
run      = 35091203273 SUCCESS
job      = 104777667691 SUCCESS
artifact = 10444188434
artifact digest = 4da307d7e971c93bd5056df6c4091f7b7b615072ea4b73fda0f3deaead0a5f7d
```

All binding, canonical-runtime, fresh-import, independent-oracle, exact-subject replay, evidence capture and artifact-upload steps succeeded.

Decision: `FRESH_VERIFIER = VERIFIED / PASS`.

## Historical G1 and holdout integrity

The frozen G1 outcome remains historical evidence:

```text
HOLDOUT_R4 = FAIL / FALSIFIED
```

The current chain does not rewrite that outcome, does not treat G1 as a PASS, and does not use a repaired/revealed G1 corpus as the next acceptance test. Frozen challenge/provenance/instrument bytes remain outside product repair scope. The future post-G2 unseen holdout remains unrevealed at this Director gate.

## Director risk adjudication

### Known `matrix_hash` diagnostic anomaly

The monolithic two-repeat control run `34849865505` completed repeat #1 fully, then its second repeat in the same workspace reached `COMPLEX2-CLOSE` after `Perf.run_matrix()` returned a non-success shape; `fabric_bake_complex2_close_acceptance.gd` subsequently indexed missing `perf["matrix_hash"]`, masking the underlying failure reason.

Director classification: **NON_BLOCKING_DIAGNOSTIC_RISK for the R4 product subject**.

Reasoning:

1. the anomaly was observed only in the second repeat of a shared-workspace monolithic control route;
2. current-head COMPLEX2-PERF and COMPLEX2-CLOSE are independently green with unchanged acceptance budgets;
3. both decisive clean isolated B0.6 closure repeats pass from clean checkout/fresh import and produce the identical canonical closure hash;
4. the fresh independent Verifier plus exact-subject replay are green;
5. no evidence currently ties the masked failure to a reproducible clean product semantic defect.

The brittle diagnostic indexing should be hardened as a separate post-R4 test-quality repair so a future Perf failure reports its original failure shape instead of a secondary missing-key error. That follow-up must not mutate the frozen R4 product subject during the current acceptance chain.

## Director verdict

The required pre-freeze chain is complete on one immutable product subject:

```text
CURRENT_HEAD_EXACT_G2   = PASS
B0.6_CLOSE_ISOLATED_X2  = VERIFIED
FRESH_REVIEWER          = PASS
FRESH_VERIFIER          = VERIFIED / PASS
DIRECTOR                = PASS
```

Therefore:

```text
PRODUCTION_FREEZE = AUTHORIZED_NEXT
UNSEEN_HOLDOUT    = STILL_LOCKED_UNTIL_FREEZE_RECORD_EXISTS
R4_ACCEPTED       = false
SCALE_R5          = LOCKED
MERGE_AUTHORIZED  = false
```

The next action is to create and validate an immutable production-freeze record binding exactly `e6228a39b6b3006a3d14ad0884c09266570fcd00` / `1b84960369868aa6d5ec23c1eae3019250ff9a8f` plus the admitted evidence above. Only after that freeze record is durable may a genuinely unseen post-G2 holdout be preregistered/revealed and independently executed.
