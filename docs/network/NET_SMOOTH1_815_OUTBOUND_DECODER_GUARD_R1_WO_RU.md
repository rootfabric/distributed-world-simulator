# NET-SMOOTH1 #815 — R1 Outbound Strict Receiver Preflight — Windows Exact Work Order

## Intent / status

This is a **fail-closed containment candidate**, NOT a proven float64-wire repair. Historic incident #815 remains OPEN, earlier PR #859 120FPS GUI_PERF_FAIL remains unchanged. The exact issue: Godot 4.7.1 double sometimes serializes a `float64` value such that its own strict `FrameScript.decode()` rejects the resulting packet (`PAYLOAD_CHECKSUM_MISMATCH` or `NON_CANONICAL_FRAME`) even though original frame was valid at sender. The preflight prevents known-bad bytes from leaving *this server*; it does not change JSON parsing, recalculate/waive checksum, or guarantee every snapshot can be delivered. Future permanent protocol work needs stronger evidence and separate review.

## Freeze and scope

Branch: repair/net-smooth1-815-outbound-decoder-preflight-r1, direct child of forensic Draft PR #862 HEAD e4c9fe490f715abd94a8e99ff3a865e73e4ec9fd, in lineage of #861/#859. Freeze HEAD/TREE from THIS new Draft PR before execution. No rebase, force, main mutation, or merge.

Original `FrameScript.validate`, `FrameScript.decode`, `Enet.put_packet`, R2.2 one-use source/epoch/session/route fences, M6 ACK/durable writer, USER1 seam, 60Hz fixed tick, ~20Hz COMPACT publication, raw packet format all unchanged. New SERVER-ONLY environment `DWS_NET_R31_815_OUTBOUND_DECODE_GUARD=1` is enabled only by external runner `--r31-815-outbound-guard`, which requires `--r31-815-wire-forensics`. Default OFF and BOTH client processes unchanged.

Both branches of native ENet send are guarded: original R2.1/legacy after frame encodes, and R2.2 attested COMPACT immediately after immutable packet capture **before minting single-use proof**. On exact `FrameScript.decode(packet)` failure returns `R31_815_OUTBOUND_RECEIVER_REJECTED`, nested decoder error included, packet never goes to ENet. Actual inconsistent sender frame or real tamper still FAIL-CLOSED. The existing simulator may **drop UNRELIABLE** COMPACT instead of delivering and retain/retry a RELIABLE message. This containment can create visible interpolation gaps, so it is not a release acceptance.

## G0 — native pinned Win/Linux exact and source

1. Worktree clean detached exact product HEAD/TREE; separately pinned Job Guard tooling at HEAD b4cbf565764cea16eb81cc163824b2a237e2cb8a. Godot 4.7.1.stable.double.custom_build.a13da4feb console SHA 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5, record separately main Godot `.exe` SHA historically prefix 6464da35. Windows 10 real interactive Session1, NVIDIA RTX 4060. Do NOT stop a foreign runner/editor or foreign Godot.
2. Quaternius full original asset pack: **123 raw source files** (plus 101 `.import` sidecars = 224 total), exact RAW asset hash d0abf6650b2de9293e720c11981354ec403d7032adbc5f5b0c042655d2ce427d. Original `manifest.identity.asset_count` always 123. If only fallback avatar is present, STOP, restore canonical pack, do not lower gate.
3. Exact cold import 0 SCRIPT/Parse/Compile errors; new native test `test_net_smooth1_r31_815_outbound_decode_guard.gd` must show at least one true RED witness (original source Frame.validate+Frame.encode PASS while receiver Frame.decode FAIL), and GREEN preflight denial BEFORE ENet, default OFF bytes identical, real corruption still rejected. Original native tests `test_net_smooth1_r31_815_r22_original_sender_attestation.gd`, `test_net_smooth1_r31_815_float_wire_repro.gd`, `test_net_smooth1_815_safety_negative.gd`, `test_net_smooth1_r31p23r22_attested_compact.gd`, plus M6/USER1/P1 boundary and focused 35+ tests must PASS. Windows/Linux exact CI on frozen SHA must both be GREEN.

## G1 — 6-arm NON-NORMATIVE real GUI campaign (source code already checked in)

Run `tools/net_smooth1/run_r31_815_guard_windows.ps1` from the frozen worktree, passing Product, GuardTools, NEW Evidence folder, ExpectedHead and ExpectedTree. Example (replace exact SHA/TREE with current PR values, first verify them, do not invent paths):

    pwsh -NoProfile -File C:\dws-815-guard\tools\net_smooth1\run_r31_815_guard_windows.ps1 -Product C:\dws-815-guard -GuardTools C:\dws-b3-tools -Evidence C:\EVIDENCE\NS1_815_GUARD_R1 -ExpectedHead <EXACT_PR_HEAD> -ExpectedTree <EXACT_PR_TREE>

Fixed order: 60FPS guard-OFF → 120FPS guard-OFF → 120FPS guard-ON → 60FPS guard-OFF → 120FPS guard-ON → 120FPS guard-OFF. All 6 arms use the full R31 scenario, one real dedicated Earth server and **two graphical OpenGL3 Quaternius** clients, 20s warmup+120s measured where functionally valid, same fixed M6/P1/R2.2 attested flags and `--r31-815-wire-forensics` in ALL 3 actors. Only `--r31-815-outbound-guard` toggles SERVER-only guard and `--server-max-fps` changes 60 versus 120. No 90FPS/perf acceptance yet.

The script uses external B3 Job Guard per arm, exact IDs, immutable raw traces, original runner `report.json` (can remain FAIL/INCONCLUSIVE), complete trace END/dropped=0, `measure.end.ack` when present and verifies CLEAN_JOB_EMPTY. Each arm has a separate run_id and fresh new evidence root. Never cherry-pick only successful runs. A job guard exit 1 caused solely by the original runner PERF_FAIL is NOT a performance PASS; process ownership must still be separately verified.

## G2 — decisive safety comparison

Read-only `analyze_r31_815_wire_fingerprints.py` now reports `outbound_guard_reject_count`, each refused exact packet/frame hash and original strict decoder reason. Must demonstrate **no `tx_enet`/`rx_enet` of the exact rejected SHA+frame ID** on guarded runs. If native packet was rejected by sender, client must NOT report PAYLOAD_CHECKSUM_MISMATCH on same packet. If guarded run drops UNRELIABLE snapshots, report exact count and visible client prediction/interpolation behavior; never relabel packet drops as smoothness PASS.

Must preserve original 120FPS unguarded incident data and keep all original server/client p99/p999/MAX, epoch/session, M6/ACK, 20Hz snapshot attempts, 60Hz fixed tick. The guard adds heavy JSON/sha work and can change p99; EVERY new run is forensic DIAGNOSTIC_ONLY. If client session disconnects, original checksum error still occurs, or guard leaks refused bytes: SAFETY_FAIL and publish raw evidence. If guarded run has 0 RX checksum rejects but also 0 guard hits, state ONLY `NO_INCIDENT_OBSERVED`, not `#815 FIXED`.

## G3 — report / no merge

Post independent report to the new Draft PR, #815 and WO #850 with exact HEAD/TREE + console/main hashes, 123 raw manifest, six run_id/sha256 inventories/JobGuard receipts, original outcome and per-role raw traces, counts of preflight blocked SHA and client rx_rejects, original p99 and actual gameplay client behavior, M6/USER1/reconnect. Confirm ALL validators remain unmodified, original genuine 1-byte mutation still fails checksum. Do NOT merge, change p99 norms or production 120FPS default. Historical #815 root cause and Project Control stay OPEN. `READY_FOR_MERGE=false`.
