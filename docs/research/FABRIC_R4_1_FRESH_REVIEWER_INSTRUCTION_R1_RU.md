# FABRIC R4.1 — FRESH REVIEWER DISPATCH R1

```text
ROLE         = REVIEWER
SUBJECT_HEAD = 5ed03392edcdaf0efaf743423f12bd9e1550e70a
SUBJECT_TREE = ef7366f3452b812ab735c42d8447c3ca84c7bea3
BASE_HEAD    = e6228a39b6b3006a3d14ad0884c09266570fcd00
STATUS       = DISPATCHED / VERDICT REQUIRED
```

This is an instruction record only. It is not a review and must never be counted as Reviewer PASS.

## Required review scope

Review exactly the product diff `e6228a39... -> 5ed03392...`. Treat every prior review on `201d34c...`, `3afd12e...`, `de89051d...`, `d09ef192...` or `ae924efe...` as stale for freshness.

Focus on:

1. generalized resistive graph numerical totality:
   - every successful return must contain finite representable observables;
   - representable high-dynamic-range cases must not be rejected merely because an intermediate naive expression overflows;
   - genuinely non-representable conductance/current/power/residual/condition paths must fail closed;
   - normal finite-path arithmetic/hash behavior must remain unchanged where fallback is not needed;
2. the three prior P1 classes:
   - common-mode boundary potential where individual `V*I` overflows although total external power is finite;
   - residual scale overflow when both finite powers approach `DBL_MAX`;
   - node-balance partial-sum overflow followed by finite cancellation;
3. PERF/CLOSE diagnostics:
   - a failed PERF result must preserve the primary error code/details;
   - missing/empty `matrix_hash` on failure must not mask the original error;
   - the fixed 12-second case budget, accepted matrix hash and closure hash must not be weakened;
4. R4.1 orchestration:
   - removal of redundant pre-runs must not remove coverage already performed by canonical B0.6-CLOSE;
5. roadmap claim boundaries:
   - historical R4 remains bounded ACCEPTED evidence only;
   - current subject requires fresh exact evidence before freeze;
   - R4.2 unseen topology/dynamic holdout remains locked until Director + production freeze.

## Concrete regressions to inspect

Current acceptance intentionally includes byte-constructed IEEE-754 subnormals rather than unreliable source literals:

```text
5.57e-309 bytes LE = f8ad43bd58010400
1e-320 bytes LE    = e807000000000000
```

The compensated-balance fixture must prove:
- each current is finite;
- naive same-sign partial `I + I` is non-finite;
- the final signed balance is finite and matches the analytic cancellation.

## Admissible verdict

Return one of:

```text
PASS
FIX_REQUIRED
INSUFFICIENT_EVIDENCE
```

A PASS must name the reviewed HEAD/TREE exactly. Any new product commit after the review invalidates freshness.
