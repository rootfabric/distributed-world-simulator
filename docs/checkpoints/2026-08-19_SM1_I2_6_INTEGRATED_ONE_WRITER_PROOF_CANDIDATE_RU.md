# SM1-I2.6 — Integrated one-writer proof candidate

Status: `RESEARCH_ONLY_CANDIDATE / DONOR_ONLY`

Branch: `research/sm1-i2-one-writer-proof`

Accepted predecessor:

- I2.5 exact base: `f430bef4b8c942e860ba228e0a5c62fb9ac4eb9d`
- gate: `SM1_I2_5_FRESH_INDEPENDENT_REVIEW_PASS`
- accepted I2.4 Repair R1: `b4b7ea41e40cda748fc1920ebe9bb6c3c90f3f54`

## Goal

I2.6 integrates the accepted I2.1-I2.5 semantics into a deterministic one-writer decision-point proof.

The checkpoint proves that, while canonical OwnershipRecord is stable, at most one simultaneously tested process incarnation is admitted by the accepted mutation-admission path, and every admitted process presents the exact canonical ownership tuple.

The proof is intentionally about **authorization decision points**, not gameplay-state commit atomicity.

## Writer definition

For this checkpoint, a writer is:

`a process incarnation whose mutation attempt returns AUTHORIZED for the exact canonical OwnershipRecord tuple`.

Canonical ownership remains only in the Directory.

The new probe never grants ownership and never mutates ownership.

## Stable-round rule

A proof round samples canonical state before and after all attempts.

If canonical state changed during the round:

`CANONICAL_MOVED_INDETERMINATE`

The round is not counted as a one-writer PASS.

This prevents a legitimate A->B ownership transition occurring inside a probe window from being misreported as split-brain or as a clean one-writer result.

## Fail-closed zero-writer state

Zero authorized writers is valid when the canonical Directory is unreachable.

Example:

```text
A is canonical owner
A gate is partitioned from Directory
mutation attempt -> DIRECTORY_UNREACHABLE
authorized writers -> 0
```

The proof does not require availability during partition.

## Restart lifecycle invariant

`process_instance_id` remains harness metadata and grants no authority.

An overlapping restart of the same AuthorityId must rotate:

- `authority_incarnation`
- `fencing_token`

through accepted I2.3 same-AuthorityId replacement before mutation.

The old incarnation is then fenced.

## Duplicate exact canonical tuple

A critical negative oracle is explicit.

If two simultaneously live processes present the same exact current canonical tuple, both underlying I2.2 authorization decisions can succeed.

I2.6 therefore does **not** silently call this safe.

The probe reports:

`MULTIPLE_AUTHORIZED_VIOLATION`

The declared process lifecycle requires the exact current authority tuple not be cloned across simultaneously live process incarnations.

Cryptographic prevention of tuple cloning is not claimed by this checkpoint.

## Integrated fault schedule

The component suite covers:

- stable current owner plus stale tuple;
- partitioned current owner;
- A->B ownership transfer;
- stale authority process restart;
- durable Directory restart;
- same-AuthorityId incarnation replacement;
- competing restart replacements;
- 64 stale process incarnations plus the current writer;
- repartition after prior successful authorization;
- missing subject;
- future-looking tuple;
- multiple independent subjects;
- duplicate exact tuple violation detection;
- canonical movement during probe;
- evidence semantics;
- 200-round transfer/restart/partition stress;
- process-isolated old/current claims.

Required result under the declared lifecycle:

```text
one_writer_violations = 0
noncanonical_authorized = 0
stale_authorized = 0
```

except the deliberate duplicate-current-tuple falsification case, which must be detected as a violation.

## Evidence

Schema:

`distributed_world_simulator.sm1_i2_6_one_writer_evidence.v1`

Kind:

`ONE_WRITER_ROUND_RESULT`

`round_sequence` is local probe emission order only.

It is not:

- Directory CAS linearization;
- Directory authorization ordering;
- gameplay commit ordering;
- global distributed ordering.

## Scope boundary

Still out of scope:

- atomic gameplay-state commit;
- durable gameplay operation ledger;
- authority liveness detection;
- lease timeout/admission policy;
- automatic failover trigger;
- real WAN/socket partition transport;
- Directory replication/consensus;
- multiple simultaneous Directory writers;
- cryptographic anti-cloning of the current tuple;
- AuthorityBinding;
- AuthorityDomain handoff;
- Gateway;
- Item Graph;
- player runtime;
- production SM1 activation.

## Gate

I2.6 requires a genuinely fresh independent READ-ONLY exact-head review.

No next research checkpoint and no production SM1 activation may be inferred from implementer-side PASS alone.
