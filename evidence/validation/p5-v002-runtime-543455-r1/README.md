# V0-P5 R2 V002 runtime evidence R1

Evidence-only receipt carrier for PR #173 exact evidence head `5434558856c00b588eed5369d2c613cd4b9858bb`.
Runtime/test bytes are the immutable freeze `5c3d936b35ecaa6b6023aac0e251f56858852186`; the only later candidate change before `543455...` is append-only control event metadata, and the two changed runtime/test Git blobs were independently re-read from `543455...` before publication.

This carrier currently publishes the machine campaign binding plus durable SHA-256 receipts for the continuous orchestration, all per-test logs as a set, critical ordinals, focused/repeat/stress/prefix executions, exact Godot identity, and Project Control. The full raw log bodies remain local implementer evidence and are **not** claimed as GitHub-published by this carrier. A fresh independent Verifier must reproduce the governed runtime predicates; a Reviewer must use `INSUFFICIENT_EVIDENCE` rather than infer any missing raw fact.

Historical R2 PRODUCT_RUNTIME_RED on `601ca87...` is not overwritten by this receipt carrier.
