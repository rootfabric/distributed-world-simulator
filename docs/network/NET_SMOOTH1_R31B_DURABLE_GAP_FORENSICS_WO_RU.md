# NET-SMOOTH1 R3C.4 R3.1b P0 — Durable stages and long-gap forensics

## Evidence and decision

Independent Windows R3.1a PR #797 HEAD 02cba1e7e0fb5126ffef9928b1eef1bad2213e01, TREE c7c2482380e62fa89137d5b4814f86984a8792cf.
VERDICT: FUNCTIONAL_PASS / PERF_FAIL / NO_MERGE. The unchanged R3.1a replay cache achieved 97.47% hits, zero bypass, replay p50 26–28ms to 0.14–0.17ms, and checkpoint capture p50 ~11.7ms.
Server frame p99 OFF→ON 35.07→27.82, 34.84→26.41, 35.25→27.63ms: all exceed 25ms. Every ON server GUI run reported >100ms frame/loop gaps, max 132.11/136.47/138.52ms; OFF max 48.99/68.44/56.16ms. Underlying cause NOT established. Absence of a nearby engine event does not prove host scheduling noise.

## What this isolated branch implements

Parent: exact frozen R3.1a PR #797 HEAD. This is P0 MEASUREMENT ONLY, not the gameplay chunk cache P1 and not a new performance fix.

1. Server-only DWS_NET_R3C4_R31B_DURABLE_ATTRIBUTION=1 / --r3c4r31b-durable-attribution. Requires enabled R3.1a R2 and USER1 ProductSeam. Invalid modes and missing prerequisites fail closed. Default OFF.
2. User1 ProductSeam new export_durable_state_r31b_profiled() builds the EXACT accepted durable DTO at ONE QUIESCENT authority boundary (no multi-frame read of mutable service). It exposes snapshot_ms, players_ms, ownership_ms, shared_item_ms, item_graph_ms, resource_ms, final_checksum_ms, validation_ms and total_ms. The existing export_durable_state() path and its checksum and validation are untouched.
3. Existing M6 adapter returns the same frozen DTO to the SAME single writer; no Node/Resource/live mutable alias crosses threads, command durable-before-ACK/generation unchanged. New checkpoint_capture.r31b_durable_stages is diagnostic-only.
4. tools/net_smooth1/analyze_r31b_durable_stages.py derives per-domain measured p50/p95/p99/max from measured ON capture events, rejects malformed stage coverage, invalid seam, accounting mismatch. Stage p99 values cannot be added to infer total p99.
5. tools/net_smooth1/diagnose_r31_long_gaps.py independently analyzes the HISTORIC six R3.1a raw trace roots. It finds frame >50/>100ms and local ±125ms associations to checkpoint capture, checkpoint completion, movement snapshot stages and server_loop.process_ms. Process clocks must never be aligned across processes. Proximity is not causality.

## Immediate offline diagnostic, no new GUI runs required

Copy the new Python tool from this branch to a safe verifier checkout. On DESKTOP-QNAGSTI using the EXISTING six R3.1a directories run:

    python tools/net_smooth1/diagnose_r31_long_gaps.py --pair "C:\dws-ns1-r31a-pair1-off" "C:\dws-ns1-r31a-pair1-on" --pair "C:\dws-ns1-r31a-pair2-off" "C:\dws-ns1-r31a-pair2-on" --pair "C:\dws-ns1-r31a-pair3-off" "C:\dws-ns1-r31a-pair3-on" --output "C:\dws-r31b-forensics\historical_long_gaps.json"

The tool validates manifest head+Godot+assets equality per pair, completed real GUI LOCAL R31, raw trace header/end and clock monotonicity. Do not edit old raw traces. Summarize observed server process duration at gap time and nearby stages. Separately collect host scheduling/rendering/GC/DPC/GPU evidence if available, otherwise leave cause UNKNOWN. Keep abnormal ON gaps as blocking.

## New R31b exact Windows GUI matrix

Fresh detached worktree exact new R31b P0 HEAD + TREE; never mix R3.1a prior HEAD measurements into a same-HEAD A/B result. Quaternius real Earth avatar, OpenGL3 900x600 VSync off max 60fps, two real clients, 20s warmup and 120s measurement, scenario r31-reconnect-roundtrip; 3 paired OFF and ON, alternate order.

Both arms use flags:

    --r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased --r3c3-staged-earth --r3c21-frame-paced-presentation --r3c4-periodic-frame-pacing --r3c4r2-worker-envelope --r3c4r31-replay-projection

ON ONLY adds:

    --r3c4r31b-durable-attribution

This compares instrumentation observer overhead (not a cache optimization). Run unmodified normative analyze_net_smooth1.py on each trace. For each ON trace:

    python tools/net_smooth1/analyze_r31b_durable_stages.py <run>/server/trace.jsonl --output <run>/r31b_durable_stages.json

Record both Godot wrapper and MAIN engine SHA256; wrapper pin alone does not establish main executable build identity. Preserve exact replay/authority, server/client p99/p999/max, 59Hz, Quaternius and per-run raw logs. Run native tests including test_net_smooth1_r31b_durable_gap_forensics.gd; independent M6 disk/ACK/replay/ITEM crash restart proof and separate slow ITEM, no claim of inherited #796 merged retry.

## Next step — R31b P1

Only after source attribution choose the actual costly domains. If Item Graph or ResourceMining immutable chunks matter, implement them in a new isolated branch with explicit monotonic mutation invalidation, revision/authority epoch/tick consistency, bounded memory, caller poison, restore and seam transfer falsifiers. Never cache cross-tick mutable player positions or read live service on worker.

NO_MERGE / NO_FORCE / NO_MAIN_CHANGES. Normative server/client frame p99 <=25ms, p999 <=50ms, max <=100ms, server sim >=59Hz; zero M6 checksum/replay/ACK/authority violations and missing traces. Any unexplained >100ms ON gap remains blocking. Project Control registry rotation and SEAM-E2E remain independently required.
