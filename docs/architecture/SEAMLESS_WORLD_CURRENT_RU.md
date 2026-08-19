# Seamless World — CURRENT research architecture

Status: `RESEARCH CURRENT POINTER — NOT PRODUCTION ACTIVATION`

Branch: `research/seamless-world-architecture-r1`

## Current candidate set

For any new review, planning, Work Order drafting or future implementation design, use the following set together:

1. `docs/architecture/SEAMLESS_WORLD_ARCHITECTURE_R2_RU.md`
2. `docs/architecture/SEAMLESS_WORLD_ARCHITECTURE_R2_REPAIR_R1_RU.md` — **normative repair overlay; wins on conflict**
3. `docs/architecture/SEAMLESS_WORLD_R2_DECISION_RECORD_RU.md`
4. `docs/plans/SEAMLESS_WORLD_SM1_ROADMAP_R2_RU.md`
5. `docs/plans/seamless-world-sm1-roadmap.v2.json`
6. `docs/testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_R2_RU.md`
7. `docs/testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_R2_REPAIR_R1_RU.md` — **normative validation overlay**
8. `docs/plans/SEAMLESS_WORLD_PRE_P6_INCUBATION_PLAN_RU.md`
9. `docs/plans/seamless-world-pre-p6-incubation.v1.json`

The repair overlay closes the reviewed same-AuthorityId incarnation fencing gap and removes PlayerAuthorityDomain as a possible second ownership truth.

## Machine-plan gate semantics

There are two intentionally different runtime gates:

```text
RESEARCH SEMANTIC INCUBATION RUNTIME
  -> allowed only after fresh independent review PASS on the repaired exact PR #137 HEAD

PRODUCTION SM1 RUNTIME
  -> allowed only after P6 acceptance + main ACTIVATE decision + exact production base
     + fresh epoch/work order + mutation lease + Director dispatch
```

The current machine roadmap encodes these separately. The ambiguous historical key `required_before_first_runtime_work` is forbidden by Project Control regression.

## Pre-P6 development rule

The pre-P6 incubation plan remains the current rule for parallel seamless research while the V0/P product train continues.

I0/I1 scaffolding may proceed under its existing bounded rules. I2 and later semantic prototypes require a **genuinely fresh independent** review PASS on the repaired exact architecture HEAD.

Incubation remains donor-only:

- no production activation;
- no active V0/P canonical owner mutation;
- no P5/P6 bypass;
- no production mutation-lease rotation to SM1;
- no incubation PASS substituted for future SM1 checkpoint acceptance;
- no research branch used as the production branch base.

## R1 historical routing

The former R1 implementation-candidate files are intentionally removed from the current tree so direct consumers cannot mistake them for CURRENT candidates:

```text
docs/architecture/SEAMLESS_WORLD_ARCHITECTURE_R1_RU.md
docs/plans/SEAMLESS_WORLD_SM1_ROADMAP_RU.md
docs/plans/seamless-world-sm1-roadmap.v1.json
docs/testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_RU.md
```

They remain preserved in Git history, including the pre-repair candidate HEAD `693043c3be2bc7c7cb0c728b87b88d6018899d6b`.

The provenance/rationale document remains in the current tree because it records source history rather than a competing implementation candidate:

`docs/architecture/SEAMLESS_WORLD_PROVENANCE_AND_RATIONALE_RU.md`

## Key R2 + Repair R1 rules

- `AuthorityDomain` is ownership/migration closure.
- `InteractionIsland` is physical/co-simulation locality, not ordinary inventory ownership.
- Item Graph remains canonical for item/container structure.
- `DIRECTORY_COMMITTED` remains the ownership linearization point.
- old-source writer rollback after Directory commit is forbidden.
- canonical mutation authorization validates current owner, epoch, fence **and AuthorityIncarnation**.
- same-AuthorityId process replacement requires a durable Directory incarnation/fence transition.
- PlayerAuthorityDomain carries gameplay/domain state; ownership metadata inside snapshots is derived `observed_*` provenance only.
- H2A/H2B precede gateway-mediated H5.
- Gateway remains non-authoritative.
- static H12 precedes dynamic D1/D2/D3.

## Production activation boundary

Production SM1 still starts only from the exact accepted predecessor declared by then-current `main` after explicit post-P6 `ACTIVATE_V0_SM1` and normal control gates.

Never use SM0 or this research lineage wholesale as the production base.
