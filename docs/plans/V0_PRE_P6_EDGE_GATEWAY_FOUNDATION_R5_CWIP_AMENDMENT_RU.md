# V0 PRE-P6 Edge Gateway Foundation — R5 Cross-World Interaction Protocol Amendment

Статус: **CURRENT EXECUTION AMENDMENT CANDIDATE / EG0 MAY CONTINUE / P6 RUNTIME BLOCKED**

Base execution plan:

- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md`
- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_R4_WORLD_GRAPH_AMENDMENT_RU.md`

Normative protocol plan:

- `docs/network/EDGE_GATEWAY_CROSS_WORLD_INTERACTION_PROTOCOL_PLAN_RU.md`

R5 дополняет R4. R4 остаётся normative для WorldGraph/View Planner/Interest Aggregator. R5 имеет приоритет в части cross-world interaction sequencing и acceptance.

## 1. Новая проблема, которую закрываем до P6

Projection должна быть не только визуальной, но и безопасно интерактивной.

Reference case:

```text
World B: shooter
World A: projected target
optional World C: blocker / closer target
```

Hard distinction:

```text
projection hit candidate != canonical hit/effect
```

Gateway координирует routing между world authorities, но не получает gameplay authority.

## 2. Новый execution order

```text
EG0
  + WorldGraph/View contracts
  + CWIP contract delta
   |
   v
EG1
   |
   v
EG2
   |
   v
EG3
   |
   v
EG4
  WorldGraph-driven projections
   |
   v
EG4.5
  CROSS_WORLD_INTERACTION_ROUTING_PROOF
   |
   v
EG5
   |
   v
EDGE_GATEWAY_FOUNDATION_ACCEPTED
   |
   v
P6 runtime activation
   |
   +-- P6.1 -> P6.11
   |
   +-- EG6 multi-world authority pivot
   +-- EG6.5 canonical cross-world effect commit
   +-- EG7 gateway rehome
   +-- EG8 fault matrix
   +-- EG9 scale/soak
```

P6 remains blocked until EG4.5 is accepted as part of `EDGE_GATEWAY_FOUNDATION_ACCEPTED`.

## 3. EG0 worker delta — do not restart

Existing EG0 work remains valid.

In addition to R4 contracts, EG0 must freeze semantic contracts for:

```text
InteractionTime
ReferenceFrameEvidence
CrossWorldInteractionIntent
InteractionDomainSegment
CollisionQuery
CollisionProof
InteractionResolution
EffectCommitRequest
EffectCommitResult
```

No product damage implementation is required in EG0.

New EG0 exit becomes:

```text
TOPOLOGY_NEUTRAL_DTOS_WORLD_GRAPH_AND_CWIP_CONTRACTS_PASS
```

## 4. EG4.5 — mandatory pre-P6 proof

Purpose: prove generic cross-world interaction routing without production gameplay mutation.

Responsibilities:

```text
ACTION AUTHORITY
  validates initiator action

GATEWAY + WORLD GRAPH
  discovers relevant world domains
  routes collision queries/proofs

EACH WORLD AUTHORITY
  validates only its own collision domain/history

ACTION AUTHORITY
  resolves first valid collision

SYNTHETIC EFFECT AUTHORITY / TEST LEDGER
  proves exactly-once effect semantics
```

Gateway never resolves the first collision and never writes canonical gameplay state.

Mandatory scenarios:

```text
A. clear B -> A target
B. C wall blocks A target
C. C nearer target wins over A farther target
```

Mandatory negative/fault cases:

- stale WorldGraph revision;
- stale authority epoch;
- stale route revision;
- stale reference-frame transform;
- out-of-window interaction time;
- duplicate/reordered CollisionProof;
- duplicate InteractionIntent;
- duplicate synthetic EffectCommitRequest;
- forged projection target hint;
- projection grant used as mutation authority.

Required exits:

```text
CROSS_WORLD_INTERACTION_CONTRACTS_PASS
CROSS_WORLD_DOMAIN_ROUTING_PASS
MULTI_AUTHORITY_COLLISION_PROOF_PASS
DETERMINISTIC_FIRST_COLLISION_RESOLUTION_PASS
PROJECTION_HIT_IS_CANDIDATE_ONLY_PASS
CWIP_SYNTHETIC_EXACTLY_ONCE_EFFECT_PASS
```

## 5. Updated Foundation acceptance

`EDGE_GATEWAY_FOUNDATION_ACCEPTED` additionally requires EG4.5 PASS and the six CWIP exits above.

This means before P6 we have already proven:

- one client-facing connection;
- shared multiplexed Gateway<->World links;
- WorldGraph-driven projections;
- Gateway-managed interest;
- interaction routing across multiple world authorities;
- first-collision resolution ownership boundaries;
- exactly-once synthetic effect semantics;
- Gateway canonical gameplay writes = 0.

## 6. EG6.5 after P6 activation

EG6.5 converts synthetic proof into product effect commit.

Reference case:

```text
remote projected player is hit by an action originating in another world
```

If combat/health domain exists, use hitscan damage. Otherwise first prove the protocol through an accepted mutable product domain and make hitscan damage mandatory when combat domain becomes available.

Hard rules:

```text
ACTION AUTHORITY validates action
TARGET EFFECT AUTHORITY alone mutates target
same InteractionId/OperationId retries are idempotent
stale target owner fails closed
Gateway never commits effect
```

Exit:

```text
CROSS_WORLD_CANONICAL_EFFECT_COMMIT_PASS
```

## 7. EG8 additions

CWIP fault matrix becomes mandatory:

- collision-domain timeout;
- stale/duplicate/conflicting proof;
- action-authority crash before effect commit;
- effect-authority crash after commit before reply;
- target authority migration during interaction;
- WorldGraph/transform revision change during interaction;
- duplicate/reordered protocol frames.

## 8. EG9 additions

Scale/soak includes concurrent cross-world interactions across multiple clients, Gateways and world pairs.

No unbounded growth is allowed in:

```text
interaction state
proof state
route state
retry state
Gateway queues
```

## 9. Worker instruction

The currently active EG0 worker should continue existing work and add CWIP contracts before freeze.

Do not implement real health/damage in EG0.

Do not start EG4.5 runtime before EG0 contracts are frozen and normal EG1-EG4 prerequisites are satisfied.

## 10. Final invariant

```text
PROJECTION MAY BE INTERACTIVE,
BUT ONLY AUTHORITIES CAN TURN AN INTERACTION INTO CANONICAL EFFECT.

GATEWAY ORCHESTRATES THE CROSS-WORLD PATH;
IT NEVER BECOMES GAMEPLAY TRUTH.
```
