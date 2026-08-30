# Distributed World Simulator — Current Project Frontiers

**Refresh date:** 2026-08-30  
**Canonical main at refresh:** `7055aef6c163099101588d5252d90ff77e089330`  
**Purpose:** human-readable routing snapshot. Machine truth remains in `config/control/**`.

## 1. Product frontier

```text
P4 ACCEPTED
 ↓
P5 ACCEPTED
 ↓
P6 ACCEPTED
 ↓
Edge Gateway ACCEPTED
 ↓
SM1 ACCEPTED
 ↓
RF0 architecture guardrail
 ↓
P7 Matter Production Convergence      P7.1 COMPLETE / P7.2 NEXT
 ↓
V0 PLAYABLE SEAMLESS PLANET           COMPOSITION ACCEPTANCE
```

Exact SM1 closure:

- runtime source `b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f`;
- runtime merge `acb9379cacc413fc25a65117fb1627f5a01b9736` / PR #327;
- verified tree `7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68`;
- formal acceptance `9cc89e6e8c6cfc81fc32873a29743e443d8229e6` / PR #329;
- acceptance record `config/control/harness/acceptance/V0-SM1-R1-CHECKPOINT-ACCEPTED-001.v1.json`.

PR #326 is historical proposal evidence, not a current product gate.

## 2. P7 ownership frontier

P7 is a production integration checkpoint over accepted foundations:

```text
P5 action/tool → SM1 authority route → MW4 mutation
MW5 persistence
MW6 network
MW7 interest
MW8 authority handoff
MW9 durable recovery
MW10 multi-region transaction when required
RL2/RL3 representation
MatterMaterialBatch → canonical Item Graph
```

No second Matter/terrain truth is allowed.

P7.0 owner-map R2 is accepted; P7.1 Tool→MW4 is complete and merged. The runtime frontier is P7.2 Bounded Planetary Matter Bubble.

## 3. Replication Foundation

RF0 is architecture-only and non-blocking.

```text
RF0 semantic boundary
RF1 shadow retained cache
RF2 first read-only consumer
```

Hard fences:

```text
REPLICATION != AUTHORITY
CACHE != PERSISTENCE
INTEREST != ACTIVATION
SERVER PROCESS != WORLD IDENTITY
cache hydration != WARM → ACTIVE authorization
```

RF1 may be semantically colocated in production, but lifecycle-decoupling acceptance uses
a separate-process cache topology. Permanent process separation remains optional.

## 4. Post-V0 successor lanes

```text
                 ┌── P8 First Mobile Construct
V0 PLAYABLE ─────┤
                 └── RF1 Shadow Cache → RF2
```

P8 and RF1 are dependency-independent, but pre-H0.3 execution still obeys the one-active-runtime-mutation-worker ceiling.

## 5. Stable/frozen foundations

- Matter: MW10 accepted stable baseline; RL3 accepted frozen surface/representation chain;
- Edge Gateway Foundation: accepted;
- P4/P5/P6 product foundations: accepted;
- SM1: accepted;
- S1 compute: proposal-only stable foundation;
- Construction T1B/C22: accepted/frozen evidence;
- G8: accepted/frozen baseline.

Do not restart these foundations inside P7 or RF.

## 6. Parallel playable test lane

A dedicated non-mutating composition lane is canonical:

`docs/plans/V0_PLAYABLE_SEAMLESS_TEST_LADDER_RU.md`.

Current test stage:

```text
V1 PLAYABLE SEAMLESS PRECHECK
```

V1 must be locally runnable in AUTOMATED and OBSERVE modes and reuse the already accepted
SM1 graphical, M5 graphical Item Graph and SM1+Item/P6 composition paths.

It may add only runners/tests/fixtures/observation helpers. It MUST NOT create missing
production semantics. Therefore it can run in parallel with P7.2 without consuming the
single runtime mutation worker.

Later promotions align with P7.3/P7.5/P7.6/P7.7 and converge into
`V0 PLAYABLE SEAMLESS PLANET` composition acceptance.

## 7. Parallel research

ECO, FABRIC and NX.C1 remain independent lanes unless main registers a concrete dependency.
They do not implicitly block P7.

## 8. Immediate work

```text
1. P7.0 COMPLETE.
2. P7.1 COMPLETE / MERGED.
3. P7.2 bounded planetary Matter bubble.
4. In parallel: implement V1 PLAYABLE SEAMLESS PRECHECK runners + coordinator + OBSERVE mode.
6. P7.3 MatterMaterialBatch → Item Graph with explicit mass quantization/residual accounting.
7. P7.4 persistence/restart composition.
8. P7.5 two-client convergence.
9. P7.6 seam + MW10 only for real multi-region mutations.
10. P7.7 graphical digging.
11. V0 PLAYABLE SEAMLESS PLANET composition acceptance.
```

## 9. Stop conditions

Stop if work creates a second canonical owner, duplicate Matter/terrain contracts,
P7-private persistence/resources/network authority, cache-based authority activation,
mandatory RF infrastructure without measured need, or dynamic placement before static correctness.


### P7.0 accepted correction

Fresh review rejected the first actor mapping because accepted P5 logical IDs can be single-segment while Matter requires canonical namespaced IDs. R2 uses the existing V0 `player_entity_id` and round-trips it to canonical PlayerRegistry state. No new identity owner was introduced.


### P7.0 canonical closure

```text
P7.0 merge       6b0143281a4a2bedeff7889f0bd6470a5fcfd60d
post-merge audit 33293384467 SUCCESS
standard PC0     YELLOW / NON_RED
directional PC0  YELLOW / NON_RED
remaining gate   DIRECTOR_DISPATCH
```
