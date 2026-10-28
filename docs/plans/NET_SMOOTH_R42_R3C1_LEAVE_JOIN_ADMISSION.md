# NET-SMOOTH1 R4.2 R3C.1 — bounded JOIN queue / async LEAVE

**Work order:** NET-SMOOTH1-R42-R3C1-LEAVE-JOIN  
**Stacked parent:** `67764d121ce92ab5a22ba92031835dbc880e167d` (R3B, PR #764)  
**Role:** IMPLEMENTER → FRESH INDEPENDENT WINDOWS VERIFIER  
**Scope:** opt-in M3/M6 network admission canary; R3 performance remains unaccepted.

## Motivation / quantitative baseline

Independent Windows R3B: `NARROW_VERIFIED / PERFORMANCE_FAIL`. Synchronous LEAVE/persist stalls main thread for seconds; reconnect JOIN receives gate backpressure and fails all 3 GUI canaries; client freezes 2–4.4s occur in baseline too. Existing M6 durable generation/FIFO/ACK, R2/R3 checksum, USER1 seam and construction authority remain immutable constraints.

## Bounded implementation

- Only opt-in `DWS_NET_R3C_ASYNC_ADMISSION=1` (or setup `r3c_async_admission_canary`, or harness `--r3c-async-admission`) activates this flow. Disabled/default behavior remains unchanged.
- While existing M6 single writer, previous periodic generation or ACK gate is busy, queue only **unmodified JOIN/LEAVE transport requests**. Maximum 32. Exact duplicate request coalesced by kind, logical ID, peer, transport session, operation ID. Conflicts or overflow fail explicitly. No canonical mutation, replay record, or ACK exists during admission. Queue expires after 20s and is invalidated on stale/disconnected transport; process at most one admission per frame, prioritizing LEAVE and existing deferred DISCONNECT over replacement JOIN.
- Persistent LEAVE takes existing P1A `reserve_mutation` before canonical `service.leave`, captures before-view, then uses existing P1B `stage_committed`/frozen single-writer submit. Only the exact committed generation permits LEAVE_ACK, with transport-session and ownership epoch checking via `peek_publication` / `mark_enqueued`. Stale or missing transport is quarantined, not acknowledged; restart replay retains canonical result.
- USER1 `requires_immediate_join_persistence()==false` means queued reconnect JOIN can be retried after the older writer without a new JOIN fsync. **Legacy Service immediate JOIN still uses its original synchronous durability path**. Do not claim it is fixed or that all command types are async.
- Periodic snapshot capture, MOVE/PRESENTATION/RESOURCE, baseline client freezes and postcommit/pre-ACK process kill are **separate follow-up gates**.

## Independent executable verification

1. Fresh exact HEAD/TREE detached Windows worktree. Pinned Godot double SHA256 `3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5`. Cold import zero parser errors.
2. New `test_net_smooth1_r42_r3c_async_leave.gd`: real M3/M6 delayed writer, no legacy synchronous barrier or early ACK, generation exactly +1, independent on-disk checkpoint and restart replay.
3. New `test_net_smooth1_r42_r3c_queued_join.gd`: real USER1 Product Service, gate-busy JOIN duplicate no mutation/rejection, later drain once, stale queued peer dropped before mutation.
4. R3B/R3/R2/M6 full regression as listed in `.github/workflows/net-smooth-r42-r3c1-admission-exact.yml`, plus `test_net_smooth1_r42_r3c_source_contract.py`.
5. Two separate baseline runs: `--scenario local --mode gui` default-off versus same with `--r3c-async-admission`. Then 3×120s `--scenario r3-slow-item --slow-item-writer-ms 1800 --r3c-async-admission` with 2 real Quaternius clients, independent raw trace folders.
6. Analyze with `analyze_r3_committed_view.py` (20Hz actual client receive) and `analyze_r3b_legacy_stalls.py` for all remaining legacy types. Any unexpected JOIN_REJECTED, early LEAVE_ACK, M6 checksum mismatch, outbox duplication, peer epoch leak, trace drop or fatal failure FAIL.
7. Thresholds unchanged: >=59 server Hz; server loop gap <=100ms; main-thread persistence max <=50ms; client p99<=25ms, p99.9<=50ms and maximum frame gap<=100ms. Main thread budget is **not** implied by source/runtime PASS.
8. Kill/restart before atomic commit AND after atomic commit but before ACK as separate evidence. Soak 4h only after both performance gates and recovery pass.

## Exclusions / status

Control-plane MVP8 schema repair is a different [PR #765](https://github.com/rootfabric/distributed-world-simulator/pull/765), independently green on CI but unmerged; no project control workaround is part of this runtime work.

**Expected status:** `IMPLEMENTED_CANDIDATE / WAIT_FRESH_WINDOWS / NOT_MERGE_READY`. Preserve `main` and PR #762–#765. Do not fabricate time-to-completion or declare performance acceptance from unit tests.
