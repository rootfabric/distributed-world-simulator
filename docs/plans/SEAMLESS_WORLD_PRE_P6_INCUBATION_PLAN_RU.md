# Seamless World — Pre-P6 Incubation Plan

Status: `RESEARCH / PRE-ACTIVATION DEVELOPMENT PLAN — NOT PRODUCTION SM1`

Current architecture: `../architecture/SEAMLESS_WORLD_ARCHITECTURE_R2_RU.md`

Current roadmap: `SEAMLESS_WORLD_SM1_ROADMAP_R2_RU.md`

Validation strategy: `../testing/SEAMLESS_WORLD_VALIDATION_STRATEGY_R2_RU.md`

Machine plan: `seamless-world-pre-p6-incubation.v1.json`

## 1. Purpose

The active V0/P product train must continue through P5 and P6 without being blocked or mutated by seamless-world research. At the same time, waiting until the post-P6 activation decision to begin all engineering work would waste the available parallel-development window.

This plan creates a bounded **pre-P6 incubation train** whose purpose is to convert Architecture R2 into executable evidence, reusable prototypes, deterministic test harnesses and future Work Orders before production SM1 becomes eligible.

The incubation train is allowed to answer engineering questions early. It is not allowed to claim production acceptance, mutate the active product runtime, move canonical ownership, or bypass the post-P6 main-owned `ACTIVATE_V0_SM1` decision.

## 2. Core control rule

Two lines run in parallel:

```text
ACTIVE PRODUCT TRAIN                 PRE-P6 SEAMLESS INCUBATION

P4 closure                           Architecture R2 review
   |                                      |
   v                                      v
P5                                    I0/I1 contracts + harness
   |                                      |
   v                                      v
P6                                    I2/I3 directory + transfer model
   |                                      |
   |                                  I4 player carrying domain
   |                                      |
   |                                  I5 gateway prototype
   |                                      |
   |                                  I6 projection/cross-owner lab
   |                                      |
   |                                  I7 fault/soak rehearsal
   |                                      |
   +-------------------+------------------+
                       |
                       v
              POST-P6 CONTROL DECISION
                       |
             ACTIVATE_V0_SM1 ?
                  /          \
                no            yes
                |              |
                v              v
        preserve research   fresh production SM1
                            from exact accepted base
```

Incubation output is a **donor**, never the production branch base.

## 3. What may start before P6

Allowed pre-P6 work:

- pure schemas/contracts and deterministic state machines;
- isolated reusable runtime prototypes that do not become canonical product owners;
- research-only Directory/CAS/fencing implementation;
- AuthorityDomain and AuthorityBinding model;
- PlayerAuthorityDomain carrying-state prototype;
- deterministic DomainMutationBarrier experiments;
- isolated gateway/session/router prototype;
- observer/projection/AOI composition prototypes;
- process-isolated authority/gateway/directory/client labs;
- deterministic network/fault harnesses;
- machine-readable acceptance reports;
- performance/scale measurements;
- protocol compatibility experiments;
- draft production Work Orders and port maps.

Not allowed before explicit post-P6 activation:

- changing the active V0/P canonical runtime owner;
- replacing Item Graph, Construction, Matter, persistence or current network authority;
- claiming an incubation PASS as SM1 checkpoint acceptance;
- making P5/P6 depend on research branch state without a new main-owned dependency;
- merging research prototypes into production merely because they work;
- opening production SM1 branches from SM0 or research history;
- rotating the production runtime mutation lease to SM1;
- starting SM-D1/D2/D3 dynamic placement work.

## 4. Branching model

After Architecture R2 receives fresh independent review PASS, implementation incubation should use small isolated research branches, not one long-lived mega-branch.

Recommended train:

```text
research/sm1-i0-contracts
research/sm1-i1-harness
research/sm1-i2-directory
research/sm1-i3-domain-transfer
research/sm1-i4-player-carrying-domain
research/sm1-i5-edge-gateway
research/sm1-i6-projection-cross-owner
research/sm1-i7-fault-soak
research/sm1-i8-production-port-plan
```

Each branch should state:

```text
RESEARCH_ONLY=true
PRODUCTION_ACTIVATION=false
CANONICAL_OWNER_MUTATION=false
DONOR_ONLY=true
```

A later incubation stage may stack on a reviewed predecessor incubation branch for research convenience, but no such stacked lineage becomes the future production lineage.

At production activation time:

```text
production SM1 base
    = exact accepted successor declared by then-current main
```

Selected contracts/algorithms/tests are ported or reimplemented intentionally from incubation evidence.

## 5. Gate before semantic implementation

### Architecture review gate

Before I2 or later semantic runtime prototypes begin, PR #137 Architecture R2 should receive fresh independent architecture/control review on its exact head.

I0 documentation cleanup and I1 harness scaffolding may be prepared before that review, but anything depending on AuthorityDomain/Directory semantics must treat R2 as mutable until the review closes.

If Architecture R2 review returns findings, repair R2 first and rebase/restart affected incubation work against the repaired research contract.

---

# I0 — Architecture Closure and Contract Freeze

## Goal

Turn R2 into an implementation-grade research contract.

## Work

- fresh independent review of PR #137;
- resolve architecture findings without production mutation;
- freeze names and responsibilities for:
  - `AuthorityId`;
  - `AuthorityIncarnation`;
  - `SubjectId` / `EntityId`;
  - `AuthorityDomainId`;
  - `AuthorityBinding`;
  - `InteractionIslandId`;
  - `OwnershipRecord`;
  - `AuthorityEpoch`;
  - `FencingToken`;
  - `DirectoryGeneration`;
  - `TransferId`;
  - `OperationId`;
  - `ClientSessionId`;
  - `GatewayId`;
  - `GatewaySessionId`;
  - `RouteRevision`;
  - `DomainMutationBarrier`;
  - temporal/timeline stamp;
- freeze R2 authority-domain vs InteractionIsland distinction;
- freeze the post-`DIRECTORY_COMMITTED` no-old-writer rule;
- write explicit donor map from SM0 P4/P7/P8/P9/P10/P11 to future SM1 concepts.

## Tests/evidence

- schema exact-field tests;
- invalid identity tests;
- stale epoch/fence/revision tests;
- name collision tests between SpatialCell/AuthorityDomain/InteractionIsland/Gateway;
- machine-readable contract inventory.

## Exit

```text
R2 architecture reviewed
contract vocabulary frozen for incubation
no unresolved ownership ambiguity
```

---

# I1 — Seamless Research Harness and Global Oracles

## Goal

Build the test infrastructure once so every later incubation stage is checked against the same invariants.

## Processes supported

```text
Directory
Gateway 1..N
Authority 1..N
Client 1..N
Scenario Coordinator
Global Evidence Analyzer
```

## Required deterministic link controls

Independent link profiles for:

```text
Client <-> Gateway
Gateway <-> Directory
Gateway <-> Authority
Authority <-> Directory
Authority <-> Authority
```

Controls:

- latency;
- jitter;
- loss;
- duplicate;
- reorder;
- bandwidth;
- queue pressure;
- disconnect;
- hard process crash;
- restart/incarnation change.

## Global oracles

At minimum:

```text
writer_violations == 0
identity_changes_due_to_topology == 0
stale_owner_mutations_accepted == 0
duplicate_canonical_commits == 0
projection_canonical_writes == 0
unexpected_revision_rollback == 0
```

## Evidence format

Every run records:

```text
code_sha
scenario_id
seed
process ids/incarnations
authority epochs/fences
directory generation
transfer ids
operation ids
domain revisions
route revisions
handoff phase timestamps
network profile
final canonical state
```

## Exit

The harness can reproduce a failed seeded run and compare global state across independent processes.

---

# I2 — Ownership Directory Prototype

## Goal

Answer the hardest production ownership question before P6 finishes: can a durable ownership oracle prevent stale-writer resurrection under crash/restart/partition?

## Prototype scope

Research-only strongly consistent ownership state with conceptual record:

```text
OwnershipRecord {
  subject_or_domain_id
  owner_authority_id
  authority_epoch
  fencing_token
  directory_generation
  authority_incarnation
  state_revision
  lease_state
  route_revision
}
```

The storage technology is still replaceable. The semantic contract is the product of this stage.

## Must prove

- atomic expected-state CAS;
- monotonic epoch/fence;
- stale CAS rejection;
- stale writer mutation rejection after restart;
- directory restart before/after durable commit;
- process incarnation change;
- draining/unavailable states;
- lookup and ownership mutation are separate operations.

## Critical crash test

```text
A owns domain D @ epoch 10 / fence 100
A partitions
Directory commits B @ 11 / 101
A restarts from old durable state
A attempts canonical mutation
=> FENCED
```

## Exit

Directory prototype demonstrates fail-closed one-writer semantics with machine evidence.

---

# I3 — Generic AuthorityDomain Transfer Prototype

## Goal

Rebuild the good SM0 transfer ideas around the R2 Directory linearization rule.

## Transfer model

```text
SOURCE ACTIVE
  -> TARGET COMPATIBILITY CHECK
  -> TARGET WARM
  -> SOURCE FREEZE / DomainMutationBarrier
  -> TARGET DURABLE PREPARED SHADOW
  -> DIRECTORY CAS               <-- ownership linearization
  -> TARGET ACTIVE
  -> SOURCE READ_ONLY / RETIRED
```

## Key change from SM0/P9

Before Directory commit, a cancelled transfer may restore the source.

After Directory commit:

```text
old source can never become writer again for that generation
```

If target fails after commit, recovery must converge through the committed owner/fencing record; it may not simply roll ownership back to the old source by local decision.

## Must prove

- exact TransferId replay;
- conflicting replay rejection;
- frozen mutation rejection;
- durable prepared shadow;
- compatibility mismatch blocks prepare;
- crash at every named transfer state;
- delayed old-owner traffic after commit is fenced;
- one writer globally;
- temporal/tick state never rewinds.

## Exit

Generic domain transfer is semantically sound before attaching real player/item gameplay state.

---

# I4 — Player Carrying Domain Lab

## Goal

Build the first real gameplay-shaped seamless state closure before production activation.

## Domain

```text
PlayerAuthorityDomain player/P
|
+ Player Aggregate
+ Inventory Root
+ Hotbar
+ Equipment
+ Backpack
+ nested containers
+ carried Item Graph subtree
+ operation continuity metadata
```

Ordinary carried descendants use inherited authority through `AuthorityBinding`; they do not each require an independent Directory ownership record.

## Canonical journey

```text
World/A owns item X
   |
   | PICKUP
   v
X binds into PlayerAuthorityDomain/P
   |
   | player domain A -> B
   v
Player + Inventory + X active on B
   |
   | USE X
   v
operation commits on B
   |
   | DROP
   v
X rebinds to WorldDomain/B
```

## Required nested fixture

```text
Player
  Inventory
    Tool
    Backpack
      Container
        Ore stack
        Battery
        Device
```

## Scale invariant

For inherited carried state:

```text
1 item     -> 1 domain ownership transition
10 items   -> 1 domain ownership transition
100 items  -> 1 domain ownership transition
1000 items -> 1 domain ownership transition
```

Directory ownership transition count must not grow linearly with ordinary inventory descendant count.

## Mutation-race matrix

Race handoff with:

- pickup;
- drop;
- stack split;
- container move;
- equip/unequip;
- mount/unmount;
- item use.

Freeze/barrier policy must yield one deterministic result: included before the barrier, queued/retried after it, or explicitly rejected. No ambiguous partial state is permitted.

## Restart/fault cases

- A dies before Directory CAS;
- A dies after CAS;
- B dies after prepared shadow;
- B dies after CAS before activation;
- client retries item operation after migration;
- stale A tries to mutate carried item after B owns domain.

## Exit

The project has evidence for the exact gameplay case that motivated the R2 correction: a player carries real nested item state across an authority boundary without item duplication/loss or per-item ownership churn.

---

# I5 — Edge Gateway Incubation

## Goal

Prototype the non-authoritative ingress layer independently of product integration.

## Stage I5A — single gateway transparency

Topology:

```text
Client -> Gateway -> Authority
```

Compare direct and gateway-routed canonical outcomes for:

- movement/input sequencing;
- one inventory mutation;
- duplicate OperationId;
- reconnect/resume.

## Stage I5B — PRIMARY/OBSERVER/WARM

Topology:

```text
Client -> Gateway
           PRIMARY  -> A
           OBSERVER -> B
           WARM     -> C
```

Must prove:

- gateway route roles do not grant ownership;
- observer cannot mutate;
- gateway does not flip PRIMARY before Directory commit;
- stale route response cannot roll back a newer route;
- client connection can remain stable while owner changes.

## Stage I5C — gateway mobility

Prototype:

- failure-driven rehome;
- quality-driven rehome;
- same PlayerId;
- resumable/stable logical ClientSessionId;
- OperationId survives path change;
- authority does not change merely because gateway changes.

## Exit

Gateway architecture is demonstrated without making the gateway a world owner.

---

# I6 — Projection/AOI and Cross-Owner Interaction Lab

## Goal

Exercise visual overlap and one bounded remote interaction before production SM1 begins.

## Projection proof

- read-only projection envelope;
- epoch/revision/checksum fencing;
- stale/degraded presentation;
- source loss without authority promotion;
- merged interest subscriptions;
- bounded physical upstream connections.

## First cross-owner operations

1. player@A uses item@B;
2. player@A uses simple world object@B;
3. lookup sees B/N, item becomes C/N+1 before commit.

Required properties:

- targeted routing;
- end-to-end OperationId;
- stale expected owner/epoch rejected;
- explicit re-resolve/retry policy;
- no broadcast-to-all fallback;
- no projection/cache mutation path.

## Exit

Border visibility and one bounded cross-owner gameplay path are understood before H8/H9 production work.

---

# I7 — Fault, WAN and Soak Rehearsal

## Goal

Run the R2 architecture as one research system under failures before product activation.

## Minimum process topology

```text
1 Directory
2 Gateways
3 Authorities
2+ Clients
```

## Scenario mix

- repeated PlayerAuthorityDomain A<->B<->C transfers;
- nested inventory use during/after handoff;
- observer projections from non-primary authorities;
- gateway crash and rehome;
- owner crash before and after Directory commit;
- directory restart;
- stale authority incarnation;
- cross-owner item operation;
- deterministic network latency/loss/reorder/partition;
- unrelated authority failure isolation.

## Metrics

Separate:

```text
AUTHORITY_CORRECTNESS
STATE_CONTINUITY
TRANSPORT_CONTINUITY
VISUAL_CONTINUITY
```

Track:

- canonical write gap;
- input gap;
- inventory operation gap;
- projection gap;
- visual gap frames;
- maximum prediction correction;
- hard correction count;
- client disconnects;
- session changes;
- queue/memory growth.

## Exit

A reproducible research soak exists showing where the architecture still fails before production integration.

---

# I8 — Production Port Plan and Work Order Pack

## Goal

Arrive at the post-P6 decision with implementation knowledge already converted into a safe production-entry package.

## Deliverables

### Port map

For each incubation component classify:

```text
PORT AS-IS
PORT WITH ADAPTER
REIMPLEMENT FROM CONTRACT
KEEP RESEARCH ONLY
DISCARD
```

### Dependency map

Identify exact production owners that future SM1 must integrate with:

- Item Graph;
- player aggregate;
- persistence;
- network runtime;
- operation ledger;
- reference frames;
- prediction/interpolation;
- product gateway/client transport boundary.

### Work Orders

Prepare but do not activate exact Work Order templates for:

```text
SM1-H0
SM1-H1
SM1-H2
SM1-H2A
SM1-H2B
SM1-H3
```

Each template states:

- exact allowed owners/files only after production base is declared;
- donor evidence SHA(s);
- mandatory tests;
- forbidden scope;
- fresh reviewer/verifier requirements.

### Baseline diff plan

When P6 is accepted, compare the then-current product baseline against incubation assumptions and explicitly list any drift before porting anything.

## Exit

If main chooses `ACTIVATE_V0_SM1`, H0 can be dispatched from a known exact accepted base without restarting architectural discovery from zero.

---

## 6. Recommended concurrency

Not every incubation stage must be strictly serial. The semantic dependency graph is:

```text
I0 architecture closure
 |
 +--> I1 harness ---------------------------+
 |                                          |
 +--> I2 directory -> I3 domain transfer -> I4 carrying domain
 |                                          |
 +---------------------------------------> I5 gateway
                                             |
                                      I6 projection/XO
                                             |
                                      I7 integrated soak
                                             |
                                      I8 production port pack
```

After I0:

- I1 can proceed in parallel with early I2;
- I5 transport scaffolding can proceed in parallel, but ownership-route semantics must consume the reviewed I2 contract;
- I4 depends on I3;
- I6 depends on enough I2/I5 semantics to route/fence correctly;
- I7 integrates reviewed incubation carriers rather than arbitrary mutable heads.

## 7. Review discipline for incubation

Research prototypes still need evidence discipline because their purpose is to become trustworthy donors.

Recommended minimum per stage:

1. implementer candidate on exact SHA;
2. deterministic/unit/process tests relevant to the stage;
3. machine-readable report;
4. fresh independent critical review for I2/I3/I4/I5/I7;
5. repair cycle as needed;
6. tag/document an exact `DONOR_CARRIER_SHA`.

A research donor PASS does **not** equal production checkpoint acceptance.

## 8. What should be ready by the time P6 closes

Ideal pre-P6 exit state:

```text
Architecture R2             REVIEWED
Research Harness            READY
Ownership Directory         PROVEN IN INCUBATION
AuthorityDomain Transfer    PROVEN IN INCUBATION
Player Carrying Domain      PROVEN IN INCUBATION
Single/Multi-route Gateway  PROVEN IN INCUBATION
Projection/AOI primitives   PROVEN IN INCUBATION
Bounded cross-owner op      PROVEN IN INCUBATION
Fault/WAN/Soak              REHEARSED
H0-H3 Work Orders           DRAFTED
Production port map         READY
```

Still intentionally not claimed:

```text
SM1 production accepted     NO
production owner changed    NO
P6 bypassed                 NO
dynamic meshing activated   NO
```

## 9. Post-P6 handoff

After P6 acceptance, main performs the mandatory seamless decision.

If deferred:

- freeze incubation donor carriers;
- keep reports and port map;
- no production mutation.

If activated:

1. main declares exact accepted SM1 predecessor/base;
2. current main Project Control must satisfy required NON_RED gates;
3. create fresh SM1 epoch/Work Order;
4. rotate the authorized runtime mutation lease/ownership to SM1-H0;
5. branch production H0 from that exact main-declared base;
6. compare product baseline drift against incubation assumptions;
7. port contracts/tests intentionally;
8. execute the normal H0 review/acceptance train.

No incubation branch is merged wholesale as the product history.

## 10. Immediate execution order before P6

The intended practical order is:

```text
NOW
  |
  +--> fresh independent review PR #137
  |
  +--> prepare I1 harness scaffolding in parallel
            |
            v
Architecture R2 PASS
  |
  +--> I2 Ownership Directory
  |      |
  |      v
  +--> I3 AuthorityDomain Transfer
  |      |
  |      v
  +--> I4 Player Carrying Domain
  |
  +--> I5 Gateway work in parallel after I2 route contract stabilizes
            |
            v
       I6 Projection/XO
            |
            v
       I7 integrated soak
            |
            v
       I8 production port pack
            |
            v
       WAIT ONLY FOR P6 CONTROL DECISION
```

This means the project does **not** wait for P6 to discover whether the architecture works. It waits for P6 only to decide whether the proven incubation work is allowed to enter the production lineage.
