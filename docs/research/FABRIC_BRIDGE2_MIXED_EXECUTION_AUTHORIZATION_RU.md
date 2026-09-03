# FABRIC BRIDGE-2 — Mixed Representation Execution — Authorization R1

## Qualification

```text
BRIDGE-2 MIXED FULL ↔ BAKED ↔ DYNAMIC ROM ↔ HYBRID BAKE
EXECUTABLE RESEARCH AUTHORIZED
NOT YET IMPLEMENTED
NOT PRODUCTION ACCEPTED
```

Authorized by FABRIC.SYNC4.

Canonical branch:

`research/fabric-bridge2-mixed-representation-r1`

## Representation set

R1 must support one graph containing explicit regions of:

- FULL;
- STRUCTURAL_BAKE;
- CONTACT_BAKE;
- DYNAMIC_ROM;
- HYBRID_BAKE.

## Ownership

Canonical world truth:

`PHYSICAL_SOURCE / Construction / Matter`.

Every physical execution region must have exactly one active representation owner.

Reduced/runtime state is derived only.

Cross-region state sharing without a declared PhysicalBoundaryContract is forbidden.

## Handoff

Representation changes must use:

```text
source representation
→ ReconstructionDescriptor / exact FULL state
→ target StateMapping / target initialization
```

or an equivalent exact FULL state handoff.

Private solver-state copying is forbidden.

## Events

Physical events remain owned by FABRIC.

BRIDGE-2 may route representation changes caused by an event, but may not create a
second physical event for the same instant.

## Invalidation

Canonical source mutation must fan out invalidation to every affected derived
representation/cache.

Affected stale representation execution is forbidden before any following mixed
step.

## First subject

`MIXED_GENERIC_MACHINE_R1`.

The subject must contain all five representation kinds under one canonical source
frontier and compare against a FULL reference.

## Fail closed

Required fallbacks:

- FULL;
- REFINE/RECONSTRUCT then FULL;
- NO_SAFE_BAKE.

Nearest representation guessing and stale artifact reuse are forbidden.

## Non-claims

This authorization does not claim:

- BRIDGE-2 closure;
- arbitrary world-scale mixed scheduling;
- distributed authority;
- FABRIC0.19 necessity;
- device-specific solver kernels;
- production acceptance.

---

## Final exact closure — 2026-09-03

```text
exact review HEAD:
6e0eae86860128dab47dc19375a20d40a21ad819

TREE:
1711636ee0028390c4ad65767ac90a57d3498814

SYNC4 acceptance:
122/122 PASS

Project Control:
33717946953 SUCCESS

exact source carrier:
33717947039 SUCCESS

bundle SHA-256:
ccd5d433ed6b089677e257eea9f43b2485627354dd18533f17aae1b1e280d80f
```

Final decision:

```text
FABRIC.SYNC4
✅ CLOSED

BRIDGE-2 EXECUTABLE RESEARCH
✅ AUTHORIZED

FABRIC0.19
⛔ NOT AUTHORIZED
```

Canonical BRIDGE-2 implementation branch is created from the final SYNC4 closure
carrier after docs/validation-only closure control passes.
