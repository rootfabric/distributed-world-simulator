# NET-SMOOTH1 R3C.4 R2 — exact periodic worker-envelope repair

Parent: `ced03db64eae3adaab270044574c0f8b96c590c6`, R1 fresh Windows GUI evidence: server frame p99 38.0–39.6ms >25ms, p999 44–46ms. R1 source + local runtime tests passed; R1 other branch #786 has independent Windows/Linux exact. No auto-merge of divergent R1 implementations.

R2 is a **server-only opt-in**: `--r3c4-periodic-frame-pacing --r3c4r2-worker-envelope`. Retains exact R1 64ms periodic dispatch pacing, existing single checkpoint worker, command durable-before-ACK, snapshot/replay/ownership generations. Invalid mode or R2 without R1 fails closed. Legacy path default OFF.

R2 captures a detached `service.export_durable_state()` and `replay_outbox.to_dict()` together on the authoritative frame. The existing worker deep-copies both BEFORE wakeup, constructs the normalized M6 envelope and SHA256, calls the unchanged `Checkpoint.create` and `repository.save_atomic`. The expensive service DTO export remains on main; do not claim multi-frame source export. This design avoids mixed-tick state and live-reference transfer.

Native GDScript negative and exact tests: wrapped envelope == legacy (dictionary plus final disk checksum), post-submit caller mutation cannot alter disk, invalid DTO rejects with no disk mutation, default-off behavior, worker generation+ACK parity, checkpoint disk restore; retain R1/M6/ITEM/reconnect/CHAR/Earth matrix. Pinned Windows double SHA `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`, Linux double SHA `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`.

**GUI Work Order**: On real Windows 10 `DESKTOP-QNAGSTI`, fresh source and Quaternius assets installed, pin exact HEAD/TREE and Godot SHA. Run 3 paired OFF (R1 flag on, R2 flag off) vs R2 ON, on same HEAD OpenGL3 900x600 VSync disabled max60fps, 120s measured `--scenario r31-reconnect-roundtrip`, 2 live Earth+Quaternius clients and server. Common `--r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased --r3c3-staged-earth --r3c21-frame-paced-presentation --r3c4-periodic-frame-pacing`. Add `--r3c4r2-worker-envelope` only to candidate, unique output directories. Run 3×slow ITEM writer=1800ms, durable crash/restart, ACK escrow, generation ordering, idempotent replay.

Use normative `tools/net_smooth1/analyze_net_smooth1.py` unmodified. Strict per-client/server p99<=25ms, p999<=50ms, client max<=100ms, server loop>=59Hz, 0 checksum/replay/ACK violations, 0 dropped trace. Compare checkpoint_capture.authority_ms and checkpoint_complete.wrap_ms. If p99 still >25, PERF_FAIL, do not merge. A next revision for true multi-frame source DTO capture would need an immutable/versioned service projection; never read live state over multiple ticks without a mutation fence.

Canonical Project Control generation 82→83 remains owned by CONTROL_DEVELOPMENT (PR #783). Synchronous command durable drain is separate M6 Work Order. No merge/force push/4h soak.
