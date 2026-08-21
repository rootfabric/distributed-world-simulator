# V0 Edge Gateway — World Graph / View Planner / Interest Aggregator Specification

Статус: **NORMATIVE AMENDMENT CANDIDATE / PRE-P6 EG FOUNDATION / NO P6 RUNTIME AUTHORITY**

Этот документ дополняет:

- `docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`
- `docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`
- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md`

При конфликте этот amendment имеет приоритет для EG0–EG6 в части world topology, projection planning и upstream subscription semantics.

## 1. Новое обязательное архитектурное решение

Gateway не должен быть пассивным ретранслятором уже готового списка projection subscriptions.

Целевая модель:

```text
World Directory / World Graph
        |
        | versioned read-only topology/policies
        v
Gateway WorldGraph Cache
        |
        v
Client View Planner
        |
        v
Interest Aggregator
        |
        v
Route / Link Manager
        |
        +---- ACTIVE authority
        +---- WARM authority
        +---- projection source(s)
        +---- macro/celestial source(s)
        |
        v
one Client WorldConnection
```

Gateway знает **что клиент должен видеть и какие upstream routes/subscriptions нужны**, но не становится canonical owner world topology или gameplay state.

Hard rule:

```text
WORLD DIRECTORY OWNS WORLD TOPOLOGY TRUTH.
DIRECTORY/AUTHORITY OWNS CANONICAL OWNERSHIP TRUTH.
GATEWAY OWNS ONLY DERIVED VIEW/INTEREST/ROUTING DECISIONS.
```

## 2. Global knowledge != global connection

Gateway может иметь доступ к metadata обо всех worlds, но не должен подключаться ко всем worlds.

```text
known_worlds = 1000
active_upstream_worlds_for_gateway = bounded by actual client interest
```

Hard invariant:

```text
GLOBAL_KNOWLEDGE_DOES_NOT_IMPLY_GLOBAL_CONNECTION
```

Physical Gateway<->World links масштабируются по active gateway-world pairs, а не по total worlds и не по clients * worlds.

## 3. World Graph contracts

EG0 MUST freeze versioned contracts at least for:

```text
WorldDescriptor {
    world_id
    world_kind
    reference_frame_id
    spatial_domain
    coverage/bounds
    authority_directory_key
    projection_capabilities
    projection_policy
    lod_classes
    visibility_rules
    interest_rules
    world_revision
}
```

```text
WorldRelation {
    relation_id
    world_a
    world_b
    relation_kind
    intersection_or_transition_region
    reference_frame_relation
    projection_policy
    relation_revision
}
```

Minimum `relation_kind` semantic vocabulary:

```text
NEIGHBOR
OVERLAP
CONTAINS
REFERENCE_FRAME_PARENT
REFERENCE_FRAME_CHILD
PORTAL_OR_TRANSITION
VISUALLY_RELEVANT
```

Concrete geometry encoding remains domain-specific and versioned.

## 4. Gateway read-only cache

Gateway maintains reconstructible:

```text
GatewayWorldGraphCache
```

Properties:

```text
READ_ONLY
DERIVED_FROM_WORLD_DIRECTORY
VERSIONED
RECONSTRUCTIBLE
NON_CANONICAL
```

Cache entries are fenced by revision/incarnation. Stale topology cannot authorize mutation.

Gateway is allowed to cache only relevant partitions of a very large graph; contract must not require loading every world into memory.

## 5. Client view planning

For each active client session Gateway derives:

```text
ClientWorldView {
    gateway_session_id
    anchor_world_id
    reference_frame_id
    active_authority_world
    warm_worlds[]
    projection_streams[]
    macro_sources[]
    view_revision
}
```

Each projection entry carries semantic data such as:

```text
source_world_id
projection_stream_id
lod_class
priority
visibility_reason
interest_revision
projection_grant
```

Gateway chooses client-facing view from:

- player position / interest anchor;
- camera/view requirements where allowed;
- reference frame;
- WorldGraph relations;
- distance / visibility / LOD policy;
- permissions/grants;
- bandwidth budget;
- source health;
- current ACTIVE/WARM route state.

Client MUST NOT choose worlds or servers itself.

## 6. Interest Aggregator

Gateway MUST aggregate demand from multiple clients before upstream subscription creation.

Example:

```text
Alice: A ACTIVE, B fine projection
Bob:   A ACTIVE, B fine projection, C coarse
Carol: D ACTIVE, C coarse
```

Physical/logical upstream shape may become:

```text
Gateway
  +-- A LinkPool
  +-- B LinkPool
  +-- C LinkPool
  +-- D LinkPool
```

rather than one subscription transport per client.

Required conceptual object:

```text
AggregatedInterestPlan {
    source_world_id
    source_role
    representation_or_lod
    subscriber_sessions[]
    aggregate_priority
    aggregate_budget
    interest_revision
}
```

The Gateway may de-duplicate compatible subscriptions while preserving per-client visibility and authorization rules.

## 7. Upstream lifecycle

Gateway Route/Link Manager opens or retains upstream relationships only for concrete need:

- ACTIVE authority for >=1 local session;
- WARM handoff candidate;
- projection source required by >=1 client view;
- macro/celestial source required by >=1 client view;
- bounded cross-authority interaction/reference-frame dependency.

When no client requires a source and no handoff/control reason remains:

```text
subscription -> drain -> close
```

Required invariant:

```text
STALE_UPSTREAM_SUBSCRIPTIONS_EVENTUALLY_ZERO
```

## 8. Saved player placement

Nearest Edge Gateway selection and saved world placement are independent.

Example:

```text
Client Australia
  -> nearest Gateway Sydney
  -> saved player world = W42
  -> W42 authority currently Frankfurt
  -> Gateway Sydney attaches to Frankfurt authority
```

Gateway MUST NOT move player ownership merely to improve ping.

## 9. Multi-world traversal semantics

The architecture MUST support unbounded logical traversal:

```text
W0 -> W1 -> W2 -> ... -> WN
```

without client topology knowledge.

Pre-P6 EG4 proves the planner/subscription side using a synthetic or read-only changing anchor over >=8 worlds:

```text
W0 -> W1 -> W2 -> W3 -> W4 -> W5 -> W6 -> W7 -> W6 -> ... -> W0
```

Required:

```text
client transport count = 1
known worlds may be large
connected upstream worlds remain bounded by interest
old subscriptions drain
old route/view entries do not leak
memory/link count does not grow with traversal history
```

This does NOT claim canonical authority handoff before P6.

Post-P6 EG6 MUST extend the authority pivot proof from A<->B to repeated multi-world traversal with actual committed ownership changes.

## 10. EG0 amendment — worker delta

If EG0 implementation already started, existing work remains valid.

Do NOT restart completed DTO/schema work unless incompatible.

Before EG0 can close, add/freeze at minimum:

- `WorldDescriptor`
- `WorldRelation`
- `GatewayWorldGraphSnapshot` or equivalent versioned cache input
- `ClientWorldView`
- `ProjectionDemand` / `ProjectionSubscription`
- `AggregatedInterestPlan`
- `ViewRevision`
- `InterestRevision`

Add fixtures/tests proving:

1. 100/1000 known worlds can be represented without requiring upstream connections.
2. World relations are versioned and stale revisions fail closed.
3. Client view plan references world IDs/opaque streams, never simulation endpoints.
4. Same world source can satisfy multiple client interests through one aggregated upstream demand.
5. Projection policy cannot grant mutation authority.
6. Gateway cache can be reconstructed from Directory data.
7. Gateway topology knowledge remains read-only.

New EG0 exit:

```text
TOPOLOGY_NEUTRAL_DTOS_AND_WORLD_GRAPH_CONTRACTS_PASS
```

## 11. EG4 amendment

EG4 is no longer only "A + B projection through one connection".

It MUST prove:

```text
WORLD_GRAPH_DRIVEN_VIEW_PLANNING_PASS
MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS
BOUNDED_DYNAMIC_UPSTREAM_SET_PASS
```

Graphical minimum still includes ACTIVE A + projection B.

Additional machine proof uses >=8 synthetic worlds and changing interest anchor to verify dynamic add/remove of projection subscriptions and absence of connection/subscription leaks.

## 12. EG6 amendment

EG6 baseline remains ACTIVE/WARM backend pivot, but donor completion must include repeated chain traversal:

```text
A -> B -> C -> D -> E -> ... -> A
```

with:

```text
same client WorldConnection
stable PlayerId / PlayerEntityId
one ACTIVE canonical writer
bounded WARM/projection set
stale route/subscription cleanup
OperationId continuity
```

## 13. Acceptance additions

`EDGE_GATEWAY_FOUNDATION_ACCEPTED` additionally requires:

```text
WORLD_GRAPH_CONTRACTS_PASS
WORLD_GRAPH_READ_ONLY_CACHE_PASS
CLIENT_VIEW_PLANNER_PASS
INTEREST_AGGREGATION_PASS
GLOBAL_KNOWLEDGE_NOT_GLOBAL_CONNECTION_PASS
BOUNDED_DYNAMIC_UPSTREAM_SET_PASS
EIGHT_WORLD_PLANNER_WALK_PASS
STALE_UPSTREAM_SUBSCRIPTIONS_EVENTUALLY_ZERO
```
