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


## Project Control evidence

Initial Project Control on the pure review commit:

```text
review HEAD:
8a3bafd0044460f766346ff394db53e44a9dd56d

#1908 FAILURE
#1909 FAILURE

failed step:
architecture and ownership passport compatibility regression
```

This was not a synchronization-contract failure. The review branch is descended from the
older FABRIC-BAKE lineage and therefore still contained the pre-fix versions of two harness
regression tests.

Exact stale → current-main blobs:

```text
tests/harness/test_project_control_architecture_compatibility.py
old  4f2da340b52f9145fa0daddefbf606bf4e6fa290
main 9a0233aa9e913d204e4ba23e525593638e3dc37b

tests/harness/test_project_control_proposed_r3_ownership_projection.py
old  923ca8844d0cb325b0d3e41ba1473ac80308cfee
main e0fb773e8c7b93698ccc7d41a86f567795b0dc08
```

The main versions delegate main-owned registry/policy reads through
`pc._core.load_main_owned(...)`, i.e. to canonical `origin/main` state.

A control carrier copied exactly those two current-main test blobs and changed no
FABRIC/FABRIC-BAKE runtime, G/ECO passport, registry declaration or critical dependency rule:

```text
control carrier:
8f0e01c8dd611e615ecfd6b49d4748d749b2f730

Project Control #1910
run id 33383353852
SUCCESS
```

All Project Control steps passed, including architecture/ownership compatibility, H0.2,
V0, generation-80 authorization safety, canonical-main PC0 and directional watch.

Therefore the synchronization review qualification is:

```text
PHYSICAL CORE ↔ FABRIC-BAKE / BRIDGE-1 SYNC REVIEW
PASS

PROJECT CONTROL PASS
CRITICAL CONTRACT CONFLICTS 0

BRIDGE-1
DESIGN SYNCHRONIZED
IMPLEMENTATION UNBLOCKED
NOT YET EXECUTABLE
NOT CLOSED
```


## BRIDGE-1 implementation result

The implementation obligations declared by this synchronization review are now covered by
exact executable candidate:

`e128cf9d49f84691b8a5428c97ab7acd53b92d90`.

Evidence:

```text
146/146 PASS
7/7 remote exact bytes
Project Control #1917 SUCCESS

derived compiler mismatch rejects old execution
persistent mode changes do not advance source frontier
canonical mutation invalidates old bake
500-part kinematics-only reconstruction
fresh physical/contact state policy after rebuild
topology mutation routed to B0.2-E
reverse-input exact deterministic identities
FULL fallback deterministic
```

This satisfies the sync-review implementation delta without changing its ownership
decisions. BRIDGE-1 is closure-ready, not production accepted.
