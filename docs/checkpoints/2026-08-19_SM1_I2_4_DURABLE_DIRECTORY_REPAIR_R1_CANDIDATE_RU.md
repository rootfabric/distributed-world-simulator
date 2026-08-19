# SM1-I2.4 Repair R1 — strict canonical OwnershipRecord validation

Status: `RESEARCH_ONLY_REPAIR_CANDIDATE / DONOR_ONLY`

Branch: `research/sm1-i2-durable-directory`

Superseded reviewed I2.4 candidate:

`7411ddba1bb4f3048e3b8930d6868c1f643350be`

Blocking fresh independent review:

- verdict: `SM1_I2_4_FRESH_INDEPENDENT_REVIEW_FIX_REQUIRED`
- GitHub review: `#4972023390`
- findings: `I2.4-R-001`, `I2.4-R-002`

## Defect

The original I2.4 loader verified the snapshot checksum and then called `OwnershipRecord.from_mapping(raw_record)`. The accepted deserializer intentionally coerces values with `str(...)` and `int(...)`, which is appropriate for its generic mapping API but unsafe at the durable canonical boundary.

A checksum-valid but structurally invalid durable record could therefore be accepted as ownership truth, including:

```text
subject_or_domain_id: null -> "None"
authority_epoch: "10" -> 10
authority_epoch: 10.9 -> 10
```

This violated the I2.4 invariant `CORRUPT_CANONICAL_SNAPSHOT_FAILS_CLOSED`.

## Repair

Repair R1 keeps accepted `directory.py` unchanged and tightens only the durable snapshot loader.

Before constructing `OwnershipRecord`, each raw canonical record must now have exactly these fields:

```text
subject_or_domain_id
owner_authority_id
authority_epoch
fencing_token
directory_generation
authority_incarnation
state_revision
lease_state
route_revision
```

Types are strict JSON-domain types:

```text
subject_or_domain_id   string
owner_authority_id     string
lease_state            string

authority_epoch       integer, not bool
fencing_token          integer, not bool
directory_generation   integer, not bool
authority_incarnation  integer, not bool
state_revision         integer, not bool
route_revision         integer, not bool
```

Missing fields, extra fields, numeric strings, floats, booleans in integer fields, null strings and other type mismatches fail with `DurableDirectoryCorruption` before any coercing deserializer is invoked.

After strict shape/type validation, the `OwnershipRecord` constructor still performs the accepted semantic checks such as non-empty IDs, positive epoch/fence/generation/incarnation, non-negative revisions and allowed lease state.

## Regression test

New test:

`tests/research/seamless/i2/test_i2_4_durable_directory_repair_r1.py`

It writes snapshots with internally correct checksums and independently invalid raw record payloads. Required fail-closed matrix:

```text
null subject
numeric-string epoch
floating epoch
boolean epoch
numeric-string fence
floating state_revision
non-string lease_state
missing field
extra field
```

A valid checksum-valid record is first reopened successfully as a control.

The intended full I2.4 component count becomes `17/17 PASS` when the original 16 tests and this repair regression are executed together.

## Preserved scope

Repair R1 does not alter:

- accepted I2.1 compare-first CAS semantics;
- accepted I2.2 exact ownership tuple authorization;
- accepted I2.3 retry convergence;
- I2.4 durable commit ordering (`fsync(temp) -> os.replace -> fsync(parent) -> success`);
- pre/post durable-commit crash semantics;
- single-active-Directory-process POSIX scope;
- production activation state.

I2.5 remains locked until a fresh independent exact-head review passes this repair.
