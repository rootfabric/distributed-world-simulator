# SM1-I1-A — Research Harness Core Candidate

Status: `IMPLEMENTED / RESEARCH ONLY / DONOR ONLY / NOT SM1 PRODUCTION ACCEPTANCE`

Architecture donor base: `research/seamless-world-architecture-r1 @ 693043c3be2bc7c7cb0c728b87b88d6018899d6b`

Implementation branch: `research/sm1-i1-harness`

Control flags:

```text
RESEARCH_ONLY=true
PRODUCTION_ACTIVATION=false
CANONICAL_OWNER_MUTATION=false
DONOR_ONLY=true
```

## Scope implemented

I1-A provides infrastructure only. It does not implement Ownership Directory, authority transfer, gateway ownership/routing semantics, PlayerAuthorityDomain, Item Graph migration or production networking.

Implemented:

- deterministic directed-link packet decision planner based on `(scenario_seed, link_id, packet_index)`;
- bounded research network profiles with latency/jitter/loss/duplicate/reorder/bandwidth/queue metadata;
- machine evidence envelope with scenario/seed/sequence/process role/id/incarnation;
- global evidence analyzer for six R2 incubation oracles;
- research process supervisor with explicit process role/id and monotonic incarnation on restart;
- process lifecycle probe used by the harness tests;
- JSONL replayable evidence;
- machine-readable runner report;
- negative/falsification tests proving every implemented global oracle can return RED.

## Global oracles implemented

```text
writer_violations
identity_changes_due_to_topology
stale_owner_mutations_accepted
duplicate_canonical_commits
projection_canonical_writes
unexpected_revision_rollback
```

The analyzer is deliberately observational. It does not decide or mutate canonical ownership.

## Validation

Pre-publication component validation was executed locally against the same I1-A source text:

```text
python -m unittest discover \
  -s tests/research/seamless/i1 \
  -p 'test_*.py' -v
```

Result:

```text
14 tests
14 PASS
0 FAIL
```

Coverage includes:

- clean global PASS;
- split-brain writer detection;
- stable-identity violation detection;
- accepted stale-owner mutation detection;
- duplicate canonical commit detection while exact replay remains idempotent;
- projection canonical-write violation detection;
- revision rollback detection;
- missing evidence fail-closed;
- invalid network profile fail-closed;
- deterministic/order-independent link fault plan;
- profile catalog load;
- real subprocess start/restart/terminate with incarnation `1 -> 2`;
- JSONL evidence replay.

This pre-publication execution is implementer evidence, not independent verification and not an exact-head production gate. The published branch runner must be rerun on the exact candidate in a normal checkout/CI environment before any I1 closure claim.

## SM0 donor relationship

SM0 P11 demonstrated useful testing patterns: global writer checks across multiple authorities, stable identity checks, deterministic repeated crossings, explicit fault isolation and process soak. I1-A generalizes the **test infrastructure pattern** only. It does not copy SM0/P11 ownership semantics or its laboratory rollback model into production R2.

## Explicit non-claims

I1-A does not prove:

- durable Directory CAS/fencing;
- stale authority restart fencing in the production ownership model;
- AuthorityDomain transfer correctness;
- Player Carrying Domain correctness;
- gateway transparency/PRIMARY/OBSERVER semantics;
- real packet transport impairment;
- WAN smoothness;
- SM1-H* acceptance.

Those belong to later incubation/production checkpoints.

## Next I1 increments

Before I1 is called complete, extend the harness with:

1. scenario manifest describing Directory/Gateway/Authority/Client processes;
2. actual message scheduling/transport shim that consumes deterministic link decisions;
3. named crash/restart points and process event capture;
4. per-link queue/backpressure accounting;
5. merged multi-process evidence collection with clock-independent ordering metadata;
6. exact-head machine report produced by the repository runner;
7. long seeded replay demonstration reproducing an injected failure.

I2+ remains gated by a genuinely fresh independent review PASS of Architecture R2. I1-A itself does not satisfy that gate.
