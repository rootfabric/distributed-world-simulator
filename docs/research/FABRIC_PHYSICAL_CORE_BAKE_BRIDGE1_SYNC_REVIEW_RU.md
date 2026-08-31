# Physical Core ↔ FABRIC-BAKE / BRIDGE-1 synchronization review

**Date:** 2026-08-31  
**Status:** REVIEW PASS / CONTRACTS SYNCHRONIZED  
**Branch:** `research/fabric-bridge1-sync-review-r1`  
**Production acceptance:** not claimed.

## Exact subjects

```text
FABRIC0.18 closure:
b9f4a11cb7c31e47884d12eaad2985811e0b6563

FABRIC0.18 exact physics:
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc
TREE c051cabd50343603efc509887f32fadf479f0f54

FABRIC-BAKE B0.2 closure:
f45801fc41ec4ddd067cc994b6de84a48cb88da1

B0.2 final executable:
91a2f79bf6738efefa342589c44e4a0f0a6960d6
TREE 610288ea119e9f7508f711ce5b0468b272a9b489

BRIDGE-1 design:
56d316283ea34ccb70fc97f97a7493a60b577b94

common dual-track merge base:
962b9c1bbf7f04c7853f1fb0e36480cf54f3250d
```

Git histories are intentionally diverged. Review compares explicit subjects; it does not
merge either research runtime into the other branch.

## Review result

```text
canonical ownership conflict         PASS / none found
source revision model                PASS / shared existing model
authority envelope                   PASS / unchanged
physical stale execution rule        PASS / already fail-closed
structural reconstruction schema     PASS / keep kinematics-only
persistent contact truth ownership   PASS / remains Physical Core derived state
event ownership                      PASS / canonical topology stays Construction/Matter
B0.3 predecessor                     UPDATED 0.16 → 0.18
BRIDGE-1 implementation              UNBLOCKED, NOT IMPLEMENTED
critical conflicts                   0
```

## Why 0.18 does not enter CanonicalSourceFrontier

The BAKE contract already separates:

```text
canonical_source_frontier
from
fabric_graph_hash / fabric_compiler_version / dependency_hash
```

That is the correct synchronization seam.

FABRIC0.18 persistent contact state is runtime-derived. Making it a canonical source would
create exactly the parallel truth/revision universe FABRIC-BAKE was designed to forbid.

## Rebuild rule

BRIDGE-1 reconstruction continues to restore only:

```text
position
orientation
linear_velocity
angular_velocity
```

After rebuild or unbake, contact/wrench state is freshly solved.

Never reconstruct an old accepted contact impulse as post-rebuild truth.

## Invalidation matrix

| Change | Canonical revision? | Structural bake action | Contact state |
|---|---|---|---|
| stick→slide/roll/spin | no | keep artifact if otherwise valid | Physical Core updates |
| support loss/separation | no, by itself | keep artifact if otherwise valid | Physical Core updates |
| FABRIC graph/compiler mismatch | no | execution forbidden; rebuild | fresh solve |
| canonical mass/material change | yes | invalidate + reconstruct/rebuild | fresh solve |
| canonical bond/topology change | yes | B0.2-E exact-once split/re-bake | affected state re-derived |

## Dependency decisions

### BRIDGE-1

BRIDGE-1 remains structural lifecycle integration.

```text
reviewed Physical Core frontier = FABRIC0.18
minimum structural graph dependency = FABRIC0.16
```

There is no reason to make BRIDGE-1 wait for or persist 0.18 transient contact semantics.

### B0.3

Final B0.3 acceptance is raised to:

```text
FABRIC0.18
RESEARCH CANDIDATE CLOSED
```

because the intended contact/wrench bake must preserve persistent generalized wrench and
mode/support event surfaces, not only 0.16 manifold geometry.

## Required next BRIDGE-1 falsifiers

- derived compiler/version change rejects an old artifact without canonical revision;
- persistent mode change alone does not advance source frontier;
- canonical mutation invalidates exactly once;
- old reduced state reconstructs exact kinematics before rebuild;
- old accepted contact impulse/history is not accepted after rebuild without fresh solve;
- topology mutation is owned only by canonical B0.2-E path;
- deterministic reverse-input replay;
- deterministic FULL fallback with fresh contact state.

## Decision

```text
PHYSICAL CORE ↔ FABRIC-BAKE SYNC
PASS

BRIDGE-1
DESIGN SYNCHRONIZED
IMPLEMENTATION UNBLOCKED
NOT YET EXECUTABLE
NOT CLOSED

B0.3
FINAL ACCEPTANCE PREDECESSOR = FABRIC0.18

FABRIC0.19
NOT CREATED BY THIS REVIEW
```

Next executable integration work is BRIDGE-1 itself.
