# NET-SMOOTH1 R31 P2.3 R2.1 — single validated CURRENT COMPACT encode / Windows Exact Work Order

## Frozen research inputs and product lineage

Exact parent: independently Windows-verified R2.0 [Draft PR #828](https://github.com/rootfabric/distributed-world-simulator/pull/828), HEAD `b112c96bde4d4909b773abd4cbe2c3f198353c6a`, TREE `3bc3e88dffa32e6783dc99aa9b8ee8468038cb97`. R2.0 is a child of P2.3 R0 #823 `cdb48e605487951c0e9a38ddffa92d4c4b946c8b`. THIS R2.1 branch has **no P2.3 R1 #825 deferred debug** in lineage. The external Windows B3 Job Guard [Draft #820](https://github.com/rootfabric/distributed-world-simulator/pull/820), TOOLING_HEAD `b4cbf565764cea16eb81cc163824b2a237e2cb8a`, is used only from its independent tools worktree.

An important documentation correction was performed without changing source: [Draft #829](https://github.com/rootfabric/distributed-world-simulator/pull/829) report branch was mistakenly targeting main and showing 272 changed files; it was retargeted to #825's branch and now has **only one changed documentation file**, evidence found under `C:\warehouseconstructionbackend\dws-artifacts\`. Do not re-merge or cherry-pick #829 into this product.

Independent Windows [#828 R2.0 evidence](https://github.com/rootfabric/distributed-world-simulator/pull/828#issuecomment-6363112340) exact HEAD native 21/21 PASS, Python 23/23, two real Earth+Quaternius GUI clients: measured ON 60.09s at sim60Hz, server p99 **28.799ms FAIL**, clients p99 24.695/24.507 PASS, 2404/2404 COMPACT events under LOCAL 100% ENet passthrough. Per packet p50: ENet `frame_encode_ms` **0.522ms**, simulator full frame.validate **0.336ms**, ENet full initial frame.validate **0.330ms**, simulator canonical_json sizing **0.180ms**, ENet put_packet **0.073ms**, boundary deep copy **0.008ms**. Worst actual server frames are encode-dominated. OFF old baseline p99 28.171ms, p999 95.98, max184.4, so two old short arms cannot prove any absolute improvement. P2.3 R1 #825 stdout deferral moved debug work correctly but worsened server frame p99 27.285→28.372; NOT included here. First JOIN checksum flake [#815](https://github.com/rootfabric/distributed-world-simulator/issues/815) remains OPEN despite 0 incidences in #828 tests.

## Product change: one narrow opt-in protocol-preserving CPU optimization, default OFF

Server-only `DWS_NET_R31P23R21_SINGLE_PASS_COMPACT=1` / GUI `--r31p23r21-single-pass-compact`. Requires R2.0 `--r31p23r2-flush-attribution`, which requires R31P22/P1/P0/R31a/R2 persistent USER1; invalid mode or missing prerequisites fails CLOSED. On flag OFF (including *all* clients), the original packet encoding and network simulator canonical size calculation execute unchanged.

### Real server COMPACT_ENET fast path — validated ONCE at original trust boundary

1. Original `FrameScript.validate(frame)` at the beginning of `EnetMultiPeerTransportPort.send_to_peer()` remains UNCHANGED. It validates exact protocol fields, session ID, sequence, delivery channel/mode, payload structure and **recomputed canonical payload checksum**, rejecting tampering with the same original error code. Original peer existence and session matching follow, before serializing.
2. Only if flag ON AND this is a **server** `COMPACT_GAMEPLAY_SNAPSHOT` on SNAPSHOT/`UNRELIABLE_SEQUENCED`, a private `_r31p23r21_encode_after_frame_validate()` canonicalizes the already-validated *CURRENT* detached frame, converts the identical canonical JSON to UTF8 bytes and enforces exactly the same `MAX_PACKET_BYTES`, `SERIALIZATION_FAILED` and `PACKET_TOO_LARGE` cases as `ProtocolFrameV2.encode()`. No unchecked frame is admitted to this helper in the product call chain; source-native falsifiers prove full validation precedes it with NO yield or mutation.
3. Original `ProtocolFrameV2.encode()` remains unchanged and still revalidates on all legacy/off/other traffic. No callback API, schema, peer sequence, outgoing frame ID, ENet channel, transfer mode, `put_packet`, outgoing queue, coalescing, retry, M6 durable-before-ACK or 60Hz/20Hz cadence is modified. No future authority frame is speculated, no worker or mutable live snapshot leaves main thread.

### LOCAL ConditionSimulatorPort size reuse (not validation removal)

`ConditionSimulatorPort.send_to_peer()` continues to execute the ORIGINAL full `FrameScript.validate(frame)`. For ONLY a real LOCAL passthrough COMPACT sent to an actual ENet delegate with the flag ON, it reuses the **actual encoded packet byte size** already returned by ENet instead of re-running `NetworkUtilsScript.canonical_json(frame).to_utf8_buffer().size()` in the simulator. It fails closed if the delegate reports no valid positive integer byte receipt. Canonicalized result structure/packet_bytes remains identical. All simulated latency/drop/reorder/duplicate/blackout profiles retain the original canonical byte calculation and queue/send/drop policy. If LOCAL pass-through cannot be proven, the fast path does not activate.

### Trace and safety evidence

R2.0 `r31p23r2_flush_packet`, `r31p23r2_simulator_stages`, `r31p23r2_enet_stages` remain unchanged; two opt-in local metadata keys `r31p23r21_fast_encode` and `r31p23r21_size_reused` show activation, never appear on network wire. A complete strict R2.0 analyzer retains 100% frame/packet source association, original PERF verdict and explicit checksum/send failures.

- Native `tests/runtime/test_net_smooth1_r31p23r21_single_pass_compact.gd`: full server OFF/ON and fail-closed missing parent; 32 generated canonical COMPACT frames with varying ticks/revision/float/inventory, ORIGINAL full validation, reference FrameScript.encode bytes vs private R2.1 encoder bit-for-bit and exact FrameScript.decode checksum; oversized 32-byte limit yields same `PACKET_TOO_LARGE` and original byte count; tampered nested payload, session ID, sequence, channel and delivery negative tests retain original validators/error codes.
- Real `ConditionSimulatorPort` + deterministic test-only ENet-contract delegate native fixture: one LOCAL OFF and ON send identical canonical raw bytes and exactly same packet-size receipt; nested tampered checksum never reaches delegate, missing byte receipt fail-closed, nonpassthrough latency profile still queues instead of pretending immediate ENet success.
- Python `test_net_smooth1_r31p23r21_source_contracts.py` verifies full source-chain checks, only one initial validation on R2.1 ON path, immutable/no-yield same-thread handoff, original strict M6/replay/OUTBOUND queue, all other wire traffic legacy.
- Dedicated fresh Windows/Linux exact cold import/native + all inherited P2.3 R2.0/P2.2/R31b/M6/USER1 suites; source CI is not a native or GUI proof.

## Independent Windows G0: frozen identity and native

Get fresh HEAD/TREE from R2.1 PR; verify exactly against PR headRefOid/tree and frozen parent R2.0 commit, tracked-clean before+after, no surprise force-push/main drift. Windows 10 DESKTOP-QNAGSTI, pwsh 7.6+, Godot 4.7.1.double canonical wrapper SHA `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`, actual main Godot EXE separately SHA `6464da3576b51f5e2f7db74a20eb1d62507a8a7c8a2fa55b1e08e1a1d0d801a4`, original CC0 Quaternius 224 hash-pinned assets with `avatar/quaternius`, no fallback. External #820 tools guard separate; do not insert into product.

Run canonical cold import (fail on every parse/compile error), new R2.1 GDScript/native suite, R2.1 Python source tests, old R2.0 native+Python negative tests and inherited USER1/CHAR2, M6 recovery/ACK/durable replay and P2.2 native. Native code must prove FULL payload checksum still rejects any modified snapshot and exactly same bytes on happy path. If native parser/JSON parity/G0 FAIL — no GUI success claim, repair with a new HEAD.

## G1: FIRST one matched 60s OFF/ON, no full matrix

Use fresh detached R2.1 PRODUCT worktree, two real graphical Earth+Quaternius clients, server, OpenGL3 900x600, VSync OFF 60fps cap, LOCAL, r31-reconnect-roundtrip, warmup10+measured60 seconds. Use external Job Guard #820 in both arms; separate original evidence root each arm.

BOTH arms share:
```text
--mode gui
--scenario r31-reconnect-roundtrip
--duration 60 --warmup 10 --profile LOCAL
--r3c-async-admission --r3c2-avatar-prewarm --r3c2-server-phased
--r3c3-staged-earth --r3c21-frame-paced-presentation
--r3c4-periodic-frame-pacing --r3c4r2-worker-envelope
--r3c4r31-replay-projection --r3c4r31b-durable-attribution
--r31bp1-durable-chunks --r31p22-loop-attribution
--r31p23r2-flush-attribution
```

**R2.1 ON ONLY additionally:** `--r31p23r21-single-pass-compact`. Do NOT enable #825 R1 debug deferral, P23 completion profiling, or other differing flags. Try alternating order ON/OFF if machine load and time allow; never silently discard an ON/OFF first-join checksum failure. Keep every startup/failed attempt with separate root and issue #815 link.

After ON run, execute strictly read-only, original `analyze_r31p23r2_flush_layers.py` on original raw run, save `r21_flush_layers.json` and all legacy GDScript/server/A/B traces and SHA256:

```powershell
python tools/net_smooth1/analyze_r31p23r2_flush_layers.py "<R21_ON_ROOT>" --output "<R21_ON_ROOT>\r21_flush_layers.json"
```

Check R2.1 opt-in actually active for all successful server outbound COMPACT transmissions, same frame/sequence/session+byte_count integrity; no `PAYLOAD_CHECKSUM_MISMATCH`, no partial snapshot errors; mandatory 3×measure.end.ack, zero M6/replay/ACK/authority/ITEM violations, natural `Job Guard` exit/empty pids, foreign Godot untouched. Compare same-HEAD R2.1 OFF/ON ENet encode p50/p99/max and simulator canonical_json p50/p99; original normative server and BOTH clients p99/p999/max, sim>=59Hz, all measured frame tails including >100ms. Source trace metadata may show ON size reuse and FastEncode when active; never invent source metrics or silently exclude bad events.

A short 60s PERF_PASS is not release; two single arms are not sufficient to prove reliable effect if host noise dominates. If R2.1 fails functional/byte parity or any checksum/replay/ACK invariant, STOP, do not attempt 3-pair acceptance.

## G2: only if G1 proves a clean likely benefit

Independent reviewer/verifier on frozen **same R2.1 HEAD**; then 3 matched 120s two-client Earth GUI OFF/ON pairs with 20s warmup and balanced order, unmodified server+clients p99 <=25ms, p999<=50ms, max<=100ms, sim>=59Hz, no unexplained >100ms, 3 slow ITEM writer 1800ms, hard-kill + recovery/replay/ACK, two-player seamless A→B→A, full exact Linux/Windows native and separate Project Control/P7.4/SEAM-E2E. Unknown first-JOIN `PAYLOAD_CHECKSUM_MISMATCH` issue #815 remains OPEN until independently explained and falsified. Human research merge gate remains mandatory; NO MERGE/AUTO-MERGE.

## Scope boundary

This R2.1 changes **no public protocol schema or FrameScript.validate/encode**, no ENet send ordering, no queue behavior and no authoritative ticks. It targets the measured repeated full validation and simulator LOCAL JSON sizing only. It deliberately does **not** skip the original ENet validation, turn off client checksum rejection, replace packet bytes with unchecked client data, or use a background worker. Whether it improves end-to-end p99 is strictly a future measured result, not yet claimed.

VERDICT: R2.1 IMPLEMENTED_CANDIDATE / SOURCE_CI_PASS / NATIVE_GUI_PENDING / HISTORICAL_PERF_FAIL / READY_FOR_MERGE=false.
