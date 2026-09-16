# FABRIC HOLDOUT-R4 POST-G2 — FRESH INDEPENDENT UNSEEN VERIFIER R1

```text
ROLE           = VERIFIER
PRODUCT_HEAD   = e6228a39b6b3006a3d14ad0884c09266570fcd00
PRODUCT_TREE   = 1b84960369868aa6d5ec23c1eae3019250ff9a8f
FREEZE_COMMIT  = 649af4ef16de00c797b4d63be70426abb3c75d68
PREREG_HEAD    = 8c28ff9ea4ab1446cd067ca4b8cb5674997a621d
REVEAL_R2_HEAD = 022fa6730031d529cfaecc40a76fc70315d355d1
CASES_SHA256   = 3e14d528a33f4ecb95c4d7fd1f3f55394fcb4b3e624e0bf728698acef99f576d
STATUS         = VERIFIED_PASS
R4_ACCEPTED    = false
```

## Reveal evidence admitted

Live GitHub evidence, not an earlier summary, is authoritative:

```text
REVEAL_RUN             = 35109278910  SUCCESS
REVEAL_HEAD            = 022fa6730031d529cfaecc40a76fc70315d355d1
REVEAL_ARTIFACT        = 10451358632
REVEAL_ARTIFACT_DIGEST = sha256:b1ee63b0dedce2f66112242dbbf74f4515a41e7e750be8eaab2d0a183351dd4f
```

The exact revealed case bytes copied from that artifact have SHA-256:

```text
3e14d528a33f4ecb95c4d7fd1f3f55394fcb4b3e624e0bf728698acef99f576d
```

The canonical first-reveal NIST pulse remains pulse `1943920`, timestamp `2026-09-16T12:46:00.000Z`, selected by the preregistered `time/next/1789562700000` rule. The historical first reveal attempt failed only while parsing that already-selected ISO timestamp; it did not select another pulse or generate cases.

## Independent primary oracle

This verifier is not the Implementer and is not the Reveal-run. `verify_unseen_cases_independent_v1.py` does not import product code or the prereg generator. It independently:

- reconstructs the domain-separated SHA-256 streams from the fixed NIST output;
- reconstructs all IEEE754 little-endian transport patterns and checks finite/bit round-trip properties;
- solves the 6-node / 9-edge / 3-port graph using exact `Fraction` Gaussian elimination, including exact KCL and port-current conservation;
- solves the multi-mass stiffness system using exact rationals and checks a unit geometric axis plus positive-definite stiffness probes;
- reconstructs the event polynomial from preregistered roots and proves the three exact roots plus the tangent derivative condition;
- reconstructs the complete canonical case object and requires byte-identical equality with the revealed case file.

Primary exact result:

```text
FABRIC_R4_POST_G2_UNSEEN_INDEPENDENT_ASSERTIONS=67
FABRIC-R4-POST-G2-UNSEEN-INDEPENDENT-ORACLE: PASS
INDEPENDENT_CASES_SHA256=3e14d528a33f4ecb95c4d7fd1f3f55394fcb4b3e624e0bf728698acef99f576d
```

The frozen prereg generator is used only as a secondary cross-check and produced bytes identical to both the independent oracle and the revealed artifact.

## Executable verification

Verifier branch exact execution:

```text
VERIFIER_HEAD = 94a0d54f30ea4b6d2311a1d93c766e6d76e2840a
VERIFIER_TREE = a3be3352c5427d5766ed23e8c3315891087fd7ad
RUN           = 35110199365  SUCCESS
JOB           = 104841606910 SUCCESS
ARTIFACT      = 10452206840
DIGEST        = sha256:92a41e4e902e096089d22e369b6b1489af3ff33482049d6e0ac9825b89575184
```

All workflow steps passed:

```text
exact product/reveal/verifier scope binding = PASS
primary independent oracle                 = PASS (67 assertions)
frozen prereg generator byte cross-check   = PASS
canonical Godot double                     = PASS
fresh import                               = PASS
secondary frozen unseen runner             = PASS (93 assertions / 0 failures)
tertiary exact frozen-product G2 replay     = PASS
evidence capture + artifact upload          = PASS
```

The verifier branch is exactly four verifier/evidence files ahead of `REVEAL_R2_HEAD`; no frozen product, prereg generator/runner, threshold, or G1 challenge byte was changed.

## Verdict

```text
FRESH_INDEPENDENT_UNSEEN_VERIFIER = PASS / VERIFIED
PRODUCT_MUTATION                  = NONE
UNSEEN_HOLDOUT                    = PASS
R4_ACCEPTED                       = false
NEXT_GATE                         = FINAL_R4_ACCEPTANCE_ADJUDICATION
```

This verifier closes the independent post-reveal verification gate. It does not by itself authorize PR merge or declare R4 accepted; a final acceptance adjudication must consume the full frozen chain.
