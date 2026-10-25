# NET-SMOOTH1 #815 — FLOAT64 JSON WIRE FORENSICS: Windows R1 Work Order

## Purpose / identity

Check source→receiver identical raw-packet SHA around real 120FPS Earth rebuild ~31.5s checksum abort. Freeze EXACT HEAD/TREE of new #815 forensic Draft; direct parent is PR #859 product HEAD 38d62f5bc6143b6d5f4e0b95ff91adbb7e0a13a4 / TREE 6edde63203bb5fdea52e227010f548ff4f850542. MAIN unchanged, no merges.

## Independently reproduced native mechanism

On uploaded exact Godot 4.7.1.double a local numeric JSON canonical text fuzz changed after JSON.parse in 22,455/60,000 samples. Frame.create-style one-roundtrip/send-validate/encode/receive-parse checksum pattern failed in 543/4,000 deterministic pseudo-JOIN payloads WITHOUT a single byte changed in transit. Many double values oscillate if repeatedly JSON-parsed. This is strong #815 root-cause CANDIDATE, not proof that reported Windows 120FPS packets were affected by the same thing. New native script test_net_smooth1_r31_815_float_wire_repro.gd exercises REAL Frame.create → validate → encode → decode. Native PASS on this diagnostic test means BUG REPRODUCED, not FIXED.

## Exact read-only opt-in

Original FrameScript.validate/decode and ENet put_packet, session/authority/ACK/M6 remain unchanged. Diagnostic helper r31_815_wire_checksum_forensics.gd logs ONLY packet sha256, frame_id, hashed peer/session, declared checksum, parsed recomputed checksum, sender dictionary hash where available, payload TYPE (not content), original error. No wire bytes or raw player snapshot included. 16,000 events bounded per process, Trace footer must be complete with dropped=0. Disabled by default; explicit CLI flag --r31-815-wire-forensics activates environment for server/client A/client B. Because it adds diagnostic work, ANY perf p99 result is NON-NORMATIVE.

## Windows G0: fresh independent environment

Windows 10 Session1 RTX4060 Godot 4.7.1.double pinned console SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5. Record actual Godot main EXE hash separately. Product detached immutable forensic HEAD/TREE and 123 raw Quaternius exact asset SHA d0abf6650b2de9293e720c11981354ec403d7032adbc5f5b0c042655d2ce427d. Job Guard Draft #820 exact HEAD b4cbf565764cea16eb81cc163824b2a237e2cb8a in SEPARATE tools worktree. No killing foreign processes/CI jobs. Import errors, tracked-dirty, wrong GPU/bin/assets => STOP/INCONCLUSIVE.

First run exact GDScript negative tests on frozen branch: tests/runtime/test_net_smooth1_r31_815_float_wire_repro.gd, test_net_smooth1_815_safety_negative.gd and test_net_smooth1_r31p23r22_attested_compact.gd; exit0/0 native errors. Check source CI and exact Windows/Linux native on same HEAD.

## G1: live targeted checksum incident, not performance

Through unchanged tools/net_smooth1/run_net_smooth1.py under exact external Job Guard run at most six independent real GUI Earth+Quaternius groups, order 60→120→120→60→120→120. Each arm has its own unique run root and original stdout/trace/manifest/report/receipt, 20s warmup and 120s measured if functional scenario survives.

Required common flags for EVERY arm:

    --mode gui --scenario r31-reconnect-roundtrip --duration 120 --warmup 20 --profile LOCAL
    --r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased
    --r3c3-staged-earth --r3c21-frame-paced-presentation
    --r3c4-periodic-frame-pacing --r3c4r2-worker-envelope
    --r3c4r31-replay-projection --r3c4r31b-durable-attribution
    --r31bp1-durable-chunks --r31p22-loop-attribution
    --r31p23r2-flush-attribution --r31p23r21-single-pass-compact
    --r31p23r22-attested-compact --r31-815-wire-forensics

Only difference: --server-max-fps 60 or 120, and the EXISTING product opt-in flag is injected by the runner only on 120. Do not force additional JOIN/RESET instructions that change workload. Historical premeasure event was client A at t≈31.5s after Earth rebuild. A first fatal checksum abort is an EXPECTED diagnostic RED but remains a product SAFETY_FAIL, not a successful scenario.

## G2: independent exact packet correlation

Run Python analyzer on ORIGINAL unmodified run roots:

    python tools/net_smooth1/analyze_r31_815_wire_fingerprints.py <RUN_ROOT> --output <NEW_JSON_PATH>

Receipt must include 3 process trace complete footers and original manifest/report, exact source, no event loss. Analyzer uses packet SHA256 and frame_id, NOT timestamps from unrelated processes. A tx_enet source-valid checksum with postparse mismatch, same SHA256 on rx_reject and original PAYLOAD_CHECKSUM_MISMATCH establishes ACTUAL sender-valid/receiver-failing numerical JSON drift. If sender hash absent, packet differs or trace lost → ROOT_CAUSE_UNPROVEN. An incident-free retry never closes #815.

Security fences: never change FrameScript checksum validation, never use tolerance/rounding to silence checksum, never remove packet loss, never publish raw payloads. An alternate numeric-wire protocol repair would need a separate explicit product PR with unchanged genuine tamper detection, normal M6/USER1 exact, Windows/Linux native and real Earth rebuild regression.

## Report to #815, Draft forensic PR and WO #850

Publish exact HEAD/TREE, console/main EXE hashes, two-server? NO: one native dedicated server + 2 real graphical clients, original packet fingerprints by frame_id/SHA, reason/time around first failure, each original runner verdict, trace/footer SHA256, clean Job Guard and 123 raw assets manifest. Classify ROOT_CAUSE_PROVEN_FOR_ACTUAL_PACKET only with matching source+receiver SHA and sender checksum evidence. No arbitrary timestamps and NO GUI_PERF_PASS claim.

Final status: DIAGNOSTIC_SOURCE_NATIVE, no 90FPS acceptance yet, original #859 PERF_FAIL, #815 OPEN, Project Control RED, SEAM-E2E multi-host separate, READY_FOR_MERGE=false.
