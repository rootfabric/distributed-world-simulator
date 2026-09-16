# FABRIC HOLDOUT-R4 G2 — FRESH INDEPENDENT VERIFIER R1

```text
ROLE            = VERIFIER
SUBJECT_BRANCH  = repair/fabric-holdout-r4-g2-generalized-capabilities-r1
SUBJECT_HEAD    = e6228a39b6b3006a3d14ad0884c09266570fcd00
SUBJECT_TREE    = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
VERIFIER_BRANCH = verify/fabric-holdout-r4-g2-fresh-independent-verifier-r1
VERIFIED_HEAD   = 2c77c1db0f54385f56e91266352659371eb46e38
VERIFIED_TREE   = 73db3d77b84f5565c8acfa137e20c9f6ef4f9604
STATUS          = VERIFIED
VERDICT         = PASS
```

## Independence and scope

The executable verifier branch started directly at the exact product subject and, at the verified head, differed from it only by:

- `.github/workflows/fabric-holdout-r4-g2-independent-verifier-r1-linux-double.yml`;
- `RUN_FABRIC_HOLDOUT_R4_G2_INDEPENDENT_VERIFIER_R1.sh`;
- `tests/research/fabric1/fabric_holdout_r4_g2_independent_verifier_r1.gd`;
- this report.

No product/runtime file, frozen G1 challenge/provenance, threshold, or Implementer acceptance file was modified. The workflow bound `origin/$SUBJECT_BRANCH` to the exact subject HEAD/TREE, required `merge-base(verifier, subject) == subject`, compared the verifier diff to the four verifier-owned paths, and ran `git diff --check`.

## Exact self-hosted verifier evidence

The fresh independent verifier completed successfully on the repository self-hosted Linux/X64 runner:

```text
WORKFLOW_RUN = 35089433455
JOB          = 104771963647
RUNNER       = dws-linux-outenemy
CONCLUSION   = SUCCESS
```

All workflow steps completed with `success`, including exact subject/scope binding, canonical runtime identity, fresh import, the primary independent oracle, fresh detached exact-subject replay, evidence capture, and artifact upload.

Immutable artifact:

```text
ARTIFACT_ID     = 10443333867
ARTIFACT_NAME   = fabric-holdout-r4-g2-independent-verifier-r1-2c77c1db0f54385f56e91266352659371eb46e38
ARTIFACT_SHA256 = c3d5a7b7f9a09fd4862ebb32066f2a9b6ac5342ff67eea214f92cddf26b8088e
```

The artifact itself records:

```text
SUBJECT_HEAD  = e6228a39b6b3006a3d14ad0884c09266570fcd00
SUBJECT_TREE  = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
VERIFIER_HEAD = 2c77c1db0f54385f56e91266352659371eb46e38
VERIFIER_TREE = 73db3d77b84f5565c8acfa137e20c9f6ef4f9604
```

Canonical runtime identity:

```text
Godot  = 4.7.1.stable.double.custom_build.a13da4feb
SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

The verifier import completed without fatal/error sentinels.

## Primary verifier-owned oracle

The independent executable oracle does not use the frozen G1 cases as its expected-answer source. It checks new analytic/fail-closed cases for bit-exact transport, a hand-solvable bridge resistive network, a hand-solvable 2x2 mechanics system plus the DAE divisor floor, and event math/parser cases including delimiter-rich IDs and known roots.

Exact self-hosted sentinels:

```text
FABRIC_HOLDOUT_R4_G2_INDEPENDENT_VERIFIER_R1_ASSERTIONS=54
FABRIC-HOLDOUT-R4-G2-INDEPENDENT-VERIFIER-R1: PASS
```

Artifact evidence SHA-256 for `independent-verifier.log`:

```text
89bd64657d8715c18fc09c5b2fe77d442ce2508cac501ff94c20141d3425db62
```

## Secondary exact-subject replay

The workflow created a detached worktree at the immutable product subject and ran the unchanged `RUN_FABRIC_HOLDOUT_R4_G2_TESTS.sh`.

The captured replay contains the required PASS sentinels, including:

```text
FABRIC-HOLDOUT-R4-G2: PASS
FABRIC-COMPOSITION-R3: PASS
FABRIC-PHYSICS-R2: PASS
FABRIC-REPAIR-R1 INTEGRITY: PASS (42 assertions)
```

Artifact evidence SHA-256 for `subject-replay.log`:

```text
a81981edca211ca6a6de0bd86f1f2a51a56aaa2447903d8c8e937233b069acaf
```

Other captured evidence hashes:

```text
subject.txt              42e9b3ed8e748c620f61c40aa35596daf0f8d9c1aa768bec2d37091c2d6d07a8
godot.txt                f33c60d53734366f33891821c0210d6b1f0b59d7ca2381817b7f6817cdc9a81d
verifier-import.log      194b45bcbcbfe4f47ea3a8579727d259b7bdf8ef0371b3fce72301c0cf1ff6ad
independent-verifier.log 89bd64657d8715c18fc09c5b2fe77d442ce2508cac501ff94c20141d3425db62
subject-replay.log       a81981edca211ca6a6de0bd86f1f2a51a56aaa2447903d8c8e937233b069acaf
```

## Trusted exact-head evidence consumed by the Verifier

The Verifier also consumed existing exact-subject evidence without claiming authorship:

- G2 exact: run `34756624051` = SUCCESS, artifact `10323837160`;
- COMPLEX2-CLOSE: run `34756626745` = SUCCESS;
- COMPLEX2-PERF: run `34756626564` = SUCCESS with unchanged 12 s case budget;
- isolated B0.6-CLOSE control: run `34967889721` = SUCCESS;
  - repeat 1 job `104376646076`, artifact `10397444837`, digest `sha256:690f3ef6bdd16d25c39ee90155809b1aa34f55a08fa9258bf93957704fbccac4`;
  - repeat 2 job `104376646294`, artifact `10399258711`, digest `sha256:cb8bd4d517eea7c4016a8fa824975b690042e2f6b75899b73ba1a33e25a8ccc9`;
  - both produced `B06_CLOSURE_HASH=892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584` and clean exact source.

The historical frozen G1 result remains `HOLDOUT_R4 = FAIL / FALSIFIED`. The verifier does not rewrite that result and does not reveal or design the future unseen holdout.

## Verifier verdict

The independent executable evidence and exact-subject replay support:

```text
FRESH_VERIFIER    = VERIFIED
VERDICT           = PASS
SUBJECT           = e6228a39b6b3006a3d14ad0884c09266570fcd00
DIRECTOR          = READY_AFTER_REPORT_STATUS_HEAD
PRODUCTION_FREEZE = NOT_GRANTED
UNSEEN_HOLDOUT    = NOT_REVEALED
R4_ACCEPTED       = false
```

This report-only status commit is intentionally not a product mutation. Its push re-runs the same verifier workflow as a final status-head integrity check; Director may proceed only after that run remains green and the product subject still resolves to the exact `e6228a39...` / `1b849603...` pair.
