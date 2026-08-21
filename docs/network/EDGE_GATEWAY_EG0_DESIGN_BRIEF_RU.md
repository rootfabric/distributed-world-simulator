# EG0 — Edge Gateway Contracts / DTO / Fixtures — Design Brief

Статус: **STACKED HIGH-RISK IMPLEMENTATION CANDIDATE / R4 HARDENED / NOT ACCEPTED / NO P6 AUTHORITY**

Control dependency: draft PR `#185`.

Current R4 control base:

`b62535ea1ed7cf6f687ab5ee91f206cd6eea0a7d`

Branch:

`feature/eg0-edge-gateway-contracts-r1`

## Problem

Before implementing the real `Client -> Gateway -> Server` process, freeze transport-independent contracts so EG1 cannot accidentally equate network topology with player identity, authority, world-topology truth or gameplay semantics.

Forbidden semantic aliases:

```text
TransportConnectionId != GatewaySessionId
GatewaySessionId       != ClientSessionId
ClientSessionId        != PlayerId
PlayerId               != PlayerEntityId
session_slot            != PlayerId
backend_peer_id         != PlayerId
RouteRevision           != AuthorityEpoch
```

R4 additionally requires a fail-closed contract boundary for World Graph / client view / interest aggregation.

## Selected design

`ClientWorldFrame` is the client-facing semantic frame. `GatewayIngressEnvelope` and `GatewayEgressEnvelope` wrap it with route/session metadata instead of rebuilding gameplay payloads.

For `WORLD_OPERATION`, canonical `operation_id` remains inside the wrapped frame and must survive Gateway forwarding unchanged.

World topology is represented at Gateway as a derived cache input:

```text
World Directory / World Graph
        -> GatewayWorldGraphSnapshot
        -> ClientWorldView
        -> AggregatedInterestPlan
        -> later EG4 View Planner / Route-Link Manager
```

The graph-cache contract is now explicit, not documentary-only:

```text
source_owner = WORLD_DIRECTORY
read_only = true
reconstructible = true
canonical = false
```

Hard rules:

```text
WORLD DIRECTORY OWNS WORLD TOPOLOGY TRUTH.
DIRECTORY / AUTHORITY OWNS CANONICAL OWNERSHIP TRUTH.
GATEWAY OWNS DERIVED VIEW / INTEREST / ROUTING ONLY.

GLOBAL KNOWLEDGE DOES NOT IMPLY GLOBAL CONNECTION.
```

## Contract surface frozen by EG0 candidate

Transport/session:

- `ClientWorldFrame`
- `GatewayIngressEnvelope`
- `GatewayEgressEnvelope`
- `GatewaySessionBinding`
- `GatewayRouteBinding`
- `ProjectionSubscription`
- `GatewayDescriptor`

World Graph / View / Interest:

- `WorldDescriptor`
- `WorldRelation`
- `GatewayWorldGraphSnapshot`
- `ClientWorldView`
- `AggregatedInterestPlan`
- explicit `ViewRevision`
- explicit `InterestRevision`

## R4 hardening added after the first EG0 implementation

The first R4 pass already had all required DTO families, but several required proofs were only implicit. The hardening makes them executable:

1. `WorldDescriptor.validate_newer()` is exercised explicitly for stale-world rejection.
2. `GatewayWorldGraphSnapshot` encodes `source_owner=WORLD_DIRECTORY` and `canonical=false`.
3. `reconstruct_from_directory(...)` provides an explicit reconstructible cache path.
4. A second client view fixture proves two compatible client demands map to one `AggregatedInterestPlan`.
5. Projection grant namespace is fenced from authority identity and mutation-authority fields are rejected.
6. `ClientWorldView` rejects both nested/top-level simulation endpoint fields and `peer_id`.
7. A 1000-world graph remains pure topology data and rejects physical upstream/link state.

## Safety semantics

- strict exact-field validation rejects accidental transport-specific fields;
- runtime Godot objects are forbidden in network DTO payloads;
- mutating client channels can route only to `ACTIVE`;
- `WORLD_PROJECTION` is read-only and requires a `PROJECTION` source;
- projection policy cannot grant mutation authority;
- projection grant IDs use an opaque `projection-grant/*` namespace and cannot be authority IDs;
- `GatewayDescriptor` and `ClientWorldView` reject simulation-server endpoint leakage;
- stale World/Relation/Graph/View/Interest revisions fail closed;
- graph cache input must be derived from `WORLD_DIRECTORY`, read-only, reconstructible and non-canonical;
- multiple compatible client sessions may aggregate into one source/LOD interest plan;
- graph/view/interest contracts cannot carry physical connection state.

## Ownership boundaries

- NX — transport/replication foundation;
- World Directory — world-topology truth;
- AUTHORITY/Directory — authority ownership/epoch truth;
- IAM — account/client-session identity;
- domain owners — canonical gameplay mutation;
- EG0 — contract donor only, not a new canonical owner.

## Non-goals

EG0 does not implement:

- real Gateway process / EG1;
- ENet listener or backend tunnel;
- auth/session placement runtime;
- shared tunnel scheduler;
- View Planner algorithm / dynamic subscription lifecycle (EG4);
- eight-world planner runtime walk (EG4);
- A->B or multi-world authority handoff (EG6);
- Gateway rehome;
- final QUIC choice;
- P6 runtime mutation;
- `EDGE_GATEWAY_FOUNDATION_ACCEPTED`.

## Validation state

Previous exact head `d9a31be3ceb376557d8e805c971c052a02b12294` passed the focused double-Godot suite:

```text
base contracts                     PASS 24 assertions
canonical fixtures                 PASS 39 assertions
WorldGraph/View/Interest            PASS 27 assertions
TOTAL                               PASS 90 assertions
```

This R4 hardening expands the WorldGraph/View/Interest suite to an expected 53 assertions, for an expected focused total of 116 assertions.

Because the current execution environment does not contain the project double-Godot binary, the new exact HEAD must rerun `RUN_EG0_EDGE_GATEWAY_TESTS.sh` or `.ps1` before Reviewer/Verifier acceptance. Project Control success is necessary but does not substitute for the focused Godot run.

## Exit and review gate

Target exit:

`TOPOLOGY_NEUTRAL_DTOS_AND_WORLD_GRAPH_CONTRACTS_PASS`

Because this is HIGH-risk public protocol work, Implementer cannot self-accept. EG0 remains blocked from acceptance and EG1 remains blocked until:

```text
PR #185 dependency is canonical
exact hardened candidate Project Control SUCCESS
exact hardened candidate focused Godot suite PASS
fresh independent Reviewer PASS
independent Verifier PASS
Director verdict
```
