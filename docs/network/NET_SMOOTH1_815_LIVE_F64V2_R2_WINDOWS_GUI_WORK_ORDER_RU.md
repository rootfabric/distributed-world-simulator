# NET-SMOOTH1 #815 — F64-v2 LIVE M3: Windows independent staged GUI acceptance R2

## Objective and current release gate

Independently exercise **real two-client graphical M3 Earth with Quaternius**, a dedicated server, per-peer negotiated COMPACT schema and native ENet R2.2 attestation. This is the NEXT gate after the deterministic real Full→Compact→Frame corpus PR #864. Neither successful native policy tests nor a headless GitHub Action prove actual Windows GUI gameplay.

Base immutable PR #864: `cdc16f68f3d2871caa28dfd445472926ebdd1967`. Live Draft branch: `feature/net-smooth1-815-live-f64-v2-negotiation-r1`, PR #868. Freeze **current HEAD/TREE from PR #868** before running; never use a previous code SHA with a newer work order, and never silently rebase.

Product default **OFF**. Server `prefer_v2` + client A `require_v2` + client B `off` is a **same-build** mixed-mode test. Compatibility with an actually different old Git build is NOT yet proven because the existing fingerprint protocol requires matching build identities. There is no in-flight downgrade after checksum failure.

## G0 Exact verified Windows host

- Windows 10 interactive Session 1, NVIDIA RTX4060/OpenGL3 on two real Quaternius windows. Godot 4.7.1 double console SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`; main EXE separately SHA256 `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`.
- Quaternius 123 raw files, 101 sidecars, canonical raw-map manifest SHA `d0abf6650b2de9293e720c11981354ec403d7032adbc5f5b0c042655d2ce427d`. No fallback capsule as a substitute. Assets may be copied only from a previously independently audited local checkout; record exact source/hash.
- External Windows Job Guard #820 in a **separate** tools worktree exact HEAD `b4cbf565764cea16eb81cc163824b2a237e2cb8a`. Never stop other GitHub Actions runners or unrelated Godot processes. Ensure no overlapping CI/GPU-heavy tasks and capture ambient CPU/GPU.
- Clean import, exact native suites: `test_net_smooth1_815_live_codec_negotiation.gd`, PR #864 2048 corpus, actual USER1 service test, #815 sender guard, 83 safety negatives, R2.2 native, M6 recovery and product USER1 seam. Hosted source + pinned Windows/Linux CI should be read at *current* HEAD, not inferred from prior commits.

## G1 Real M3 native two-client experiment

Choose a NEW evidence root (not pre-existing) and run harness `tools/net_smooth1/run_net_smooth1.py` through the independent #820 Windows Job Guard. Use the exact pinned Godot console and current checkout.

Recommended named cases, each with **20s warmup + 120s original measured window** and unchanged canaries:

1. Control: server `off`, client A `off`, client B `off`. Legacy v1 only, preserve full original report.
2. Mixed: server `prefer_v2`, client A `require_v2`, client B `off`. REQUIRE handshake traces and actual v2 packets from server to A, while B stays v1.
3. Required-v2 negative: server `require_v2`, client A `off`, client B `off`. Must fail cleanly **before JOIN**, not by checksum bypass. Run separately: do NOT merge this negative into the measured paired benchmark.

All functional controls use server `--max-fps 60` and 60Hz authority, ~20Hz COMPACT publication, same LOCAL conditions, two active Earth Quaternius clients and `r31-reconnect-roundtrip` A→B→A and B reconnect.

Common flags for (1)/(2):

```text
--mode gui --scenario r31-reconnect-roundtrip --duration 120 --warmup 20 --profile LOCAL
--r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased
--r3c3-staged-earth --r3c21-frame-paced-presentation
--r3c4-periodic-frame-pacing --r3c4r2-worker-envelope
--r3c4r31-replay-projection --r3c4r31b-durable-attribution
--r31bp1-durable-chunks --r31p22-loop-attribution
--r31p23r2-flush-attribution --r31p23r21-single-pass-compact
--r31p23r22-attested-compact
--r31-815-compact-server-mode prefer_v2
--r31-815-compact-client-a-mode require_v2
--r31-815-compact-client-b-mode off
```

For the legacy control, the last 3 flags are explicitly `off`. Give every arm a distinct run root, run ID, exact HEAD/TREE, Job Guard receipt `CLEAN_JOB_EMPTY` and SHA256 manifest. Do NOT suppress exit 1 caused by original p99 FAIL. Native process cleanup must still be independently verified.

## G2 Fail-closed evidence

For the mixed case, independently verify:
- Original fingerprint HELLO/ACK checksum and session/handshake ID, selected server and client mode. Server should have **one v2 recipient and one v1 recipient**.
- Original frame bytes/outer checksum and versioned COMPACT `h`; restored original FullSnapshot `c`. No alternative decoder after checksum failure.
- `r31_815_compact_v2_sent` on server and `r31_815_compact_v2_received` on actual GPU client A; B has no v2 receipt and **must have accepted legacy COMPACT snapshots** (not just a packet-received marker).
- Reconnect must reset negotiated format and repeat handshake on new transport session/epoch. A→B→A and M6 durable-before-ACK must still work.
- Actual two-client rendering + Quaternius, no fallback avatar, movement/remote player positions, no lost ITEM Graph, no resource/Construction regression.
- Three complete trace headers/END with dropped=0, three measure.end.ack, raw manifests and original per-role performance reports.

Original normative limits apply when assessing perf: server AND both clients p99≤25ms, p999≤50ms, max≤100ms; server fixed tick≥59Hz and ~20Hz COMPACT. **No performance acceptance** solely from successful version handshake or absence of checksum incidents. Also report actual server >25ms gaps per SECOND so increased event count cannot dilute p99.

The #815 historical actual packet cause is still unproven: a successful live v2 test demonstrates mitigation in its scope but does NOT reclassify the old R1/R2 Windows evidence.

## G3 Publication and merge policy

Publish immutable final results in Draft #868 and issue #815/#850: exact HEAD/TREE, verified Windows binaries/raw assets, all native and GUI tests, legacy/control vs mixed raw traces, original scoreboard, v2/v1 per-client source+RX evidence, complete reports/SHA256, Job Guard receipts, source/Win/Linux CI IDs, no security waivers. No merge or production rollout. Treat a valid native GUI test as `WINDOWS_GUI_V2_CANDIDATE_PASS`, **not** production accepted until Linux staging and independent release gates also complete.

Do not enable v2 globally, do not change standard server FPS from 60 to 120, do not change the accepted packet schema under old peers, and do not merge into main. `READY_FOR_MERGE=false`.
