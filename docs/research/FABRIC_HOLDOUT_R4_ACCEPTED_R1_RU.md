# FABRIC HOLDOUT-R4 — ACCEPTED R1

```text
PRODUCT_HEAD = e6228a39b6b3006a3d14ad0884c09266570fcd00
PRODUCT_TREE = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
R4_ACCEPTED  = true
SCALE_R5     = UNLOCKED
MERGE_AUTHORIZED = false
```

## Final acceptance chain

1. exact G2 current-head execution — PASS;
2. full B0.6 closure from two independent clean repeats — VERIFIED;
3. fresh exact-head Reviewer — PASS;
4. fresh exact-head independent Verifier — PASS;
5. Director pre-freeze adjudication — PASS;
6. immutable production freeze — FROZEN;
7. genuinely unseen post-G2 preregistration before the randomness cut — VERIFIED;
8. first NIST pulse after the preregistered cut fixed as pulse `1943920`, `2026-09-16T12:46:00.000Z`;
9. frozen unseen execution — 93 assertions / 0 failures, PASS;
10. fresh independent unseen verifier — 67 independent oracle assertions, frozen-generator byte match, 93/93 unseen replay and exact G2 replay, PASS;
11. verifier status-head run `35110718641` — SUCCESS.

Historical G1 remains `FAIL / FALSIFIED` and is retained as falsification evidence. It was not rewritten as PASS and its frozen challenge/provenance/instrument bytes were not used as the final unseen acceptance corpus.

The first reveal attempt is retained honestly: NIST pulse selection succeeded, but orchestration parsed the ISO timestamp as an integer and failed before cases were generated. R2 reused exactly the already selected pulse; it did not choose another pulse.

The known `matrix_hash` missing-key diagnostic behavior is classified as a separate non-blocking test-quality follow-up. It must not mutate the accepted R4 product subject.

## Decision

`FABRIC HOLDOUT-R4` is accepted on immutable product `e6228a39… / 1b849603…`. This unlocks `SCALE-R5`. PR #592 remains a separate merge gate and is not merged by this acceptance record.
