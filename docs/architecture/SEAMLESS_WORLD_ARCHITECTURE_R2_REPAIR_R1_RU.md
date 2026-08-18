# Seamless World Architecture R2 — Repair R1

Status: `RESEARCH / NORMATIVE REPAIR OVERLAY — CURRENT WITH R2`

Applies to: `SEAMLESS_WORLD_ARCHITECTURE_R2_RU.md`

Review findings closed by this overlay: `R2-R-002`, `R2-R-003`.

This file is **normative** for the current R2 candidate. If a statement in the base R2 document conflicts with this repair, this repair wins. It does not activate production SM1 and does not change the post-P6 product-lineage gate.

---

## 1. Canonical ownership remains Directory-owned

There is exactly one canonical ownership oracle:

```text
Ownership Directory / OwnershipRecord
```

Neither an `AuthorityDomain` payload, a gateway route, a projection, a prepared transfer snapshot nor a recovered process-local snapshot may grant writer authority.

A canonical mutation is accepted only if all ownership-critical values match the current Directory record and current subject binding:

```text
current owner_authority_id
current authority_epoch
current fencing_token
current authority_incarnation
current binding_generation       # when subject authority is inherited/bound
```

Any stale value fails closed.

---

## 2. Same-AuthorityId incarnation replacement is a fenced ownership transition

`AuthorityId` identifies the logical authority slot. `AuthorityIncarnation` identifies one concrete live process incarnation of that slot.

Therefore:

```text
AuthorityId != AuthorityIncarnation
```

Starting a replacement process with the same `AuthorityId` does **not** inherit writer authority merely because `owner_authority_id` and `authority_epoch` are unchanged.

### 2.1 Required replacement rule

If `Authority A / incarnation i1` is replaced by `Authority A / incarnation i2` while A remains logical owner, the Directory must commit an incarnation-replacement transition before `i2` may write:

```text
(A, epoch N, fence F, incarnation i1, generation G)
    CAS
(A, epoch N, fence F+1, incarnation i2, generation G+1)
```

Equivalent implementations may advance `AuthorityEpoch` as well, but they must at minimum rotate an ownership fence and Directory generation and bind the current record to `i2`.

The linearization point is the durable Directory commit of that replacement record.

### 2.2 Consequences

After the replacement commit:

- `A/i2` may become the active writer only after validating the committed record;
- `A/i1` is permanently stale for `fence F` even if it reconnects from a partition;
- process-local leases, cached routes or durable snapshots from `i1` cannot restore its writer capability;
- a gateway cannot choose between `i1` and `i2` by packet freshness alone;
- replayed mutations from `i1` are rejected even though the logical `AuthorityId` is still `A`.

### 2.3 Required mutation envelope check

Any ownership-critical mutation path must validate the effective tuple:

```text
(owner_authority_id,
 authority_epoch,
 fencing_token,
 authority_incarnation,
 binding_generation?)
```

against current canonical state.

`AuthorityIncarnation` is not observability-only metadata.

---

## 3. Corrected PlayerAuthorityDomain payload rule

The base R2 conceptual example showed:

```text
owner_authority_id
authority_epoch
```

inside `PlayerAuthorityDomain`.

For the current candidate, those fields are **not canonical domain-owned ownership state**.

The canonical domain payload is conceptually:

```text
PlayerAuthorityDomain {
    authority_domain_id
    player_entity_id
    domain_revision
    operation_sequence
    inventory_root_id
    carried_binding_generation
    timeline_stamp
}
```

Ownership is resolved from the current `OwnershipRecord` for `authority_domain_id`.

### 3.1 Snapshot provenance is allowed, but derived only

A transfer/debug snapshot may carry explicitly named observations:

```text
observed_owner_authority_id
observed_authority_epoch
observed_fencing_token
observed_authority_incarnation
observed_directory_generation
```

These fields are derived provenance only.

They are forbidden as a source for:

- mutation authorization;
- PRIMARY route promotion;
- ownership recovery;
- Directory reconstruction;
- stale-source reactivation;
- deciding which process is canonical writer.

The receiver must revalidate against the current Directory record before activation or canonical mutation.

---

## 4. Transfer and restart implications

The production domain-transfer sequence remains:

```text
SOURCE ACTIVE
TARGET WARM
SOURCE DOMAIN FROZEN
TARGET DURABLY PREPARED
DIRECTORY COMMITTED
TARGET ACTIVE
SOURCE RETIRED / READ_ONLY
```

This repair adds one rule:

> Target activation requires both the committed owner tuple and the committed target `AuthorityIncarnation` to match the activating process.

A target process that restarted between prepare and activation must not activate using a prepared record for its prior incarnation. It must follow an explicit recovery/re-prepare policy tied to the current Directory record.

---

## 5. Required falsification cases

The current validation set must include all of these:

### INC-01 same-owner zombie after replacement

```text
Directory: A/i1 owns D @ epoch 10 / fence 50
A/i1 partitions but keeps running
start A/i2
Directory CAS: A/i1/F50 -> A/i2/F51
A/i1 mutation -> REJECT STALE INCARNATION/FENCE
A/i2 mutation -> ACCEPT after activation
writer_count <= 1
```

### INC-02 replacement commit ambiguous response

Directory durably commits `A/i2/F51`, then response is lost. Retry must converge to the same committed record and must not allocate two active incarnations.

### INC-03 old incarnation restart

After `A/i2` is current, restart `A/i1` from durable local state. It remains fenced without requiring ownership to move to a different AuthorityId.

### INC-04 target restarts after prepare

A transfer prepares target `B/j1`, but B restarts as `B/j2` before Directory commit/activation. `j2` cannot activate a prepare bound to `j1` without the explicit recovery contract.

### PAD-01 no second ownership truth

Mutate snapshot `observed_owner_*` values while Directory remains unchanged. Authorization and routing promotion must continue to follow Directory and reject the forged/stale observation.

---

## 6. Freeze rule for H0/H1

`SM1-H0` must freeze `AuthorityIncarnation` as part of the ownership-critical authorization tuple.

`SM1-H1` must prove same-AuthorityId incarnation replacement by durable Directory transition and old-incarnation fencing before H2 can claim a production-capable Directory.

This rule also applies to pre-P6 `I2 Ownership Directory Prototype` evidence.
