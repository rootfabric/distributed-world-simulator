# V0 PRE-P6 Edge Gateway Foundation — R4 World Graph / View Planner Amendment

Статус: **CURRENT EXECUTION AMENDMENT CANDIDATE / EG0 IN PROGRESS / P6 RUNTIME BLOCKED**

Base roadmap:

`docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md`

Normative architecture delta:

`docs/network/EDGE_GATEWAY_WORLD_GRAPH_VIEW_PLANNER_SPEC_RU.md`

Этот amendment не отменяет уже начатый EG0. Он расширяет EG0 до правильной границы прежде, чем contracts будут заморожены.

## 1. Почему изменение нужно сейчас

Текущий Gateway Foundation уже правильно фиксирует:

```text
Client -> nearest Gateway
one WorldConnection
shared Gateway->Server links
Gateway-mediated projections
```

Но для целевой модели не хватало явного слоя:

```text
World Graph
  -> Gateway View Planner
  -> Interest Aggregator
  -> dynamic upstream routes
```

Без него Gateway рискует стать только транспортным proxy, который получает готовый список subscriptions извне.

Целевая роль Gateway шире:

```text
Gateway знает ЧТО показать клиенту
и К КАКИМ world sources подключиться,
но не решает canonical ownership.
```

## 2. Новый pre-P6 маршрут

```text
EG0
 contracts + World Graph/View/Interest contracts
   |
   v
EG1
 Client -> Gateway -> saved/current world authority
   |
   v
EG2
 auth/session/placement
 nearest Gateway != saved world authority
   |
   v
EG3
 shared multiplexed Gateway<->World link pools
   |
   v
EG4
 WorldGraph-driven view planning
 projection aggregation
 multi-client interest aggregation
 >=8-world planner walk
 bounded upstream set
   |
   v
EG5
 multiple Edge Gateways
 nearest healthy edge selection
   |
   v
EDGE_GATEWAY_FOUNDATION_ACCEPTED
   |
   v
P6 runtime activation
```

## 3. Revised EG0

Existing EG0 work is retained.

Add mandatory contracts:

```text
WorldDescriptor
WorldRelation
GatewayWorldGraphSnapshot/cache input
ClientWorldView
AggregatedInterestPlan
ViewRevision
InterestRevision
```

EG0 exit changes from:

```text
TOPOLOGY_NEUTRAL_DTOS_PASS
```

to:

```text
TOPOLOGY_NEUTRAL_DTOS_AND_WORLD_GRAPH_CONTRACTS_PASS
```

Worker must update schema fixtures and tests before declaring EG0 complete.

## 4. Revised EG1/EG2

No redesign.

Add explicit invariant:

```text
nearest Gateway selection
!=
saved/current world authority selection
```

A saved player can be attached through a nearby Gateway to an authority located arbitrarily far away.

Client never receives simulation endpoint.

## 5. Revised EG3

Existing shared tunnel work remains.

Clarification:

```text
GatewayServerLinkPool
```

is keyed by real required source/server relationships, not by player count.

The same physical pool may carry:

- ACTIVE sessions;
- WARM/control sessions;
- projection subscriptions;
- multiple clients.

Logical routing remains isolated per session/subscription.

## 6. Revised EG4

EG4 now proves three things together:

1. one client connection aggregates ACTIVE + projection sources;
2. Gateway derives projection demand from WorldGraph + client interest;
3. Gateway does not accumulate links/subscriptions as client moves through many worlds.

Required machine scenario:

```text
known worlds >= 100
walk path >= 8 worlds
client transport = 1
active upstream set bounded
old subscriptions drain
stale route/view entries = 0 after grace
```

Required outputs:

```text
WORLD_GRAPH_DRIVEN_VIEW_PLANNING_PASS
MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS
INTEREST_AGGREGATION_PASS
BOUNDED_DYNAMIC_UPSTREAM_SET_PASS
EIGHT_WORLD_PLANNER_WALK_PASS
```

This is a planner/projection proof only; it does not claim canonical player handoff yet.

## 7. EG5 unchanged in purpose

EG5 still proves many Gateway POP/instances and nearest healthy path selection.

Additional assertion:

```text
world graph size / saved world location
does not influence edge selection except through explicit health/path policy
```

Routine world authority changes do not rehome Gateway.

## 8. Post-P6 EG6 change

EG6 must no longer stop at A<->B.

Initial bring-up may use A<->B, but donor acceptance requires repeated committed chain traversal:

```text
A -> B -> C -> D -> E -> ... -> A
```

with one stable Client<->Gateway connection and bounded ACTIVE/WARM/projection routes.

## 9. New hard invariants

```text
GLOBAL_KNOWLEDGE_DOES_NOT_IMPLY_GLOBAL_CONNECTION
WORLD_GRAPH_CACHE_IS_READ_ONLY_DERIVED_RECONSTRUCTIBLE
GATEWAY_VIEW_PLAN_IS_NOT_CANONICAL_WORLD_TRUTH
CLIENT_NEVER_SELECTS_SIMULATION_WORLD_ENDPOINT
INTEREST_IS_GATEWAY_MANAGED
STALE_UPSTREAM_SUBSCRIPTIONS_EVENTUALLY_ZERO
TRAVERSAL_HISTORY_DOES_NOT_CAUSE_UNBOUNDED_LINK_OR_MEMORY_GROWTH
```

## 10. Immediate instruction for the EG0 worker

Continue current EG0 branch/work.

Do not discard already implemented:

- Client/Gateway envelopes;
- session identity separation;
- channel definitions;
- schema infrastructure;
- fixtures that remain compatible.

Before freeze/closure add:

```text
WorldDescriptor
WorldRelation
GatewayWorldGraphSnapshot/cache input
ClientWorldView
AggregatedInterestPlan
ViewRevision
InterestRevision
```

and the corresponding stale-revision/read-only/aggregation fixtures.

The worker must treat this amendment as a delta to the active Work Order until a refreshed durable dispatch is published.
