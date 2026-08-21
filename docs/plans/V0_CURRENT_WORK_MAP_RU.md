# V0 — Current Primary Work Map

Статус: **PRIMARY WORK MAP CANDIDATE R5 / PRE-P6 EDGE GATEWAY FOUNDATION + CWIP**

После formal P5 acceptance текущая работа V0 идёт не в P6 runtime, а в обязательный pre-P6 Edge Gateway Foundation.

Текущий sequencing определяется:

- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md`
- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_R4_WORLD_GRAPH_AMENDMENT_RU.md`
- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_R5_CWIP_AMENDMENT_RU.md`

R4 остаётся normative для WorldGraph / View Planner / Interest Aggregator. R5 имеет приоритет для cross-world interactions и текущего execution order.

Связанные normative документы:

- `docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`
- `docs/network/EDGE_GATEWAY_WORLD_GRAPH_VIEW_PLANNER_SPEC_RU.md`
- `docs/network/EDGE_GATEWAY_CROSS_WORLD_INTERACTION_PROTOCOL_PLAN_RU.md`
- `docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`
- `config/control/harness/v0-edge-gateway-fabric-test-plan.v1.json`
- `config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`

Canonical roadmap main anchor:

`1d9de3c479c60045d613660b2a5c5db0374963f8`

Future P6 product base остаётся:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

## Current route

```text
P5 ACCEPTED
    |
    v
PRE-P6 EDGE GATEWAY FOUNDATION
    |
    v
EG0 Contracts / DTO / fixtures
    + WorldGraph contracts
    + View/Interest contracts
    + CWIP contracts
    |
    v
EG1 Client -> Gateway -> Server A
    |
    v
EG2 Auth / Session / Placement
    |
    v
EG3 Shared multiplexed Gateway->World tunnel pool
    |
    v
EG4 WorldGraph-driven projection aggregation
    + >=8-world planner walk
    + bounded dynamic upstream set
    |
    v
EG4.5 CROSS-WORLD INTERACTION ROUTING PROOF
    + projection hit -> candidate only
    + multi-authority collision proofs
    + deterministic first-hit resolution
    + synthetic exactly-once effect
    |
    v
EG5 Multi-Gateway nearest healthy Edge selection
    |
    v
EDGE_GATEWAY_FOUNDATION_ACCEPTED
    |
    +------------------------------------+
    |                                    |
    v                                    v
refresh P6 control                 EG6 multi-world authority pivot
activate P6 runtime                EG6.5 canonical cross-world effect
P6.1 -> P6.11                     EG7 Gateway rehome
    |                              EG8 WAN + CWIP faults
    |                              EG9 scale/fairness/CWIP soak
    +----------------+-------------------+
                     |
                     v
                P6 ACCEPTED
                     |
                     v
                ACTIVATE V0-SM1
                     |
                     v
Production Edge Gateway + Directory + multi-world authorities
                     |
                     v
seamless world + cross-world interactions behind one WorldConnection
                     |
                     v
                    P7
                     |
                     v
                    P8
```

## Hard sequencing rule

```text
P6 runtime mutation == FORBIDDEN
until
EDGE_GATEWAY_FOUNDATION_ACCEPTED
```

Pre-P6 cutoff теперь строго:

```text
EG0 + EG1 + EG2 + EG3 + EG4 + EG4.5 + EG5
```

EG6/EG6.5/EG7/EG8/EG9 не блокируют начало P6 после Foundation acceptance и продолжаются параллельно.

## Edge Gateway baseline

```text
Client -> nearest healthy Edge Gateway
Edge Gateway -> current ACTIVE authority
Edge Gateway -> WARM / projection / macro sources as required
```

Hard invariant:

```text
client_active_world_transports == 1
```

Client не получает simulation-server endpoint и не координирует server handoff или cross-world routing.

## WorldGraph / View baseline

Gateway использует read-only versioned WorldGraph cache:

```text
World Directory / WorldGraph
    -> GatewayWorldGraphCache
    -> Client View Planner
    -> Interest Aggregator
    -> Route / Link Manager
```

Hard rules:

```text
GLOBAL_KNOWLEDGE_DOES_NOT_IMPLY_GLOBAL_CONNECTION
WORLD_GRAPH_CACHE_IS_READ_ONLY_DERIVED_RECONSTRUCTIBLE
GATEWAY_VIEW_PLAN_IS_NOT_CANONICAL_WORLD_TRUTH
```

Gateway может знать metadata многих worlds, но открывает upstream только по реальному ACTIVE/WARM/projection interest.

## Shared backend links

Gateway->World baseline:

```text
1..K physical links per GatewayInstance <-> ServerInstance
many logical player sessions/subscriptions multiplexed over those links
```

EG3 доказывает no cross-session leakage, bounded queues, fairness/backpressure и независимый detach logical sessions.

## Projection baseline

```text
Authority A ACTIVE ------\
Projection B -------------> Gateway -> same client WorldConnection
Macro projection --------/
```

Projection может использоваться для visual/presentation и interaction candidate generation, но не для canonical mutation.

## Cross-World Interaction Protocol baseline

CWIP фиксирует роли:

```text
ACTION AUTHORITY
  validates action

EACH WORLD AUTHORITY
  validates only its own collision domain

ACTION AUTHORITY
  resolves first valid collision

TARGET EFFECT AUTHORITY
  alone commits canonical effect

GATEWAY
  routes/orchestrates protocol traffic only
```

Hard invariants:

```text
PROJECTION_HIT_IS_CANDIDATE_NOT_CANONICAL_EFFECT
GATEWAY_ROUTES_INTERACTION_BUT_DOES_NOT_RESOLVE_GAMEPLAY_TRUTH
ONE_INTERACTION_AT_MOST_ONE_CANONICAL_EFFECT_COMMIT
```

EG4.5 до P6 использует synthetic/read-only collision domains и synthetic effect ledger. Real product damage/effect commit остаётся EG6.5 после P6 activation.

## EG0 current worker delta

Уже начатый EG0 не перезапускается.

Кроме R4 WorldGraph contracts, до freeze требуется добавить:

- `InteractionTime`;
- `ReferenceFrameEvidence`;
- `CrossWorldInteractionIntent`;
- `InteractionDomainSegment`;
- `CollisionQuery`;
- `CollisionProof`;
- `InteractionResolution`;
- `EffectCommitRequest`;
- `EffectCommitResult`.

Новый exit:

```text
TOPOLOGY_NEUTRAL_DTOS_WORLD_GRAPH_AND_CWIP_CONTRACTS_PASS
```

Durable worker delta: PR #185 comment `#5367438252`.

## EG4.5 mandatory reference cases

```text
A. B shooter -> A target, clear path -> A target wins
B. B shooter -> C wall -> A target -> C blocks
C. B shooter -> C nearer target -> A farther target -> C target wins
```

Required results:

```text
CROSS_WORLD_INTERACTION_CONTRACTS_PASS
CROSS_WORLD_DOMAIN_ROUTING_PASS
MULTI_AUTHORITY_COLLISION_PROOF_PASS
DETERMINISTIC_FIRST_COLLISION_RESOLUTION_PASS
PROJECTION_HIT_IS_CANDIDATE_ONLY_PASS
CWIP_SYNTHETIC_EXACTLY_ONCE_EFFECT_PASS
```

## EG6.5 after P6 activation

EG6.5 превращает synthetic CWIP proof в реальный product effect commit.

Reference case — hitscan damage, если combat/health domain уже accepted; иначе сначала используется первый accepted mutable product domain через тот же protocol, а combat case становится обязательным при появлении domain.

Only target Effect Authority may commit target state.

## Multi-Gateway selection

Gateway выбирается по healthy network score, а не только по географии.

Минимум учитываются RTT, jitter, loss, health и capacity/load hints.

Routine world authority handoff не требует Gateway rehome. Gateway rehome — отдельный recovery event.

## Gateway authority boundary

Gateway маршрутизирует, мультиплексирует, агрегирует projection/interest и CWIP traffic, но не владеет:

- PlayerId / PlayerEntityId truth;
- Item Graph / Inventory / Equipment;
- Construction;
- persistence;
- OperationId dedup truth;
- authority ownership / AuthorityEpoch;
- canonical mutation authorization;
- canonical collision truth;
- canonical effect commit.

## P6 control warning

PR #182 и #184 остаются stale относительно mandatory pre-P6 gate и не должны давать P6 runtime authority до `EDGE_GATEWAY_FOUNDATION_ACCEPTED`.

После acceptance они должны быть refresh/rebase/replaced так, чтобы новый P6 Work Order прямо зависел от accepted Gateway Foundation.

## Operator rule

Текущий next work:

```text
IMPLEMENT / REVIEW / VERIFY
EG0 -> EG1 -> EG2 -> EG3 -> EG4 -> EG4.5 -> EG5
```

Не dispatch P6 runtime Implementer.
Не rotate V0 runtime mutation lease to P6.
Не реализовывать real product damage внутри pre-P6 CWIP proof.

Final rule:

```text
FIRST PROVE THE WORLD CONNECTION,
WORLD VIEW,
AND CROSS-WORLD INTERACTION ROUTING.

THEN BUILD P6 ON TOP OF IT.
```
