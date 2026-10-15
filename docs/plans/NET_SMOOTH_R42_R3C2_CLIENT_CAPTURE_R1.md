# NET-SMOOTH1 R4.2 R3C.2 — CLIENT ATTACH / PHASED ITEM PUBLICATION

**Work Order:** `NET-SMOOTH1-R42-R3C2-R1`  
**Base:** R3C.1 independently Windows narrow-verified `c68f35b68203e812f81e87b56fc3a76b37da58a3`, PR #766  
**Scope:** small opt-in visual/replication/performance repair, no new network/authoritative owner  
**Status:** implementation candidate, awaiting fresh independent Windows GUI and M6 verification, merge prohibited

## Input evidence and precise remaining problems

R3C.1 Windows exact source/runtime 17/17 suites (~7040 assertions) PASS; async LEAVE/JOIN queued and 3/3 ITEM network canaries have GATE A PASS, no early ACK/checksum leaks. GATE B FAIL: baseline client CONNECTING→CONNECTED 3.1–3.3 s freeze without ITEM writes; server ~44Hz and 400–490ms gaps after slow-item durable completion; main-thread persistence 208–239ms. Crash before/after commit not both proven. `slow_item_writer_ms` omitted manifest despite real injection.

## R3C2.1 — Real client visual prewarming

- Existing `JOIN_ACK` synchronously emits `session_ready` and attaches Earth+P3, constructs remote Quaternius rig via `ResourceLoader.load()` and `PackedScene.instantiate()`. The new `DWS_NET_R3C2_AVATAR_PREWARM=1` (harness `--r3c2-avatar-prewarm`) prewarms exactly one external visual in Earth `_ready`, **before** client network admission, and caches at most two retired remote visuals keyed by logical ID.
- When a remote reconnects, the existing Quaternius AvatarHost is reused, while old NX5 delegate is freed and a new delegate is created with the new canonical session/snapshot epoch. No fabricated server tick, no stale interpolation, avatar authority always false, legacy capsule remains hidden. Disabled/default still creates presenters on demand.
- Bounded trace events `r3c2_join_ack_breakdown` (snapshot/item/prediction/report/replica signal/session_ready), `r3c2_client_connect_attach`, `r3c2_earth_attach`, `r3c2_resource_attach` distinguish JOIN_ACK runtime, Earth visual, Item and Resource costs. The prewarm itself occurs while loading Earth (may still cost seconds on startup). This is **not** yet proof that 3s CONNECTED stalls are gone: measure real before/after.

## R3C2.2 — Phased M6 ITEM completion

- `DWS_NET_R3C2_PHASED_ITEM_PUBLICATION=1` (harness `--r3c2-server-phased`) still uses the existing M6 proof and single writer. On exact durable completion retain M6 ACK and visibility gates; process one stage per server loop: (0) canonical after ITEM snapshot, (1) delta, (2) exact-session ACK or replay quarantine via original proof, (3) ITEM broadcast, (4) full gameplay resync + pending waiter flush. Durability/generation first, ACK only once eligible, no new command or periodic generation overtakes unfinished publication.
- An unbounded `_write_report()` path still did full gameplay+replay export and synchronous diagnostic file IO after each ITEM completion. R3C2 defers this non-authoritative diagnostic report from the frame-critical stage; the durable source is the M6 repository, completion and raw trace. Final explicit stop still writes the full diagnostic. This optimization is opt-in and does not change checkpoint, ACK or gameplay authority.
- No changes to canonical M6 replay state, checksum schema, ownership, player/item authority, construction truth or commit generation. Debug events report each stage duration, with no heavy event-copy of world state.
- **New R3C2 narrow performance repair:** ITEM `create_canonical_item_graph_snapshot()` was already computed and checksummed during the pre-worker capture. In the opt-in path the detached `after_item_frozen` DTO is retained under the original pending M6 operation and reused, with its exact checksum checked at stage 0; no second full graph export on durable completion. Only the frozen root envelope is shallow-copied on completion; default/non-opt-in retains deep copy. The periodic checkpoint worker-completion handler now defers `_write_report("READY", false)` only when R3C2 opt-in is active; this JSON report is diagnostic and is NOT the atomic checkpoint or ACK proof. Trace records the deferred report count. Full replay/authority capture remains unchanged and can still violate budget.
- **Critical limitation:** splitting large main-thread capture/replication work across frames does not guarantee a hard <=50ms frame. `_recovery_authority.export_recovery_state()` and `_replay_outbox.to_dict()` still export/serialize full checkpoint on the main thread. If stages/capture exceed 50ms, GATE B **FAIL** and next bounded repair must isolate/version immutable captures.

## R3C2.3 — Tooling

- Exact integer `slow_item_writer_ms` now written in every `manifest.json`. Full-trace R3 ITEM analyzer applies the strict >=500ms injection proof instead of silently skipping the window thresholds.
- `tools/net_smooth1/analyze_r3c2_stages.py` gives process-local p50/p95/p99/max by stage from verified raw trace (diagnostic only); normative acceptance remains `analyze_net_smooth1.py` and `analyze_r3_committed_view.py`.

## Required independent validation

1. Exact HEAD/TREE detached Windows + native Linux Godot double; import/parse zero errors and SHA pinned; new `tests/runtime/test_net_smooth1_r42_r3c2_phased_item_publication.gd` and `tests/characters/test_net_smooth1_r42_r3c2_avatar_prewarm.gd` must pass real M6/CHAR2. Regress the R3C1, R3B, R3, P1A, M6, USER1 and NX3 paths.
2. Run separate GUI baselines `--scenario local --duration 120 --mode gui`, default-off and `--r3c2-avatar-prewarm --r3c2-server-phased --r3c-async-admission` on the same quiet host, then **3×** `--scenario r3-slow-item --slow-item-writer-ms 1800 --r3c2-avatar-prewarm --r3c2-server-phased --r3c-async-admission`, each unique root and two real Quaternius client processes. Never kill unrelated Godot jobs.
3. Run existing normative smoothness analyzers, plus per-role `analyze_r3c2_stages.py`. Compare baseline CONNECTED client p99/p99.9/max and stage walltime; <=25ms p99, <=50ms p99.9, <=100ms max frame gap, server >=59Hz and <=100ms max server loop gap, <=50ms main-thread persistence, zero scheduler dropped time, >=20Hz actual dual-client movement during all ITEM pending, zero checksum rejects/early ACK/backpressure reconnect failure.
4. Verify both crash windows: kill during worker precommit (no false durable) **and kill after atomic commit before ACK** using real process, same durable root and independent server2 recovery markers. `tools/net_smooth1/fault_kill_r3c2.py` is a new real OS process tool, with a **test-hook-only permanent pre-ACK hold** in the second scenario. It requires exact SUBMIT, exact COMMIT and hold events on the server trace, then hard-kills server1, starts **server2 as a new process** on the same root, checks the ACTIVE generation and outbox, and independently verifies `_service.has_durable_replay_operation(operation_id)` in server2 memory through a test-only boolean. It fails closed on absent markers, stale generation, malformed SHA, duplicate outbox record, missing recovery or in-memory replay mismatch. **This instrument is not considered PASS until run on the exact target with real binaries.**
5. Execute dedicated bounded real-process recovery proofs after short gates:
   `python tools/net_smooth1/fault_kill_r3c2.py --godot <GODOT> --window before-commit --output <NEW_EVIDENCE_DIR>`
   and separately `--window after-commit-before-ack` with a NEW output root. The exact M6 active checkpoint, server2 PID, recovery_source, generation, item checksum, and outbox operation must agree. The second window uses a strictly test-only nonblocking 6-second postcommit/pre-ACK hold (both `DWS_NET_SMOOTH_TEST_HOOKS` and R3C2 opt-in required), without sleeping in the game loop.
6. Do not 4h soak/merge if GATE A/B or either fault window incomplete. Exact reports/evidence hashes and independent human-readable final verdict required.

**Explicit status:** `R3C2_IMPLEMENTATION_CANDIDATE / LINUX_AND_WINDOWS_GODOT_PENDING / PERFORMANCE_NOT_ACCEPTED / NO_MERGE`. Source contracts including fault falsifiers pass on current repair candidate, but real Godot and GUI evidence are still required. Sub-50ms ITEM capture is **not** proven by these optimizations.
