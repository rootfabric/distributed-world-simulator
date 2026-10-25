# NET-SMOOTH1 #815 R2 — original R2.2 source checksum attestation: WINDOWS EXACT WORK ORDER

## Existing R1 evidence — do not discard

Independent Windows R1 at C:\distributed-world-simulator\ns1-815-wire-r1\ ran six genuine Earth + two Quaternius-client arms on Draft #861 HEAD e488a1117d3f2f5bd335c32214082ecb126656e9. Arm2 (server cap 120) rejected two COMPACT_GAMEPLAY_SNAPSHOT frames, one at client A 31,641ms about 2.35s after Earth rebuild, and one at client B. Both packet SHA256 and frame_id MATCH an exact ENet sender record, but R1 analyzer classified SAME_EXACT_PACKET_REJECT_CAUSE_NOT_PROVEN; its aggregate sender_postparse_mismatch_count was zero.

**Specific now-proven R1 FORENSICS DEFECT:** R2.2 immutable attested send called _r31_815_emit_wire(tx_enet, peer_id, packet) WITHOUT source Dictionary. inspect_packet(... sender_frame={}) therefore assigned sender_dictionary_payload_sha256='' and sender_checksum_matches=null for EVERY real attested R2.2 compact. The strict correlator counted drift only if sender_checksum_matches IS true, so old sender_postparse_mismatch_count=0 does NOT exclude parse drift. This explains missing diagnosis, NOT necessarily the native product failure.

## R2 scope — isolated new branch, not a network repair

R2 is strict child of R1 Draft #861; do not edit or merge original #861, #859 or main. In r22_prepare_validated_compact (only when explicit forensic opt-in), hash the ORIGINAL source-validated frame payload and attach it to private one-use proof. _r22_take_attestation forwards hash in private success details ONLY when opted in; byte-for-byte packet, payload_checksum, session, route, epoch and code paths unchanged. r22_send_prepared passes the hash into SHA-only tx_enet forensic metadata. Default OFF produces the exact former private proof shape and send behavior.

Read-only analyzer v2 preserves original report and old R1 traces. For each rejected packet it reports source hash provenance, source-to-frame checksum match (True/False/null), TX and RX postparse checksums/matches, source role and classification. New classes distinguish original missing R2.2 sender attestation from same-packet source-valid/postparse mismatch and from unusual TX/RX parser divergence. IMPORTANT: even proven same-byte postparse mismatch does not establish specifically which float field changed; numeric_root_cause_proven remains FALSE absent field-level proof.

## G0 — exact Windows/CI

Freeze new Draft R2 exact HEAD/TREE from GitHub. Check direct ancestry of e488a1117d3f2f5bd335c32214082ecb126656e9, clean detached worktree, pinned Godot 4.7.1.stable.double.custom_build.a13da4feb, console SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5. Separately hash main executable (historic 6464da35…01a4), GPU RTX4060 Session1, Quaternius 123 RAW assets SHA d0abf6650b2de9293e720c11981354ec403d7032adbc5f5b0c042655d2ce427d and Job Guard #820 b4cbf565764cea16eb81cc163824b2a237e2cb8a in a separate worktree.

Require clean Godot cold import, full source unit tests, the **new** tests/runtime/test_net_smooth1_r31_815_r22_original_sender_attestation.gd, existing float64 RED test and old #815 safety 83/0 and R2.2 native 283/0, plus pinned exact Windows/Linux jobs. The new test must prove original source checksum is present and true only when forensics ON; OFF sends identical bytes without any new proof field. No change to FrameScript.validate/decode or ENet put_packet.

## G1 — reread original R1 immutable evidence BEFORE any fresh GUI

Do not infer the exact per-arm directory structure from its name; enumerate the existing manifest.json files recursively and locate true run roots with server/a/b/trace.jsonl. First compute/store SHA256 of every existing manifest/report/trace; NEVER mutate them. For each run:

    python tools/net_smooth1/analyze_r31_815_wire_fingerprints.py <ORIGINAL_R1_RUN_ROOT> --output <NEW_R2_REPORT_OUTSIDE_ORIGINAL_R1_ROOT>

Arm2 must show 2 decode rejects and exact source SHA/frame matches, but `sender_original_proof_missing_count` is nonzero because R1 had no original-frame hash. Preserve both `tx_postparse_checksum_matches` and `rx_postparse_checksum_matches`: TRUE at TX and FALSE at RX for same bytes suggests parser inconsistency rather than a proven sender-postparse drift; FALSE at both without source attestation remains INSUFFICIENT. Never reclassify the historical incident as FIXED by reparsing old traces.

## G2 — new native live re-reproduction (non-normative)

On exact NEW R2 HEAD use the existing tools/net_smooth1/run_net_smooth1.py under external B3 Job Guard (CLEAN_JOB_EMPTY), one headless dedicated Earth + two actual GPU Quaternius clients, r31-reconnect-roundtrip/LOCAL, 20s warmup + 120s measurement when possible. Use both 60 FPS original and 120 FPS server-only opt-in; alternate candidate/baseline with at most six new unique groups. DO NOT run 90 FPS until #815 addressed. Every arm must use the exact same verified full M6/P1/R2.2 flags and add --r31-815-wire-forensics to *all* processes via runner:

    --mode gui --scenario r31-reconnect-roundtrip --duration 120 --warmup 20 --profile LOCAL
    --r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased
    --r3c3-staged-earth --r3c21-frame-paced-presentation
    --r3c4-periodic-frame-pacing --r3c4r2-worker-envelope
    --r3c4r31-replay-projection --r3c4r31b-durable-attribution
    --r31bp1-durable-chunks --r31p22-loop-attribution
    --r31p23r2-flush-attribution --r31p23r21-single-pass-compact
    --r31p23r22-attested-compact --r31-815-wire-forensics

Only --server-max-fps 60 versus 120 differs. Script must preserve all failures, initial JOIN and Earth rebuild timing, actual checksum errors, all original role reports, 3 complete trace footers/measure ACK, asset/engine/identity hashes, and owned process cleanup receipt. Forensic extra SHA/JSON costs mean every frame p99 result is DIAGNOSTIC_ONLY; original #859 120 FPS GUI_PERF_FAIL unchanged.

Run exact same read-only v2 analyzer on each run, OUTSIDE original run root. The evidence gate to classify an actual failure requires SAME packet SHA256/frame ID, TX original source hash TRUE with R22_ORIGINAL_VALIDATED_FRAME provenance, TX parsed checksum comparison, RX parsed checksum comparison, and original FrameScript.decode rejection. Source attestation FALSE or TX/RX parse divergence requires more diagnosis; don't patch checksum based on assumption. If no actual failure, retain #815 OPEN.

## G3 — publish

Post source-native Win/Linux exact SHA and test counts; original R1 retro-analysis (hashes unchanged); fresh R2 native actor metadata for any real rejected COMPACT, source/tx/rx hash and time relative to Earth rebuild. Classify `R22_PROOF_REPAIRED / HISTORICAL_PACKET_UNATTESTED / LIVE_CAUSE_PROVEN_OR_UNKNOWN / ISSUE_815_OPEN / GUI_PERF_FAIL / READY_FOR_MERGE=false`.

Never log raw player payload/tokens, waive SHA checks, stop unrelated CI, merge to main, or infer float64 from p99 improvements. A numeric-wire protocol fix is a SEPARATE tightly scoped product PR after exact same-packet evidence.
