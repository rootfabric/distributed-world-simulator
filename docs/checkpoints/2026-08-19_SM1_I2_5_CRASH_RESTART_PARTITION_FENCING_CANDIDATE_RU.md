# SM1-I2.5 — Crash / Restart / Partition Fencing candidate

Status: `RESEARCH_ONLY_CANDIDATE / DONOR_ONLY`

Branch: `research/sm1-i2-partition-fencing`

Accepted predecessor:

- I2.4 Repair R1 exact base: `b4b7ea41e40cda748fc1920ebe9bb6c3c90f3f54`
- gate: `SM1_I2_4_REPAIR_R1_FRESH_INDEPENDENT_REVIEW_PASS`
- accepted I2.3 base: `2e709249b5854e1bd0584041c3731e5bf102bde6`

## Goal

I2.5 proves the stale-writer side of crash/restart/partition behavior without prematurely implementing liveness, leases or automatic failover policy.

Canonical scenario:

```text
Directory: A owns D @ epoch10 / fence50 / incarnation1
Authority A becomes partitioned from Directory
A mutation admission -> DIRECTORY_UNREACHABLE (fail closed)
External/control-path canonical CAS commits B @ epoch11 / fence51
A crashes/restarts with stale local claim A/10/50/i1
Partition heals
A mutation admission -> FENCED
Directory process restarts from I2.4 durable state
A stale mutation admission -> FENCED
B exact current tuple -> AUTHORIZED
```

The checkpoint deliberately does **not** decide when A is dead or when failover should occur. The A→B CAS is externally orchestrated test setup. Liveness detection, timeout/lease policy and automatic failover remain later work.

## Mutation gate

`PartitionFencingGate` is a research-only prerequisite gate. It has no owner cache and never mutates ownership.

When connected, every attempt delegates to accepted I2.2:

```text
OwnershipDirectory.authorize_ownership_tuple(exact claim)
```

When partitioned:

```text
DIRECTORY_UNREACHABLE
admitted = false
```

The gate cannot fall back to stale process-local state.

`AuthorityRuntimeClaim.process_instance_id` and `restart_generation` are harness metadata only. They never grant authority and cannot self-upgrade a stale ownership tuple.

## Accepted semantics preserved

Canonical ownership mutation remains the accepted I2.4 durable Directory CAS path. I2.5 does not add another ownership store or mutation path.

After canonical A→B transfer:

- old A tuple remains `FENCED` after heal;
- a restarted A process carrying the same stale tuple remains `FENCED`;
- reopening the durable Directory does not resurrect A;
- exact B tuple is `AUTHORIZED`;
- future-looking tuples remain `FENCED` under accepted I2.2 semantics.

Same-AuthorityId incarnation replacement is also covered: old i1 remains fenced after i2 becomes canonical even when AuthorityId and authority_epoch are unchanged.

## Evidence

Gate evidence schema:

`distributed_world_simulator.sm1_i2_5_partition_fencing_evidence.v1`

Event kind:

`AUTHORITY_MUTATION_GATE_RESULT`

Fields include local `attempt_sequence`, reachability, operation_id, process/restart metadata, claim, observed canonical record, status and mismatched fields.

`attempt_sequence` is local gate emission order only. It is not Directory CAS linearization, Directory authorization sequence or global distributed order.

## Candidate tests

Semantic suite covers:

1. current connected owner authorized;
2. partition fail-closed without Directory authorization call;
3. A→B transfer while A partitioned, stale A fenced after heal;
4. stale A process restart remains fenced;
5. current B authorized;
6. Directory restart preserves stale-A fencing;
7. same-AuthorityId old incarnation fenced;
8. future-looking tuple fenced;
9. missing subject NOT_FOUND;
10. gate attempts do not mutate Directory/storage revision;
11. restart metadata cannot self-upgrade a stale claim;
12. multiple stale A process instances all fenced;
13. repartition fails closed even for current owner;
14. evidence ordering is explicitly local;
15. real subprocess restarted stale authority is fenced;
16. machine contract.

## Scope boundary

Explicitly out of scope:

- authority liveness detection;
- lease timeout/admission policy;
- automatic failover trigger;
- real socket/WAN partition transport;
- multiple simultaneous Directory writers;
- Directory replication/consensus;
- durable gameplay operation ledger;
- atomic gameplay-state commit;
- AuthorityBinding generation;
- AuthorityDomain handoff;
- Gateway routing;
- Item Graph;
- player runtime;
- production SM1 activation.

## Next gate

I2.5 requires a genuinely fresh independent READ-ONLY exact-head review before I2.6 may begin.

Next intended checkpoint after PASS:

`SM1-I2.6 — Integrated One-Writer Proof`
