# SM1-I2.3 — Same-AuthorityId Incarnation Replacement candidate

Status: `RESEARCH_ONLY_CANDIDATE`

Branch: `research/sm1-i2-incarnation-replacement`

Accepted I2.2 base:

`c09a53b5c7aba10c091e8cfb2ea8307d5f6b39da`

Accepted I2.2 gate:

`SM1_I2_2_FRESH_INDEPENDENT_REVIEW_PASS`

Accepted I2.1 base:

`f1fd65ad73da8c95612a641be0ad52048c90169a`

Architecture base:

`87a9ca12c38a9b15069fb49a57bfa344b8c25cfa`

## Goal

I2.3 closes the next Ownership Directory incubation question: can one logical `AuthorityId` replace a concrete process incarnation without creating a second writer, and can an ambiguous successful response be retried without rotating ownership again?

Canonical ownership remains exclusively in the accepted I2.1 `OwnershipDirectory`. I2.3 does not add a second ownership store, does not allocate fencing tokens or Directory generations, and does not bypass `compare_and_swap()`.

## Replacement operation

The candidate adds:

```text
IncarnationReplacementRequest {
  expected: OwnershipRecord
  desired: OwnershipRecord
}

IncarnationReplacementCoordinator.replace(request)
```

The operation is intentionally restricted to the same logical authority:

```text
expected.subject == desired.subject
expected.owner_authority_id == desired.owner_authority_id
expected.authority_incarnation != desired.authority_incarnation
```

Fence/generation/epoch validity remains owned by the accepted Directory transition validator.

Possible results:

```text
REPLACED
ALREADY_COMMITTED
STALE_REPLACEMENT
INVALID_REPLACEMENT
NOT_FOUND
```

## Normal replacement

```text
A/i1 @ epoch10 / fence50 / generation1
    -> Directory CAS ->
A/i2 @ epoch10 / fence51 / generation2
```

The first successful call returns:

```text
REPLACED
Directory CAS = CAS_OK
```

After the commit:

```text
A/i1 mutation authorization -> FENCED
A/i2 mutation authorization -> AUTHORIZED
```

The logical `AuthorityId` and epoch may remain unchanged. The rotated fence and new `AuthorityIncarnation` prevent the old process from regaining writer authority.

## Ambiguous response convergence

Critical I2.3 case:

```text
1. Directory commits A/i1/F50/G1 -> A/i2/F51/G2.
2. Success response is lost.
3. Caller retries the exact same expected/desired replacement.
```

The accepted I2.1 CAS returns `CAS_MISMATCH` on retry because current state no longer equals old `expected`.

I2.3 interprets only this exact convergence condition:

```text
CAS_MISMATCH
and current == desired
    -> ALREADY_COMMITTED
```

It does not create another transition. Therefore exact retry leaves:

```text
fence = 51
Directory generation = 2
incarnation = i2
```

No second fence/generation rotation is permitted.

If canonical state later advances beyond the original desired record, replay is not called already committed:

```text
current != desired -> STALE_REPLACEMENT
```

## Concurrency cases

### Duplicate same replacement

Two simultaneous identical requests from the same expected state must converge as:

```text
exactly one Directory CAS_OK -> REPLACED
exactly one CAS_MISMATCH with current==desired -> ALREADY_COMMITTED
final canonical record == desired
```

### Competing different replacements

For example:

```text
A/i1 -> A/i2
A/i1 -> A/i3
```

Only one may install a canonical record. The loser returns `STALE_REPLACEMENT`. There is never a canonical two-incarnation state.

## Stale local restart model

I2.3 does not yet claim real process restart recovery or durable Directory restart.

It does prove the semantic predicate needed later: if an old process restarts from stale local ownership state after `A/i2` is canonical, reconstructing the old `A/i1/F50` ownership claim still returns `FENCED` under accepted I2.2 authorization.

This prevents local cached ownership state from resurrecting writer capability.

## Evidence

I2.3 emits local replacement-result evidence:

```text
kind = INCARNATION_REPLACEMENT_RESULT
emission_sequence
status
directory_cas_status
expected
desired
observed
current
error
```

`emission_sequence` means only local result emission order. It is deliberately **not** advertised as Directory linearization order.

Canonical CAS causality remains the accepted I2.1 `CAS_RESULT.linearization_sequence` evidence.

## Validation

I2.3-specific suite before publication:

```text
16/16 PASS
```

Coverage:

```text
I2.3-INC-01 valid same-AuthorityId replacement
I2.3-INC-02 ambiguous response exact retry convergence
I2.3-INC-03 concurrent duplicate request
I2.3-INC-04 competing replacements one winner
I2.3-INC-05 old incarnation fenced after commit
I2.3-INC-06 same AuthorityId/epoch cannot rescue old incarnation
I2.3-INC-07 stale local restart claim remains fenced
I2.3-INC-08 replay after later replacement becomes stale
I2.3-INC-09 missing canonical record
I2.3-INC-10 owner change rejected as wrong operation kind
I2.3-INC-11 same incarnation rejected
I2.3-INC-12 reused fence invalid and mutation-free
I2.3-INC-13 non-increasing generation invalid and mutation-free
I2.3-INC-14 replacement evidence semantics
I2.3-INC-15 Directory CAS evidence proves single commit on retry
I2.3-INC-16 machine contract consistency
```

Additional stress:

```text
2000 concurrent duplicate-retry iterations PASS
```

Each iteration requires:

```text
statuses = {REPLACED, ALREADY_COMMITTED}
final == A/i2/F51/G2
old i1 authorization == FENCED
new i2 authorization == AUTHORIZED
```

## Explicitly out of scope

I2.3 does not claim:

- durable Directory storage;
- Directory process restart/recovery;
- network partition recovery;
- durable replacement-operation ledger;
- process liveness detection;
- lease admission policy;
- AuthorityBinding generation;
- atomic gameplay-state commit;
- AuthorityDomain handoff;
- Gateway routing;
- Item Graph integration;
- player runtime integration.

Those remain later I2/I3 work.

## Next checkpoint

`SM1-I2.4 — Durable Directory`

I2.4 should make the accepted ownership/CAS/replacement semantics survive Directory process restart and prove pre/post durable-commit convergence without changing the accepted semantic contracts.
