# Seamless World — CURRENT research architecture

Status: `RESEARCH CURRENT POINTER — NOT PRODUCTION ACTIVATION`

Branch: `research/seamless-world-architecture-r1`

## Current candidate set

For any new review, planning, Work Order drafting or future implementation design, use this set as the current seamless-world candidate:

1. `docs/architecture/SEAMLESS_WORLD_ARCHITECTURE_R2_RU.md`
2. `docs/plans/SEAMLESS_WORLD_SM1_ROADMAP_R2_RU.md`
3. `docs/plans/seamless-world-sm1-roadmap.v2.json`
4. `docs/testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_R2_RU.md`
5. `docs/architecture/SEAMLESS_WORLD_R2_DECISION_RECORD_RU.md`
6. `docs/plans/SEAMLESS_WORLD_PRE_P6_INCUBATION_PLAN_RU.md`
7. `docs/plans/seamless-world-pre-p6-incubation.v1.json`

## Pre-P6 development rule

The pre-P6 incubation plan is now the current rule for parallel seamless development while the active V0/P product train continues.

It allows research-only engineering before P6 in bounded incubation stages:

```text
I0 architecture closure
I1 research harness
I2 ownership directory prototype
I3 generic AuthorityDomain transfer
I4 Player Carrying Domain lab
I5 Edge Gateway incubation
I6 projection/AOI + bounded cross-owner operations
I7 fault/WAN/soak rehearsal
I8 production port plan + Work Order pack
```

I0/I1 scaffolding may proceed now. I2 and later semantic runtime prototypes require fresh independent Architecture R2 review PASS first.

None of these stages activates production SM1, changes canonical product owners, bypasses P5/P6, or substitutes research evidence for future checkpoint acceptance.

If P6 closes while incubation succeeds, the intended result is that the project already has reviewed donor carriers, machine evidence, port maps and Work Order drafts. Production SM1 still starts only from the exact accepted successor declared by then-current `main` after explicit `ACTIVATE_V0_SM1` and the normal mutation-lease/dispatch gates.

## Superseded for future implementation planning

The following remain preserved as research history/provenance but are not the current implementation plan:

- `docs/architecture/SEAMLESS_WORLD_ARCHITECTURE_R1_RU.md`
- `docs/plans/SEAMLESS_WORLD_SM1_ROADMAP_RU.md`
- `docs/plans/seamless-world-sm1-roadmap.v1.json`
- `docs/testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_RU.md`

The R1 provenance document remains useful historical/source material:

- `docs/architecture/SEAMLESS_WORLD_PROVENANCE_AND_RATIONALE_RU.md`

## Key R2 changes

R2 adds or tightens:

- `AuthorityDomain` as ownership/migration closure;
- `AuthorityBinding` with inherited authority for carried/nested state;
- `PlayerAuthorityDomain`;
- `DomainMutationBarrier`;
- pickup/drop Item Graph + authority-binding consistency;
- temporal/tick continuity;
- protocol/build compatibility before target prepare;
- gateway mobility including quality-driven rehome;
- strict prohibition on old-source writer rollback after `DIRECTORY_COMMITTED`;
- `SM1-H2A` and `SM1-H2B` before gateway-mediated player handoff;
- H5 now transfers a real player domain, not a naked player;
- H10 is specifically a **physical** InteractionIsland checkpoint;
- H12 includes an end-to-end player + nested inventory + gateway rehome + fault journey.

## Control rule

This pointer does not activate runtime work.

Future production SM1 must start from the exact accepted predecessor declared by then-current `main` after explicit main-owned SM1 activation. Research/SM0 branches are evidence donors only.
