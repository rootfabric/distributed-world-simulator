# V0 EG0 — Edge Gateway Contracts Candidate

Статус: **IMPLEMENTED CANDIDATE / NOT ACCEPTED / STACKED ON PR #185 / P6 BLOCKED**

Goal:

`TOPOLOGY_NEUTRAL_DTOS_AND_WORLD_GRAPH_CONTRACTS_PASS`

Initial stacked base:

`c5d7d0d682181f0a796d0e059508a1fdfe91b6e1`

Current R4 control base:

`b62535ea1ed7cf6f687ab5ee91f206cd6eea0a7d`

Branch:

`feature/eg0-edge-gateway-contracts-r1`

## Implemented

- topology-neutral client/Gateway frames and ingress/egress envelopes;
- Gateway session and route bindings;
- read-only projection subscription;
- Gateway locator descriptor;
- WorldDescriptor / WorldRelation;
- read-only/reconstructible GatewayWorldGraphSnapshot;
- ClientWorldView;
- AggregatedInterestPlan;
- explicit route/world/graph/view/interest revisions;
- canonical JSON golden fixtures;
- stale-revision and projection-authority negative tests;
- 1000-world global-knowledge-without-global-connection proof;
- Windows/Linux focused runners;
- HIGH-risk design brief + protocol glossary.

## Implementer validation

```text
Godot: 4.7.1.stable.double.custom_build.a13da4feb
SHA-256: bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
editor parse: PASS
base contracts: PASS (24 assertions)
canonical fixtures: PASS (39 assertions)
WorldGraph/View/Interest: PASS (27 assertions)
TOTAL: PASS (90 assertions)
```

## Proven candidate invariants

```text
client/gameplay identity is topology-neutral
Gateway route metadata is not authority
OperationId survives Gateway wrapping unchanged
mutating ingress requires ACTIVE route
WORLD_PROJECTION requires PROJECTION source
projection subscriptions are read-only
projection policies cannot grant mutation authority
GatewayDescriptor/ClientWorldView do not expose sim-server endpoint
graph cache is read-only + reconstructible
stale graph/relation/view revisions fail closed
1000 known worlds do not imply upstream connections
multiple sessions may aggregate one source-interest demand
```

## Explicit non-authority

This candidate does not:

- launch a Gateway process;
- implement EG1;
- activate P6;
- alter NX/AUTHORITY/World Directory ownership;
- become product ancestry;
- create `EDGE_GATEWAY_FOUNDATION_ACCEPTED`;
- self-review or self-verify.

Next allowed gate: exact-head Project Control, then fresh independent Reviewer and independent Verifier after the #185 dependency is accepted. EG1 remains blocked.
