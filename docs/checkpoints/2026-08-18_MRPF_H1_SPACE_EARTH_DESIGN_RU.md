# MRPF-H1 — SPACE + EARTH graphical/process-isolated stand — Design Brief

**Status:** DESIGN BRIEF / USER-AUTHORIZED IMPLEMENTATION / NOT ACCEPTED  
**Program:** MRPF-H research  
**Risk:** HIGH  
**Risk trigger:** real process-isolated network protocol / UDP transport behavior  
**Branch:** `research/mrpf-h1-space-earth`  
**Stack base:** `research/mrpf-h0-contracts @ dc202f6382b8c9b2e9e3e86200b913f7fa03118b`  
**Parent roadmap:** `docs/plans/MRPF_HIERARCHICAL_PROJECTION_STANDS_RU.md`  
**Execution rules companion:** `docs/plans/MRPF_HIERARCHICAL_PROJECTION_STANDS_EXECUTION_RULES_RU.md`

H1 starts as a stacked research implementation while H0 formal final acceptance/control closure is still pending. H1 implementation does not retroactively mark H0 accepted and cannot be used as H0 acceptance evidence.

## 1. Problem statement

H0 proves deterministic offline composition, identity fencing, revision fencing and coarse/fine fallback without processes or transport.

H1 must prove that the same representation semantics survive a real process boundary:

```text
SPACE publisher process
EARTH publisher process
CLIENT graphical/composer process
```

The client must receive projection data from separate sources, prefer the finer Earth representation while its source is healthy, fall back to SPACE when EARTH disappears, and accept a newer fine revision after EARTH process restart.

The important result is distributed-source behavior, not astronomical scale fidelity.

## 2. Current behavior

H0 currently provides:

- closed projection DTO;
- stable `canonical_subject_id`;
- `SPACE < EARTH < SURFACE < BASE` specificity;
- sticky representation identity/revision ledger;
- tombstoned removal;
- coarse fallback;
- deterministic view hash;
- presentation-only / no canonical-write semantics.

It has no transport, source liveness, process isolation or graphical Earth representation.

## 3. Desired behavior

Automated process scenario:

```text
A. Start SPACE publisher.
B. Start CLIENT with two independent UDP receive routes.
C. Client receives SPACE Earth LOD0 and renders one coarse Earth.
D. Start EARTH publisher revision 1.
E. Client receives EARTH Earth LOD1 and atomically swaps the one Earth visual to fine.
F. Stop EARTH process.
G. Client detects EARTH route timeout, tombstones fine revision 1 and reveals SPACE coarse fallback.
H. Restart EARTH publisher revision 2.
I. Client accepts the same fine representation identity at newer source revision and swaps back to fine.
J. No duplicate Earth node, no canonical mutation and no SPACE-route interruption occur.
```

Graphical operator mode uses the same client runtime and casual-scale Earth geometry.

## 4. Casual scale decision

H1 does not use real Earth radius or astronomical approach distance.

Selected fixture geometry:

```text
Earth radius: approximately 1.6 scene units
coarse camera distance: approximately 8 scene units
fine camera distance: approximately 4.5 scene units
```

These values exist only to make the replacement visible and fast.

They do not alter canonical WorldAddress/spatial contracts or claim real-scale simulation evidence.

## 5. Framework-readiness constraint

The implementation follows the prospective Network Framework-Ready Development Policy from the frozen SM0 guidance carrier:

```text
feature/sm0-two-authority-seamless-handoff-lab
@ 9acf8efb47895dff785265bcee55d51b1b33da0a
```

No framework repository or production framework extraction is created.

Dependency goal:

```text
SPACE/EARTH fixture + graphical adapter
        ↓
generic-shaped MRPF research datagram/route envelope
        ↓
PacketPeerUDP loopback transport
```

Transport/envelope code must not import Item Graph, Construction, Matter, Ecology or Earth gameplay semantics.

Earth-specific representation construction remains in a fixture/adapter layer.

## 6. Selected design

### 6.1 Existing H0 contract/composer

Reuse exact H0 implementation. Do not fork a second composer or representation truth.

### 6.2 Generic-shaped research datagram

Add a bounded H1 research envelope with fields such as:

```text
schema
source_route_id
sequence
payload
payload_hash
```

`payload` contains the existing closed H0 representation DTO.

The datagram helper validates schema, route identity, sequence, deterministic payload hash and H0 DTO validity.

This remains research code under MRPF; it is not promoted to `scripts/network/` merely for future extraction aesthetics.

### 6.3 Scenario fixture

A SPACE/EARTH fixture creates:

```text
SPACE coarse Earth representation
EARTH fine Earth representation
```

Both use the same:

```text
canonical_subject_id = earth
replacement_group_id = earth/full
coverage_scope = earth/full
reference_frame_id = frame/earth
```

but distinct immutable representation identities and publishers.

### 6.4 Publisher processes

A single publisher-process implementation receives role/configuration through command-line user arguments and periodically emits a deterministic datagram over loopback UDP.

Scenario adapter decides whether to construct SPACE or EARTH payload. The transport loop itself does not interpret Earth semantics.

### 6.5 Client process

The client owns two independent bound UDP sockets:

```text
SPACE route port
EARTH route port
```

This proves simultaneous route fan-in rather than one socket whose destination is rewritten.

It feeds validated H0 DTOs into the existing composer.

EARTH liveness timeout removes only the fine representation at the exact accepted revision. SPACE remains resident.

### 6.6 Presentation

The client creates exactly one `MeshInstance3D` for Earth.

Selected representation changes the mesh/detail/material of that node; it never creates a second Earth presentation for fine LOD.

A small HUD exposes:

```text
SPACE route state
EARTH route state
selected domain / LOD
source revision
view hash
phase
```

Automated headless mode verifies the same scene-node state.

### 6.7 Process orchestrator

A focused Godot test launches child Godot processes:

```text
SPACE publisher
CLIENT
EARTH publisher rev1
```

and later terminates/restarts EARTH at rev2.

Child processes write bounded machine-readable state/evidence under a test artifact directory supplied by the orchestrator.

The orchestrator checks phase transitions, exact source/revision selection, route isolation, one-Earth presentation cardinality and clean child shutdown.

## 7. Alternatives considered

### One process with synthetic source toggles

Rejected as primary H1 evidence because it does not prove process isolation or transport failure.

### One client UDP socket with destination redirect

Rejected because it does not prove simultaneous source routes.

### Real-scale Earth geometry

Rejected as unnecessary H1 scope. It slows graphical iteration without strengthening the network contract.

### Immediate generic implementation under `scripts/network/`

Rejected for H1. Framework-readiness policy explicitly says not to broaden the current task for speculative extraction. The bounded research route helper should first prove semantics; a later Work Order can promote stable generic pieces.

### Reusing full V0/NX gameplay networking stack

Rejected because it would pull Item/player/gameplay authority semantics into a projection-only research proof and substantially increase blast radius.

## 8. Affected canonical owners

No canonical gameplay owner changes.

H1 consumes:

```text
MRPF-H0 representation/composer research contracts
Godot PacketPeerUDP transport primitive
```

It does not claim ownership of:

```text
AUTHORITY
NX production protocol
Item Graph
Construction
persistence
WorldAddress
Matter
Ecology
```

## 9. Allowed implementation surfaces

Expected bounded paths:

```text
scripts/runtime/seamless/mrpf/h1/**
scenes/labs/mrpf/**
tests/runtime/seamless/mrpf/**
RUN_MRPF_H1_TESTS.sh
RUN_MRPF_H1_TESTS.ps1
RUN_MRPF_H1_GRAPHICAL.sh
RUN_MRPF_H1_GRAPHICAL.ps1
docs/checkpoints/2026-08-18_MRPF_H1_*.md
docs/plans/MRPF_HIERARCHICAL_PROJECTION_STANDS_EXECUTION_RULES_RU.md
```

Avoid `scripts/network/**` unless a concrete correctness need appears and scope/risk is explicitly reclassified.

## 10. Forbidden / non-goals

H1 must not implement:

- canonical player handoff;
- `ClientConnectionSet` production foundation;
- dynamic directory/interest resolver;
- persistence/recovery durability;
- HLOD generation;
- Surface/Base hierarchy;
- Moon policy;
- production Earth renderer;
- real-scale spatial simulation;
- Item/Construction/gameplay mutation;
- framework repository/package extraction;
- production NX protocol mutation.

## 11. Required invariants

```text
one Earth canonical subject identity
one visible Earth presentation node
SPACE coarse selected before EARTH route
EARTH fine atomically replaces coarse
EARTH dropout reveals coarse without visible hole once timeout is declared
SPACE route remains live during EARTH dropout
EARTH rev2 reconnect is accepted after rev1 tombstone
no stale rev1 resurrection
no coarse+fine duplicate presentation
all received payloads are presentation-only
zero canonical mutation APIs added
transport helper has no Earth/gameplay dependency
```

## 12. Validation plan

### Contract/focused

- datagram schema validation;
- deterministic payload hash;
- malformed/unknown/wrong route fields fail closed;
- H0 representation validation inherited;
- route sequence stale/duplicate handling where stateful client filtering applies.

### Process isolated

Real child Godot processes over loopback UDP:

```text
SPACE-only coarse
EARTH rev1 fine
forced EARTH process death
coarse fallback
EARTH rev2 restart
fine restoration
```

### Graphical

Same client runtime:

- casual-scale Earth visible;
- one Earth node only;
- coarse/fine visual distinction;
- camera approach;
- forced source dropout/fallback visible;
- HUD state consistent with composer.

### Regression

Run H0 focused suite unchanged after H1 implementation.

## 13. Evidence and review

Because risk is HIGH:

```text
Implementer
→ bounded post-build critique
→ Evidence Map
→ fresh independent Reviewer
→ fresh independent Verifier
→ Director verdict
```

No H1 acceptance/merge is inferred from implementer test success.

H0 final acceptance and external Project Control resolution remain separate prerequisites for declaring the H-line formally advanced.

## 14. Framework impact expectation

```text
Framework impact:
- generic core changed: NO
- simulator adapter changed: NO production adapter; research fixture only
- research-only code changed: YES
- new simulator -> network dependency: research MRPF H1 -> Godot UDP primitive
- new network -> simulator dependency: NONE
```

If implementation requires a new production `scripts/network/**` component, this section and risk/scope must be revisited before that change.
