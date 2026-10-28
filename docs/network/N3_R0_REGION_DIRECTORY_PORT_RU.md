# N3 R0a — Region Directory Port: audit, gates and evidence (27 October 2026)

Status: SOURCE_CANDIDATE / LAB_NATIVE_PARTIAL_PASS / FULL_N3_R0_NOT_ACCEPTED / READY_FOR_MERGE=false.
Tracking: Issue #870. Independent implementation branch: feature/n3-r0-region-directory-port-r1-20261027.
Base: main aac301b9a9a89e027f6d99864437eb750a4202ca. Does not update main, #869, #868, #864 or other ongoing NET-SMOOTH1 drafts.

## Product decision

PLAYABLE_BASELINE — DONE_FOR_NOW means an old server-frame p99 26.5–27 ms vs target 25 ms no longer blocks feature development. Preserve historic PERF_FAIL measurements. This does NOT waive checksum/reconnect #815, M6 durability, ownership, actual dropped connections or real multi-host safety. F64-v2 remains experimental.

## Exact prerequisite audit on the selected main commit

| Concern | Found | Gate |
| --- | --- | --- |
| M1–M6 / A3 single-server architecture | A3 accepted documentation, gameplay service, dedicated runtime and M6 native test fixtures present | New-HEAD independent regression still required |
| B0 service request/reply port | Native schema, two in-memory adapters and strict response envelope present | AVAILABLE_FOR_LOCAL_CONTRACTS_ONLY |
| Existing EG2 world directory | scripts/network/gateway/runtime/eg2_world_directory.gd, one authority per world, identifier-only resolution; no region leases | NOT AN N3 DIRECTORY |
| SM1 route pivot and player transfer | scripts/runtime/networked_gameplay/sm1 has donor/production local seam proofs | LOCAL_TRANSFER_IS_NOT_MULTI_HOST |
| B1 NATS Core | No NATS Core adapter found under scripts/network/bus/adapters on pinned main | MISSING_PORT_INTEGRATION / NO_DEPLOYMENT_PROOF |
| B2 JetStream/outbox delivery | M0 local durable transaction/outbox exists, but no JetStream-backed distributed lease/storage adapter found in pinned tree | NOT_DISTRIBUTED_DURABILITY |
| Linux + Windows real executors and original Godot 4.8 integration | Their CURRENT connectivity, canonical asset inventory, SHAs and availability not verified by this candidate | VERIFY_BEFORE_REAL_HOST_RUN |

These are source-tree observations, not claims that no experimental GitHub branch has ever implemented those capabilities. Check and reuse accepted branches only after exact ancestry and independent review.

## What R0a actually implements

- n3_region_lease_directory.gd is a stand-alone in-memory lab coordinator, indexed by canonical world_id and region_id. It does not replace EG2 or SM1.
- Trusted local control-plane operations are acquire, renew, mark health, release; untrusted B0 consumers have read-only lookup.
- CAS acquire requires previous lease_generation, issues strictly increasing per-region generation, and rejects conflicting active owners, stale generation, concurrent restart, invalid IDs, replayed claim and expired lease.
- Every route has exactly world_id, region_id, authority_id, server_instance_id, lease_generation, route_revision, expires_at_ms. No host/port, claim IDs, broker subject or canonical player/item data.
- Resolve fails closed on directory outage, expiration, unhealthy region, unknown region or regressing monotonic time. Renewal increments route_revision; cached old routes are rejected by explicit verification.
- B0 ServiceRequestReplyPort adapter: service/n3/world-directory, resolve_region only, request planet_simulator.n3_region_route_request.v1, response planet_simulator.n3_region_route_response.v1.
- B0 in-memory adapters replay identical request_id responses by design. A replayed response may have already expired; neither the B0 reply nor its route grants write authority. A fresh admission/fence check is mandatory for each canonical mutation.

## Hard safety boundary — do NOT deploy as distributed lease authority

The R0a coordinator holds all leases, epochs and claim history only in process memory. It does not survive a directory process crash; independent coordinator replicas would not form a consensus or protect against split brain. Client-supplied clocks must never drive production lease decisions. Only the trusted control-plane may invoke mutations; public B0 bus access is lookup-only. The method check_writer is not wired into live NetworkedGameplayService / Item Graph / Construction mutation admission. No two-host acceptance or production single-writer guarantee is claimed.

To reach real N3, first implement a single durable, linearizable lease owner with surviving epoch/generation state and correctly fenced restart across all authorities (or an equivalent externally validated quorum/CAS authority), plus B1 discovery and B2 durable recovery. JetStream message delivery/ACK by itself is not proof of exclusive lease ownership. Route metadata must stay transport-neutral; do not expose simulation endpoints to graphical clients. Extend existing owner/admission ports instead of building a second gameplay model.

## Local evidence, not full acceptance

Source of the native proof: Godot 4.7.1.stable.double.custom_build.a13da4feb Linux editor unpacked from the user-provided archive; executable SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7.

- Standalone native headless test tests/network/test_n3_region_directory_contracts.gd on exact locally authored blob: PASS, 47 assertions, 0 failures.
- Published GitHub blob hashes for the directory and test have been independently compared to local git hash-object output; they match byte-for-byte.
- tests/network/test_n3_directory_b0_routes.gd is provided for full repository execution. Its current-branch FULL-B0 native result is pending; do not label it PASS based on source inspection.
- GUI, Linux/Windows multi-host, fault injection, full M6/world regressions and 30-minute soak were not run in this R0a candidate.

Run from a full checkout with the exact double build: bash RUN_N3_R0_DIRECTORY_CONTRACTS.sh /path/to/godot-double.

## N3 R0b work order and acceptance gate

1. Independently verify the accepted ancestor/main ancestry, on-branch changed-file inventory, Godot build hashes and complete native B0 contracts; repair any verifier finding without modifying historic PRs.
2. Resolve prerequisite ports: B1 real NATS Core discovery/health/read-only request/reply through B0; B2 durable lease epoch/claim history and retry/failover without split-brain. No direct NATS in domain/gameplay.
3. Wire the authoritative lease check into the existing canonical mutation admission as a fail-closed fence; an expired/revoked generation must refuse even a direct/stale client command, not merely fail a lookup. Preserve M6 durable-before-ACK and idempotent operation ledger.
4. Launch TWO genuinely independent authority processes on different hosts/VMs for Earth and Moon/second region, with one common directory owner. Record process IDs, addresses privately, region/authority identities, directory revision, exact source HEAD/TREE and Godot SHA.
5. Run negative matrix: duplicate claim; concurrent same-region writers; identical/different claim replay; forged caller; timed-out route; stale cached route; missing/failed directory; clock anomaly; abrupt authority kill + new generation; partition; retry/ACK replay; stale post-restart authority input; reused session.
6. Run two real graphical clients with preserved player/world presentation, movement, inventory, building, native M6 recovery. Do not call this seamless N5 migration. No serious repeated stutter or connection loss in accepted functional run; keep p99 diagnostic rather than a fresh blocking microbenchmark.
7. Produce independently reviewed Windows + Linux exact evidence, 30-minute multi-host stability run and an explicit N4/N5 boundary. Only then consider FULL_N3_R0_VERIFIED and a separate merge decision.

Decision: N3 R0a CONTRACT CANDIDATE, NOT N3 R0 COMPLETE. Issue #815 remains OPEN; Draft PR #869 remains separate and is not integrated into this branch.
