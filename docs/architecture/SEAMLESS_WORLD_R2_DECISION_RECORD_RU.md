# Seamless World R2 — Decision Record

Status: `RESEARCH ARCHITECTURE DECISION RECORD`

This document records **why** R2 changed the R1 candidate and what evidence/source motivated each change. It is intentionally explicit so later implementers do not reintroduce superseded assumptions.

## ADR-R2-01 — AuthorityDomain is the ownership/migration closure

### Trigger

Review of the real gameplay case:

```text
player on A
picks up item owned by A
carries nested inventory
crosses to B
continues using inventory
```

SM0 proves player handoff and separately proves item authority-boundary transfer semantics, but not one end-to-end player + nested inventory domain migration.

### Decision

Introduce `AuthorityDomain` as the unit whose canonical writer ownership normally changes together.

### Why

Per-item ownership CAS during normal player handoff scales with inventory size and creates unnecessary race windows.

### Expected improvement

- one ownership transition for carried state closure;
- stable item identities and Item Graph relationships;
- smaller ownership/routing surface;
- easier crash/replay reasoning.

### What is not implied

An AuthorityDomain is not a new Item Graph and is not automatically a physics island.

---

## ADR-R2-02 — AuthorityBinding with inheritance

### Trigger

Need to connect stable canonical subjects to a movable domain without storing an independently mutable ownership record for every child.

### Decision

Use versioned `AuthorityBinding` with normal `INHERIT` mode and bounded `EXPLICIT` mode.

### Expected improvement

- effective authority can follow parent domain;
- nested inventory can migrate through one domain owner change;
- stale rebind attempts are rejectable by binding generation.

---

## ADR-R2-03 — PlayerAuthorityDomain is mandatory before gateway player handoff

### Trigger

R1 roadmap placed InteractionIsland late and allowed H5 to prove a player handoff without proving real carried state closure.

### Decision

Add `SM1-H2A AuthorityBinding + Domain Closure` and `SM1-H2B Player Carrying Domain Lab` before gateway milestones.

H5 is renamed conceptually to gateway-mediated `PlayerAuthorityDomain` handoff.

### Expected improvement

The project cannot declare production player seamlessness on a naked-player fixture while inventory/equipment remains unproven.

---

## ADR-R2-04 — InteractionIsland is physical/locality, not default inventory ownership

### Trigger

Follow-up review showed that calling player inventory an InteractionIsland would mix two different concerns.

### Decision

Keep:

```text
AuthorityDomain = ownership/migration closure
InteractionIsland = co-simulation/placement constraint
```

### Expected improvement

- inventory ownership remains simple;
- physics/collision locality remains independently optimizable;
- later dynamic meshing can use interaction topology without redefining Item Graph ownership.

### Provenance

The InteractionIsland concept remains motivated by physical/nested-reference-frame evidence in SM0 and by external server-meshing research that groups strongly interacting/colliding objects. R2 only narrows its role.

---

## ADR-R2-05 — Pickup/drop must coordinate Item Graph and authority binding

### Trigger

A pickup changes both canonical container membership and the authority context that may mutate the carried item.

### Decision

Pickup/drop are canonical operations whose accepted result must leave Item Graph membership and AuthorityBinding consistent.

### Forbidden states

```text
Item Graph says PLAYER, binding says WORLD
Item Graph says WORLD, binding says PLAYER
```

### Expected improvement

Prevents duplicated/lost/stale carried objects during handoff and recovery.

---

## ADR-R2-06 — DomainMutationBarrier is required

### Trigger

Inventory/gameplay operations may race with authority handoff freeze.

Examples:

- pickup;
- drop;
- stack split;
- container move;
- equip;
- item use.

### Decision

Freeze records an exact domain revision and operation-sequence barrier. Every racing operation is deterministically classified as before/included or after/queued-retried-rejected.

### Expected improvement

No acknowledged operation disappears between source and target and no operation commits twice because route changed.

---

## ADR-R2-07 — SM0 P9 is a donor, not the production post-CAS protocol

### Trigger

P9 laboratory transfer can retire source and, if target commit fails, roll source state back. R1 introduced a stronger canonical Directory CAS linearization point.

### Decision

Retain P9 evidence for freeze, shadow, stable ItemId, revision fencing, retirement proof, replay and failure tests.

Do **not** retain old-source writer rollback after `DIRECTORY_COMMITTED`.

### Production rule

```text
before Directory commit:
  rollback/cancel may restore source

after Directory commit:
  old source is fenced permanently for that generation
  recovery is forward or fail-closed
```

### Expected improvement

Eliminates a path where two systems disagree on whether ownership was already committed.

---

## ADR-R2-08 — Temporal continuity is explicit

### Trigger

Ownership correctness alone does not prevent simulation tick/state revision rewind, prediction jumps or reference-frame discontinuity.

### Decision

Carry a monotonic timeline/state stamp through domain transfer and assert continuity independently from ownership.

### Expected improvement

- smoother movement handoff;
- safer prediction/interpolation;
- clearer ordering of projections;
- measurable hard-correction/rewind behavior.

---

## ADR-R2-09 — Gateway mobility includes quality-driven rehome

### Trigger

Multi-region gateways solve geographic ingress, but a long-lived client may later have a materially better path to another gateway without any gameplay authority change.

### Decision

H7 covers both:

```text
FAILURE_DRIVEN rehome
QUALITY_DRIVEN rehome
```

with hysteresis/cooldown.

### Expected improvement

Network edge can optimize/fail over independently of canonical simulation placement.

---

## ADR-R2-10 — Protocol/build compatibility before prepare

### Trigger

A long-running distributed world will need rolling upgrades; a healthy target can still be semantically incompatible with transfer payload/contracts.

### Decision

Target eligibility checks `build_id`, `protocol_hash`, contract versions and required capabilities before prepare/commit.

### Expected improvement

Schema incompatibility fails before ownership transition rather than after it.

---

## ADR-R2-11 — Seamlessness has four acceptance dimensions

### Trigger

SM0 correctly prioritized authority correctness, but future production acceptance must not confuse one-writer correctness with user-visible seamlessness.

### Decision

Report separately:

```text
AUTHORITY_CORRECTNESS
STATE_CONTINUITY
TRANSPORT_CONTINUITY
VISUAL_CONTINUITY
```

### Expected improvement

A smooth visual demo cannot hide ownership bugs, and a correct handoff cannot be mislabeled visually seamless if it causes reconnect, long input gap or hard rewind.

---

## ADR-R2-12 — Integrated journey is mandatory at H12

### Trigger

A collection of isolated PASS tests can miss composition failures.

### Decision

Static SM1 closure includes an end-to-end journey combining:

- movement;
- pickup;
- nested inventory;
- PlayerAuthorityDomain handoff;
- immediate post-handoff item use;
- multi-authority projection;
- gateway rehome;
- cross-authority operation;
- drop to target world domain;
- authority restart/recovery;
- deterministic adverse network conditions.

### Expected improvement

Proves that individually correct components compose into a usable seamless world.

---

## 13. Source/evidence map

### Internal DWS / SM0 evidence

Used as donors for:

- stable identity;
- one-writer/epoch fencing;
- prewarm/freeze/prepare/retire/activate reasoning;
- durable recovery lessons;
- nested moving reference frames;
- P9 foreign item boundary and item identity/replay semantics;
- P10 multi-authority read-only presentation;
- P11 fault/soak discipline.

SM0 remains frozen research evidence and is not a production base.

### Earlier Edge Gateway research

Used as donor for:

- multiple geographic gateways;
- one stable client ingress abstraction;
- PRIMARY/OBSERVER/WARM logical routes;
- pooled/multiplexed gateway-authority transports;
- gateway rehome semantics.

### External distributed-simulation/server-meshing research

Used as pattern provenance for:

- explicit ownership/responsibility transfer framing;
- static-first progression;
- dynamic region/domain placement before fine-grained split/merge;
- interaction-aware grouping for strongly interacting physical objects.

External projects/standards remain conceptual donors only. No source code is copied and no external topology is treated as mandatory DWS design.

---

## 14. What R2 deliberately does not solve yet

- exact backing store/consensus technology for Ownership Directory;
- arbitrary automatic InteractionIsland formation;
- dynamic domain allocator;
- split/merge algorithm;
- global deployment/orchestration technology;
- Construction/Matter-wide cross-authority transactions;
- exact gateway score coefficients;
- exact client transport protocol;
- a separate extracted networking framework repository.

Those decisions remain deferred until prior static evidence requires them.
