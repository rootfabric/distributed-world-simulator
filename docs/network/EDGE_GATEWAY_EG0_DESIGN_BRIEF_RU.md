# EG0 — Edge Gateway Contracts / DTO / Fixtures — Design Brief

Статус: **STACKED HIGH-RISK IMPLEMENTATION CANDIDATE / NOT ACCEPTED / NO P6 AUTHORITY**

Control dependency: draft PR `#185`.

Initial implementation base:

`c5d7d0d682181f0a796d0e059508a1fdfe91b6e1`

Current refreshed R4 control base:

`b62535ea1ed7cf6f687ab5ee91f206cd6eea0a7d`

Branch:

`feature/eg0-edge-gateway-contracts-r1`

## Problem

Before implementing the real `Client -> Gateway -> Server` process, freeze transport-independent contracts so EG1 cannot accidentally equate network topology with player identity, authority or gameplay semantics.

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

The R4 World Graph amendment additionally requires Gateway world/view/interest contracts before EG0 closure.

## Selected design

`ClientWorldFrame` is the client-facing semantic frame. `GatewayIngressEnvelope` and `GatewayEgressEnvelope` wrap it with route/session metadata instead of rebuilding gameplay payloads.

For `WORLD_OPERATION`, canonical `operation_id` remains inside the wrapped frame and must survive Gateway forwarding unchanged.

Gateway topology knowledge is a read-only, derived and reconstructible view of World Directory truth:

```text
World Directory / World Graph
        -> GatewayWorldGraphSnapshot
        -> ClientWorldView
        -> AggregatedInterestPlan
        -> later Route/Link Manager
```

Hard rules:

```text
GATEWAY ROUTES; IT DOES NOT OWN GAMEPLAY TRUTH.
WORLD DIRECTORY OWNS WORLD TOPOLOGY TRUTH.
DIRECTORY/AUTHORITY OWNS AUTHORITY TRUTH.
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

## Safety semantics

- strict exact-field validation rejects accidental transport-specific fields;
- runtime Godot objects are forbidden in network DTO payloads;
- mutating client channels can route only to `ACTIVE`;
- `WORLD_PROJECTION` is read-only and requires a `PROJECTION` source;
- projection policy cannot grant mutation authority;
- `GatewayDescriptor` and `ClientWorldView` reject simulation-server endpoint leakage;
- stale World/Relation/Graph/View/Interest revisions fail closed;
- graph cache input must be `read_only=true` and `reconstructible=true`;
- multiple client sessions may aggregate into one source-interest plan;
- a 1000-world graph contract does not contain or require upstream connection state.

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
- A->B authority handoff;
- Gateway rehome;
- final QUIC choice;
- P6 runtime mutation;
- `EDGE_GATEWAY_FOUNDATION_ACCEPTED`.

## Validation

Implementer validation on double Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
editor parse                                      PASS
EG0 base contracts                                PASS 24 assertions
EG0 canonical fixtures                            PASS 39 assertions
EG0 WorldGraph/View/Interest contracts            PASS 27 assertions
TOTAL                                             PASS 90 assertions
```

This is implementer evidence only.

## Exit and review gate

Target exit:

`TOPOLOGY_NEUTRAL_DTOS_AND_WORLD_GRAPH_CONTRACTS_PASS`

Because this is HIGH-risk public protocol work, Implementer cannot self-accept. EG0 remains blocked from acceptance and EG1 remains blocked until:

```text
PR #185 dependency is canonical
exact candidate Project Control SUCCESS
fresh independent Reviewer PASS
independent Verifier PASS
Director verdict
```
