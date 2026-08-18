# Seamless World Architecture — Provenance and Rationale

Status: `RESEARCH EVIDENCE / DECISION RECORD`

This document explains **why** the elements in `SEAMLESS_WORLD_ARCHITECTURE_R1_RU.md` exist, which internal/external ideas influenced them, what was adopted, what was rejected, and what each addition is expected to improve.

The goal is not to claim novelty or to copy another engine. The goal is to preserve the reasoning so future implementation work does not accidentally remove an invariant whose purpose is no longer obvious.

## 1. Source classes

Architecture R1 draws from four source classes:

1. **DWS internal evidence** — SM0, NX/network work, existing product/control rules and previous Edge Gateway research.
2. **Unreal Engine 5.8 MultiServerReplication public API documentation** — useful proxy/gateway routing patterns.
3. **IEEE HLA family** — long-standing distributed-simulation framing and explicit coordinated ownership/responsibility concepts.
4. **Cloud Imperium / Star Citizen published server-meshing evolution** — static partition first, then dynamic zone placement, then interaction-based simulation islands.

No external source is treated as an implementation mandate.

## 2. Internal donor: SM0 two-authority seamless handoff lab

Research branch:

```text
feature/sm0-two-authority-seamless-handoff-lab
```

Recorded final runtime evidence carrier from the completed research analysis:

```text
b5966ef113b73e3156488805057ce9b464362d89
```

Relevant proven/candidate capabilities include:

- stable player/entity identity across A↔B transfer;
- exactly one active writer under tested scenarios;
- authority epoch progression/fencing;
- explicit freeze/prepare/commit/activate/retire lifecycle;
- replay-safe transfer identity;
- durable prewarm proof/recovery work after a real target-restart race was found;
- nested/moving reference-frame work;
- foreign item boundary without creating a second Item Graph;
- read-only multi-authority view composition/LOD;
- deterministic fault matrix and process soak involving three authorities.

### What Architecture R1 adopts from SM0

#### Stable identity independent of process

Reason: reconnect/handoff cannot be implemented as entity destruction/recreation without breaking inventory, operation continuity, references and client presentation.

Expected improvement: seamless authority movement without logical object replacement.

#### One-writer invariant

Reason: distributed overlap is unavoidable for warm routes and visual projections; allowing overlap to imply mutation authority creates split-brain.

Expected improvement: a clear correctness oracle for all future mesh work.

#### Explicit authority epochs/fencing

Reason: old processes and delayed packets can survive longer than their ownership.

Expected improvement: stale authority cannot write after ownership moves.

#### Freeze → prepare → directory commit → activate/retire protocol

Reason: authority transfer is a distributed transaction with crash/replay windows, not a routing-table edit.

Expected improvement: deterministic recovery and one canonical outcome under bounded failures.

#### Durable evidence

Reason: the discovered target-restart race demonstrated that transient PREWARM state was insufficient to guarantee progress after restart.

Expected improvement: recovery does not depend on volatile reservation state.

#### Read-only foreign projection

Reason: visual continuity needs overlap, but overlap must not create a backup writer.

Expected improvement: smooth borders without weakening ownership correctness.

#### Fault-first validation

Reason: the most valuable SM0 discovery came from testing restart timing rather than happy-path movement.

Expected improvement: future milestones treat crash/reorder/replay evidence as first-class acceptance, not post-feature hardening.

### What Architecture R1 does NOT do with SM0

- does not wholesale merge the research branch into a newer product line;
- does not treat A/B fixture topology as production topology;
- does not treat the lab coordinator/directory as the final production ownership store;
- does not claim arbitrary-N dynamic meshing from three-process evidence;
- does not make visual latency results equivalent to production WAN smoothness.

SM0 is a **semantic and evidence donor**.

## 3. Internal donor: previous Edge Gateway research

Research PR:

```text
#135 — Research: multi-region edge gateway architecture
branch: research/edge-gateway-architecture
```

This earlier research introduced the idea of placing a non-authoritative edge proxy between clients and world authorities.

### Adopted ideas

- multiple gateways distributed by real-world region;
- client gateway discovery/probing and primarily RTT-based selection;
- one stable client→gateway gameplay session;
- gateway-managed primary/observer/warm authority routes;
- authority handoff separated from client transport handoff;
- interest-driven upstream authority connectivity instead of all-to-all;
- shared gateway↔authority physical transports with many logical client routes;
- gateway view composition as presentation-only;
- `ClientSessionId` independent of `GatewaySessionId` so future gateway rehome is possible;
- gateway crash/retry scenarios must preserve end-to-end `OperationId` exactly-once behavior.

### Why these ideas were added

The old direct-client N5 shape required the client to know and maintain active/warm server routes. That makes the client participate in server topology and complicates authority changes, multi-server visibility and global deployment.

The Edge Gateway moves topology churn to infrastructure while keeping canonical simulation ownership in authorities.

Expected improvements:

- simpler client networking model;
- stable client session while simulation ownership changes;
- better regional latency placement;
- natural location for multi-authority view/LOD composition;
- transport pooling and interest aggregation opportunities;
- cleaner later failover/rehome path.

### What is deliberately not adopted

The gateway is not a simulation server, canonical world database, second physics world or second Item Graph.

## 4. External donor: Unreal Engine 5.8 MultiServerReplication

Official public API documentation consulted:

- `MultiServerReplication` module:
  `https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/MultiServerReplication`
- `UProxyNetDriver`:
  `https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/MultiServerReplication/UProxyNetDriver`
- `UMultiServerNode`:
  `https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/MultiServerReplication/UMultiServerNode`
- `UProxyBackendNetDriver`:
  `https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/MultiServerReplication/UProxyBackendNetDriver`

The Epic documentation describes a proxy that presents a normal server-like endpoint to game clients while connecting to backend game servers. It also describes primary versus non-primary backend roles, backend connection drivers, proxy routing/reassignment machinery and shared identity/NetGUID-related support.

### Pattern adopted: client-facing proxy

**Source idea:** `UProxyNetDriver` hides backend game-server connections behind a proxy-facing client endpoint.

**DWS adaptation:** Edge Gateway presents one stable client ingress while routing to multiple authorities.

**Why:** client should not carry distributed world topology.

**Expected improvement:** authority changes become infrastructure routing events instead of client reconnect events.

### Pattern adopted: primary/non-primary routes

**Source idea:** one backend is primary for the proxy client while others can contribute relevant replicated state.

**DWS adaptation:** logical `PRIMARY`, `OBSERVER`, `WARM` routes under strict Directory/epoch authority rules.

**Why:** exactly matches the need for canonical mutation routing plus read-only overlap.

**Expected improvement:** seamless authority handoff plus multi-authority visibility.

### Pattern adopted: proxy/backend driver separation

**Source idea:** proxy listener networking is separated from backend server networking.

**DWS adaptation:** client ingress transport, gateway-authority upstream transport and logical route state are separate abstractions.

**Why:** physical transport lifecycle should not be the same thing as gameplay route lifecycle.

**Expected improvement:** transport pooling, route multiplexing and independent backpressure/failure handling.

### Pattern adopted: stable/shared network identity

**Source idea:** UE proxy support includes NetGUID cache behavior that reuses backend-assigned identity rather than minting independent proxy identity.

**DWS adaptation:** canonical `EntityId`, `ItemId`, `ReferenceFrameId`, session/operation IDs remain independent of gateway process identity.

**Why:** an edge layer must not create duplicate identities.

### Patterns deliberately rejected or generalized

#### Do not connect every client to every registered backend

Epic's documented proxy path opens backend connections to registered game servers for a proxy connection. That is reasonable for a bounded multi-server plugin topology, but DWS targets potentially many authorities.

DWS uses interest-driven/demand-driven upstream connectivity.

#### Do not make a shared proxy world canonical

UE documentation describes backend state being replicated into a shared proxy `UWorld` and then replicated to proxy clients.

DWS gateway state is strictly presentation/read-only/derived. It does not become canonical simulator state.

#### Do not make gameplay broadcast-to-all the default

DWS prefers targeted route resolution with expected owner/epoch/revision and end-to-end operation identity.

#### Do not make architecture PlayerController/Pawn-centric

DWS authority contracts must work for players, items, vehicles, structures, matter regions, interaction islands and other aggregates.

### Licensing / clean-room note

This architecture uses public documentation and conceptual patterns. It does not copy Unreal Engine source code or private implementation code. DWS implementation must remain independently designed and compatible with the project's own licensing and reusable-framework goals.

## 5. External donor: IEEE High Level Architecture (HLA)

Official standard family references consulted:

- IEEE 1516-2025 — HLA Framework and Rules:
  `https://standards.ieee.org/ieee/1516/6687/`
- IEEE 1516.1-2025 — HLA Federate Interface Specification:
  `https://standards.ieee.org/ieee/1516.1/6688/`

IEEE describes HLA as a common architecture/framework for interconnecting interacting simulations, with coordinated services/interfaces supplied through runtime infrastructure.

The broader HLA ownership-management tradition is relevant to DWS because it treats responsibility/ownership transfer as an explicit distributed-simulation concern rather than an incidental networking side effect.

### Pattern adopted

```text
explicit ownership responsibility
+ coordinated transition
+ no assumption that object identity belongs to one process forever
```

### DWS-specific strengthening

DWS makes the ownership transition explicit through:

```text
OwnershipRecord
AuthorityEpoch
FencingToken
TransferId
DIRECTORY_COMMITTED linearization point
```

### What is not adopted

- no requirement to implement an HLA RTI;
- no requirement to expose HLA APIs to gameplay;
- no requirement to use HLA federation topology;
- no claim that DWS is HLA-conformant.

The value is the architectural framing, not protocol compatibility.

## 6. External donor: Star Citizen / Cloud Imperium server-meshing evolution

Official published source consulted:

- Roberts Space Industries, “Letter From The Chairman” (server meshing discussion):
  `https://robertsspaceindustries.com/en/comm-link/transmission/19078-Letter-From-The-Chairman`

The published progression describes:

```text
Static Server Meshing
    fixed Entity Zones

Dynamic Server Meshing V1
    dynamic assignment of servers to Entity Zones based on load

Dynamic Server Meshing V2
    subdivide Entity Zones into simulation islands
    grouped by objects that can interact/collide
```

### Pattern adopted: static first

**Why:** dynamic placement adds a second distributed-systems problem on top of ownership correctness.

**DWS decision:** SM1 success does not depend on dynamic balancing.

**Expected improvement:** smaller proof surface and clearer fault attribution.

### Pattern adopted: interaction-based grouping

**Why:** physical interaction does not follow arbitrary spatial cell boundaries.

**DWS adaptation:** introduce `InteractionIslandId` explicitly independent of `SpatialCellId` and `AuthorityId`.

**Expected improvement:** vehicles, passengers, constrained physics objects, docked structures and other tightly coupled sets can remain co-located on one authority.

### Pattern adopted: dynamic whole-domain placement before fine split/merge

**Why:** moving an existing authority domain is easier to reason about than inventing/merging partitions while under load.

**DWS roadmap:**

```text
SM1 static N-authority world
-> SM-D1 dynamic domain placement
-> SM-D2 dynamic split/merge
-> SM-D3 interaction-aware dynamic meshing
```

### What is not adopted

- no attempt to clone Star Citizen's Replication Layer;
- no assumption that Entity Zones are identical to DWS spatial cells;
- no dependence on their backend persistence/topology;
- no claim that their production tradeoffs are correct for DWS.

The useful contribution is the staged decomposition and interaction-island concept.

## 7. New DWS-specific synthesis: Ownership Directory

The research identified a risk in treating discovery/routing as ownership truth.

### Added element

A canonical `Ownership Directory` with strong atomic owner transition and fencing semantics.

### Why added

A transport message saying “B is ready” cannot safely mean “B now owns the object”. Delayed messages, process restart and partitions make that ambiguous.

### Expected improvement

- one explicit ownership linearization point;
- stale owner rejection after restart;
- directory-driven gateway route flips;
- independently testable ownership state;
- separation of NATS/broker delivery from canonical authority.

## 8. New DWS-specific synthesis: AuthorityDomain

### Added element

`AuthorityDomain` groups one or more islands/subjects for current placement and ownership operations.

### Why added

Dynamic work needs an intermediate granularity between “move one entity” and “split arbitrary world regions”.

### Expected improvement

- dynamic V1 can move existing domains without inventing split/merge simultaneously;
- placement policy can reason about a bounded set;
- region topology remains independent of permanent entity/cell identity.

## 9. New DWS-specific synthesis: interaction-aware placement cost

### Added element

A future placement cost model that includes interaction cut and migration cost, plus hysteresis/cooldown.

### Why added

CPU-only balancing can move mutually interacting objects apart and create more network/latency cost than it saves.

### Expected improvement

- fewer oscillating migrations;
- lower cross-authority traffic;
- better physics/gameplay locality;
- measurable decision quality.

## 10. New DWS-specific synthesis: authority seamlessness versus visual seamlessness

### Added distinction

```text
Authority Seamlessness
!=
Visual Seamlessness
```

### Why added

A system can look visually smooth while ownership is wrong, or be correct while visually pausing. Mixing the two makes acceptance ambiguous.

### Expected improvement

- correctness gates cannot be waived by visual quality;
- visual work can iterate without weakening canonical invariants;
- test reports can state which dimension regressed.

## 11. Rejected architecture shortcuts

Architecture R1 explicitly rejects these shortcuts:

### “Cell owner == object owner forever”

Rejected because moving/nested physical structures and interaction clusters cross cell boundaries.

### “Gateway decides ownership because it sees the client”

Rejected because gateway is an exposed routing/presentation tier, not canonical simulation truth.

### “Target imported state, therefore target owns it”

Rejected because PREPARE is not ownership commit.

### “Broker message arrival grants authority”

Rejected because transport delivery is not a strong ownership CAS.

### “Read-only ghost can take over when primary disappears”

Rejected because availability must not create split-brain.

### “Dynamic mesh is just CPU balancing”

Rejected because interaction cut, migration cost, latency and oscillation matter.

### “Every client talks to every server”

Rejected because it exposes topology and scales poorly.

### “Gateway holds a full second canonical world”

Rejected because it duplicates truth and domain systems.

## 12. Governance provenance

Current branch base `main @ c58339c30e6d7e708a06c41e59208bd45f0709a4` contains the sequential V0/P product-train control update merged through PR #132.

Architecture R1 therefore records a future program but does not make it immediately eligible.

Production activation must obey the exact main-declared accepted predecessor lineage at that time. Research evidence or an approved architecture document cannot substitute for checkpoint acceptance.

SM0 and the previous gateway research remain donors, not alternate production bases.

## 13. Decision summary

| Architecture element | Main origin | DWS improvement target |
|---|---|---|
| stable identity / epoch handoff | SM0 + distributed simulation practice | no recreate/split-brain during transfer |
| durable transfer proof | SM0 restart-race evidence | crash-safe progress |
| Ownership Directory CAS/fencing | SM0 semantics + DWS synthesis | formal linearization and stale-owner fencing |
| Edge Gateway | UE proxy pattern + DWS gateway research | topology-hidden stable client ingress |
| PRIMARY/OBSERVER routes | UE proxy primary/non-primary + SM0 projections | mutation route + read-only overlap |
| shared upstream transports | UE proxy/backend separation + DWS scaling requirement | avoid clients×authorities sockets |
| geographic gateway selection | DWS edge research | lower client-edge latency and load-aware ingress |
| InteractionIsland | CIG published simulation-island idea + DWS P8.x reference-frame evidence | co-locate interacting physics/gameplay groups |
| AuthorityDomain | DWS synthesis | safe dynamic V1 granularity |
| static-before-dynamic | SM0 research discipline + CIG staged progression | bounded proof surface |
| interaction-aware placement cost | DWS synthesis from island model | avoid expensive partition cuts/thrashing |
| authority vs visual seamlessness | SM0 correctness-first principle | independent correctness/UX gates |

## 14. Future update rule

If a future implementation changes or removes one of these elements, the replacement checkpoint should update this document or supersede it with a new decision record explaining:

- which original risk no longer applies;
- what evidence justifies the change;
- what new invariant replaces it;
- which tests prove equivalent or stronger safety.

The purpose of this file is to make architecture evolution evidence-driven rather than memory-driven.