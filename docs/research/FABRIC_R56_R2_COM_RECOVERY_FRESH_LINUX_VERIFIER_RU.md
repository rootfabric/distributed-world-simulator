# FABRIC R5.6.1 R2 — Fresh Ubuntu Exact Verifier

Дата: 2026-10-21.

**VERDICT: FRESH_UBUNTU_EXACT_PASS**, not separate-actor approval.

## Frozen identity

- Product HEAD: `60f193d6602d2d6ebb62393d3db6633b14623627`.
- Product TREE: `1a92363e7cc159fef4c42e3443542ebb00a71464`.
- Red parent COM-recovery: `91223acb7bf79c37e12fc11d44054ad3e2732455`.
- Canonical Linux Godot: `4.7.1.stable.double.custom_build.a13da4feb` SHA256 `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.
- Restored repository from GitHub Actions artifact 12315485919, full source archive / Git bundle hashes verified against its SHA256SUMS. Git bundle detached checkout, clean tracked state; source diff check PASS.

## Reproduction

Unmodified `RUN_FABRIC_R5_6_1_R2_TESTS.sh` on the exact product HEAD completed **EXIT=0**. Source environment exported `GODOT_BIN`, `R56_R2_EXPECTED_HEAD`, `R56_R2_EXPECTED_TREE` and an initially empty evidence directory. No test threshold, code, or exact runner modified.

| Gate | Independent Linux result |
| --- | --- |
| Cold import / parse | PASS, seven parse gates |
| R2 core | 3 × 626/0; raw result payload identical |
| R2 5k/20k/100k | 255/0, max nodes 12/14/16 |
| Numeric conditioning | 54/0 |
| Center-of-mass representability | 52/0, 6 unsafe rejected / 2 safe accepted |
| COM recovery liveness | 18/0, 2 legal commits, fail-closed bad Matter / stale source / replay |
| R1 regression | 203/0, prior deterministic hash MATCH |
| R1 narrow admission | 26/0 |
| BRIDGE-4 | 49/0 |
| Strict collector | `fabric.r56_r2.dynamic_aggregates.exact_evidence.v4` PASS |
| Tamper matrix | 21/21 rejected |
| Evidence SHA256SUMS | 21/21 verified |

Deterministic R2 result hash: `7fb3eb72caec05dd5341399c8f032f90165a4459610ab3058d798a97fa98dd43`.

`identity-before.txt` and `identity-after.txt` byte-identical. Linux Godot binary SHA256 matched the canonical. No additional source mutations in exact checkout.

**Scope:** exact runner verifies fixed bounded point-mass constructs. Generalized rigid-body physics, arbitrary world coordinates, concurrency, persistent world owner, and end-to-end O(log N) are not inferred.
