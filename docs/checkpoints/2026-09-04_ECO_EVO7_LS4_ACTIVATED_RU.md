# ECO.EVO7 LS4 — Activated / Scope Frozen

Дата активации: 2026-09-04
Дата scope freeze: 2026-09-05

## Статус

```text
PERF2.CONV                  CLOSED / ACCEPTED
LS4                         ACTIVE
LS4 SCOPE CONTRACT          FROZEN
LS4.1 Multi-Species Ecology AUTHORIZED NEXT
LS4.2+                      BLOCKED BY PREDECESSOR ACCEPTANCE
```

## Exact accepted predecessor

```text
PERF2.CONV accepted control HEAD:
b4f73a4073ac16b2a1de535acd64ae16641d4588

TREE:
81caf408e75059fde6b897e0f967e8b7d373ca1e

Exact tested convergence runtime:
81a0b3fa60664684b02d8387e4693c5f328dbe28

TREE:
a192950483267dd428baf2d1daa25de915df2370

Accepted report hash:
1064567c83c1bd023589fdf9e36f8436b9624eeb928e8b7d413b92ce3254c3f6
```

## Frozen scope

LS4 North Star:

```text
Multi-Species Ecosystem
        +
Shared Resources
        +
WORLD <-> ECO feedback
```

Authoritative machine-readable scope:

```text
config/ecology/eco-evo7-ls4-scope-contract.v1.json
revision ECO.EVO7-LS4-SCOPE-2026-09-05-R1
blob 624076f10d85575315ef6b392be6345185a335f1
```

Detailed design:

```text
docs/plans/ECO_EVO7_LS4_SCOPE_CONTRACT_RU.md
```

## Ownership invariant

LS4 does not gain WORLD authority.

```text
WORLD owner
   -> immutable environment snapshot
   -> LS3/LS4 ecology
   -> bounded EnvironmentFeedbackProposal
   -> WORLD owner validates/applies
   -> new immutable environment snapshot
   -> ecology consumes it
```

Forbidden:

```text
ECO -> direct canonical WORLD mutation
```

VIS/PLAY remain presentation-only.

## Frozen stage order

```text
LS4.1 Multi-Species Ecology
  ↓
LS4.2 Interaction Graph
  ↓
LS4.3 Shared Resource Competition
  ↓
LS4.4 Trophic Network
  ↓
LS4.5 Disturbance Envelope
  ↓
LS4.6 Ecological Succession
  ↓
LS4.7 Ecosystem Engineering
  ↓
LS4.8 WORLD<->ECO Feedback Loop
  ↓
LS4.FINAL Emergent Ecosystem Challenge
  ↓
PLAY1 Living Ecosystem Region
```

Each major stage requires visual evidence.

## Exact scope test

```text
tests/ecology/eco_evo7_ls4_scope_contract_acceptance.gd
RUN_ECO_EVO7_LS4_SCOPE_TESTS.sh
RUN_ECO_EVO7_LS4_SCOPE_TESTS.ps1
```

The scope acceptance checks predecessor provenance, authority fences, minimum 3-species catalog, interaction kinds, shared resources, disturbance identity, proposal-only WORLD feedback, deterministic hashes, exact roadmap order, final challenge and LS4.1-only authorization.

## Current executable item

```text
LS4.1 — Multi-Species Ecology
```

Minimum executable falsifier:

- at least three functionally distinct species;
- same physical patch/environment chain;
- stable species catalog identity;
- no desired-biome placement;
- same LS3 dispersal/recruitment/competition authority path;
- deterministic same-input replay;
- physical counterfactual changes species distribution;
- LS4-VIS1 species distribution overlay is derived-only;
- predecessor behavior remains regression-bound.

No LS4.2 runtime is authorized before LS4.1 exact acceptance.
