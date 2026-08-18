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
