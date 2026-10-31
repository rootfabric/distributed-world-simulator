# NET-SMOOTH1 — R31b P1 / PR #802 Safety Repair R1 (Windows independent exact work order)

## Product, identity, no-merge rule

Parent: exact #802 P1 HEAD 439a0371436a95bc28cf749ef6f6f882daefe316; P0 parent e75ec0e32c5d1b38b1c32526aa56407aa2fb4716, R31a #797 ancestor 02cba1e7e0fb5126ffef9928b1eef1bad2213e01.

This repair is isolated from frozen PR #802 and from competing PR #801. Test exact repair HEAD/TREE obtained by fresh fetch and verify the actual GitHub PR head before running. No merge, no changes to main or P0 branch, no force.

## What must be falsified on exact repair HEAD

1. Post-export fence: R31b private cache re-reads owner-native ItemGraph/ResourceMining version fence after the component's canonical export, before returning or caching. A synthetic RefCounted source that advances state_serial/revision inside export_durable_state MUST yield SOURCE_FENCE_CHANGED, empty value, no private cached result. A real ProductSeam mediator must NOT hide this failure with a second mutable export. No worker reads live state.
2. Periodic-only scope: ProductSeam direct export_durable_state() contains exact legacy canonical _canonical_multiplayer_items.export_durable_state() and _resource_mining.export_durable_state() regardless of cache enabled. Under real M6 ITEM durable-before-ACK, command-side export MUST leave P1 cache counters unchanged. ONLY capture_frozen_gameplay_source_r31b_profiled() (periodic) uses cached chunks. A rollback of optimized periodic source must preserve exact checksum and payload.
3. Coherent full state: R31b periodic profiler recomputes live players, ownership, shared item, full global checksum and full validate_durable_state; pre/post tick, service revision, owner, epoch, SM1 transfer serial and BOTH source component fences must still match, else fail closed. Item Graph fence now includes tick. No stale cross-tick player row, no shadow authority.
4. Evidence reducer: analyze_r31bp1_durable_chunks.py computes actual active-seam measured-window deltas (last minus first active measured counter) for hits/misses/bypasses, and excludes legitimate seam-unbound fallback captures. No startup-hit contamination or counter resets. Each bypass records exact reason; only CHUNK_OVERSIZE may be a legitimate explicit bypass, SOURCE_FENCE_CHANGED/SOURCE_EXPORT_EMPTY always fail. At most 4MiB per cached chunk.
5. Native disk: full M6 R2 worker checkpoint exactly equals legacy current_snapshot/durable schema/checksum, with caller alias poisoning after submit; durability generation and ACK advance only after disk completion. Verify hard-kill mid-item, restart, duplicate operation replay, A->B->A seam handoff and resource mining selective invalidation with P1 ON.
6. Existing known issue: test_v0_p7_4_persistence_restart_composition.gd phase-harness failure reproduced on untouched P0 parent (reported); do NOT waive all P7.4 tests or claim entire suite PASS. Classify base-equal scenario and keep separate.

## Native exact and Windows host identity

Environment: DESKTOP-QNAGSTI Windows 10 pwsh 7.6.6, Godot 4.7.1.stable.double.custom_build.a13da4feb, Quaternius CC0 real textures, fallback FORBIDDEN, no replacements of tracked sources.

Pin Windows console wrapper:
3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5.

Also hash the MAIN executable separately (historic local SHA 6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4). A wrapper pin does not prove main engine bit identity. If the original main binary reference is not independently available, classify GUI_LOCAL_CANDIDATE rather than pinned WINDOWS_EXACT even if functional comparisons on same actual binary are useful.

Fresh clone/worktree on exact repair HEAD, tracked clean, Quaternius asset manifest, cold import. Run new source Python tests test_net_smooth1_r31bp1_802_safety_contracts.py and test_net_smooth1_r31bp1_durable_chunks.py, plus test_net_smooth1_r31b_durable_source.py and inherited tools. Native test_net_smooth1_r31bp1_durable_chunk_cache.gd, P0 43/0 expected, R31a/R30/R2 and inherited M6 full focused tests. No false-positive gate from an unrelated V0 LIVE.2 workflow.

## Three paired real Earth GUI runs: same exact repair HEAD

Use tools/net_smooth1/run_net_smooth1.py, mode gui, scenario r31-reconnect-roundtrip, profile LOCAL, duration 120, warmup 20, OpenGL3 900x600, VSync disabled, maxfps60, 2 real Earth Quaternius clients, unique evidence root each. OFF/ON, ON/OFF, OFF/ON order.

Both arms:
--r3c-async-admission
--r3c2-avatar-prewarm
--r3c2-server-phased
--r3c3-staged-earth
--r3c21-frame-paced-presentation
--r3c4-periodic-frame-pacing
--r3c4r2-worker-envelope
--r3c4r31-replay-projection
--r3c4r31b-durable-attribution

ON ONLY: --r31bp1-durable-chunks.

OFF means P1 chunks OFF, NOT R31a replay OFF. Both arms on exactly the SAME NEW REPAIR HEAD/TREE, same assets and main Godot binary, no unapproved change to CPU/GPU, compiler or workload.

Invoke the unchanged normative analyze_net_smooth1.py; retain PERF_FAIL even if functionally PASS. For each ON server trace:
python tools/net_smooth1/analyze_r31bp1_durable_chunks.py <RUN>/server/trace.jsonl --output <RUN>/r31bp1_chunks.json

For all 3 pair directories use the existing compare_r31bp1_paired_gaps.py (common R31a+P0 ON) and keep raw root manifest, report.json, trace.jsonl for server/client A/B, screenshot, Quaternius provider proofs, SHA256 of files. Server + both clients frame p99 <=25ms, p999 <=50ms, max <=100ms, server sim >=59Hz. A >100ms unexplained gap is blocking even if p99 falls below 25.

## Separate slow ITEM + crash evidence

On same exact repair HEAD and P1 ON run real GUI slow item 1800ms and independent fault kill/restart. Preserve durable 24/24 unique operations, same operation_id retransmission and revision idempotence, ACK only after durable disk write, monotonic checkpoint generation, no checksum/replay/authority corruption. Note PR #796 retry is divergent and not inherited; do not merge it or count #796 earlier results as combined acceptance.

## Report and gate

Report EXACT_HEAD, TREE, PARENT, tracked clean, engine wrapper+MAIN SHA, Quaternius hash, native/source exact, three paired OFF/ON functional+normative, P1 chunk measured-window deltas, stage p50/p99, GUI long gaps, stress/kill, CI status, independent Project Control and SEAM-E2E, and evidence paths. Publish to the repair PR and link #802.

Current expected state is not yet independently verified: IMPLEMENTED_REPAIR_CANDIDATE / SOURCE_CI_PENDING_OR_PASS / NATIVE_GUI_PENDING / NO_MERGE. No automated merge authorization.
