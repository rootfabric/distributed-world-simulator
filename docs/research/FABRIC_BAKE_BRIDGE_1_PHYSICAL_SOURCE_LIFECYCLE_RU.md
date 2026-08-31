# FABRIC-BAKE BRIDGE-1 — Physical source lifecycle + bake reconstruction

**Status:** DESIGN SYNCHRONIZED / IMPLEMENTATION NOT YET EXECUTABLE  
**Branch:** `research/fabric-bake-bridge1-physical-source-lifecycle-r1`  
**Base:** `f45801fc41ec4ddd067cc994b6de84a48cb88da1`  
**Risk:** MEDIUM research integration.  
**Canonical owners:** unchanged — Construction / Matter remain authoritative.  
**Production acceptance:** not claimed.

## Problem

B0.0 proves source binding/invalidation contracts and B0.2 proves structural bake,
guarded local unbake and topology re-bake, but the roadmap still requires one explicit
end-to-end gate:

```text
canonical state
→ FABRIC graph
→ bake
→ execute
→ invalidate
→ deterministic rebuild / unbake
```

The missing proof is that these steps can share the existing canonical source revision
universe without BAKE inventing another source revision, authority epoch, mutation owner
or topology-event owner.

## Selected design

BRIDGE-1 adds a non-owning canonical physical-source read view plus a derived FABRIC graph
projection and lifecycle orchestrator.

```text
existing RepresentationSourceRevision
+ caller-owned canonical Construction / Matter payload
+ existing AuthorityEnvelope
        ↓ validate payload hash == source_hash
non-owning PhysicalSourceView
        ↓
derived PhysicalSourceFabricGraph
        ↓
B0.2 structural aggregate + reconstruction mapping
        ↓
B0.2-C conservative guard field
        ↓
B0.0 PhysicalBakeArtifact
        ↓
existing BakeExecutionGate
```

The source view is compile-time/runtime input only. It is not persisted inside the
artifact and cannot create or advance canonical revisions.

## Physical Core binding

Synchronization review observes the current closed Physical Core frontier:

```text
FABRIC0.18 closure HEAD:
b9f4a11cb7c31e47884d12eaad2985811e0b6563

FABRIC0.18 exact physics executable:
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc
```

BRIDGE-1 itself remains a structural source-lifecycle gate and does **not** import
persistent contact/wrench state. Its minimum structural graph dependency therefore remains
the already-closed FABRIC0.16 executable:

```text
FABRIC0.16 executable HEAD:
3307d553c1c3c79cd9c15a5c565af7fef3f0400c
```

This is intentional, not stale dependency drift:

- FABRIC0.18 is the reviewed Physical Core frontier;
- FABRIC0.16 remains the minimum BRIDGE-1 structural graph dependency;
- transient 0.18 contact state is not canonical provenance;
- contact/wrench reduction belongs to B0.3, whose final predecessor is now FABRIC0.18.

The integration compiler identity remains distinct from the upstream solver identity.

## Mutation lifecycle

Only an existing canonical `RepresentationInvalidation` can invalidate the bake:

```text
canonical mutation owner
→ new RepresentationSourceRevision
→ RepresentationInvalidation
→ BRIDGE-1 consumes it
→ BakeInvalidation
→ old artifact STALE
→ old execution forbidden
```

BRIDGE-1 never emits a new canonical source revision or canonical mutation/event.

## Reconstruction semantics

Before rebuild, the old reduced kinematic state is deterministically expanded through the
B0.2 structural reconstruction mapping.

For same-topology canonical property changes:

```text
old reduced state
→ old exact structural mapping
→ full per-part kinematic state
+ current canonical source payload
→ compile new derived graph/bake
→ project kinematic state into new reduced mapping
→ new artifact executes
```

If reduction is no longer worthwhile/safe while canonical topology is unchanged, the
same full per-part kinematic state is returned as a FULL derived physical state. Canonical
mass/topology/material truth still comes only from the current canonical payload.

If canonical part/bond topology changed outside the declared B0.2-E topology lifecycle,
BRIDGE-1 fails closed instead of guessing a handoff.

## Required falsifiers

Acceptance must cover:

- payload bytes do not match declared canonical `source_hash`;
- source frontier mismatch;
- foreign / cross-authority mutable source;
- stale artifact execution;
- canonical mutation without corresponding invalidation;
- invalidation for a different previous source;
- rebuild from stale/foreign source view;
- undeclared topology change during generic rebuild;
- duplicate source/mutation ownership attempt;
- deterministic reverse-input replay;
- deterministic artifact/graph identity;
- deterministic FULL fallback when reduction is intentionally disabled.

## Validation plan

Focused BRIDGE-1 fixture uses the existing 500-part B0.2 rigid-tree source.

Positive path:

```text
500 canonical parts
→ derived graph
→ 13-DOF bake
→ execute
→ canonical mass-property revision
→ old bake stale
→ reconstruct 500 full kinematic states
→ rebuild
→ new 13-DOF bake
→ execute
```

Fallback path forces reduction policy above available complexity while preserving topology:

```text
stale old bake
→ exact full reconstruction
→ no safe/useful rebake
→ FULL_RECONSTRUCTED
```

Required regression chain remains B0.0 → B0.2-E.

## Non-goals

BRIDGE-1 does not add:

- a canonical Construction/Matter registry;
- a second revision clock;
- a new authority system;
- contact/wrench bake;
- cross-authority mutable bake;
- arbitrary topology reconstruction;
- production scheduler ownership;
- production acceptance.


## Physical Core ↔ BAKE synchronization decisions

Review subjects:

```text
Physical Core:
FABRIC0.18 closure
HEAD b9f4a11cb7c31e47884d12eaad2985811e0b6563
exact physics e079565b4b9cd0dae530ff5042f057ce8fa0d0cc

FABRIC-BAKE:
B0.2 closure
HEAD f45801fc41ec4ddd067cc994b6de84a48cb88da1
final executable 91a2f79bf6738efefa342589c44e4a0f0a6960d6

BRIDGE-1 design:
HEAD 56d316283ea34ccb70fc97f97a7493a60b577b94

common dual-track merge base:
962b9c1bbf7f04c7853f1fb0e36480cf54f3250d
```

The two research lines remain intentionally diverged; synchronization is contractual,
not an implicit physics merge.

### Canonical source rule

```text
Construction / Matter RepresentationSourceRevision
= canonical source

FABRIC0.18 state
= derived physical runtime state

PhysicalBakeArtifact
= derived reduced runtime state
```

Therefore FABRIC, persistent contact identity, accepted contact impulse, contact age,
mode state, event-localization state and warm-start proposal MUST NOT be inserted into
`CanonicalSourceFrontier` as a new source domain.

The existing B0.0 split is already sufficient:

```text
canonical source changes
→ frontier_hash / RepresentationInvalidation

derived physical compiler changes
→ fabric_graph_hash / fabric_compiler_version / dependency_hash
```

`BakeExecutionGate` already rejects both classes independently.

### Persistent contact state is not reconstruction truth

B0.2 reconstruction maps only canonical-part kinematics:

```text
position
orientation
linear_velocity
angular_velocity
```

The review explicitly keeps that schema unchanged.

On BRIDGE-1 rebuild/unbake:

```text
old reduced structural state
→ exact per-part kinematic reconstruction
→ current canonical payload
→ new structural graph / bake
→ fresh Physical Core solve
→ optional new persistent contact history
```

Do not reconstruct or transfer as accepted physical truth:

- `accepted_generalized_impulse`;
- `warm_start_proposal`;
- stick/slide/roll/spin mode;
- normal support;
- contact age;
- mode-transition hypothesis.

FABRIC0.18-A already marks warm-start as proposal and requires solver refresh.
FABRIC0.18-D strengthens the same rule by selecting fresh zero-init C physics before
applying persistent history. BRIDGE-1 therefore must re-derive contact physics after a
representation rebuild.

### Event / invalidation ownership matrix

```text
persistent stick→slide/roll/spin
→ derived physical event
→ NO canonical source revision
→ NO structural bake invalidation by itself

support loss / separation
→ derived physical event
→ NO canonical source revision by itself

FABRIC compiler / graph dependency changes
→ derived dependency mismatch
→ old artifact execution forbidden
→ rebuild
→ NO canonical source revision invented

canonical mass/material/property revision
→ RepresentationSourceRevision advances
→ RepresentationInvalidation
→ BakeInvalidation
→ old artifact STALE / forbidden
→ reconstruct + rebuild

canonical bond/topology mutation
→ canonical owner emits event/revision
→ B0.2-E exact-once topology lifecycle
→ affected old reduced artifacts invalidated
→ split/rebuild/re-bake
→ affected persistent contact state re-derived
```

BRIDGE-1 must never turn a derived contact-mode transition into a canonical Construction
or Matter mutation.

### Contact identity at representation transitions

BRIDGE-1 does not own FABRIC0.18 contact identity.

After structural rebuild:

- affected contact state is discarded and freshly derived;
- an unaffected persistent identity may be reused only if the Physical Core itself proves
  exact pair/manifold identity continuity;
- BRIDGE-1 may not manufacture equivalence between old and new manifold IDs.

This prevents bake reconstruction from becoming a second contact-history authority.

### B0.3 dependency update

The old roadmap rule allowed final B0.3 acceptance after FABRIC0.16. That is no longer
strong enough for the intended B0.3 claim.

Final B0.3 acceptance now requires the closed FABRIC0.18 physical boundary because B0.3
must preserve not only convex manifold support but also:

- generalized tangent/rolling/torsional wrench limits;
- persistent support redistribution;
- stick→slide / roll / spin thresholds;
- lift-off/support-loss semantics;
- contact-loss event timing;
- passive energy behavior across persistent trajectories;
- fresh-physics-over-history invariant.

Prototype experiments may still use narrower predecessors, but final acceptance is
`FABRIC0.18+`.

## BRIDGE-1 implementation delta after synchronization

The synchronization review does not implement BRIDGE-1 runtime. It makes the implementation
boundary executable-ready.

Required BRIDGE-1 acceptance additions:

1. same canonical frontier + changed FABRIC compiler/graph dependency rejects old artifact
   without fabricating a new canonical revision;
2. a persistent mode transition alone does not invalidate the structural bake;
3. canonical source mutation invalidates the structural bake exactly once;
4. rebuild reconstructs only kinematics and performs a fresh Physical Core solve;
5. previous accepted contact impulse/warm-start cannot become accepted post-rebuild truth;
6. topology revision routes through B0.2-E ownership rather than BRIDGE-1 inventing an event;
7. reverse canonical-input presentation produces deterministic graph/artifact/rebuild identity;
8. FULL fallback also drops/re-derives transient contact solver history.

Result:

```text
SYNC REVIEW
PASS

CRITICAL CONTRACT CONFLICTS
0

BRIDGE-1
IMPLEMENTATION UNBLOCKED
NOT YET EXECUTABLE / NOT CLOSED

B0.3 FINAL
DEPENDENCY = FABRIC0.18
```


## BRIDGE-1 executable evidence

Exact executable:

```text
HEAD
e128cf9d49f84691b8a5428c97ab7acd53b92d90

TREE
f0deeb1848c6570d12364976f4fd07007657029d
```

Status at this evidence boundary:

```text
BRIDGE-1
PHYSICAL SOURCE LIFECYCLE + BAKE RECONSTRUCTION

IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
146/146 PASS
REMOTE BYTE IDENTITY 7/7 PASS
PROJECT CONTROL #1917 SUCCESS
NOT YET CLOSED
NOT PRODUCTION ACCEPTED
```

### Executable lifecycle

```text
canonical Construction / Matter
→ canonical source frontier
→ PhysicalSourceView
→ derived PhysicalSourceFabricGraph
→ B0.2 structural aggregate + guard field
→ PhysicalBakeArtifact
→ BakeExecutionGate
→ execute reduced state
→ RepresentationInvalidation
→ BakeInvalidation
→ old artifact STALE / forbidden
→ exact 500-part kinematic reconstruction
→ same-topology rebuild OR deterministic FULL fallback
```

The graph records two different Physical Core facts deliberately:

```text
minimum structural dependency:
FABRIC0.16 exact executable
3307d553c1c3c79cd9c15a5c565af7fef3f0400c

reviewed Physical Core frontier:
FABRIC0.18 closure
b9f4a11cb7c31e47884d12eaad2985811e0b6563
```

BRIDGE-1 remains structural lifecycle integration; B0.3 owns contact/wrench reduction.

### Canonical-source and authority proof

The source view validates the supplied canonical payload bytes against each
`RepresentationSourceRevision.source_hash` and reuses the existing canonical frontier
and authority envelope.

Negative cases:

```text
payload tamper        → BRIDGE1_SOURCE_PAYLOAD_HASH_MISMATCH
cross-authority bake  → AUTHORITY_ENVELOPE_CROSSED
```

No second source clock, authority system or canonical FABRIC state is introduced.

### Stale execution / invalidation / rebuild

A canonical mass-property revision advances Construction source revision.

Without the new frontier the old artifact fails execution with source-frontier mismatch.
With a valid RepresentationInvalidation the existing BRIDGE-0 mapping emits a
BakeInvalidation and the old artifact becomes immediately non-executable:

`STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN`.

The old 13-DOF reduced state is reconstructed into exactly 500 per-part states containing
only:

```text
position
orientation
linear_velocity
angular_velocity
```

The new source is then recompiled. Build generation advances `1 → 2`, the derived graph
and artifact identity change, and the fresh artifact passes its execution gate.

Measured handoff error:

`2.0097183471152322e-14`.

### Transient contact history boundary

The artifact is explicitly checked not to contain accepted Physical Core transient history
such as warm start, accepted generalized impulse or contact age.

For:

```text
STICK_TO_SLIDE
STICK_TO_ROLL
STICK_TO_SPIN
SUPPORT_TO_SEPARATION
```

BRIDGE-1 emits neither a canonical revision nor structural bake invalidation.

After rebuild:

```text
contact_state_policy = DISCARD_AND_REDERIVE
accepted_previous_contact_impulse = false
```

A fresh Physical Core solve owns the new contact state.

### Topology ownership / duplicate lifecycle proof

Generic same-topology rebuild refuses a changed structural topology:

`BRIDGE1_TOPOLOGY_CHANGE_REQUIRES_B0_2_E`.

Thus B0.2-E remains the unique topology split/re-bake lifecycle owner.

An already-consumed source invalidation also fails closed:

`BRIDGE1_SOURCE_INVALIDATION_ALREADY_APPLIED`.

### Determinism and FULL fallback

Reversing canonical input presentation preserves exact:

- source view identity;
- derived graph hash;
- topology hash;
- guard-field checksum;
- artifact checksum.

A deterministic FULL fallback reconstructs the same 500-part state under reverse input.

FULL state hash:

`d268103540016a9818a4aa75f1dcbb5fa54004643ca01ff541fedbac6a441178`.

A policy that asks for a minimum reduction complexity above the 500-part fixture also
chooses FULL before emitting an unsafe/useless bake.

### Exact outputs

```text
focused acceptance:
146/146 PASS

artifact:
7d9accdc4393f2cc041942b1a33f59651476d2d6e33b76217a8c5534484be0ad

physical graph:
d81e27c550f83c8dd0fe75284e7aad8305f6d1d093d219899d345b21a05d0114

rebuilt artifact:
bf8fccc033d13cbe25975c228113dc8199d7e40d1182c408bb8113df4dbba269

handoff error:
2.0097183471152322e-14

FULL state:
d268103540016a9818a4aa75f1dcbb5fa54004643ca01ff541fedbac6a441178
```

Two fresh-filesystem focused runs produced identical acceptance/playground summaries.

Predecessor heavy-tail verification:

```text
B0.2-D   609/609 PASS
B0.2-E  2580/2580 PASS
B0.2-E playground PASS
```

The heavy B0.2 wrapper itself was not claimed as one uninterrupted completed command;
D and E were rerun independently to completion.

Fresh import exits 0. The new BRIDGE scripts pass parse/check/editor scan. The inherited
B0.2 exact tree still prints known unrelated historical ECO scene diagnostics; these are
not reclassified as BRIDGE failures or as a globally clean import claim.

### Exact BRIDGE-1 file identity

```text
physical_source_view_v1.gd
blob 866d2eff719c9279b0bf6ed224ae1be4ab8a88c9
sha256 c3e063542b1a5b2e7c2556233a9b7ab9e0f2cadb1c38523d9a92f05468cf6693

physical_source_fabric_graph_v1.gd
blob a9da05ec5526bebd650cd406b9c4c854ea9c0389
sha256 88ec674d667cbfe619f0c2bc0e1ffe689a77d46b56d89579613d8a78b025efd6

physical_source_lifecycle_v1.gd
blob f9ab4ccc384c060017108db05a7ae4c76045e00d
sha256 f20c6d0c1c6dbd30907bbc7e9bbff52a628f7e46df4085de4b8f0eb9b537d91c

fabric_bake_bridge1_fixture.gd
blob 1b926d7208634fbf3ddb1488f2f2d95c457c72b0
sha256 e550e65b4c19eed9b9f83d274d8eced8109290550b4fe807e3e26e4945f35954

fabric_bake_bridge1_acceptance.gd
blob 7d374a6327519a4bc0b3b3af5a4ff0c91fe68372
sha256 85b30f749c1ebda902d95939cd1740f8449cd2557178037282e191fc13fc6e96

fabric_bake_bridge1_playground.gd
blob 57d82abc0175823a77c536c87226b6a287c7cee8
sha256 ec6b07f1b346dc579dc38e6daa252b67a0dc7d47cbca5f803a60f1fdf0bc936d

RUN_FABRIC_BAKE_BRIDGE1_TESTS.sh
blob 00b06d8e1869f78a2ff759644d5b71464c90f8d5
sha256 cf6c687065b8eeeae3a4fa2678378234a0d52236c9157949d93a604af3e7a97f
```

Remote exact-byte audit: `7/7 PASS`.

### Project Control

Exact executable:

```text
Project Control #1917
run id 33388409345
SUCCESS
```

All repository-level architecture/ownership, H0.2, V0, generation-80 safety,
canonical-main PC0 and directional-watch steps passed.

### Current qualification

```text
BRIDGE-1
IMPLEMENTED CANDIDATE
PROJECT CONTROL PASS
CLOSURE-READY
NOT YET CLOSED
NOT PRODUCTION ACCEPTED
```


## BRIDGE-1 final closure

```text
BRIDGE-1
PHYSICAL SOURCE LIFECYCLE + BAKE RECONSTRUCTION

RESEARCH INTEGRATION CHECKPOINT CLOSED
EXACT DOUBLE PASS
REMOTE BYTE IDENTITY PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

Exact executable remains:

```text
HEAD
e128cf9d49f84691b8a5428c97ab7acd53b92d90

TREE
f0deeb1848c6570d12364976f4fd07007657029d
```

Evidence/control carrier:

```text
a10ced235113a0e1d8a29e452e4519b87ae0b443
Project Control #1918 SUCCESS
run id 33388671545
```

The exact executable itself passed:

```text
Project Control #1917 SUCCESS
run id 33388409345
```

Closure changes no runtime bytes.

Closed research/integration claims:

- canonical source payload hash validation;
- reuse of existing source frontier and authority envelope;
- deterministic derived physical source graph;
- B0.2 structural bake emission from canonical source;
- stale execution fail-closed under source/dependency mismatch;
- canonical invalidation → bake invalidation;
- exact 500-part kinematic reconstruction;
- same-topology rebuild with a fresh artifact;
- deterministic FULL fallback;
- transient contact state discarded/re-derived rather than persisted as truth;
- topology changes routed to B0.2-E;
- duplicate invalidation consumption rejected;
- reverse-input exact deterministic identity;
- cross-authority mutable bake rejected.

Persistent non-claims:

- B0.3 Contact/Wrench Bake;
- arbitrary topology rebuild inside BRIDGE-1;
- multi-authority mutable bake;
- production scheduler ownership;
- production acceptance;
- FABRIC0.19.

The next FABRIC-BAKE executable checkpoint is:

```text
B0.3
CONTACT / WRENCH BAKE

final Physical Core predecessor:
FABRIC0.18
RESEARCH CANDIDATE CLOSED
```

Do not reinterpret BRIDGE-1 closure as production acceptance or as ownership transfer from
Construction/Matter.
