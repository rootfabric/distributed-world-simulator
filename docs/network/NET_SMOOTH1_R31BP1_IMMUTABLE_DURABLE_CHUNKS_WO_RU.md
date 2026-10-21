# NET-SMOOTH1 R31b P1 — Source-fenced immutable durable chunks

## Evidence gate

Parent: corrected R31b P0 Draft PR #799 HEAD e75ec0e32c5d1b38b1c32526aa56407aa2fb4716, ancestor R31a #797 02cba1e7e0fb5126ffef9928b1eef1bad2213e01.

Windows P0 6/6 functional PASS but all server frame p99 OFF/ON 28.06/28.67, 29.24/27.83, 28.86/28.57ms FAIL vs <=25ms. Historic R31a >100ms server spikes were NOT reproduced in P0; cause remains UNKNOWN. P0 durable stage p99 validation 6.9-9.6ms, ItemGraph 4.7-6.1ms, final checksum around 3.7ms. Stage p99 cannot be summed. Project Control CANDIDATE_MAIN_DRIFT stays separate and unwaived.

R31b P1 caches ONLY M4 Item Graph and ResourceMining durable components. This is an implementation candidate, not a verified performance fix. Full gameplay validation, outer checksum, live player+ownership reconstruction and M6 writer are unchanged.

## Product boundary and invariants

Server-only default OFF: DWS_NET_R31BP1_DURABLE_CHUNKS=1 / --r31bp1-durable-chunks. Requires R31a replay projection, R31b P0 stage attribution, R2 worker, actual USER1 ProductSeam and persistence enabled. Bad/missing mode fails closed.

A single quiescent authority frame exports active player+ownership rows and shared items live. M4 and mining components may reuse detached private immutable chunks if owner, epoch, revision/generation, instance identity and monotone reset/mutation serial all match. M4 serial also changes for zero-revision player inventory/P5 mining tool seeding, native live fixture bootstrap and restore. Mining serial changes on setup/restore even for identical generation (ABA protection). Ordinary M4/Resource operations bump revision/generation. Re-check complete source fences and server tick/revision/seam transfer serial after full legacy checksum + complete validate_durable_state. On source mismatch fail CLOSED. No live data/Node/Resource enters worker.

Exactly two private chunks at most 4 MiB each. Oversize bypass uses the unchanged full component export and is measured, not hidden. Every cache hit returns duplicate(true); source on miss is independently cloned into private cache. Final payload and disk checkpoint must be exactly equal to legacy R31b P0, including checksum and generation. Durable-before-ACK, restore, replay idempotence unchanged.

## Native and source falsifiers

Cold import + inherited exact focused M6 suites + new tests/runtime/test_net_smooth1_r31bp1_durable_chunk_cache.gd, Python source and analyzer fixtures. Confirm:
- First miss then warm hit for BOTH chunks, exact durable JSON and checksum.
- Caller nested poison cannot mutate private snapshots or disk checkpoint.
- New player/P5 tool inventory without item revision invalidates; ITEM command invalidates only M4; resource same-generation restore invalidates only resource.
- Native live item policy bootstrap, M4 restore, generation and command ACK fences.
- Memory budgets, changed-fence failures, no async live reads and no default impact.
- Fresh independent Windows/Linux exact runner; GH queued jobs are NOT native PASS.

## Independent Windows GUI matrix

Fresh detached exact P1 HEAD/TREE. Same Godot binary, canonical Quaternius assets (no fallback), 2 real Earth GUI clients, OpenGL3 900x600 VSync OFF 60fps, scenario r31-reconnect-roundtrip, 20s warmup plus 120s measured. Three pairs OFF/ON, ON/OFF, OFF/ON; preserve six unique roots and unmodified normative analyzer.

Common OFF and ON flags:

~~~text
--r3c-async-admission
--r3c2-avatar-prewarm
--r3c2-server-phased
--r3c3-staged-earth
--r3c21-frame-paced-presentation
--r3c4-periodic-frame-pacing
--r3c4r2-worker-envelope
--r3c4r31-replay-projection
--r3c4r31b-durable-attribution
~~~

ON alone additionally uses --r31bp1-durable-chunks. This is a SAME P1 HEAD comparison, NOT R31a replay OFF/ON.

For each ON run, after normative analyzer:

~~~powershell
python tools/net_smooth1/analyze_r31bp1_durable_chunks.py "C:\P1\pair1-on\server\trace.jsonl" --output "C:\P1\pair1-on\r31bp1_chunks.json"
~~~

Apply for all ON runs. Requires >=90% active-seam M4+mining cache-hit, no unexplained bypass, valid resource and item chunk sizes, preserved full validation. Track expected fallback ProductSeam-unbound checkpoints separately. For both OFF and ON use the inherited patched analyze_r31b_durable_stages.py to compare item_graph_ms, resource_ms, validation_ms, final_checksum_ms and capture_ms, without summing p99 values.

Three-pair gap comparison:

~~~powershell
python tools/net_smooth1/compare_r31bp1_paired_gaps.py --pair "C:\P1\pair1-off" "C:\P1\pair1-on" --pair "C:\P1\pair2-off" "C:\P1\pair2-on" --pair "C:\P1\pair3-off" "C:\P1\pair3-on" --output "C:\P1\paired_gap_forensics.json"
~~~

This comparator intentionally requires R31a replay ON and P0 attribution ON in BOTH arms; do NOT apply historic R31a gap comparator, where OFF meant replay-cache disabled. Report all actual >100ms frame gaps server/client, server process durations and interarrival; proximity is not causation. Historic unaccounted >100ms R31a spikes still block final acceptance.

Windows Godot console-wrapper pinned SHA256 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5, actual main exe previously seen SHA 6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4. Hash BOTH and compare main exe to a separately established reference. Wrapper SHA alone cannot certify the main engine.

Separate slow ITEM 1800ms with R31b P1 actually ON, crash-kill / restart / duplicate-operation replay, generation order, no early ACK, 2-player seam A→B→A. The test-only retry in divergent PR #796 is NOT merged into P1; do not claim inherited combined coverage.

## Product gate and decision

Do not merge this branch, #799 or #797. R31b P1 acceptance requires 3 full paired real GUI results on same exact HEAD; server and clients frame p99 <=25ms, p99.9<=50ms, max<=100ms, server >=59Hz; no missing/invalid trace, checksum/replay/ACK/authority violations; full independent native acceptance and reviewer; Project Control canonical owner rotation and SEAM-E2E separate. Unexplained >100ms gaps remain blocking.

If ItemGraph cache saves ~5ms but validation remains 7–10ms, prepare a separate measured P2 incremental/prevalidated durable component design; NEVER drop checksum, cross-domain validation or authoritative tick fence without RED/GREEN correctness evidence.
