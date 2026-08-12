# H0.2 / NX.C1 Dispatch Preparation — Independent Control Review

**Verdict:** `PREPARATION_ACCEPTED`  
**Disposition:** `FROZEN_UNTIL_POST_R3_REFRESH`  
**Reviewed package commit:** `5f9b65e3219d53a60c52ddb136ffbf88b8d4afdc`  
**Package:** `docs/control/H0_2_NX_C1_DISPATCH_PACKAGE_RU.md`  
**Lane:** docs/control preparation only  
**Runtime authorization:** `false`

## 1. Verification facts

Independent GitHub comparison against the declared preparation base
`4a42c2fb6befb386f5c3eb48d9ba070745e25bbb` confirms:

```text
status          ahead
commits         1
behind          0
changed files   1
runtime files   0
added file      docs/control/H0_2_NX_C1_DISPATCH_PACKAGE_RU.md
```

The package therefore satisfies the bounded PREPARE_NOW requirement and did not mutate runtime, canonical registry, architecture ownership, harness policy, or main.

## 2. Architecture review

The package correctly constrains NX.C1 to the minimum H0.2 convergence slice:

```text
owner-predicted local player
server-authoritative fixed-tick canonical simulation
prediction / reconciliation
remote interpolation
pickup/drop optimistic presentation
rollback on rejection
authority epoch correctness
reconnect identity preservation
```

It correctly keeps outside the H0.2 scope:

```text
NX7 generic physics authority profiles
NX8 interest / replication budget
NX9 persistence / production hardening
server zones / cross-server handoff
new IAM / AUTHORITY / Item / persistence foundations
NET-min implementation
V0 runtime
```

The selected truth boundary is accepted:

```text
prediction != canonical ownership
client presentation != canonical player truth
NX replication policy != AUTHORITY foundation
NX optimistic item projection != Item Graph mutation authority
```

Legacy M7/FIX lineage is evidence-only and must not become the base or authorization for the fresh H0.2 runtime frontier.

## 3. Acceptance package quality

The prepared package is sufficient for later materialization of a HIGH-risk H0.2 Work Order because it contains:

```text
Design Brief                         READY
Work Order materialization template READY
risk classification                 HIGH
scope boundary                      READY
allowed / forbidden surfaces        READY
ownership / dependency map          READY
entry gates                         READY
acceptance matrix                   READY
Evidence Map skeleton               READY
Reviewer / Verifier focus           READY
V0-facing capability boundary       READY
stop conditions                     READY
```

The exact allowed-path list remains advisory preparation only. At actual dispatch it must be reread against the post-R3 tree and may shrink; any expansion requires Director amendment and fresh pre-build review.

## 4. Current-state correction after package creation

The package was created while H0.1 R7 / PR #88 was observed as `VERIFYING`.

After package creation, R7 correctly failed closed and PR #88 became:

```text
CANCELLED / DO NOT MERGE
```

Reason: the harness freshness fence in `scripts/harness/state_builder.py` derived an implementation head that did not include the bounded C22 runtime mutation surfaces. Accepting Reviewer/Verifier PASS under that fence would have violated exact-head truth.

This does **not** invalidate the H0.2 preparation design because the package already requires a fresh reread of main/registry/R3/dependencies before any real H0.2 Project Epoch or Work Order. However, all R7-specific observed-state lines are historical context only.

The primary runtime path remains H0.1 and must proceed through a successor R8-style repair/verification frontier before C22 can reach the merge gate.

## 5. Machine-control gap — BLOCKING BEFORE H0.2 DISPATCH

Independent reread of canonical
`config/control/harness/checkpoint-catalog.v1.json` confirms:

```text
H0_1_CLOSED_LOOP_C22_PILOT  exists as HARNESS checkpoint
NX_SOURCE_ACCEPTED          exists as PROJECT checkpoint
H0_2_PASS                   has no separate machine checkpoint object
```

This is a real control gap because the primary execution roadmap uses:

```text
H0.2 / NX.C1
  -> H0_2_PASS
  +  NX SOURCE_ACCEPTED
```

Before real H0.2 dispatch, main-owned control must resolve this explicitly.

### Recommended resolution

Prefer **Option A**:

```text
add a HARNESS H0.2 checkpoint
that composes the closed-loop H-process predicates
with project checkpoint NX_SOURCE_ACCEPTED
and produces success_state = H0_2_PASS
```

Reason: H0.2 exists specifically to prove that the H closed-loop process is repeatable on a second HIGH-risk subsystem. Representing that proof only as an informal Director verdict would weaken the machine-verifiable harness model already established by H0.1.

Do not modify the canonical checkpoint catalog while doing so would create unsafe main movement for the active H0.1 successor epoch. Resolve it at a safe control boundary before H0.2 Project Epoch creation.

## 6. Required refresh before use

This preparation package is frozen evidence, not an executable authorization.

Before materializing H0.2:

```text
H0_1_PASS
-> HUMAN C22 runtime merge
-> post-C22 standard + directional PC0
-> C22 MAIN_INTEGRATED
-> GLOBAL-P0 R3 current-main refresh
-> HUMAN GLOBAL_ARCHITECTURE_PROMOTION
-> post-R3 standard + directional PC0
-> resolve machine H0_2_PASS checkpoint contract
-> reread exact main SHA / registry generation / R3 ownership
-> recompute all producer -> NX directional hits
-> reread allowed / forbidden paths against actual tree
-> create fresh H0.2 Project Epoch
-> materialize real NX.C1 Work Order
-> HIGH exact-head pre-build review
-> Director dispatch
```

Any stale SHA, old R7/R6 state, legacy FIX branch, or unresolved critical dependency hit is fail-closed.

## 7. Final verdict

```text
H0_2_NX_C1_DISPATCH_PACKAGE_READY     ACCEPTED AS PREPARATION
PREPARATION_ACCEPTED                  YES
RUNTIME_AUTHORIZED                    NO
RUNTIME_BRANCH_ALLOWED_NOW            NO
NX_C1_DISPATCH_ALLOWED_NOW            NO
MAIN_CHANGED_BY_THIS_REVIEW           NO
ACTIVE_H0_1_CHANGED_BY_THIS_REVIEW    NO

BLOCKED_ON:
  H0.1 successor -> H0_1_PASS
  C22 MAIN_INTEGRATED
  R3 canonical + post-R3 PC0
  machine H0_2_PASS contract resolution
  fresh post-R3 dependency/path reread
```

STOP. The preparation lane should remain frozen until those gates are satisfied.