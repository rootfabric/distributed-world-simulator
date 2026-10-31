# NET-SMOOTH1 P2.3 R2.2 — Source-fenced CURRENT COMPACT proof (Work Order / RU)

## Scope / точная база

Parent: R2.1 independently verified PR #830, PRODUCT_HEAD \`e01d371123e296b5c74d730eb5136bafc020ce41\`, TREE \`b13a18e91d2d9167e1a952f184dd4eb7a2392647\`. Separate Draft child branch. No merge, no main rewrite. Ранее: 60s Windows server p99 OFF 28.467ms, ON 26.287ms, норматив p99 <=25ms НЕ достигнут, не путать с эффектом R2.2.

R2.2 is a strict **default OFF**, opt-in server-only successor to R2.1. Runtime env: \`DWS_NET_R31P23R22_ATTESTED_COMPACT=1\`, CLI: \`--r31p23r22-attested-compact\`, requires R2.1+R2.0/persistence/R31a/P0/P1/P2.2 existing chain. Any invalid mode/dependency must abort startup.

## Proof architecture

Only the original **synchronous** simulator \`FrameScript.validate(frame)\` may authorize minting. On the same call stack and without yield, \`ENet.r22_prepare_validated_compact\` canonicalizes the same authoritative, detached current frame ONCE, retains exact private bytes and source ID, creates a single-use ticket with peer/session, sequence/frame_id, checksum, server authority owner/epoch, ENet route generation and packet SHA256. \`r22_send_prepared\` receives ONLY the ticket, not mutable frame/bytes. Its consume clears pending state before checking proof and verifies live source, peer, session, route generation, authority epoch, packet integrity. Original transfer channel/mode and put_packet are unchanged. No external proof, no wire field, no cache, no untrusted replay input; fail-closed on stale/reused proof. If corrupted native packet bytes are detected, preserve \`PAYLOAD_CHECKSUM_MISMATCH\`. Other frames and condition simulation retain original full validators, as do client inbound decoder and all M6/ACK and durable paths.

**Trust boundary / limitation:** attestation is internal proof for a trusted native synchronous call graph, NOT a remotely verifiable signature. A malicious arbitrary in-process Godot script able to call private runtime methods is outside this model. Native tests and source contracts must guarantee there is no external entry point from client/disk/replay, no source writes, and no yields between full validator and packet freeze. Authority change during a running server must invalidate the proof or fail closed; do not infer more than the configured authority epoch and ENet route-generation fence.

## Acceptance stages (stop on first failure)

1. Fresh exact-head source: inspect full diff, run \`python -m unittest discover -s tests/tools -p 'test_net_smooth1_r31p23r22_source_contracts.py' -v\` plus all inherited R2.1/R2.0 source tests. Require 0 failures and tracked-clean status. The frozen parent is exact ancestry.
2. Cold Godot import with **native 4.7.1.double a13da4feb** pinned binary (Windows wrapper SHA256 \`3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5\`; Linux canonical executable SHA256 \`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7\`), zero SCRIPT/Parse/Compile errors.
3. Native exact new R2.2 single-use/ABA/bad packet + inherited full 32-packet R2.1 parity, M6/USER1, seam and two-client tests on Linux AND Windows. Windows interactive session (not Session 0) must independently hash main EXE, wrapper, assets and report the actual GPU.
4. ONLY AFTER clean native: **one** 60s real two-client Earth+Quaternius GUI paired OFF/ON on **same exact R2.2 HEAD**, 20s warmup, both arms have R31a/P0/P1/R2.0/R2.1 ON; ON adds ONLY \`--r31p23r22-attested-compact\`. Keep raw server/a/b traces, metadata, exact spawn/exit receipts, capture all failed fresh JOIN attempts for issue #815. Compare p50/p95/p99 of simulator validate, attestation + ENet send, source ENet original validate (ON must disappear), packet-size parity and actual end-to-end server/client p99. No cherry-picking or unpaired host load.
5. If measurable advantage and safety all PASS: three independently instrumented 120s matched GUI pairs (3×OFF/ON), 20s warmup, p99 <=25ms, p999 <=50ms, max <=100ms, 59Hz+, no unaccounted >100ms gaps; 1800ms slow ITEM, hard-kill/restart replay/ACK checksum, 2-player A→B→A seamless, Project Control, issue #815 and P7.4 must be separately closed before merging.

The R2.2 CI merely verifies source/native; it is **not** a GUI performance claim. PR remains Draft; \`READY_FOR_MERGE=false\` even if source/native jobs pass until all independent release blockers close.

## Windows local agent minimal commands

\`\`\`powershell
$ErrorActionPreference = 'Stop'
git fetch origin
git worktree add --detach C:\dws-r22-exact origin/feature/net-smooth1-r31p23-r22-validated-wire-attestation-r1
Set-Location C:\dws-r22-exact
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
python -m unittest discover -s tests/tools -p 'test_net_smooth1_r31p23r22_source_contracts.py' -v
$G = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'
(Get-FileHash $G -Algorithm SHA256).Hash.ToLowerInvariant()
& $G --headless --editor --path . --import --quit
& $G --headless --path . --script res://tests/runtime/test_net_smooth1_r31p23r22_attested_compact.gd
& $G --headless --path . --script res://tests/runtime/test_net_smooth1_r31p23r21_single_pass_compact.gd
git status --porcelain --untracked-files=no
\`\`\`

For GUI run use the inherited PR #830 paired two-client harness/Job Guard Work Order; use exact new SHA/TREE, retain its required strict source/trace identity and add the single R2.2 flag only to ON, never force-process-kill other jobs.
