# NET-SMOOTH1 R2 — bounded snapshot hot-path repair

## Контекст и идентичность

- Base exact remote: `a81df800ae3a25e4b8683d9b31d14bb8a09d40ab` (NET-SMOOTH1 R1 + Windows HOLD + evidence).
- R1 Windows implementer result: `FAIL / GUI_LOCAL_CANDIDATE`; focused 16/17, pre-existing M6 crash-observation FAIL reproduced on CHAR2 base.
- HOTSPOTS: 3-tick movement snapshot capture+encode+per-peer deep copies; client 99% of >25ms frames follow snapshot_received; command-path sync checkpoints remain a separate HIGH-risk problem.
- Scope R2: **value-copy elimination where independent canonical object creation already guarantees ownership; measurement of separate server/client snapshot stages**. No protocol, channel, fixed-tick, persistence or replay semantics change.
- Scope fence: `scripts/network/transports/v2/{protocol_frame_v2,network_transport_boundary_v2}.gd`, `scripts/runtime/networked_gameplay/m3/{m3_dedicated_server_runtime_p2,m3_graphical_client_runtime_nx6}.gd`, focused hotpath test, this Repair Map. The unchanged R1 + Windows report are baseline.

## Repair doctrine / falsifiers

| Finding | Causal chain | Narrow change | Falsifier |
|---|---|---|---|
| P-1 snapshot construction | `create_snapshot -> Compact.encode -> duplicate(true) -> _send_on_channel duplicate(true) -> Frame.create duplicate(true) + JSON roundtrip` | Eliminate only redundant copies whose downstream canonical JSON already isolates ownership | Two peers decode to same checksummed snapshot; mutate source after frame creation; prior frames remain unmodified |
| P-2 inbound frame processing | `Frame.decode parsed.duplicate(true) -> TransportUtils.success duplicate(true) -> boundary accepted duplicate(true) -> success duplicate(true)` | Avoid the first duplicate after parsing and intermediate boundary duplicate; preserve public result deep copy | Tamper decoded frame and verify checksum rejection; late source mutation cannot change returned validated event |
| P-3 client 20Hz processing | Client fetches `_replica.get_snapshot()` twice per accepted compact frame | Reuse detached snapshot within reconcile+signal; retain public copy contract | CHAR2 presentation, NX4/NX5 and 2-client GUI behavior remain identical |
| P-4 missing per-stage cost breakdown | Existing `snapshot_received` correlation cannot isolate capture vs encode vs transmit vs client accept vs animation | Add bounded trace events `movement_snapshot_stages`, `compact_snapshot_stages` | Windows GUI trace must contain stage events; no fabricated performance pass if absent |

## Explicit non-goals

- No optimistic ACK or journal design: durable command checkpoint stays sync, with correct crash semantics. Command-path `wait_completed` and canonicalize+write require separate durability/WAL design and crash-before/after-commit verification.
- No lowering snapshot frequency, frame thresholds or NX5 buffer tuning to hide stutters.
- No ledger compaction or backlog deletion without cross-restart idempotency evidence.
- No merge and no independent acceptance from implementer-only Linux tests.

## Tests and exit gates

1. Canonical Linux 4.7.1 double cold import and `test_net_smooth1_snapshot_hotpath` (checksums, detached payload, two peers, tamper rejection, port/boundary event isolation).
2. NX2 physical/channel, protocol-contract, NX3, NX4/NX5, CHAR2 presentation, async checkpoint and M6 replay tests (exact Linux).
3. Windows exact HEAD GUI A/B 3×120s async, per-role p50/p95/p99/p99.9/max; traces include all stage timings, no dropped trace packets.
4. Windows negative controls stall server/A; compare to previous R1 Windows report without changing thresholds.
5. Sync durability issue and pre-existing M6 remain known FAIL unless separately repaired. **Never call R2 full PASS solely because unit tests pass.**

## Decision points

- If snapshots still exceed 25ms at p99, next Repair Map prioritizes repeated validation/checksum construction and per-message scene event fanout based on stage traces; preserve wire validation.
- If command sync continues to block 108–190ms, next HIGH-risk slice is a dedicated durable journal/ordered pending-ACK state machine with fault injection. A simple asynchronous ACK before persistence is forbidden.
