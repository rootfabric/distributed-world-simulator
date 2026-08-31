# FABRIC-BAKE BRIDGE-1 — Physical source lifecycle + bake reconstruction

**Status:** DESIGN BRIEF / IMPLEMENTATION IN PROGRESS  
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

The derived graph records the closed FABRIC0.16 research executable dependency:

```text
FABRIC0.16 executable HEAD:
3307d553c1c3c79cd9c15a5c565af7fef3f0400c
```

BRIDGE-1 does not import contact/wrench behavior and therefore does not claim B0.3.
The integration compiler identity is distinct from the upstream solver identity.

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
