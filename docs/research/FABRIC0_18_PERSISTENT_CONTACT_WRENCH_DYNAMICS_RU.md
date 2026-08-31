# FABRIC0.18 — Persistent Contact Wrench Dynamics

## 1. Status

```text
FABRIC0.18
PERSISTENT CONTACT WRENCH DYNAMICS

RESEARCH CHECKPOINT
IN PROGRESS
NOT PRODUCTION ACCEPTED
```

Branch:

`research/fabric0-18-persistent-contact-wrench-r1`

Frozen predecessor:

```text
FABRIC0.17 closure
751c55e76f57b7a9ceef8f5bbda3dcf6d4fad1a0

FABRIC0.17 exact physics executable
643b4bdc5d33756819869c3faacc1dccf1251a1f
```

FABRIC0.18 is independent of FABRIC-BAKE / BRIDGE-1 for implementation. A synchronization review is required before formalizing a post-0.18 Physical Core successor.

## 2. Goal

0.17 proves same-instant simultaneous impact plus generalized contact wrench. 0.18 must prove that a general convex multipoint contact can persist through time without device-specific physics and can move between bounded wrench modes through explicit event semantics.

Target lifecycle:

```text
FREE
  ↓
IMPACT
  ↓
PERSISTENT CONTACT
  ↓
STICK / SLIDE / ROLL / SPIN / MIXED
  ↓
SEPARATION
  ↓
FREE
```

## 3. Slices

```text
FABRIC0.18-A
PERSISTENT WRENCH CONTACT STATE
        ↓
FABRIC0.18-B
MODE TRANSITION LOCALIZATION
        ↓
FABRIC0.18-C
MULTICONTACT PERSISTENT WRENCH GRAPH
        ↓
FABRIC0.18-D
UNIFIED PERSISTENT CONTACT TRAJECTORY
        ↓
closure decision
```

### 0.18-A — Persistent Wrench Contact State

Must provide deterministic contact identity continuity across timesteps and preserve only solver-assist state, never stale physical truth.

Required state:

- canonical pair identity;
- stable manifold/member identity independent of caller/member ordering;
- first/last seen time and contact age;
- identity epoch/update count;
- current freshly solved normal support;
- current freshly solved 5DOF generalized impulse;
- current generalized post-solve velocity;
- current tangent/rolling/torsion limits;
- mode classification;
- warm-start proposal derived only from the previous accepted solve and projected into current limits;
- transition hypothesis only, with no event-time claim.

Invariant:

```text
previous accepted impulse
        ↓
warm-start proposal only
        ↓
fresh solver required
        ↓
new accepted impulse
```

A must fail closed on malformed identity, time reversal, invalid wrench bounds, out-of-cone impulse and moving-unsaturated mode inconsistency.

A does not localize transition time. That belongs to 0.18-B.

### 0.18-B — Mode Transition Localization

Localize:

- stick → slide;
- roll-stick → roll;
- spin-stick → spin;
- support → separation;
- re-contact where applicable.

Transition time/state must refine.

### 0.18-C — Multicontact Persistent Wrench Graph

Resolve persistent shared-body contacts as one graph. Pair-by-pair mutation order is not acceptable.

Primary falsifier: a rigid body/plank on multiple support contacts with load redistribution, mixed modes and support loss.

### 0.18-D — Unified Persistent Contact Trajectory

One event-driven trajectory must include impact, persistent support, at least one mode transition, separation, refinement, deterministic replay, energy ledger and momentum/external-reaction accounting.

## 4. Closure requirements

0.18 may close as a research candidate only after:

- A/B/C/D exact double acceptance;
- predecessor regression;
- persistent static-contact no-creep evidence;
- no uncontrolled mode chatter;
- strict transition-time/state refinement;
- passive contact cannot create energy;
- internal momentum closure or explicit external-reaction ledger;
- caller/contact ordering determinism;
- unresolved mode/topology ambiguity fails closed;
- Project Control PASS.

## 5. Non-claims

FABRIC0.18 does not imply:

- pressure-distribution contact PDE;
- Hertz/compliant contact;
- tire/Pacejka or wheel-specific physics;
- lubrication, wear or thermal friction;
- production sparse solver;
- production acceptance;
- Construction/authority/persistence/network ownership transfer.

A pressure-resolved wrench model is intentionally left beyond 0.18.


## 6. 0.18-A implemented candidate

Exact-tested executable:

```text
HEAD
c7f20c51794690930d059d10747d1a1c3e4e2c52

TREE
56588245f5b15bfb2ad929ae843e4dc48e326e64
```

Files:

- `scripts/research/fabric0/fabric0_persistent_wrench_contact_state_v1.gd`
- `tests/research/fabric0/fabric0_persistent_wrench_contact_state_acceptance.gd`
- `tests/research/fabric0/fabric0_persistent_wrench_contact_state_playground.gd`

Exact engine:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Gate:

```text
0.18-A acceptance 60/60 PASS
0.18-A playground PASS
editor parse/compile CLEAN
remote byte identity 3/3 PASS
```

### 6.1 State semantics

A persistent contact state contains canonical pair/manifold identity, stable member ordering, first/last seen time, contact age, update count, identity epoch, current normal support, current 5DOF generalized impulse, current generalized velocity, current wrench limits and current mode classification.

The key anti-stale invariant is executable:

```text
previous accepted impulse
        ↓
project into CURRENT limits
        ↓
warm_start_proposal
        ↓
NEVER accepted directly
        ↓
fresh solve required
        ↓
current accepted_generalized_impulse
```

`solver_refresh_required=true` is explicit state.

Changing manifold membership increments the identity epoch, resets age/update continuity and clears warm start. Reordering bodies or manifold member IDs does not change canonical identity/signature.

### 6.2 Mode hypothesis boundary

A classifies post-solve generalized modes:

- tangent: stick / slide / unconstrained;
- rolling: stick / roll / unconstrained;
- torsion: stick / spin / unconstrained.

A moving constrained DOF must lie on its corresponding wrench boundary. Moving-but-unsaturated input fails closed with `MODE_CONSTRAINT_UNRESOLVED`.

Mode changes are emitted only as hypotheses, e.g. `STICK_TO_SLIDE_CANDIDATE`. A does not claim transition time; exact localization belongs to 0.18-B.

### 6.3 Long bookkeeping probe

10,000 continued updates over 10 seconds preserve:

```text
identity_epoch = 0
update_count = 10000
contact_age = 10.0
accepted impulse = 0
warm-start proposal = 0
```

This proves persistence bookkeeping itself has no hidden impulse carryover. It is not yet a physical static-contact/no-creep proof.

### 6.4 Fail-closed cases

Acceptance covers:

- time reversal;
- negative/non-finite normal support;
- malformed generalized dimensions;
- duplicate/empty manifold identity;
- invalid wrench limits;
- impulse outside admissible limit;
- moving constrained DOF without saturation.

### 6.5 Exact files

```text
runtime
git blob a30a16ed51193138332d1cb69d8950521fb531ee
sha256 209702774c1e21a72e82b4249b419d5b5a5197f34d73e49be3ff0e134e945cae

acceptance
git blob d2bfe98bce39fc667ee988c54d872a108e76337d
sha256 c525e41f1a56b680f0b1d41064a60066de8a0dddcf5debf80da6d25e1aa385cf

playground
git blob a27c8148ba4bcac7ad265844069d569206672e88
sha256 8693926c99e5cf8f9feee51aba4cdb2bbf37dbe8682273732e9b091c82fc174e
```

## 7. 0.18-A non-claims / next wall

0.18-A does not solve persistent contact forces through time, does not localize stick/slide/roll/spin transitions, does not prove physical no-creep, does not solve a multicontact persistent graph, and does not close FABRIC0.18.

Next wall:

`FABRIC0.18-B — MODE TRANSITION LOCALIZATION`.


### 6.6 Direct 0.17 representation bridge

0.18-A consumes the existing canonical research representation directly:

```text
Fabric0PersistentMultipointManifoldV1
  pair_id
  points[*].id = feature_key|pN
        ↓
observation_from_fabric_manifold(...)
        ↓
Persistent Wrench Contact State
```

It also normalizes the existing C output:

```text
GENERALIZED_CONTACT_WRENCH
  normal_impulse
  generalized_impulse[5]
  generalized_velocity_after[5]
  limits
        ↓
solved_from_generalized_wrench(...)
```

The bridge fails closed if a canonical manifold point has no persistent ID. This prevents 0.18-A from inventing a second contact identity system.


### 6.7 Project Control

Repository-level control on the 0.18-A evidence boundary:

```text
Project Control #1867
run id 33367039128
SUCCESS
```

All control steps passed, including architecture/ownership compatibility, H0.2 machine checkpoint, V0 product checkpoint, generation-80 authorization safety, canonical-main PC0 and directional watch.

Closed FABRIC0.17 D executable bytes remain preserved 6/6 on the 0.18 branch.

0.18-A remains an implemented research candidate; FABRIC0.18 itself remains IN PROGRESS.


## 8. 0.18-B — Mode Transition Localization

Exact-tested executable:

```text
HEAD
649d7a9d62384a6d3cdfe2efbd92534bc52573e7

TREE
f9f19abf98c5b338261ac2e1e03d98b70a59aaf2
```

Status:

```text
FABRIC0.18-B
MODE TRANSITION LOCALIZATION

IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
108/108 PASS
REMOTE BYTE IDENTITY 4/4 PASS
FABRIC0.18 NOT CLOSED
```

### 8.1 Root quantity

B does not infer transition time merely from a mode label changing between discrete samples.

It localizes a continuous feasibility guard:

```text
tangent:
  admissible tangent wrench capacity
  -
  hypothetical stick demand

rolling:
  admissible rolling moment capacity
  -
  hypothetical roll-stick demand

torsion:
  admissible torsional moment capacity
  -
  hypothetical spin-stick demand

support:
  normal support margin
```

Semantics:

```text
guard > 0   persistent constraint feasible
guard = 0   mode boundary
guard < 0   old mode infeasible
```

This distinction matters because after a stick→motion transition the accepted friction/moment impulse remains saturated at the wrench limit. Therefore the accepted impulse itself is not a signed root quantity.

### 8.2 Event locator

New runtime:

`Fabric0PersistentWrenchModeEventLocatorV1`.

Pipeline:

```text
continuous feasibility guard
        ↓
deterministic horizon scan
        ↓
first positive → nonpositive bracket
        ↓
bisection refinement
        ↓
explicit bracket uncertainty
        ↓
semantic probes around root
        ↓
0.18-A state validation
        ↓
localized mode event
```

Supported events:

```text
tangent  STICK_TO_SLIDE
rolling  STICK_TO_ROLL
torsion  STICK_TO_SPIN
support  SUPPORT_TO_SEPARATION
```

For tangent/rolling/torsion, A verifies:

```text
pre-state  = stick
post-state = slide / roll / spin
```

For support:

```text
pre-state active
post-state separated/open
accepted generalized impulse cleared
```

### 8.3 Reference transition stand

Reference roots:

```text
tangent  0.812345679
rolling  1.012345679
torsion  1.212345679
support  1.412345679
```

Exact-localized values at the acceptance tolerance:

```text
tangent  0.812345679034
rolling  1.012345679046
torsion  1.212345679058
support  1.412345679011
```

### 8.4 Refinement

For each of the four transition families, against exact root `1.123456789`:

```text
root tolerance     absolute event-time error
1e-4               1.79891516e-5
1e-6               6.8808292e-7
1e-8               6.11608e-9
1e-10              6.823e-11
```

Bracket uncertainty also strictly decreases:

```text
5.03303816e-5
7.8641221e-7
6.14385e-9
~9.6e-11
```

For every refinement level:

`event-time error <= reported bracket uncertainty`.

### 8.5 Temporal-resolution event sets

Near-coincident roots:

```text
tangent = 1.0000
rolling = 1.0002
```

At declared resolution `1e-3`:

```text
simultaneous:
rolling:STICK_TO_ROLL
tangent:STICK_TO_SLIDE

deferred:
none
```

At `1e-5`:

```text
current:
tangent:STICK_TO_SLIDE

deferred:
rolling:STICK_TO_ROLL
```

So mode-event simultaneity follows the same explicit temporal-resolution principle established by 0.17-A: near coincidence is not silently converted into exact simultaneity.

### 8.6 Determinism

Acceptance verifies exact identity under:

- same-tolerance replay;
- reversed body/member presentation;
- reversed event-spec order.

Event-set signature, event IDs, root time and canonical manifold identity remain exact.

### 8.7 Fail-closed boundary

B refuses:

- unknown transition channel;
- channel/kind mismatch;
- invalid start/horizon/tolerance/scan budget;
- transition already passed at the start;
- no transition in requested horizon;
- incomplete evaluator result;
- missing/non-finite guard;
- evaluator state rejected by 0.18-A;
- wrong guard direction;
- semantic pre/post mode mismatch;
- empty event-spec set;
- invalid simultaneous resolution.

### 8.8 Exact gate

Exact Godot:

`4.7.1.stable.double.custom_build.a13da4feb`.

```text
0.18-B 108/108 PASS
0.18-A  60/60 PASS
B playground PASS
import CLEAN
editor parse/compile CLEAN
```

Remote exact bytes:

```text
B 4/4 exact
A 3/3 preserved
0.17-D 6/6 preserved
```

Exact B files:

```text
fabric0_persistent_wrench_mode_event_locator_v1.gd
blob   9c34645ff11c3a33222e993fad3607c41fefa448
sha256 543851a6393abaee2f468173000cd84b4fe332a0e5bc52f1677dbf4b0928b02b

fabric0_persistent_wrench_mode_transition_experiments_v1.gd
blob   833506434b254a11115a7f89b548e8c6f74070b3
sha256 16908605215be31e4ffe4edf56025e4ed9dcc8155bb6c8f46f152199da32da69

fabric0_persistent_wrench_mode_transition_acceptance.gd
blob   66435982de3127574dbe524ee55891262f05c690
sha256 180f7d1ac7966de36ce02c2ef03ad1ecf098a14b951420039f29a93435bfb81e

fabric0_persistent_wrench_mode_transition_playground.gd
blob   cfb176fccc86b2500a0df3f175a632d9c5275e46
sha256 7a8c502201cb615a2408fe80a5b03553d261c9f07de5085f533607975ee550c2
```

### 8.9 B non-claims

0.18-B proves generic mode-boundary localization and its coupling to the persistent-state contract. It does not yet prove:

- physical static-contact no-creep under gravity;
- a production external-force integrator;
- multicontact persistent wrench coupling;
- graph-wide support redistribution;
- a unified impact→persistent→transition→separation trajectory;
- FABRIC0.18 closure;
- production acceptance.

Those remain later slices, beginning with 0.18-C.
