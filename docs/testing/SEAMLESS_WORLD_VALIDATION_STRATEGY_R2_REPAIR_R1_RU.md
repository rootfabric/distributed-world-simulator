# Seamless World Validation Strategy R2 — Repair R1

Status: `RESEARCH / NORMATIVE VALIDATION OVERLAY — CURRENT WITH R2`

Applies to: `SEAMLESS_WORLD_VALIDATION_STRATEGY_R2_RU.md`

This overlay closes the validation gaps identified by review findings `R2-R-002` and `R2-R-004`. If it conflicts with the base R2 validation strategy, this overlay wins.

## 1. Ownership-incarnation tests

### OD-06 — same logical owner, new process incarnation

Fixture:

```text
D owner = A
AuthorityEpoch = 10
FencingToken = 50
AuthorityIncarnation = A/i1
```

Fault sequence:

```text
partition A/i1 without proving it dead
start replacement A/i2
Directory CAS replacement -> A/i2, fence 51, generation +1
allow old A/i1 to send mutations again
```

Required:

```text
A/i1 accepted mutations = 0
A/i2 accepted only after committed replacement record
writer_count <= 1
fencing_token monotonic
Directory generation monotonic
```

### OD-07 — replacement CAS response loss

Commit the A/i1 -> A/i2 replacement durably and drop the response. Retry must return/converge to the same current incarnation/fence and must not create a second writer lease.

### OD-08 — old incarnation durable restart

Restart A/i1 after A/i2 is current while owner AuthorityId remains A. A/i1 must still be fenced.

### DT-INC-01 — target restart after prepare

Prepare transfer for target incarnation B/j1, restart B as j2 before activation, and prove that j2 cannot activate j1-bound prepared state without explicit recovery/re-prepare tied to the Directory record.

## 2. PlayerAuthorityDomain ownership-truth test

### PAD-AUTH-01 — observed ownership metadata is non-authoritative

A prepared/debug snapshot may contain `observed_owner_*` fields. Corrupt or stale those observations while keeping Directory canonical state intact.

Required:

```text
mutation authorization follows Directory
route promotion follows Directory
recovery follows Directory
projection remains derived
forged observed_owner fields grant no authority
```

## 3. Machine-plan consistency gate

Project Control must parse and structurally validate both current machine plans:

```text
docs/plans/seamless-world-sm1-roadmap.v2.json
docs/plans/seamless-world-pre-p6-incubation.v1.json
```

Required checks:

- valid JSON object;
- current R2 repair overlay references exist;
- research semantic runtime and production runtime use distinct gates;
- no key named `required_before_first_runtime_work` exists in current roadmap;
- `required_before_first_production_runtime_work` contains the P6/main/lease/dispatch gates;
- pre-P6 semantic runtime requires fresh repaired-head independent architecture review;
- milestone/stage IDs are unique;
- every dependency resolves;
- dependency graphs are acyclic;
- H2A and H2B precede H5;
- H12 precedes D1, D2 and D3;
- incarnation fencing invariant is present;
- stale R1 candidate machine/human implementation artifacts are absent from current tree.

The check is a contract regression, not a production activation mechanism.
