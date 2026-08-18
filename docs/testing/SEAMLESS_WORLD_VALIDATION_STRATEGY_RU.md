# Seamless World Validation Strategy

Status: `RESEARCH TEST STRATEGY CANDIDATE`

Architecture: `../architecture/SEAMLESS_WORLD_ARCHITECTURE_R1_RU.md`

Roadmap: `../plans/SEAMLESS_WORLD_SM1_ROADMAP_RU.md`

## 1. Validation philosophy

The seamless-world program must continue the strongest lesson from SM0: distributed correctness is established by adversarial state-transition evidence, not by a visually smooth demo.

Every milestone should answer four different questions:

1. **Contract correctness** — can invalid/stale/conflicting messages be rejected deterministically?
2. **Process correctness** — do separate real processes preserve the same invariants?
3. **Fault/recovery correctness** — do restart, retry, reorder and partition converge safely?
4. **User continuity** — does the graphical/client experience remain stable after correctness is proven?

These dimensions are reported separately.

## 2. Global invariants used as test oracles

### G1 — one writer

For every canonical subject:

```text
accepted_active_writer_count <= 1
```

The test harness should collect writer evidence from all authority processes and run a global analyzer, not trust one process's local view.

### G2 — monotonic ownership

For a canonical subject:

```text
authority_epoch never decreases
fencing_token never decreases
directory_generation never rolls back
```

### G3 — stale writer cannot resurrect

After ownership commit to `(B, epoch N+1)`, any mutation attempt from `(A, epoch <= N)` is rejected even after A restarts from durable state.

### G4 — transfer converges to one result

Duplicate/replayed transfer messages either reproduce the same accepted result or are rejected fail-closed. They cannot create a second transfer outcome.

### G5 — projection never writes

No observer, cache, gateway presentation object or stale projection may be used as a canonical mutation path.

### G6 — stable identity

Entity/player/item/reference-frame identity does not change only because authority, gateway or process changes.

### G7 — operation identity is end-to-end

The same `OperationId` routed through a different gateway/authority path cannot create a duplicate canonical commit.

### G8 — gateway is not owner

No `GatewayId` or gateway route state may satisfy an ownership check in place of a canonical `OwnershipRecord`.

### G9 — interaction-island co-location policy is preserved

When a policy marks an island as co-location-required, accepted ownership state may not leave required members split across authorities.

### G10 — unrelated failure isolation

Loss or backpressure of one authority/gateway/client must not stop unrelated healthy routes unless a documented shared dependency requires it.

## 3. Test layers

### Layer A — pure contract/model tests

Fast deterministic tests for schemas, state machines, cost models and routing rules.

Use fixed seeds and exact expected outcomes.

### Layer B — loopback component tests

Gateway, Directory and Authority components in one process where deterministic scheduling is useful.

Loopback is not sufficient for acceptance of process boundaries but is useful for exhaustive state-machine coverage.

### Layer C — real multi-process tests

Separate OS processes for:

```text
Directory
Gateway(s)
Authority A/B/C/...
Client(s)
```

These tests prove no hidden shared-memory dependency.

### Layer D — deterministic network-condition tests

Use existing network-condition simulation concepts for each logical link independently:

```text
Client <-> Gateway
Gateway <-> Directory
Gateway <-> Authority
Authority <-> Authority
Authority <-> Directory
```

Do not use one global latency knob when link asymmetry matters.

### Layer E — crash/restart tests

Hard process termination at named transition points followed by recovery.

### Layer F — graphical evidence

Only after correctness gates pass: visible movement, handoff, vehicle/passenger continuity, remote projection and gateway rehome behavior.

## 4. Ownership Directory test suite

### OD-01 monotonic CAS

Initial:

```text
owner=A epoch=10 fence=100
```

Accept exactly:

```text
CAS A/10/100 -> B/11/101
```

Reject:

- wrong expected owner;
- wrong expected epoch;
- wrong fence;
- non-monotonic desired epoch;
- reused stale generation.

### OD-02 stale resurrected authority

```text
A owns E @ 10
A partitioned
Directory commits B @ 11
A restarts from durable snapshot @ 10
A attempts mutation
```

Expected:

```text
mutation rejected as fenced
Directory remains B/11
B writer remains active
writer_count = 1
```

### OD-03 directory restart around commit

Crash/restart at:

- immediately before ownership CAS;
- after durable CAS before response;
- after response but before event publication.

Retry must converge to the durable record.

### OD-04 stale lookup result

Gateway gets owner A/N, then ownership becomes B/N+1 before operation send.

The operation at A must fail ownership validation; gateway re-resolves and follows explicit retry policy.

### OD-05 draining

Authority marked `DRAINING` cannot receive new placements/leases but remains able to finish explicitly permitted retire/transfer work.

## 5. Authority transfer crash matrix

Use named transition points:

```text
T0 ACTIVE_SOURCE
T1 TARGET_ROUTE_WARM
T2 SOURCE_FROZEN
T3 TARGET_PREPARED_SHADOW
T4 BEFORE_DIRECTORY_CAS
T5 AFTER_DIRECTORY_CAS
T6 BEFORE_TARGET_ACTIVATE
T7 BEFORE_SOURCE_RETIRE
T8 SOURCE_RETIRED
```

For source and target crashes at each meaningful point verify:

- which process may recover as writer;
- whether transfer can resume;
- whether a retry reuses the same TransferId or creates an explicitly new transfer generation;
- writer count <= 1;
- no state revision rollback;
- correct durable proof cleanup timing.

The key rule is:

```text
before T5: source may remain/recover canonical owner
at/after T5: old source may never recover canonical writer role
```

## 6. Gateway selection tests

### GS-01 minimum-quality candidate

```text
G1 RTT 20ms
G2 RTT 45ms
G3 RTT 90ms
```

Expected: G1.

### GS-02 loss penalty

```text
G1 RTT 18ms, loss 8%
G2 RTT 25ms, loss 0%
```

Expected outcome follows the frozen score policy; test stores the exact score inputs and decision.

### GS-03 jitter penalty

A gateway with lower average RTT but severe jitter may lose to a slightly slower stable gateway according to policy.

### GS-04 health exclusion

Unhealthy gateway is excluded regardless of ping.

### GS-05 load penalty

A severely overloaded edge should not continue receiving all new sessions solely because it has the lowest RTT.

### GS-06 hysteresis

Repeated measurements such as:

```text
21/22
22/21
21/22
22/21 ms
```

must not cause flapping.

### GS-07 cooldown

After intentional rehome, prevent immediate reverse migration until cooldown/major-failure condition allows it.

## 7. Gateway authority-route tests

### GR-01 primary cannot flip before ownership commit

Gateway observes prepared/newer target state but Directory still says A/N.

Expected:

```text
A remains canonical PRIMARY route
B may remain WARM/OBSERVER
```

### GR-02 committed ownership flips route

After Directory record becomes B/N+1, gateway may update canonical operation route to B.

### GR-03 stale source packet

A/N packet arrives after B/N+1 committed and observed.

Expected: never re-promote A.

### GR-04 stale directory response

A delayed old lookup response may not overwrite a newer route revision.

### GR-05 observer outage

Observer/source loss degrades only its presentation stream; primary gameplay route remains healthy.

### GR-06 primary outage without ownership change

Gateway cannot promote an observer merely because primary is unreachable.

Availability may degrade until canonical recovery/ownership protocol resolves the owner.

## 8. Gateway rehome tests

### GH-01 crash before forwarding

Client operation was accepted at G1 but not forwarded. After rehome to G2, retry produces one commit.

### GH-02 crash after forwarding before result

G1 forwards `op-100`, authority commits, G1 dies before delivering result. Client retries via G2.

Expected:

```text
operation canonical commits = 1
client eventually receives deterministic existing result
```

### GH-03 old gateway restart

G1 restarts with stale route cache after client is on G2 and authority moved.

G1 cache cannot alter canonical owner/session identity.

### GH-04 simultaneous duplicate retry paths

The same OperationId arrives through G1/G2 due to a race. Canonical operation ledger deduplicates.

### GH-05 rehome during authority handoff

Gateway changes while A->B transfer is in progress. Neither gateway may infer ownership from local route state; both converge on Directory record.

## 9. Projection/AOI tests

### PA-01 epoch rollback

Reject foreign projection with older authority epoch than already accepted source state.

### PA-02 revision reorder

Reject/defer stale state revision according to contract.

### PA-03 conflicting same revision

Same `(source, epoch, revision)` with different checksum is an error, not an acceptable update.

### PA-04 identical replay

Exact duplicate is idempotent.

### PA-05 stale cache

After source loss, gateway may continue a marked stale/coarse representation only if policy allows; it remains non-authoritative.

### PA-06 interest merge

100 clients request overlapping representation. Assert bounded/merged upstream subscriptions rather than 100 identical authority subscriptions when the case is mergeable.

### PA-07 interest leave cleanup

After last client leaves interest, upstream subscription/cache lifecycle obeys retention policy and eventually releases resources.

### PA-08 budget downgrade

Under constrained bandwidth, deterministic priority/LOD policy preserves high-priority nearby state and downgrades/deferred lower priority data.

## 10. Physical transport multiplexing tests

### TM-01 connection count

Example:

```text
100 clients
1 gateway
2 authorities
```

Assert physical gateway-authority connection count remains bounded by pooling policy and does not become `100 * 2`.

### TM-02 logical route isolation

Closing one client's logical route must not tear down the shared physical authority transport if others still depend on it.

### TM-03 slow client

Artificially backpressure one client. Other clients continue within defined latency/queue limits.

### TM-04 slow authority

Backpressure from Authority B must not stall unrelated Authority A routes beyond shared-resource budgets.

### TM-05 reconnect pooling

Authority transport reconnect recreates logical routing/subscription state without duplicating canonical client/entity identity.

## 11. Cross-authority operation tests

### XO-01 player@A -> item@B

Gateway resolves item owner B and routes operation with expected epoch/revision.

### XO-02 owner changes after lookup

Lookup says B/N, then item transfers to C/N+1 before commit.

B rejects stale operation. Retry policy re-resolves; exactly one canonical outcome.

### XO-03 projection is stale

Client sees item in observer projection but canonical owner rejects expected revision.

Expected: deterministic stale-state result, never mutation of projection cache.

### XO-04 duplicate through different gateways

One OperationId, two edge paths, one canonical result.

### XO-05 target unavailable

Failure result does not cause gateway to become owner or broadcast mutation to all authorities.

## 12. InteractionIsland tests

### II-01 identity independence

Prove:

```text
InteractionIslandId != SpatialCellId
InteractionIslandId != AuthorityId
```

Island can move across cells while identity remains stable.

### II-02 co-location crossing

Island:

```text
ship
pilot
passenger
mounted item
cargo
```

Crosses spatial boundary. Required members remain under one allowed authority according to policy.

### II-03 membership generation

Join/leave increments/changes explicit membership generation; stale membership update rejected.

### II-04 join race with transfer

Passenger joins while island handoff is in PREPARE/FROZEN phase.

Contract must define whether join is frozen, included in next generation, or rejected/retried. Test exact chosen policy.

### II-05 leave race with transfer

Equivalent deterministic policy for leaving/detaching.

### II-06 reference-frame continuity

Moving/nested reference-frame state remains consistent across island transfer.

### II-07 invalid partial placement

If island policy requires co-location, a placement proposal splitting required members is rejected.

### II-08 owner restart

Current island owner crashes/restarts; stale fencing prevents competing writer.

## 13. Dynamic-placement model tests

These tests may exist before production D1 but must not activate dynamic placement.

### DP-01 CPU-only temptation rejected

Server A load high, Server B low, but candidate subjects have very high mutual interaction cost.

Expected: no move if interaction cut + migration cost exceeds benefit.

### DP-02 beneficial independent move

High load with low interaction cut and sufficient projected benefit.

Expected: move proposal accepted by cost policy.

### DP-03 hysteresis

Small oscillating load changes do not ping-pong domains.

### DP-04 cooldown

Recently moved domain cannot immediately move back absent critical condition.

### DP-05 migration budget

Large number of overloaded domains cannot all migrate simultaneously beyond configured safety budget.

### DP-06 allocator has no ownership power

Even an accepted placement proposal must execute through normal transfer + Directory CAS. A rogue allocator decision alone cannot mutate owner record.

## 14. Static N-authority topology tests

### NT-01 no A/B hardcode

Generate arbitrary AuthorityIds and verify all contracts/routes operate without literal fixture IDs.

### NT-02 3-hop relevance path

A, B, C with client primary on B and observers as needed. Connectivity is interest-driven, not mandatory full mesh.

### NT-03 unrelated outage

Kill C; A/B gameplay that does not depend on C continues.

### NT-04 simultaneous independent transfers

Multiple subjects transfer across different authority pairs without global serialization when contracts allow independence.

### NT-05 draining/new node

Add new authority process, advertise readiness, drain old one. No ownership is granted merely by registration.

## 15. Network-condition matrix

At minimum use deterministic presets representing:

```text
LOCAL
GOOD
AVERAGE
MOBILE
BAD
EXTREME
LAG_SPIKE
ASYMMETRIC
PARTITION
```

For each relevant link track:

- one-way latency;
- jitter;
- packet loss;
- duplicate;
- reorder;
- bandwidth;
- queue size;
- disconnect/reconnect schedule.

Important: controlled handoff latency evidence must not be labeled full WAN gameplay smoothness unless ordinary movement/projection/input paths are included in the same scenario.

## 16. Soak strategy

Static SM1 final acceptance should include long deterministic/random-seeded process soak with:

- repeated A↔B↔C transfers;
- multiple clients;
- periodic gateway failures;
- periodic unrelated authority failures;
- projection loss/recovery;
- cross-authority item interactions;
- controlled network perturbations;
- no identity changes;
- no split-brain;
- no unexplained canonical revision rollback;
- bounded queue/memory growth.

The run must emit seed and configuration so failures are replayable.

## 17. Observability assertions

Tests should assert telemetry, not only final state.

Required evidence fields where relevant:

```text
build_id / code_sha
scenario_id
seed
client_session_id
gateway_id + incarnation
authority_id + incarnation
subject_id
authority_epoch
fencing_token
directory_generation
transfer_id
operation_id
projection source/epoch/revision
physical transport id
logical route id/state
handoff phase timestamps
queue/backpressure counters
final canonical owner/revision
```

## 18. Machine-readable acceptance report

Each milestone should produce a report with at least:

```json
{
  "checkpoint": "SM1-H5",
  "code_sha": "<exact>",
  "scenario_seed": 12345,
  "processes": {},
  "assertions_total": 0,
  "assertions_failed": 0,
  "writer_violations": 0,
  "identity_changes": 0,
  "stale_owner_mutations_accepted": 0,
  "duplicate_canonical_commits": 0,
  "unexpected_errors": 0,
  "result": "PASS|FAIL"
}
```

Additional milestone-specific metrics are required.

## 19. Review gates

For every milestone with authority, durability, directory or gateway-session semantics:

1. implementer evidence on exact candidate SHA;
2. Project Control exact-head result where configured;
3. fresh independent critical review;
4. repair cycle if required;
5. final verifier when risk/control policy requires it;
6. only accepted main lineage unlocks the successor.

A prior review on another HEAD is not transferable evidence.

## 20. What counts as a successful seamless-world test program

The program is successful when tests can prove not only that movement looks continuous, but that under faults and topology changes:

```text
identity stays stable
one writer remains true
old owners are fenced
operations remain exactly-once
client edge session can remain stable
projections remain non-authoritative
interaction locality can override cell boundaries safely
upstream connectivity scales through pooling/interest
unrelated failures remain isolated
and every failure is reproducible from exact evidence
```

This is the validation standard for calling the result a working seamless distributed world.