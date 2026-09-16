# FABRIC HOLDOUT-R4 G2 — FRESH INDEPENDENT VERIFIER R1

```text
ROLE           = VERIFIER
SUBJECT_BRANCH = repair/fabric-holdout-r4-g2-generalized-capabilities-r1
SUBJECT_HEAD   = e6228a39b6b3006a3d14ad0884c09266570fcd00
SUBJECT_TREE   = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
VERIFIER_BRANCH= verify/fabric-holdout-r4-g2-fresh-independent-verifier-r1
STATUS         = PENDING_EXACT_CI
```

## Independence and scope

This branch is verifier-owned evidence only. It starts at the exact product subject and may differ from it only by:

- `.github/workflows/fabric-holdout-r4-g2-independent-verifier-r1-linux-double.yml`;
- `RUN_FABRIC_HOLDOUT_R4_G2_INDEPENDENT_VERIFIER_R1.sh`;
- `tests/research/fabric1/fabric_holdout_r4_g2_independent_verifier_r1.gd`;
- this report.

No product/runtime, frozen G1 challenge, threshold, or Implementer acceptance file is modified. The workflow binds `origin/$SUBJECT_BRANCH` to the exact subject HEAD/TREE and requires `merge-base(verifier, subject) == subject`.

## Primary verifier-owned oracle

The independent executable oracle does not use the frozen G1 cases as its expected-answer source. It checks new analytic/fail-closed cases:

1. lossless transport: exact f64 bit round-trip including signed zero, safe-integer boundary, nonfinite rejection, noncanonical JSON rejection and checksum tamper rejection;
2. generalized resistive graph: a two-leg bridge with a hand-derived `X=Y=20/3 V`, zero cross-link current and source current `25/9 A`, plus insertion-order invariance and a floating-component negative control;
3. generalized mechanics: a hand-derived 2x2 spring system with unit-load displacements `M1=1/550 m`, `M2=3/1100 m`, geometric-axis invariance under endpoint/element-ID reversal, and the DAE mass-divisor-floor negative control;
4. generalized event math/parser: delimiter-rich bond IDs, invalid-sign rejection, two known transient polynomial roots (`0.2`, `0.8`) and a tangent root (`0.5`).

Local pre-publication execution on the canonical Linux double runtime completed with:

```text
FABRIC_HOLDOUT_R4_G2_INDEPENDENT_VERIFIER_R1_ASSERTIONS=54
FABRIC-HOLDOUT-R4-G2-INDEPENDENT-VERIFIER-R1: PASS
```

This local run is development evidence only; the binding verdict requires self-hosted exact CI.

## Secondary exact-subject replay

The workflow creates a detached clean worktree at `SUBJECT_HEAD` and runs the unchanged `RUN_FABRIC_HOLDOUT_R4_G2_TESTS.sh`. That replay independently rechecks the current G2 targeted/transport/bond-id/signed-effort gates, unchanged R3/R2/R1 regressions, and preservation of the historical frozen G1 FAIL/FALSIFIED record.

## Trusted exact-head evidence consumed by the Verifier

The Verifier may consume already-produced exact-head evidence without pretending it generated it:

- G2 exact: run `34756624051` = SUCCESS, artifact `10323837160`;
- COMPLEX2-CLOSE: run `34756626745` = SUCCESS;
- COMPLEX2-PERF: run `34756626564` = SUCCESS with unchanged 12 s case budget;
- isolated B0.6-CLOSE control: run `34967889721` = SUCCESS;
  - repeat 1 job `104376646076`, artifact `10397444837`, digest `sha256:690f3ef6bdd16d25c39ee90155809b1aa34f55a08fa9258bf93957704fbccac4`;
  - repeat 2 job `104376646294`, artifact `10399258711`, digest `sha256:cb8bd4d517eea7c4016a8fa824975b690042e2f6b75899b73ba1a33e25a8ccc9`;
  - both produced `B06_CLOSURE_HASH=892a66dbcb9e29c99ba7088a03dd41c167fd728a6f97923d4e944e4aef682584` and clean exact source.

Canonical runtime identity:

```text
Godot = 4.7.1.stable.double.custom_build.a13da4feb
SHA256 = bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Gate

Until the exact verifier workflow succeeds and this report is updated with durable run/artifact evidence:

```text
FRESH_VERIFIER   = PENDING
DIRECTOR         = BLOCKED
PRODUCTION_FREEZE= NOT_GRANTED
UNSEEN_HOLDOUT   = NOT_REVEALED
R4_ACCEPTED      = false
```
