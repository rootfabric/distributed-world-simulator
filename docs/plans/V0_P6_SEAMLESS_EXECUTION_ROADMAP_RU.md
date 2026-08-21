# V0 P6 + Seamless — Execution Roadmap

Статус: **CONTROL CANDIDATE / PRIMARY WORK MAP FOR P6 CAMPAIGN**

Canonical base used to author this roadmap:

`main @ 4057b4e5daf1842de412e78838e876225674e859`

Accepted P5 product lineage / declared P6 successor base:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

This roadmap does not by itself activate P6 runtime mutation and does not activate production SM1. P6 activation still requires fresh main-owned control, epoch, Work Order, PC0 and mutation-lease rotation.

---

## 1. Purpose

The P6 campaign is no longer treated as only a persistence checkpoint. Its product goal is:

```text
P6 = Persistent Shared Outpost + Seamless-Ready Gameplay Foundation
```

The campaign has two parallel trains:

```text
PRODUCT P6                                      SEAMLESS RESEARCH

P6.0 control activation                         I2.6 closure
P6.1 ownership map                              I3 AuthorityDomain transfer
P6.2 topology-neutral identity                  I4 Player Carrying Domain
P6.3 operation continuity                       I5A Edge Gateway transparency
P6.4 mutation admission boundary                I5B ACTIVE/WARM routing prototype
P6.5 AuthorityDomain-ready closure adapter      I8 production port map
P6.6 gateway-ready command routing              NX <-> SM1 ownership audit
P6.7 persistent shared outpost                  bounded MRPF donor work
P6.8 restart/recovery
P6.9 WARM/SHADOW authority compatibility
P6.10 fault/race matrix
P6.11 repeat + soak + final closure
            |                                      |
            +-------------------+------------------+
                                |
                                v
                           P6 ACCEPTED
                                |
                                v
                   POST-P6 SEAMLESS DECISION
                                |
                                v
                         ACTIVATE V0-SM1
                                |
                                v
                  production A <-> B handoff
```

The key rule is:

- P6 MUST become seam-ready;
- Seamless Research MUST prepare proven donor semantics in parallel;
- P6 acceptance MUST NOT depend on a full production two-authority handoff;
- after P6 acceptance the preferred next product action is immediate `ACTIVATE_V0_SM1`, not P7;
- future SM1 starts from the exact accepted P6 product lineage, never from a research branch.

---

# 2. Primary product map

## P0 — Baseline / project foundation

Short description: establish the executable product baseline, project ownership rules and durable control boundaries.

Visual/manual checkpoint: basic client launch and project scene smoke test.

## P1 — First playable networked world slice

Short description: prove that a real client can enter the world and participate in the first authoritative networked gameplay loop.

Visual/manual checkpoint: REQUIRED. Launch at least one graphical client, connect, move and observe authoritative world state.

## P2 — Character / interaction composition

Short description: establish a usable player interaction layer without creating private gameplay truth.

Visual/manual checkpoint: REQUIRED. Run the graphical client and manually exercise interaction targets and visible player state.

## P3 — Visual networked interaction

Short description: prove that networked gameplay actions have correct presentation and remote-client visibility.

Visual/manual checkpoint: REQUIRED. Two graphical clients; visually inspect local/remote interaction, state convergence and no presentation duplication.

## P4 — Real-resource construction

Short description: connect canonical mined resources to authoritative Construction through the canonical Item Graph.

Visual/manual checkpoint: REQUIRED. Mine real resources, build a real object, verify both clients see the same construction and resource debit.

## P5 — Equipment and tools

Short description: turn canonical items into usable equipment/tools without introducing a second equipment truth.

Visual/manual checkpoint: REQUIRED. Equip/unequip a tool in the graphical client, use it for a real gameplay action, reconnect and verify the same visible equipment state.

Status: ACCEPTED.

## P6 — Persistent Shared Outpost + Seamless-Ready Foundation

Short description: establish the first stable persistent shared outpost and make the product architecture ready for proxy/gateway routing and future authority migration without redesigning canonical gameplay owners.

Visual/manual checkpoint: REQUIRED at multiple sub-stages; see P6 visual test matrix below.

Mandatory product outcomes:

```text
TWO_CLIENT_SHARED_OUTPOST_STATE
SERVER_RESTART_RECONSTRUCTS_CANONICAL_OUTPOST
PLAYER_RECONNECT_RECONSTRUCTS_INVENTORY_EQUIPMENT_AND_CONSTRUCTION
FIVE_CLEAN_END_TO_END_REPEATS
THIRTY_MINUTE_TWO_CLIENT_SOAK
ZERO_DUPLICATE_CANONICAL_TRUTH
TOPOLOGY_NEUTRAL_IDENTITIES
OPERATION_CONTINUITY_ACROSS_RECONNECT
SEAM_READY_MUTATION_ADMISSION_BOUNDARY
WARM_SHADOW_READ_ONLY_COMPATIBILITY_PROOF
```

## POST-P6 — Seamless insertion gate

Short description: make the explicit product decision whether production SM1 is activated now or deliberately deferred.

Preferred decision under this roadmap:

`ACTIVATE_V0_SM1`

Visual/manual checkpoint: no new gameplay feature required; control/evidence gate only.

## SM1 — Production seamless product integration

Short description: integrate Directory-backed one-writer ownership, AuthorityDomain transfer, Player Carrying Domain, Edge Gateway routing and static multi-authority operation into the accepted P6 product.

Visual/manual checkpoint: REQUIRED and central. The client must stay connected while the real player, backpack, equipment and operations migrate A <-> B with no respawn/reconnect.

## P7 — Bounded terrain mutation

Short description: add bounded authoritative terrain/material mutation on top of the selected seam-aware authority model.

Visual/manual checkpoint: REQUIRED. Two clients visually inspect terrain mutation, persistence, reconnect and authority-boundary behavior.

## P8 — First mobile construct / ship

Short description: create the first mobile construct over canonical Construction, items, persistence, reference frames and the selected seam-aware authority model.

Visual/manual checkpoint: REQUIRED. Board/use/observe the mobile construct with multiple clients; later extend to authority-boundary movement only after static SM1 acceptance.

---

# 3. P6 detailed execution plan

## P6.0 — Control sync and activation preparation

Goal:

- update main-owned product routing from accepted P5 to P6 activation;
- declare exact P6 product execution base `491ca7d058690d3de5fcea5e41aaee230a31b3ab`;
- create fresh P6 epoch and Work Order;
- run standard and directional PC0;
- rotate the single V0 runtime mutation lease to P6;
- canonicalize the P6 + Seamless convergence plan without activating SM1.

Visual/manual test: NOT REQUIRED. This is control-only.

Exit:

```text
P5 = ACCEPTED
P6 = CURRENT_ACTIVATION / DISPATCH_READY
exact P6 base declared
fresh epoch/WO present
PC0 NON_RED
mutation lease ready for P6
production_sm1_activated = false
```

## P6.1 — Canonical ownership map

Goal: freeze the canonical owner of every P6 state before implementation.

Required ownership map:

- player identity -> existing canonical player owner;
- movement -> current accepted network/gameplay owner;
- inventory/containers -> canonical M4 Item Graph;
- equipment/tools -> accepted P5 composition over Item Graph;
- Construction/outpost -> canonical P4 Construction owner;
- persistence -> existing canonical persistence/recovery owner;
- operation dedup -> existing operation ledger;
- transport/session/prediction -> NX or accepted successor;
- future ownership/migration -> Seamless R2 / SM1 only;
- projection -> derived/read-only.

Forbidden:

```text
OutpostTruthStore
OutpostInventory
OutpostPersistence
private Equipment truth
private Item Graph
private Construction truth
private network foundation
```

Visual/manual test: OPTIONAL smoke only. No new visible behavior is expected.

Exit: machine-readable ownership audit with zero unresolved duplicate truth.

## P6.2 — Topology-neutral identities

Goal: remove any canonical identity dependence on transport/process topology.

Must distinguish:

```text
TransportConnectionId != ClientSessionId
ClientSessionId        != PlayerId
PlayerId               != PlayerEntityId
ProcessId              != AuthorityId
```

Canonical IDs must survive:

- disconnect/reconnect;
- changed ENet peer id;
- server restart;
- future proxy rehome;
- future authority route change.

Visual/manual test: REQUIRED.

Manual scenario:

1. launch server + graphical client;
2. note visible player/equipment/inventory state;
3. disconnect client;
4. reconnect with a new transport connection;
5. visually confirm same character, same equipment, same inventory and same constructed state;
6. capture logs proving stable logical IDs while transport IDs changed.

Exit: no topology-induced canonical identity changes.

## P6.3 — Operation continuity and idempotency

Goal: every canonical mutation is retry-safe across reconnect, response loss and future path changes.

Required end-to-end identity:

`OperationId`

Required scenarios:

- response lost after commit;
- duplicate command;
- reconnect then exact retry;
- server restart then exact retry;
- same OperationId through a changed route abstraction.

Visual/manual test: REQUIRED for at least build and one inventory/equipment action.

Manual scenario:

1. perform build or item move;
2. inject/drop the response after canonical commit;
3. reconnect/retry;
4. client must show exactly one resulting construction/item operation;
5. no duplicate visual object or duplicated resource debit.

Exit: duplicate canonical commits == 0.

## P6.4 — Seam-ready mutation admission boundary

Goal: move canonical mutation permission behind an explicit admission interface without changing ownership truth.

P6 production implementation uses a single-authority adapter preserving current semantics. Future SM1 replaces only the adapter with Directory-backed validation.

Conceptual interface:

```text
authorize_mutation(subject_or_domain, operation, authority_context)
```

Future adapter validates owner/epoch/fence/incarnation/binding generation. The P6 adapter MUST NOT invent those values or become a second ownership oracle.

Visual/manual test: REQUIRED smoke plus negative test.

Manual scenario:

- normal player action still works visibly;
- deliberately unauthorized/read-only test context attempts the same canonical mutation;
- client must not show a committed world change;
- rejection must be explicit, not silent divergence.

Exit: Item Graph/Construction/equipment handlers no longer assume process/socket identity alone grants write authority.

## P6.5 — AuthorityDomain-ready closure adapter

Goal: create a deterministic immutable transfer candidate from canonical P6 owners without creating a new persistence store or ownership truth.

Target Player Carrying closure shape:

```text
PlayerAuthorityDomain
+ Player Aggregate
+ Inventory Root
+ Hotbar
+ Equipment
+ Backpack
+ nested containers/items
+ operation continuity metadata
```

Required properties:

- deterministic IDs and ordering;
- canonical hashes;
- no mutation authority;
- no per-item ownership transition requirement for ordinary carried descendants;
- closure reads canonical state and does not own it.

Visual/manual test: REQUIRED inspection mode.

Manual scenario:

1. create a player with equipped tool + backpack + nested container + resources;
2. show the live client state;
3. build the domain snapshot;
4. render/debug-inspect the reconstructed shadow representation;
5. visually compare inventory/equipment topology while machine hashes must match.

Exit: deterministic PlayerDomain snapshot/reconstruction candidate available for P6.9 and research I4 comparison.

## P6.6 — Gateway-ready command/session routing

Goal: decouple gameplay command semantics from direct client-to-gameplay-server addressing.

Target abstraction:

```text
Client
  -> stable logical session
  -> RoutePort / CommandRouter boundary
  -> current gameplay authority
```

P6 may route directly behind the abstraction. Future SM1 may route through Edge Gateway without rewriting gameplay handlers.

Gateway/router MUST NOT own world state or decide ownership.

Visual/manual test: REQUIRED.

Manual scenario:

- run the normal graphical client through the new route boundary;
- perform movement, inventory, equipment and construction;
- compare visible outcome with the direct baseline;
- no user-visible semantic difference is allowed.

Exit: route-path topology is no longer embedded in canonical gameplay handlers.

## P6.7 — Persistent shared outpost

Goal: complete the original P6 gameplay composition.

Canonical manual scenario:

```text
server + client A + client B
A mines
A equips tool
A builds
B observes
B mines
B builds shared storage
A opens storage
A puts ore into storage
B removes ore
A disconnects
B continues gameplay
A reconnects
```

Visual/manual test: MANDATORY GRAPHICAL ACCEPTANCE GATE.

Operator must visually confirm:

- both clients see one shared outpost;
- remote equipment is correct;
- shared containers converge;
- construction appears once;
- disconnecting A does not freeze B;
- reconnecting A reconstructs the same visible state.

Exit: `TWO_CLIENT_SHARED_OUTPOST_STATE` and reconnect continuity proven.

## P6.8 — Server restart and recovery

Goal: prove that a new server process reconstructs the same world rather than creating a new authority truth.

Scenario:

1. server + clients A/B;
2. mine/equip/build/container mutations;
3. durable commit;
4. hard-kill server;
5. start a new process;
6. reconnect A/B;
7. verify same canonical state and IDs.

Visual/manual test: MANDATORY GRAPHICAL ACCEPTANCE GATE.

Operator confirms the outpost, player equipment, inventory/container topology and constructions are visually unchanged after restart.

Machine checks include no revision rollback and no duplicate canonical IDs.

Exit: `SERVER_RESTART_RECONSTRUCTS_CANONICAL_OUTPOST`.

## P6.9 — WARM/SHADOW authority compatibility proof

Goal: prove that another authority process can reconstruct P6 state read-only before production handoff is activated.

Topology:

```text
ACTIVE Authority A
      |
      | immutable transfer candidate
      v
WARM/SHADOW Authority B
      |
      +-- reconstruct
      +-- verify hashes
      +-- canonical_write_allowed = false
```

Visual/manual test: MANDATORY SEAM-READINESS GATE.

Preferred visual setup:

- client remains connected to ACTIVE A;
- debug/operator view shows B loaded as WARM/SHADOW;
- B displays/inspects the same player closure and shared outpost projection/state subset;
- force B mutation attempt and prove it is rejected;
- no duplicate object appears in the real client.

This is NOT yet production A -> B handoff.

Exit:

```text
A canonical hashes == B reconstructed hashes
shadow canonical writes == 0
```

## P6.10 — Fault and race matrix

Goal: harden P6 and seam-ready boundaries before soak.

Required families:

- duplicate/delayed/reordered command;
- lost response;
- reconnect during operation;
- crash before commit;
- crash after commit before response;
- concurrent pickup/container/build actions;
- topology identity change;
- stale shadow snapshot;
- same revision with conflicting checksum;
- WARM/SHADOW mutation attempt.

Visual/manual test: SELECTIVE REQUIRED.

At minimum visually test:

- reconnect during a visible construction operation;
- server restart after visible commit;
- WARM/SHADOW mutation rejection;
- two-client concurrent shared-container activity.

Most permutation coverage should remain deterministic automated testing.

Exit global invariants:

```text
duplicate_canonical_commits == 0
identity_changes_due_to_topology == 0
unexpected_revision_rollback == 0
shadow_canonical_writes == 0
duplicate_item_ids == 0
duplicate_construction_ids == 0
```

## P6.11 — End-to-end repeat, soak and closure

Goal: prove P6 is stable enough to become the product base for production SM1.

Required five clean repeats:

```text
server + A + B
mine
inventory/container
equip/use tool
build
shared outpost
disconnect/reconnect
server restart
state verification
shadow compatibility verification
```

Required soak:

`30 minutes / two graphical clients`

Mixed workload:

- movement;
- mining;
- equipment;
- inventory/containers;
- construction;
- disconnect/reconnect;
- periodic canonical digest verification;
- periodic shadow snapshot/hash verification.

Visual/manual test: MANDATORY FINAL GATE.

A human/operator must run the real graphical clients and confirm the game remains playable during the soak. Machine evidence remains authoritative for exact state/invariants; visual acceptance covers presentation, usability and obvious discontinuities that state assertions may miss.

Exit:

- five clean E2E repeats;
- 30-minute two-client soak;
- full required regression green;
- fresh exact-head independent review;
- fresh independent verifier;
- append-only closure evidence;
- checkpoint proposal;
- explicit acceptance.

---

# 4. P6 visual test matrix

| P6 stage | Graphical/manual | Minimum visible proof |
|---|---|---|
| P6.0 | No | Control only |
| P6.1 | Optional | Smoke launch only |
| P6.2 | Yes | Reconnect with stable visible player/equipment/inventory |
| P6.3 | Yes | Retry does not create duplicate visible build/item effect |
| P6.4 | Yes | Authorized action works; forbidden write causes no visible commit |
| P6.5 | Yes | Live player closure matches reconstructed debug/shadow view |
| P6.6 | Yes | Same gameplay through route abstraction as direct baseline |
| P6.7 | Mandatory | Two-client shared outpost gameplay |
| P6.8 | Mandatory | Same visible world after server restart |
| P6.9 | Mandatory | WARM/SHADOW reconstructs state but cannot write |
| P6.10 | Selective mandatory | Reconnect/crash/race/shadow rejection |
| P6.11 | Mandatory | Five repeats + 30-minute real graphical soak |

Rule: automated state tests are necessary but are not sufficient for P6.7-P6.11. Those stages must retain a runnable human-visible Godot client scenario.

---

# 5. Parallel Seamless Research roadmap

The Seamless Research line is donor-only before post-P6 activation. It must not mutate the active P6 runtime or become the production lineage.

## SR0 — Close I2.6 integrated one-writer proof

Current known candidate:

`research/sm1-i2-one-writer-proof @ a195ededee95a4ca92053bac2dd585cfd788e4b6`

Goal: obtain a fresh independent exact-head review and freeze a reviewed I2.6 donor boundary unless a concrete blocker requires bounded repair.

Do not create speculative I2.7/I2.8 if I2.6 closes cleanly; proceed to I3.

Visual/manual test: NOT REQUIRED. Machine correctness/oracles dominate.

Merge/readiness output for P6 convergence:

- exact donor SHA;
- accepted one-writer semantics;
- explicit known limitations;
- no production ownership claim.

## SR1 — I3 Generic AuthorityDomain Transfer

Goal: prove generic fail-closed authority transfer around Directory linearization.

State machine:

```text
SOURCE ACTIVE
-> TARGET COMPATIBILITY CHECK
-> TARGET WARM
-> SOURCE FREEZE / DomainMutationBarrier
-> TARGET DURABLE PREPARED
-> DIRECTORY CAS      <-- linearization point
-> TARGET ACTIVE
-> SOURCE READ_ONLY / RETIRED
```

Required proof:

- cancellation before Directory commit;
- no old-writer resurrection after Directory commit;
- crash at every named transfer state;
- exact TransferId replay/conflict semantics;
- stale delayed traffic fenced;
- temporal state never rewinds.

Visual/manual test: OPTIONAL research visualization. A state-machine timeline/debug panel is useful, but correctness is machine-first.

Required convergence artifact: generic transfer contract + tests + exact donor boundary.

## SR2 — I4 Player Carrying Domain

Goal: attach real gameplay-shaped carried state to I3 semantics.

Required fixture:

```text
Player
  Inventory
    equipped Tool
    Backpack
      Container
        Ore
        Battery
        Device
```

Required invariant:

```text
1 item     -> 1 domain transition
10 items   -> 1 domain transition
100 items  -> 1 domain transition
1000 items -> 1 domain transition
```

Required races:

- handoff vs pickup/drop;
- handoff vs stack split/container move;
- handoff vs equip/unequip;
- handoff vs item use.

Every operation must classify deterministically as before barrier, after barrier/retry or rejected; partial state is forbidden.

Visual/manual test: REQUIRED RESEARCH DEMO.

Run a graphical/debug client or visualization where the same player, backpack and equipped tool are shown before and after research A -> B transfer. This does not claim production integration, but provides direct human evidence that the closure is understandable and gameplay-shaped.

Required convergence artifact: Player Carrying Domain contract + nested Item Graph fixture + transfer evidence.

## SR3 — I5A Edge Gateway transparency

Goal: prove that inserting a non-authoritative gateway does not change canonical gameplay outcomes.

Topologies to compare:

```text
Client -> Authority
Client -> Gateway -> Authority
```

Required equivalence paths:

- movement/input sequencing;
- inventory mutation;
- equipment/tool mutation;
- construction command;
- duplicate OperationId;
- reconnect/resume.

Hard invariant:

```text
Gateway canonical writes = 0
Gateway ownership decisions = 0
Gateway command-semantic changes = 0
```

Visual/manual test: REQUIRED RESEARCH DEMO.

Use the same graphical client first direct and then through Gateway. Operator-visible gameplay result must be indistinguishable aside from instrumentation.

Required convergence artifact: gateway transparency contract, route/session adapter recommendations and measured latency overhead.

## SR4 — I5B ACTIVE/WARM routing prototype

Goal: prove the future proxy pattern while keeping ownership in Directory semantics.

Topology:

```text
Client
  -> Gateway
       -> ACTIVE A
       -> WARM B
```

Rules:

- route role does not grant ownership;
- WARM cannot mutate;
- Gateway cannot promote B before Directory commit;
- stale route revision cannot roll back newer routing;
- logical client session remains stable while route changes.

Visual/manual test: REQUIRED RESEARCH DEMO.

Preferred demo: one graphical client remains connected to Gateway while debug route changes ACTIVE A -> B after the simulated Directory commit; no client reconnect/respawn.

Required convergence artifact: route-role state machine + stable-session proof.

## SR5 — I8 Production Port Map

Goal: convert research knowledge into an explicit future production integration package before P6 acceptance.

For every research component classify:

```text
PORT_AS_IS
PORT_WITH_ADAPTER
REIMPLEMENT_FROM_CONTRACT
KEEP_RESEARCH_ONLY
DISCARD
```

Must cover:

- Directory;
- AuthorityIncarnation/fencing;
- AuthorityDomain transfer;
- DomainMutationBarrier;
- AuthorityBinding/domain closure;
- Player Carrying Domain;
- Gateway/session routing;
- ACTIVE/WARM/DRAIN route state;
- global one-writer oracles;
- fault harness.

Visual/manual test: NOT REQUIRED; evidence/design task.

Required convergence artifact: exact production port map referencing exact P6 integration surfaces and exact research donor SHAs.

## SR6 — NX <-> SM1 ownership audit

Goal: ensure Seamless does not create a private transport/prediction/reconciliation/network authority foundation.

Audit at minimum:

- protocol ownership;
- connection/session transport;
- input sequencing;
- prediction/reconciliation;
- transport health/backpressure;
- replica/presentation boundaries;
- route abstraction overlap;
- ownership metadata carried through networking.

Visual/manual test: OPTIONAL targeted impaired-network demo if the audit changes adapter expectations. No canonical runtime mutation in research.

Required convergence artifact: explicit `NX_OWNS / SM1_OWNS / ADAPTER_BOUNDARY` matrix.

## SR7 — Bounded MRPF projection donor alignment

Goal: retain only the projection semantics needed by first production SM1 without making full MRPF a blanket blocker.

Required donor concepts where available:

- read-only projection envelope;
- projection fencing/revision;
- ACTIVE vs projection distinction;
- bounded connection budget;
- AOI/interest source composition.

Visual/manual test: OPTIONAL but recommended if a graphical projection prototype exists.

Required convergence artifact: exact usable donor boundary or explicit deferral list.

---

# 6. P6 <-> Seamless convergence contract

The two lines must meet through explicit adapters and evidence, not by wholesale branch merge.

Required compatibility pairs before P6 acceptance:

| P6 production surface | Seamless donor counterpart | Required result |
|---|---|---|
| topology-neutral PlayerId/EntityId | I2/I3 identity + fencing model | no semantic conflict |
| OperationId continuity | I3/I4 replay semantics | exact adapter mapping |
| MutationAdmission boundary | Directory-backed authorization | future adapter defined |
| PlayerDomain closure adapter | I4 Player Carrying Domain | schema/identity compatibility |
| RoutePort/session abstraction | I5 Gateway | gateway adapter defined |
| WARM/SHADOW read-only proof | I3/I5 WARM semantics | compatible state/revision model |
| canonical Item Graph | I4 inherited carried descendants | no second Item Graph |
| canonical Construction/persistence | future AuthorityDomain composition | no second owner |
| NX transport/prediction | SM1 ownership transfer | explicit ownership boundary |

Required pre-P6-acceptance convergence review:

```text
P6 exact candidate surface inventory
+ I2.6 exact accepted donor
+ I3 exact accepted/reviewed donor
+ I4 exact accepted/reviewed donor if ready
+ I5A/I5B donor evidence if ready
+ I8 port map
+ NX <-> SM1 audit
+ MRPF bounded donor state
```

A missing optional donor may be explicitly deferred, but an unresolved semantic conflict in identity, canonical ownership, mutation admission, Item Graph closure or network ownership is a blocker to immediate post-P6 SM1 activation.

---

# 7. Production SM1 roadmap after P6

Production branch:

`feature/v0-sm1-seamless-product-integration`

Production base:

`exact accepted P6 product lineage declared by then-current main`

Milestones:

```text
SM1-H0  production seamless contracts
SM1-H1  durable Ownership Directory integration
SM1-H2  generic AuthorityDomain transfer
SM1-H2A AuthorityBinding + domain closure
SM1-H2B Player Carrying Domain
SM1-H3  single Edge Gateway transparency
SM1-H4  ACTIVE/WARM/DRAIN routing
SM1-H5  gateway-mediated PlayerAuthorityDomain handoff
SM1-H6  multi-region gateway selection
SM1-H7  gateway rehome/failure
SM1-H8  projection/AOI integration
SM1-H9  cross-authority operation foundation
SM1-H10 InteractionIsland runtime
SM1-H11 static N-authority world
SM1-H12 integrated static seamless acceptance
```

Mandatory graphical milestone at H5:

```text
Client -> Gateway
Player starts on Authority A
real backpack/equipment/items
A -> B ownership transfer
same logical session
same player/entity/item identities
no reconnect
no respawn
continue gameplay on B
B -> A return
```

Dynamic split/merge, elastic placement and arbitrary many authorities remain after H12.

---

# 8. Human-visible product route

```text
P5 ACCEPTED
    |
    v
P6 Persistent Shared Outpost + Seamless-Ready Foundation
    |   graphical proof throughout P6.2-P6.11
    |
    +---- parallel ----> Seamless I2.6 -> I3 -> I4 -> I5 -> I8/NX audit
    |                                      |
    +----------------------+---------------+
                           v
                      P6 ACCEPTED
                           |
                           v
                    ACTIVATE V0-SM1
                           |
                           v
              Directory + Gateway + A/B
                           |
                           v
               real seamless player handoff
                           |
                           v
                          P7
                           |
                           v
                          P8
```

---

# 9. Definition of readiness for P6 acceptance

P6 may be proposed for acceptance only when:

1. persistent two-client outpost loop works end-to-end;
2. server restart/reconnect reconstruct canonical state;
3. topology-neutral identity checks pass;
4. OperationId retry/idempotency checks pass;
5. mutation admission boundary is seam-ready and has no second ownership oracle;
6. PlayerDomain closure adapter is deterministic;
7. gateway-ready route/session abstraction is in place;
8. WARM/SHADOW read-only compatibility proof passes;
9. five clean graphical E2E repeats pass;
10. 30-minute two-client graphical soak passes;
11. standard/full regressions pass;
12. Seamless I2.6 is closed at a reviewed boundary;
13. I3 transfer semantics are available as reviewed donor evidence or a concrete blocker is recorded;
14. I4 Player Carrying Domain is the target readiness donor and must be completed where no concrete research blocker exists;
15. I8 production port map and NX <-> SM1 ownership audit are current against the exact P6 candidate;
16. no unresolved identity/ownership/network-foundation collision prevents immediate production SM1 activation;
17. fresh independent Reviewer and Verifier complete the P6 closure.

This makes P6 a stable product checkpoint and, at the same time, a deliberate launchpad for production seamless integration rather than a dead-end single-server architecture.
