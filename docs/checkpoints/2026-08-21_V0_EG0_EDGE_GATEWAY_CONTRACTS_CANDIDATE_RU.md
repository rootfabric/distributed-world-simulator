# V0 EG0 — Edge Gateway Contracts Candidate

Статус: **R5 CWIP + CONNECT-GATE IMPLEMENTATION CANDIDATE / NOT ACCEPTED / STACKED ON PR #185 / P6 BLOCKED**

Goal:

`TOPOLOGY_NEUTRAL_DTOS_WORLD_GRAPH_AND_CWIP_CONTRACTS_PASS`

Current control dependency:

`PR #185 @ d83ba3598d8a4cbf3a313633c4e42a85397a3a7f`

Branch:

`feature/eg0-edge-gateway-contracts-r1`

## Implemented contract families

Gateway/session:

- `ClientWorldFrame`;
- `GatewayIngressEnvelope`;
- `GatewayEgressEnvelope`;
- `GatewaySessionBinding`;
- `GatewayRouteBinding`;
- `ProjectionSubscription`;
- `GatewayDescriptor`.

World Graph / View / Interest:

- `WorldDescriptor`;
- `WorldRelation`;
- `GatewayWorldGraphSnapshot`;
- `ClientWorldView`;
- `AggregatedInterestPlan`;
- explicit route/world/graph/view/interest revisions.

R5 CWIP:

- `InteractionTime`;
- `ReferenceFrameEvidence`;
- `CrossWorldInteractionIntent`;
- `InteractionDomainSegment`;
- `CollisionQuery`;
- `CollisionProof`;
- `InteractionResolution`;
- `EffectCommitRequest`;
- `EffectCommitResult`.

Connect admission boundary:

- `GatewayConnectGate`.

## GatewayConnectGate semantics

`GatewayConnectGate` is not an auth, placement, Directory or authority owner. It is a fail-closed derived admission record that allows `WorldReady` only after all required connect-flow evidence is present:

```text
protocol admission
-> verified identity
-> resolved/resumed session
-> resolved placement
-> Directory/authority resolution
-> backend route attached
-> player domain ready
-> ready snapshot
-> WorldReady
```

The gate carries versioned evidence for protocol admission, identity verification, session, placement, Directory generation, authority epoch, route revision and ready snapshot.

Hard rules:

```text
CONNECT_GATE_FAILS_CLOSED_BEFORE_WORLD_READY
CONNECT_GATE_NO_SIMULATION_ENDPOINT_OR_CREDENTIAL
ROUTE_REVISION_NOT_AUTHORITY_EPOCH
CLIENT_NEVER_RECEIVES_SIMULATION_SERVER_ENDPOINT
```

A numerically equal `RouteRevision` and `AuthorityEpoch` is legal; they remain different semantic namespaces.

## R5 CWIP semantics

The EG0 contract layer now encodes:

```text
PROJECTION_HIT_IS_CANDIDATE_NOT_CANONICAL_EFFECT
ACTION_AUTHORITY_VALIDATES_ACTION
EACH_WORLD_AUTHORITY_VALIDATES_ONLY_ITS_COLLISION_DOMAIN
ACTION_AUTHORITY_RESOLVES_FIRST_VALID_COLLISION
TARGET_EFFECT_AUTHORITY_COMMITS_CANONICAL_EFFECT
GATEWAY_ROUTES_INTERACTION_BUT_DOES_NOT_RESOLVE_GAMEPLAY_TRUTH
ONE_INTERACTION_AT_MOST_ONE_CANONICAL_EFFECT_COMMIT
CROSS_WORLD_INTERACTION_USES_VERSIONED_TIME_AND_REFERENCE_FRAME_EVIDENCE
```

The contracts are strict/exact-field JSON-safe DTOs. They reject malformed/stale evidence shapes, authority IDs disguised as projection target hints, inconsistent WorldGraph/reference-frame evidence, invalid collision ranges and invalid effect-result claims.

No product health/damage mutation is implemented in EG0.

## R4 invariants retained

`GatewayWorldGraphSnapshot` remains:

```text
source_owner = WORLD_DIRECTORY
read_only = true
reconstructible = true
canonical = false
```

The existing R4 hardening remains intact:

- stale World/Relation revisions fail closed;
- Gateway cannot claim topology ownership;
- projection grant cannot become mutation authority;
- client view cannot expose simulation endpoints or `peer_id`;
- compatible client interest can aggregate;
- large WorldGraph knowledge does not imply physical upstream connections.

## Focused validation surface

Supported runners:

- `RUN_EG0_EDGE_GATEWAY_TESTS.ps1`;
- `RUN_EG0_EDGE_GATEWAY_TESTS.sh`.

Focused suites:

```text
test_eg0_edge_gateway_contracts.gd
test_eg0_edge_gateway_fixtures.gd
test_eg0_world_graph_contracts.gd
test_eg0_cwip_connect_gate_contracts.gd
```

Historical implementer evidence remains:

```text
d9a31be3ceb376557d8e805c971c052a02b12294
Godot 4.7.1.stable.double.custom_build.a13da4feb
TOTAL 90 assertions PASS
```

That historical run does not validate the R4 hardening or the new R5/CWIP/connect-gate delta.

The new exact candidate must receive:

```text
Project Control SUCCESS
focused double-Godot PASS on the exact HEAD
fresh independent Reviewer PASS
independent Verifier PASS
```

before EG0 can be accepted.

## Explicit non-authority

This candidate does not:

- launch the EG1 Gateway process;
- perform live IAM/auth;
- perform live placement;
- open client/backend listeners;
- implement shared tunnel scheduling;
- run EG4 View Planner;
- run EG4.5 collision routing;
- resolve canonical gameplay truth at Gateway;
- implement real product damage;
- activate P6;
- rotate the V0 runtime mutation lease;
- create `EDGE_GATEWAY_FOUNDATION_ACCEPTED`;
- self-review or self-verify.

Next stage remains blocked until EG0 exact-head validation, independent review/verification and the control dependency are satisfied.
