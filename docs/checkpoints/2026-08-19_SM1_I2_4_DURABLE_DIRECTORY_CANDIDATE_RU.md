# SM1-I2.4 — Durable Directory candidate

Status: `RESEARCH_ONLY_CANDIDATE / DONOR_ONLY`

Branch: `research/sm1-i2-durable-directory`

Accepted predecessor:

- I2.3 exact base: `2e709249b5854e1bd0584041c3731e5bf102bde6`
- gate: `SM1_I2_3_FRESH_INDEPENDENT_REVIEW_PASS`
- accepted I2.2 Directory blob remains unchanged: `4cd3f97cb31e7afc1964595af3356ac1e83040e5`
- accepted I2.3 replacement blob remains unchanged: `2d7d12a41ee8fa61ef4bc66c32230db0eeeaf1a4`

## Goal

I2.4 replaces the process-lifetime-only storage assumption with a small durable ownership snapshot while preserving the accepted I2.1 CAS, I2.2 authorization and I2.3 same-AuthorityId replacement semantics.

This checkpoint proves one active Directory process can restart and recover the canonical ownership record without granting stale authority.

It does **not** yet prove network partition recovery, multiple simultaneous Directory writers, replicated consensus, liveness, leases or gameplay integration.

## Durable commit boundary

The prototype backend is POSIX atomic-file storage. A mutating operation is committed as:

```text
serialize complete canonical snapshot
write unique temp file
flush temp file
fsync(temp file)
        |
        | crash here => old canonical file remains truth
        v
os.replace(temp, canonical)
fsync(parent directory)
        |
        | durable commit point
        v
only now publish CREATED / CAS_OK
```

`CAS_OK` is therefore never returned before the new ownership snapshot has crossed the durable boundary.

If persistence raises at any ambiguous point, the live instance is poisoned and refuses lookup/authorization until reopened from canonical durable state. This prevents an in-memory stale tuple from being used after a commit whose response was lost.

## Snapshot contract

Canonical file fields:

```text
schema
storage_revision
records[]
checksum_sha256
```

`checksum_sha256` covers canonical JSON for schema + storage_revision + records. It detects accidental/torn/corrupt content; it is not an anti-tamper trust anchor.

`storage_revision` is a local durable snapshot revision. It survives reopen and advances only on durable mutation. It is not a distributed consensus index and does not detect external rollback of the whole file.

A corrupt canonical snapshot fails closed with `DurableDirectoryCorruption`; it is never interpreted as an empty Directory.

Stale temp files are never canonical ownership truth.

## Crash/restart predicates

### Pre-commit crash

```text
canonical: A/i1/F50/G1
write+fsync temp for A/i2/F51/G2
process exits before os.replace
restart Directory
```

Required:

```text
canonical == A/i1/F50/G1
storage_revision unchanged
retry may commit A/i2/F51/G2 normally
```

### Post-durable-commit / lost response

```text
canonical: A/i1/F50/G1
replace + fsync(parent) commits A/i2/F51/G2
process exits before caller receives CAS_OK
restart Directory
```

Required:

```text
canonical == A/i2/F51/G2
old A/i1 -> FENCED
new A/i2 -> AUTHORIZED
exact I2.3 retry -> ALREADY_COMMITTED
no second fence/generation increment
```

The tests include real subprocess termination with `os._exit()` at both boundaries rather than only exception simulation.

## Regression boundary

I2.4 does not modify the accepted `directory.py` or `incarnation_replacement.py`. The durable subclass reuses the accepted OwnershipRecord/result types and `validate_transition()`, while placing persistence before publication of successful mutations.

Failed `CAS_MISMATCH`, `NOT_FOUND` and `INVALID_TRANSITION` paths do not rewrite the durable snapshot or advance `storage_revision`.

## Evidence

Durability events:

```text
DURABLE_DIRECTORY_OPENED
DURABLE_CREATE_COMMITTED
DURABLE_CAS_COMMITTED
```

They carry `storage_revision` and snapshot checksum where applicable.

The accepted `CAS_RESULT.linearization_sequence` remains the CAS serialization evidence. `storage_revision` describes durable local snapshot progression, not global distributed ordering.

## Implementer validation

I2.4-specific suite:

```text
16/16 PASS
```

Includes:

- create/reopen;
- owner-transfer/reopen;
- same-AuthorityId replacement/reopen;
- pre-commit injected failure;
- post-commit lost response;
- failed/invalid CAS durable mutation-free checks;
- multi-subject preservation;
- checksum corruption fail-closed;
- malformed snapshot fail-closed;
- stale temp rejection;
- durable revision continuity;
- real subprocess exit before replace;
- real subprocess exit after durable commit;
- evidence contract;
- machine contract.

Additional restart stress:

```text
1000 pre-commit crash/reopen cycles PASS
1000 post-commit lost-response/reopen/retry cycles PASS
TOTAL 2000/2000 PASS
```

## Explicitly out of scope

- multiple simultaneous Directory process writers;
- Directory replication / consensus;
- network partition recovery;
- authority process liveness detection;
- lease admission policy;
- durable operation ledger;
- anti-tamper/external rollback detection;
- non-POSIX durability implementation;
- AuthorityBinding generation;
- atomic gameplay state commit;
- AuthorityDomain handoff;
- Gateway routing;
- Item Graph;
- player runtime;
- production SM1 activation.

## Next gate

I2.4 requires a genuinely fresh independent READ-ONLY exact-head review before I2.5 may begin.

Next intended checkpoint after PASS:

`SM1-I2.5 — Crash / Restart / Partition Fencing`
