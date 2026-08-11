# GLOBAL-P0 R3 — Parallel Implementation Plan (Refresh R1)

**Candidate:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Base:** `main @ 1112d1f7cfad1df18fb3621a537e191e674848c6`  
**Registry:** `75`  
**Promotion:** forbidden in this plan

## 1. Immediate project rule

R3 preparation may run in parallel with H0.1/C22, but R3 promotion may not invalidate the active H0.1 R2 checkpoint.

```text
H0.1 / C22 runtime train          GLOBAL-R3 architecture train
        |                                  |
        |                                  +-- refresh ownership
        |                                  +-- transition policy
        |                                  +-- evidence/review/PC0
        |                                  |
        +-- reach checkpoint boundary      +-- R3_REFRESHED_CANDIDATE
                         \                 /
                          \               /
                           +-- human promotion gate later
```

## 2. Activation classes

```text
A CONTRACT_NOW
  DTO/value objects/interfaces/validators/fakes/tests only

B ADAPTER_NOW
  adapters around accepted domains, no truth migration

C PRODUCTION_AFTER_GATE
  runtime only after named dependencies converge

D RESERVE_ONLY
  ownership reserved, no implementation yet
```

The fresh candidate itself creates no new runtime branch.

## 3. Wave A — only after canonical R3 promotion

Maximum four new foundation frontiers.

### IAM0 / IAM1 — Identity and Session

Class: A/B

Implement later:

```text
AccountId
PrincipalId
SessionId
ActorBinding
AuthenticationResult
SessionClaims
IdentityProviderPort
LocalIdentityProvider
```

Acceptance:

- reconnect changes SessionId without changing AccountId;
- network peer ID never becomes account identity;
- session expiration/revocation fails closed;
- gameplay stores are not imported into IAM.

### MAT0 — Material Ontology

Class: A

Implement later:

```text
MaterialDefinitionId
MaterialDefinition
MaterialPropertySet
MaterialRegistryPort
MaterialProjectionDescriptor
```

Fixture identities may include water, ice, oxygen, nitrogen, iron, steel, basalt, granite and soil. They are test fixtures, not final scientific content.

Acceptance:

- stable IDs/checksums;
- duplicate ID rejected;
- RenderMaterial cannot substitute canonical material ID;
- deterministic serialization/reload;
- no dependency on G9 runtime.

MAT0 is a hard prerequisite for G9.

### WT0 — WorldOperation contracts

Class: A

Implement later:

```text
WorldOperationId
WorldOperation
WorldOperationActor
DomainMutationIntent
WorldTransactionPlan
WorldOperationResult
WorldTransactionCompilerPort
```

Mock fixture:

```text
MOCK_MINE
  matter -10 kg material/iron
  item   +10 kg material/iron
```

WT plans only; M0 remains the atomic commit owner.

### WQ0 / WQ1 — World Query contracts

Class: A

Implement later:

```text
WorldQuery
WorldQueryScope
WorldQueryFilter
WorldQueryCandidate
WorldQueryResult
WorldQueryAdapterPort
WorldQueryPlanner
```

No canonical WQ database is permitted.

## 4. Wave B — after first contract freeze

```text
RF0/RF1   reference frames + geodesy adapter
TF0       simulation-time contracts
AUTHZ0    authorization policy contracts
LIFE0     lifecycle vocabulary
WB0/WB1   work-budget contracts + fake arbiter
COMPAT0   compatibility/version taxonomy
```

SD0 may start after RF0 shape is frozen.

## 5. Existing frontiers and R3 interaction

### H0.1 / C22

Current observed H0.1 R6 Work Order is PLANNED on exact current-main base. It remains R2 until its checkpoint boundary.

R3 rules:

```text
no architecture mutation inside H0.1 C22 Work Order
no R3 promotion while H0.1 is open
finish H0.1 or explicitly invalidate/rebuild it
```

### G

G8 is frozen accepted evidence. Do not rewrite G8 for R3.

After promotion + MAT0:

```text
fresh current-main G9
-> layered geology/material composition
```

### NX

NX.C0 remains preparation. NX.C1 starts after H0.1 PASS and, if R3 has been promoted by then, must use R3. If NX.C1 begins before R3 promotion, promotion must wait for its checkpoint boundary or explicitly refresh it.

### T / Construction

T1B stays frozen evidence. C22 convergence is handled by H0.1. T2.0 remains gated by C22 MAIN_INTEGRATED + TS0.4 + PC0 convergence.

### ECO / ECON

`ECO` is the live Evolutionary Ecology research program. It remains advisory/nonblocking and may continue research.

`ECON` is reserved for future world economy/markets/contracts. No ECON runtime work begins in this refresh.

### MATTER / S1

Remain stable foundations. New R3 programs consume them through explicit contracts; they are not replaced.

## 6. Parallel work allowed before promotion

Safe now:

```text
GLOBAL-R3 ownership/intersection review
GLOBAL-R3 Evidence Map
GLOBAL-R3 PC0/reviewer/verifier
ECO research validation
H0.1/C22 single runtime worker
V0 composition planning
```

Do not start yet:

```text
IAM0 production branch
MAT0 production branch
WT0 production branch
WQ0 production branch
G9 runtime
NX runtime because of R3 alone
ECON runtime
SP/ENV/AI/POP production
```

Wave A is prepared by this plan but activated only after canonical R3 promotion.

## 7. Promotion sequence

```text
R3_REFRESHED_CANDIDATE
    |
    +-- verify active runtime checkpoints are at safe boundaries
    +-- final current-main freshness
    +-- CRITICAL review
    +-- ownership/intersection PASS
    +-- Evidence Map PASS
    +-- standard + directional PC0 NON_RED
    |
    +-- HUMAN: GLOBAL_ARCHITECTURE_PROMOTION
            |
            +-- control-only canonical architecture update
            +-- post-merge PC0
            +-- create Wave A from one accepted R3 base
```

## 8. Long-range convergence

```text
R3 + Wave A
    -> IAM/MAT/WT/WQ foundations
    -> RF/TF/AUTHZ/LIFE/WB/COMPAT
    -> SD
    -> G9/G10 + GM
    -> seamless authority regions
    -> moving ship/station reference frames
    -> actor AI through AUTHZ/WQ/WT
    -> distributed living world
```

The architecture train must remain subordinate to checkpointed project development: architecture revision is a controlled compatibility boundary, not a reason to churn accepted runtime branches.
