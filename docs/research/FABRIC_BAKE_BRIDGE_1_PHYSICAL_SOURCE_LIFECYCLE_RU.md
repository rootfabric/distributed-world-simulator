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
