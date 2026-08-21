# V0 P6 + Seamless — R2 Stable Gateway / Proxy Overlay

Статус: **CONTROL CANDIDATE / NORMATIVE OVERLAY OVER R1 / NO RUNTIME AUTHORITY**

Canonical main base:

`1d9de3c479c60045d613660b2a5c5db0374963f8`

Accepted P5 product lineage / declared P6 execution base:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

Base detailed roadmap retained:

`docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md`

Machine companion:

`config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`

This R2 overlay does not authorize P6 runtime mutation, does not rotate the V0 mutation lease, does not activate production SM1, and does not make Seamless Research or MRPF a production base.

---

## 1. Why R2 exists

R1 correctly introduced:

- topology-neutral identities;
- OperationId continuity;
- seam-ready mutation admission;
- PlayerAuthorityDomain-ready closure;
- gateway-ready command/session routing;
- WARM/SHADOW compatibility;
- parallel I5A Edge Gateway and I5B ACTIVE/WARM research;
- post-P6 production SM1.

However, R1 leaves one important ambiguity: `Gateway` can still be interpreted as only an adapter or discovery/router abstraction while the gameplay client physically reconnects to each simulation authority.

R2 removes that ambiguity.

The target product architecture is a **stable gameplay ingress**:

```text
Game Client
    |
    | stable gameplay transport/session
    v
World / Edge Gateway
    |
    +----> ACTIVE Authority A
    |
    +----> WARM Authority B
    |
    +----> later ACTIVE Authority B after committed handoff

Ownership truth: Directory / AUTHORITY foundation
Canonical gameplay truth: existing domain owners
Gateway canonical writes: ZERO
Gateway ownership decisions: ZERO
```

For normal A -> B authority crossing the client gameplay endpoint/session MUST remain stable. Backend routing changes behind the Gateway.

This is aligned with the recent seamless-network architecture analysis and with the useful proxy pattern identified while comparing multi-server networking approaches: topology changes should normally be hidden behind a stable client ingress rather than exposed as physical gameplay-server reconnects.

---

## 2. R2 target network split

R2 deliberately separates **canonical gameplay transport** from **read-only projection transport**.

### 2.1 Canonical gameplay path

Preferred production path:

```text
Client
  -> stable Gateway session
  -> current ACTIVE authority
  -> canonical domain owners
```

Gameplay path includes at minimum:

- movement/input commands;
- authoritative gameplay RPC/commands;
- inventory/container operations;
- equipment/tool operations;
- mining;
- Construction operations;
- OperationId continuity;
- reconnect/resume metadata;
- authority-route changes.

The client must not need to know or switch its public gameplay endpoint when authority changes A -> B.

### 2.2 Projection path

MRPF direct source projections remain allowed and preferred where they reduce relay cost:

```text
ProjectionPublisher A -------> Client
Earth/Macro Publisher -------> Client
Moon/Celestial Publisher ----> Client
```

These routes are:

- read-only;
- grant-controlled;
- presentation-only;
- independently fenced by source epoch/sequence/revision;
- incapable of canonical mutation.

Therefore R2 is a hybrid:

```text
canonical gameplay = stable Gateway ingress
read-only projection = direct source -> Client where useful
```

The Gateway is not required to relay all visual/projection traffic.

---

## 3. Gateway responsibility boundary

The production Gateway may own:

- public ingress endpoint;
- transport termination where selected by NX;
- logical gameplay session attachment;
- authentication/session handoff integration with IAM;
- backend route table/cache;
- forwarding of client commands and authoritative responses;
- route revision fencing;
- connection health/backpressure instrumentation;
- stable client-facing session during backend authority pivot.

The Gateway MUST NOT own:

- PlayerId or PlayerEntityId canonical identity;
- Item Graph truth;
- inventory/equipment truth;
- Construction truth;
- persistence truth;
- OperationId dedup truth;
- authority ownership truth;
- authority epoch assignment;
- Directory linearization;
- cross-authority transaction coordination;
- gameplay mutation authorization by itself.

Hard rule:

```text
GATEWAY ROUTES
DIRECTORY / AUTHORITY DECIDES OWNERSHIP
DOMAIN OWNERS DECIDE CANONICAL MUTATION
```

---

## 4. Identity and routing model

R2 strengthens P6.2/P6.6 identity separation:

```text
TransportConnectionId != GatewaySessionId
GatewaySessionId       != ClientSessionId
ClientSessionId        != PlayerId
PlayerId               != PlayerEntityId
GatewayInstanceId      != AuthorityId
ServerInstanceId       != AuthorityId
RouteRevision          != AuthorityEpoch
```

A route binding is conceptually:

```text
GameplayRouteBinding {
    gateway_session_id
    player_entity_id
    active_authority_id
    active_server_instance_id
    observed_authority_epoch
    route_revision
    route_role
}
```

The binding is routing metadata, not ownership truth.

Gateway may consume Directory/AUTHORITY evidence but cannot synthesize a newer authority epoch or promote a target based only on local routing state.

---

## 5. Normal A -> B handoff data path

Target behavior:

```text
before:
    Client <-> Gateway = STABLE
    Gateway -> A = ACTIVE
    Gateway -> B = optional PROJECTION/WARM backend path

prepare:
    B reconstructs PlayerAuthorityDomain
    B = WARM / canonical writes forbidden
    A remains ACTIVE

commit:
    Directory/AUTHORITY linearization commits A -> B
    authority_epoch advances

pivot:
    Gateway route_revision advances
    A = DRAIN/READ_ONLY
    B = ACTIVE
    Client <-> Gateway transport/session unchanged

settled:
    late A traffic is fenced
    B handles new canonical gameplay commands
```

The client must not see:

- reconnect screen;
- respawn/new player entity;
- new gameplay login;
- backend server endpoint switch;
- duplicate canonical result.

A bounded presentation correction may still be tolerated before later perceptual-smoothness hardening, but transport/session/identity continuity is a hard gate.

---

## 6. P6 product changes relative to R1

All R1 P6.0-P6.11 stages remain in force unless overridden here.

### P6.2 — topology-neutral identity

Add required proof:

```text
future GatewaySessionId insertion does not alter PlayerId/PlayerEntityId
future backend authority route change does not require identity recreation
```

P6 still does not need production A -> B transfer.

### P6.3 — OperationId continuity

Add invariant:

```text
OperationId is end-to-end stable through:
Client -> RoutePort/Gateway boundary -> Authority -> canonical owner
```

Gateway retries/forwarding must not mint replacement OperationIds for the same logical operation.

### P6.4 — mutation admission

Add explicit rule:

```text
GatewaySessionId, GatewayInstanceId and RouteRevision are insufficient to authorize canonical mutation.
```

Future SM1 authorization still resolves against Directory/AUTHORITY owner/epoch/fence/incarnation/binding semantics.

### P6.6 — stable-ingress-compatible command/session routing

R1 name `GATEWAY_READY_COMMAND_SESSION_ROUTING` is retained for compatibility, but R2 strengthens the goal.

Target abstraction:

```text
Client Gameplay API
    -> Stable Logical Session
    -> RoutePort / Gateway-compatible boundary
    -> current authority route
```

P6 direct single-authority implementation may remain behind this boundary, but handlers MUST NOT assume:

```text
client socket endpoint == canonical authority identity
network peer id == player identity
direct server address == gameplay semantic owner
```

P6.6 exit becomes:

```text
STABLE_INGRESS_COMPATIBLE_GAMEPLAY_SURFACE
```

### P6.9 — WARM/SHADOW compatibility

Add Gateway-oriented evidence shape:

```text
ACTIVE A
WARM B
stable logical gameplay session model exists
B reconstruction matches closure/hash
B canonical writes = 0
```

Still no production A -> B ownership switch inside P6.

### P6.10 — fault matrix

Add cases:

- stale Gateway route revision;
- duplicate forwarded command;
- delayed A response after future route pivot model;
- route metadata newer than observed authority epoch;
- forged Gateway identity used as mutation authority;
- Gateway path response loss with exact OperationId retry;
- direct projection route attempting canonical command injection.

---

## 7. Seamless Research changes

R2 makes the Gateway research path explicit and completion-bearing for immediate post-P6 SM1 readiness.

### SR3 / I5A — Stable Edge Gateway MVP

R1 `EDGE_GATEWAY_TRANSPARENCY` is strengthened to a real process prototype.

Required topology:

```text
Client
  -> Gateway process
      -> Authority A process
```

Required properties:

- client connects to the Gateway endpoint, not directly to A for gameplay;
- Gateway forwards real movement/input and gameplay commands;
- OperationId and input sequence survive forwarding unchanged semantically;
- direct vs gateway outcomes are canonical-equivalent;
- Gateway canonical writes = 0;
- Gateway ownership decisions = 0;
- Gateway restart/failure limitations are measured and documented;
- per-direction bytes/packets/latency/queue metrics are captured.

Required graphical demo:

```text
same client build
same gameplay scenario
DIRECT baseline
vs
GATEWAY path
```

Canonical outcome must match.

SR3 is required donor evidence for immediate post-P6 SM1 activation.

### SR4 / I5B — Stable-ingress ACTIVE/WARM backend pivot

R1 `ACTIVE_WARM_ROUTING_PROTOTYPE` becomes a hard research proof for the proxy architecture.

Topology:

```text
Client <-> Gateway = one stable gameplay connection/session
Gateway -> A = ACTIVE
Gateway -> B = WARM
```

Required pivot:

```text
A ACTIVE
B WARM
Directory/AUTHORITY commit A -> B
Gateway route_revision advances
A -> DRAIN
B -> ACTIVE
Client gameplay connection/session remains unchanged
```

Hard gates:

- no new client gameplay transport connection at crossing;
- no gameplay endpoint change;
- no reconnect/login/respawn;
- stable logical_player_id;
- stable player_entity_id;
- exactly one canonical writer;
- monotonic authority epoch;
- monotonic Gateway route revision;
- stale A traffic rejected/fenced;
- duplicate OperationId remains idempotent across pivot;
- WARM cannot mutate before ownership commit;
- Gateway cannot promote B before ownership commit.

Required fault cases:

- B fails before Directory commit -> A remains writer;
- A fails during prepare -> recovery path explicit;
- delayed A packets arrive after B activation -> fenced;
- Gateway sees stale Directory/route data -> fail closed;
- response to an operation is lost during pivot -> exact retry yields one result;
- rapid A -> B -> A sequence does not rewind epoch/route revision.

SR4 is upgraded from optional donor to required donor for the preferred immediate SM1 route unless a concrete reviewed blocker is recorded.

### SR7 / MRPF — Gateway/projection split alignment

MRPF must explicitly prove compatibility with R2:

```text
Gameplay commands -> Gateway
Read-only projections -> direct authorized source routes where useful
```

Required non-conflict rules:

- projection route cannot become gameplay write route merely because it is open;
- projection grant is not mutation authority;
- client is never cross-authority transaction coordinator;
- active gameplay authority is not forced to relay all projection traffic;
- projection source dropout must not break the stable gameplay Gateway session.

Full MRPF remains non-blocking if a bounded compatible donor contract is available or an explicit defer is recorded.

---

## 8. Production SM1 changes

Production SM1 remains post-P6 and starts from the exact accepted P6 product lineage.

R2 refines the production milestones:

```text
SM1-H0  production seamless contracts
SM1-H1  durable Ownership Directory integration
SM1-H2  generic AuthorityDomain transfer
SM1-H2A AuthorityBinding + domain closure
SM1-H2B Player Carrying Domain
SM1-H3  production Stable Edge Gateway
SM1-H4  ACTIVE/WARM/DRAIN backend routing through Gateway
SM1-H5  Gateway-mediated PlayerAuthorityDomain A <-> B handoff
SM1-H6  multi-region route/directory selection
SM1-H7  Gateway instance failure/rehome/session resume
SM1-H8  MRPF projection/AOI hybrid integration
SM1-H9  cross-authority operation foundation
SM1-H10 InteractionIsland runtime
SM1-H11 static N-authority world
SM1-H12 integrated static seamless acceptance
```

### SM1-H3 hard gate

A real graphical client must use a stable Gateway gameplay endpoint for all tested canonical gameplay commands.

### SM1-H5 hard gate

```text
Client <-> Gateway connection/session stays logically continuous
Player starts on A
B becomes WARM
ownership commit A -> B
Gateway backend route pivots
same PlayerId
same PlayerEntityId
same inventory/equipment identities
no reconnect screen
no respawn
continue movement/gameplay on B
B -> A return also passes
```

### SM1-H7 hard gate

Gateway must not become a new single point of architectural truth.

Required result:

- Gateway process/instance may fail or be replaced;
- canonical ownership remains in Directory/AUTHORITY;
- client session can resume/rehome according to NX/IAM contract;
- a failed old Gateway cannot resurrect a stale backend route.

---

## 9. Required test/evidence matrix added by R2

Before production SM1 can claim stable-proxy seamlessness, evidence must cover:

1. direct vs Gateway canonical equivalence;
2. one stable client gameplay ingress across A -> B;
3. stable PlayerId/PlayerEntityId across pivot;
4. exactly one writer for all observed ticks/operations;
5. OperationId continuity through Gateway and across pivot;
6. stale old-authority packet fencing;
7. stale Gateway route revision fencing;
8. WARM mutation rejection;
9. target failure before ownership commit;
10. response loss around handoff and exact retry;
11. repeated A <-> B pivots;
12. latency/jitter/loss/duplicate/reorder profiles through Gateway;
13. no unbounded Gateway queue/session growth;
14. projection source dropout does not break gameplay ingress;
15. direct projection cannot authorize canonical mutation.

Perceptual smoothness is a separate quality gate after canonical/transport seamlessness. Prediction/interpolation/camera continuity should then be hardened against the same pivot scenarios.

---

## 10. Updated convergence requirements before P6 acceptance

For the preferred immediate post-P6 `ACTIVATE_V0_SM1` path, the convergence package should now contain:

```text
P6 exact candidate
+ reviewed I2.6 one-writer donor
+ reviewed I3 AuthorityDomain transfer donor
+ reviewed I4 Player Carrying Domain donor or concrete blocker
+ reviewed SR3/I5A Stable Edge Gateway MVP donor
+ reviewed SR4/I5B stable-ingress A/W pivot donor or concrete blocker
+ current I8 production port map
+ current NX <-> SM1 ownership audit
+ bounded MRPF Gateway/projection compatibility result
```

An unresolved conflict in stable ingress, identity, ownership, mutation admission, OperationId continuity or NX transport ownership blocks immediate SM1 activation.

P6 itself remains a stable single-authority product checkpoint and does not claim production multi-authority handoff.

---

## 11. Open control work affected by R2

At the time of this overlay, canonical main is:

`1d9de3c479c60045d613660b2a5c5db0374963f8`

Open stacked P6 control candidates include:

- PR #182 — P6 preactivation;
- PR #184 — P6.1 canonical ownership map stacked on #182.

They were authored against R1 semantics.

Therefore, if this R2 overlay is independently reviewed and accepted into main, #182/#184 MUST be refreshed/rebased or replaced so their Work Order/ownership map bind the R2 stable-ingress contract before runtime mutation is authorized.

Do not merge an older preactivation candidate that silently restores weaker R1 Gateway semantics after R2 becomes canonical.

---

## 12. Final product route after R2

```text
P5 ACCEPTED
    |
    v
P6 Persistent Shared Outpost + Seamless-Ready Foundation
    |
    | P6.6 stable-ingress-compatible gameplay surface
    |
    +------ parallel ------> I3/I4
    |                       I5A Stable Edge Gateway MVP
    |                       I5B ACTIVE/WARM backend pivot
    |                       I8 + NX audit
    |                       bounded MRPF projection alignment
    |
    v
P6 ACCEPTED
    |
    v
ACTIVATE V0-SM1
    |
    v
Directory + Stable Gateway + Authority A/B
    |
    v
real A <-> B handoff behind one client gameplay ingress
    |
    v
Gateway failure/rehome + projection/AOI integration
    |
    v
static N-authority seamless world
    |
    v
P7 -> P8
```

Final rule:

```text
ONE STABLE GAMEPLAY INGRESS FOR THE CLIENT
BACKEND AUTHORITY MAY CHANGE BEHIND IT
GATEWAY NEVER BECOMES CANONICAL OWNERSHIP TRUTH
DIRECT PROJECTIONS MAY BYPASS GATEWAY BUT REMAIN READ-ONLY
```
