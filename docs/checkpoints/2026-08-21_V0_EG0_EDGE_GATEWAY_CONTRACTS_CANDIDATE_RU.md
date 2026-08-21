# V0 EG0 — Edge Gateway Contracts Candidate

Статус: **R4 HARDENED IMPLEMENTATION CANDIDATE / NOT ACCEPTED / STACKED ON PR #185 / P6 BLOCKED**

Goal:

`TOPOLOGY_NEUTRAL_DTOS_AND_WORLD_GRAPH_CONTRACTS_PASS`

Current R4 control base:

`b62535ea1ed7cf6f687ab5ee91f206cd6eea0a7d`

Branch:

`feature/eg0-edge-gateway-contracts-r1`

## Implemented

- topology-neutral client/Gateway frames and ingress/egress envelopes;
- Gateway session and route bindings;
- read-only projection subscription;
- Gateway locator descriptor;
- `WorldDescriptor` / `WorldRelation`;
- `GatewayWorldGraphSnapshot`;
- `ClientWorldView`;
- `AggregatedInterestPlan`;
- explicit route/world/graph/view/interest revisions;
- canonical JSON golden fixtures;
- Windows/Linux focused runners.

## R4 hardening

The hardened graph-cache contract now requires:

```text
source_owner = WORLD_DIRECTORY
read_only = true
reconstructible = true
canonical = false
```

Added machine proofs cover:

- stale `WorldDescriptor` and `WorldRelation` rejection;
- explicit reconstruction of Gateway graph cache from Directory-provided worlds/relations;
- rejection when Gateway claims itself as topology owner;
- rejection of `canonical=true`;
- two compatible client views aggregating into one source/LOD interest plan;
- projection-grant namespace cannot alias authority identity;
- mutation-authority fields cannot be injected into projection grants/view entries;
- top-level and nested simulation endpoint leakage rejection;
- transport `peer_id` leakage rejection;
- 1000 known worlds without physical upstream/link state in the topology contract.

## Validation history

Previous exact EG0 head:

`d9a31be3ceb376557d8e805c971c052a02b12294`

passed:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
base contracts: PASS 24
fixtures: PASS 39
WorldGraph/View/Interest: PASS 27
TOTAL: PASS 90
```

The hardened suite is expected to execute:

```text
base contracts: 24
fixtures: 39
WorldGraph/View/Interest: 53
TOTAL: 116
```

The new hardened exact HEAD requires an exact-head focused double-Godot rerun before review/acceptance. Project Control is tracked independently.

## Proven contract intent

```text
WORLD_DIRECTORY owns world topology truth
Directory/AUTHORITY owns ownership truth
Gateway graph cache is derived / read-only / reconstructible / non-canonical

Gateway may know 1000 worlds
without owning 1000 physical upstream connections

ClientWorldView contains semantic world/stream data
and no simulation-server endpoint or peer identity

compatible client demand may aggregate by source + LOD
without making the interest plan a physical link or authority record
```

## Explicit non-authority

This candidate does not:

- launch a Gateway process;
- implement EG1;
- implement EG4 planner runtime;
- implement EG6 authority traversal;
- activate P6;
- alter NX/AUTHORITY/World Directory ownership;
- become product ancestry;
- create `EDGE_GATEWAY_FOUNDATION_ACCEPTED`;
- self-review or self-verify.

Next allowed gate: exact-head Project Control + focused Godot PASS, then fresh independent Reviewer and independent Verifier after the #185 dependency is accepted. EG1 remains blocked.
