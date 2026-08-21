# V0 Edge Gateway — Cross-World Interaction Protocol (CWIP) Plan

Статус: **NORMATIVE PRE-P6/POST-P6 EXECUTION PLAN CANDIDATE / NO P6 RUNTIME AUTHORITY**

Связанные документы:

- `docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`
- `docs/network/EDGE_GATEWAY_WORLD_GRAPH_VIEW_PLANNER_SPEC_RU.md`
- `docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`
- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md`
- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_R5_CWIP_AMENDMENT_RU.md`

## 1. Цель

Сделать projection интерактивным представлением удалённой authoritative сущности без передачи authority проекции, клиенту или Gateway.

Эталонный сценарий:

```text
World B: shooter
World A: projected target
optional World C: blocker / closer target
```

Игрок может целиться и попадать в projection, но:

```text
PROJECTION_HIT != CANONICAL_EFFECT
```

Projection создаёт только `interaction candidate`.

## 2. Основные роли

```text
ACTION AUTHORITY
= authority, которая канонически подтверждает действие инициатора

COLLISION DOMAIN AUTHORITY
= authority, которая проверяет геометрию/коллизии своей части мира

EFFECT AUTHORITY
= authority, которая канонически изменяет целевой объект

GATEWAY
= маршрутизирует protocol traffic и использует WorldGraph,
  но не решает gameplay truth
```

Для hitscan reference case:

```text
Player B shoots -> Server B = ACTION AUTHORITY
Player A target -> Server A = EFFECT AUTHORITY
World C wall -> Server C = COLLISION DOMAIN AUTHORITY
```

## 3. Hard invariants

```text
PROJECTION_MAY_CREATE_INTERACTION_CANDIDATE
PROJECTION_NEVER_COMMITS_CANONICAL_EFFECT
ACTION_AUTHORITY_VALIDATES_ACTION
EACH_WORLD_AUTHORITY_VALIDATES_ONLY_ITS_COLLISION_DOMAIN
ACTION_AUTHORITY_RESOLVES_FIRST_VALID_COLLISION
TARGET_EFFECT_AUTHORITY_COMMITS_CANONICAL_EFFECT
GATEWAY_ROUTES_INTERACTION_BUT_DOES_NOT_RESOLVE_GAMEPLAY_TRUTH
ONE_INTERACTION_AT_MOST_ONE_CANONICAL_EFFECT_COMMIT
CROSS_WORLD_INTERACTION_USES_VERSIONED_TIME_AND_REFERENCE_FRAME_EVIDENCE
STALE_ROUTE_WORLDGRAPH_EPOCH_TIME_OR_TRANSFORM_EVIDENCE_FAILS_CLOSED
```

## 4. Protocol model

### 4.1 InteractionId / OperationId

Каждое cross-world действие имеет стабильные identifiers:

```text
interaction_id
operation_id
input_seq
```

Retry всегда использует тот же `interaction_id` / `operation_id`.

### 4.2 InteractionTime

Нельзя сопоставлять локальные server ticks напрямую.

Нужен versioned interaction time mapping:

```text
InteractionTime {
    simulation_epoch
    canonical_time
    source_local_tick
    time_mapping_revision
}
```

Конкретный clock implementation остаётся transport/simulation-owned, но CWIP требует общей временной семантики для rewind.

### 4.3 Reference frame evidence

Cross-world ray/volume никогда не передаётся как "голый Vector3" без provenance.

```text
ReferenceFrameEvidence {
    source_reference_frame_id
    target_reference_frame_id
    transform_revision
    world_graph_revision
}
```

### 4.4 CrossWorldInteractionIntent

Action Authority после проверки действия создаёт:

```text
CrossWorldInteractionIntent {
    interaction_id
    operation_id
    interaction_kind

    actor_id
    actor_entity_id
    action_authority
    action_authority_epoch

    interaction_time

    source_world_id
    source_reference_frame_id

    origin_or_shape
    direction_or_motion
    max_range_or_extent

    capability_definition_id
    capability_definition_revision

    optional_projection_target_hint
    projection_revision

    world_graph_revision
    route_revision
}
```

Target hint — только optimization. Он не является hit proof.

### 4.5 InteractionDomainSegment

Gateway/WorldGraph строит ordered набор world domains, которые потенциально пересекает interaction path:

```text
InteractionDomainSegment {
    world_id
    authority_ref
    path_t_start
    path_t_end
    reference_frame_evidence
    relation_revision
}
```

### 4.6 CollisionQuery

Gateway маршрутизирует query каждой relevant authority:

```text
CollisionQuery {
    interaction_id
    interaction_time
    domain_segment
    world_graph_revision
    authority_epoch_observed
    query_revision
}
```

### 4.7 CollisionProof

Каждая world authority проверяет только свою каноническую геометрию/history и отвечает:

```text
CollisionProof {
    interaction_id
    world_id
    authority_id
    authority_epoch

    path_t_start
    path_t_end

    first_collision_t?
    collided_entity_id?
    collision_kind
    hit_zone?

    interaction_time
    history_revision
    transform_revision
    proof_revision
}
```

Proof immutable/versioned.

### 4.8 InteractionResolution

Action Authority получает proofs и детерминированно выбирает первый допустимый collision:

```text
InteractionResolution {
    interaction_id
    result
    winning_world_id?
    winning_entity_id?
    winning_collision_t?
    proof_set_digest
    resolution_revision
}
```

Gateway не производит `InteractionResolution`.

### 4.9 EffectCommitRequest

Если first collision требует mutation другой authority:

```text
EffectCommitRequest {
    interaction_id
    operation_id
    resolution_digest

    target_entity_id
    target_authority
    target_authority_epoch_observed

    effect_kind
    effect_definition_id
    effect_payload
}
```

Effect Authority независимо проверяет ownership/epoch/idempotency и только после этого коммитит canonical effect.

### 4.10 EffectCommitResult

```text
EffectCommitResult {
    interaction_id
    operation_id
    result
    canonical_effect_revision?
    target_authority_epoch
}
```

Lost response -> retry same ids -> same canonical result.

## 5. Reference hitscan flow

```text
Client B
  -> Gateway
  -> Server B / ACTION AUTHORITY
       validates shooter, weapon/capability, origin, input
       creates InteractionIntent
  -> Gateway WorldGraph routing
       discovers B/C/A path segments
  -> Server B, C, A
       each returns CollisionProof for own domain
  -> Server B / ACTION AUTHORITY
       resolves nearest valid collision
  -> target EFFECT AUTHORITY
       exactly-once commit
  -> Gateways
       authoritative feedback to shooter and target clients
```

## 6. Pre-P6 scope

До P6 запрещено заявлять реальный product damage commit.

Pre-P6 должен доказать protocol semantics на synthetic collision/effect fixtures.

### CWIP-0 — EG0 contract delta

Добавить/freeze DTO/contracts:

- `InteractionId` semantics;
- `InteractionTime`;
- `ReferenceFrameEvidence`;
- `CrossWorldInteractionIntent`;
- `InteractionDomainSegment`;
- `CollisionQuery`;
- `CollisionProof`;
- `InteractionResolution`;
- `EffectCommitRequest`;
- `EffectCommitResult`.

Существующий EG0 не перезапускается; это bounded contract delta.

### CWIP-1 — EG4.5 synthetic interaction routing proof

После EG4 и до EG5 запускается отдельный mandatory pre-P6 stage:

```text
EG4.5 = CROSS_WORLD_INTERACTION_ROUTING_PROOF
```

Он использует synthetic/read-only collision domains и test effect ledger.

Обязательные cases:

```text
CASE A
B shooter -> A target
clear path
=> A target is winning candidate

CASE B
B shooter -> C wall -> A target
=> C blocks, A untouched

CASE C
B shooter -> C closer target -> A farther target
=> C target wins, A untouched
```

Дополнительно:

- stale WorldGraph revision rejected;
- stale authority epoch rejected;
- stale transform revision rejected;
- out-of-window InteractionTime rejected;
- duplicate InteractionIntent produces one resolution identity;
- duplicate EffectCommitRequest produces at-most-one synthetic commit;
- Gateway canonical gameplay writes = 0;
- Gateway never chooses first collision itself;
- client-facing transport count remains 1.

Required exits:

```text
CROSS_WORLD_INTERACTION_CONTRACTS_PASS
CROSS_WORLD_DOMAIN_ROUTING_PASS
MULTI_AUTHORITY_COLLISION_PROOF_PASS
DETERMINISTIC_FIRST_COLLISION_RESOLUTION_PASS
PROJECTION_HIT_IS_CANDIDATE_ONLY_PASS
CWIP_SYNTHETIC_EXACTLY_ONCE_EFFECT_PASS
```

## 7. Post-P6 scope

### EG6.5 — canonical product effect commit

После P6 activation, параллельно с EG6 multi-world handoff:

```text
EG6.5 = CROSS_WORLD_CANONICAL_EFFECT_COMMIT
```

Reference product case — hitscan damage, если combat/health domain уже существует. Если product combat ещё не принят, сначала используется первый accepted mutable product domain через тот же protocol, а hitscan damage становится обязательным при появлении combat domain.

EG6.5 доказывает:

- Action Authority подтверждает действие;
- target authority может находиться на другом server;
- target authority alone commits effect;
- effect exactly-once under lost reply/retry;
- target ownership change before commit causes fail-closed reroute/retry, not stale mutation;
- action authority cannot directly mutate target state;
- projection revision is never sufficient authority;
- same client WorldConnection survives interaction;
- authoritative feedback reaches shooter and target through their Gateways.

Required exit:

```text
CROSS_WORLD_CANONICAL_EFFECT_COMMIT_PASS
```

## 8. EG8 fault-matrix additions

Добавить:

- one collision-domain server timeout;
- stale CollisionProof;
- duplicated CollisionProof;
- conflicting proof revision;
- action authority crash after proofs before effect commit;
- effect authority crash after commit before reply;
- target authority migration during interaction;
- WorldGraph revision changes during interaction;
- reference-frame transform revision changes during interaction;
- Gateway route cache stale;
- duplicate/reordered cross-world protocol frames.

Correctness rule: ambiguous state fails closed or retries idempotently; never speculative double effect.

## 9. EG9 scale additions

Soak includes many concurrent cross-world interactions from multiple Gateway sessions and multiple world pairs.

Measure:

- interactions/sec;
- proof fan-out count;
- proof latency;
- resolution latency;
- effect commit latency;
- retries;
- stale-proof rejects;
- duplicate suppression;
- per-Gateway interaction routing queues;
- leak-free interaction state cleanup.

## 10. Final contract

```text
PROJECTION MAY BE INTERACTIVE.
PROJECTION MAY CREATE A CANDIDATE.
PROJECTION NEVER COMMITS AN EFFECT.

ACTION AUTHORITY VALIDATES THE ACTION.
EACH WORLD AUTHORITY VALIDATES ITS OWN COLLISION DOMAIN.
ACTION AUTHORITY RESOLVES THE FIRST VALID COLLISION.
TARGET EFFECT AUTHORITY COMMITS THE CANONICAL EFFECT.

GATEWAY ORCHESTRATES ROUTING, NOT GAMEPLAY TRUTH.
```
