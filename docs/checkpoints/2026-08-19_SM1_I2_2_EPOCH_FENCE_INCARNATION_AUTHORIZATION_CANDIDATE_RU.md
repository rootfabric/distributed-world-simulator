# SM1-I2.2 — Epoch / Fence / Incarnation Authorization candidate

Status: `RESEARCH_ONLY_CANDIDATE`

Branch: `research/sm1-i2-authorization`

Accepted I2.1 donor base:

`f1fd65ad73da8c95612a641be0ad52048c90169a`

Accepted I2.1 gate:

`SM1_I2_1_REPAIR_R2_FRESH_INDEPENDENT_REVIEW_PASS`

Architecture base:

`87a9ca12c38a9b15069fb49a57bfa344b8c25cfa`

## Goal

I2.2 adds the smallest executable ownership-authorization layer on top of the accepted I2.1 Directory CAS semantics.

The checkpoint answers one question:

> Can a would-be canonical writer be accepted only when its ownership-critical tuple exactly matches current canonical Directory state, while every stale or forged tuple fails closed?

The tuple frozen by the R2 Repair architecture is:

```text
owner_authority_id
authority_epoch
fencing_token
authority_incarnation
```

`binding_generation` is intentionally not included yet because AuthorityBinding has not been introduced in this incubation stage.

## API

`MutationAuthorityClaim` contains:

```text
subject_or_domain_id
owner_authority_id
authority_epoch
fencing_token
authority_incarnation
```

`OwnershipDirectory.authorize_ownership_tuple(claim)` returns:

```text
AUTHORIZED
FENCED
NOT_FOUND
```

The decision runs under the same ownership `RLock` used by Directory CAS. Therefore an ownership CAS and an authorization decision are serialized with one unambiguous order.

`AUTHORIZED` means only:

> the ownership-critical tuple matched canonical Directory state at a linearized Directory decision point.

It does **not** mean that a gameplay mutation was committed. I2.2 does not yet implement binding checks, lease admission policy or gameplay-state commit coupling.

## Fail-closed rules

- exact current tuple -> `AUTHORIZED`;
- absent subject -> `NOT_FOUND`;
- different owner -> `FENCED`;
- stale or future epoch -> `FENCED`;
- stale or future fence -> `FENCED`;
- stale or future incarnation -> `FENCED`;
- any combination of mismatches -> `FENCED`;
- authorization is read-only and never changes the canonical OwnershipRecord.

The check uses exact equality. There is no `>= epoch`, `>= fence`, "newer-looking process wins", packet-freshness, route freshness or process-local recovery shortcut.

## Same-AuthorityId replacement

Required scenario:

```text
Directory: A/i1 @ epoch10 / fence50 / generation1
A/i1 claim -> AUTHORIZED

Directory CAS:
A/i1/F50/G1
    ->
A/i2/F51/G2

A/i1 claim after commit -> FENCED
A/i2 claim after commit -> AUTHORIZED
```

The old `A/i1` fails because both its `fencing_token` and `authority_incarnation` are stale even though its logical `AuthorityId` remains A and its epoch may remain unchanged.

## Owner transfer

Required scenario:

```text
A/i1 @ epoch10 / fence50
    CAS
B/i7 @ epoch11 / fence51

old A/i1 claim -> FENCED
new B/i7 claim -> AUTHORIZED
```

## Concurrency causality

I2.2 includes a race between:

- same-AuthorityId replacement CAS `A/i1 -> A/i2`;
- authorization attempt from old `A/i1`.

Both decisions share the same ownership lock.

Valid outcomes are only:

```text
AUTH old i1
CAS replacement
```

or:

```text
CAS replacement
FENCE old i1
```

If authorization observes post-replacement canonical state, it must never return `AUTHORIZED`.

After the replacement CAS has definitely returned `CAS_OK`, every later authorization attempt from old i1 must be `FENCED`.

## Machine evidence

Each decision emits:

```text
kind = OWNERSHIP_AUTHORIZATION
authorization_sequence
status
claim
observed
mismatched_fields
```

`authorization_sequence` is assigned under the ownership lock.

Evidence is intended to prove why a claim was accepted or fenced. It is not a durable or cross-process sequence.

## Component validation

Command:

```text
PYTHONPATH=. python3 -m unittest discover \
  -s tests/research/seamless/i2 \
  -p 'test_i2_*.py'
```

I2.2 adds `14` authorization tests while preserving the accepted I2.1 CAS behavior.

The I2.2 suite covers:

```text
I2.2-AUTH-01 exact current tuple authorized
I2.2-AUTH-02 wrong owner fenced
I2.2-AUTH-03 stale epoch fenced
I2.2-AUTH-04 stale fence fenced
I2.2-AUTH-05 stale incarnation fenced
I2.2-AUTH-06 forged/future tuple fenced
I2.2-AUTH-07 missing subject NOT_FOUND
I2.2-AUTH-08 same-AuthorityId replacement fences old incarnation
I2.2-AUTH-09 owner transfer fences old owner
I2.2-AUTH-10 authorization is read-only
I2.2-AUTH-11 machine evidence
I2.2-AUTH-12 concurrent replacement/authorization serialization
I2.2-AUTH-13 machine contract
I2.2-AUTH-14 invalid claim values
```

## Explicitly out of scope

I2.2 does not claim:

- durable storage;
- Directory restart convergence;
- actual process restart recovery;
- network partition recovery;
- AuthorityBinding/binding generation;
- lease admission semantics;
- atomic gameplay-state commit together with authorization;
- AuthorityDomain handoff;
- Gateway routing;
- Item Graph integration;
- player runtime integration.

These remain later I2/I3+ work.

## Next checkpoint

`SM1-I2.3 — Same-AuthorityId Incarnation Replacement`

The next stage should extend the accepted tuple authorization into process replacement/recovery scenarios, including ambiguous replacement responses and stale incarnation restart behavior, without yet claiming full durable Directory restart convergence.
