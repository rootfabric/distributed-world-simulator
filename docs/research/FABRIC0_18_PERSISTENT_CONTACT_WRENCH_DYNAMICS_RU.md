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


### 8.10 Project Control

Repository-level gate on the 0.18-B evidence boundary:

```text
Project Control #1888
run id 33369362645
SUCCESS
```

All steps passed, including architecture/ownership compatibility, H0.2, V0 product checkpoint, generation-80 authorization safety, canonical-main PC0 and directional watch.

FABRIC0.18 remains IN PROGRESS. This pass qualifies 0.18-B as an implemented candidate; it does not close the parent checkpoint.


## 9. 0.18-C — Multicontact Persistent Wrench Graph

Exact-tested executable:

```text
HEAD
5b37312bd986c5dc4951ebe13ac670df0af11073

TREE
76eff3e6ab0cd206420a68ed2fc1fa3b40f663e4
```

Status:

```text
FABRIC0.18-C
MULTICONTACT PERSISTENT WRENCH GRAPH

IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
153/153 PASS
REMOTE BYTE IDENTITY 4/4 PASS
FABRIC0.18 NOT CLOSED
```

### 9.1 Graph solve

C solves all persistent patches of one dynamic rigid body against multiple fixed anchors in one projected maximum-dissipation graph.

Per contact unknowns:

```text
[Pn, Pt1, Pt2, Mroll1, Mroll2, Mtorsion]
```

Projection:

```text
Pn >= 0
||Pt||    <= mu_t   * Pn
||Mroll|| <= mu_r   * Pn * R_eff
|Mtors|   <= mu_tau * Pn * R_eff
```

The full effective matrix is assembled from unit generalized impulses, so shared-body coupling between contacts is explicit. Contacts are canonicalized by `contact_id`; caller order is not physical.

### 9.2 Support redistribution and support loss

Two-support plank at x=-1/+1 with total downward free impulse 1:

```text
load x     L support      R support
0.00       ~0.500         ~0.500
0.25       ~0.375         ~0.625
0.50       ~0.250         ~0.750
0.75       ~0.125         ~0.875
1.00       0              ~1.000
```

The result follows:

```text
L = (1-x)/2
R = (1+x)/2
```

within approximately `2e-11`.

At `load_x=1.1` the weak left support does not become negative:

```text
L Pn = 0
L persistent state = open
L normal separation velocity ≈ +0.0125
post angular velocity z ≈ -0.00625
normal complementarity error ≈ 1.7e-12
```

Thus the graph opens the support and permits tipping instead of creating a tensile contact reaction.

### 9.3 Persistent support-loss continuity

A previous two-support state is advanced from `load_x=0.9` to `1.1`.

Left support:

```text
active=false
contact transition hypothesis=SEPARATION_CANDIDATE
warm start=0
current wrench limits=0
```

Right support:

```text
identity_continued=true
update_count=1
contact_age=0.01
first_seen_time preserved
```

C therefore uses the A persistent-state lifecycle directly instead of inventing a graph-specific history model.

### 9.4 Mixed modes in one graph

A floor+wall corner stand demonstrates simultaneous different modes on one shared body:

```text
FLOOR tangent = slide
WALL  tangent = stick
```

Both supports remain active.

Audit:

```text
max cross-contact coupling >= 1.0
normal complementarity error < 6e-12
energy ledger error < 1e-14
kinetic delta < 0
```

Reversing contact input order produces an exact-identical signature.

A separate generalized-wrench drive activates, on both plank contacts:

```text
tangent = slide
rolling = roll
torsion = spin
```

Each active channel lies on its corresponding current support-scaled wrench bound.

### 9.5 Sequential pair-callback falsifier

Unified graph:

```text
reverse contact order
state error = 0
signature identical
```

Naive sequential one-contact callbacks:

```text
L→R vs R→L
max state delta ≈ 0.03125
```

Representative outputs:

```text
forward:
v_y ≈ -0.025
w_z ≈ +0.025

reverse:
v_y ≈ -0.00625
w_z ≈ -0.00625
```

This is the decisive C falsifier against pair-by-pair mutation.

### 9.6 Solver refinement

For `load_x=0.6`, relative to a `1e-14` reference:

```text
solver tolerance      max support error
1e-6                  8.71521294e-6
1e-8                  8.450098e-8
1e-10                 8.1938e-10
1e-12                 8.74e-12
```

The sequence is strictly decreasing.

### 9.7 Physical static-contact no-creep

C upgrades the earlier A bookkeeping probe to an actual physical graph test.

For 10,000 steps, `dt=0.001`, the stand repeatedly applies a downward gravity-like free impulse, solves both supports as one graph, advances the persistent A states, and integrates the resulting body state.

After 10 simulated seconds:

```text
max linear speed ≈ 1.7390949791362686e-13
max angular speed = 0
position drift < 2e-12
angle drift < 2e-12

L support = 0.5
R support = 0.5

both contacts:
tangent/rolling/torsion = stick/stick/stick
identity_epoch = 0
update_count = 9999
contact_age = 9.999
```

This is a physical no-creep claim for the bounded two-support research stand.

### 9.8 Reaction and energy ledgers

For the offset-load stand:

```text
reaction force impulse y ≈ 1.0
reaction moment impulse z ≈ load_x
```

The graph reports the anchored external reaction explicitly.

Acceptance probes require passive contact not to increase kinetic energy, matrix symmetry near machine precision, and energy-ledger error below `1e-14`.

### 9.9 Exact gate

Exact Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

SHA-256:

`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

```text
0.18-C 153/153 PASS
0.18-B 108/108 PASS
0.18-A  60/60 PASS

C playground PASS
import CLEAN
editor parse/compile CLEAN

C 4/4 exact
B 4/4 preserved
A 3/3 preserved
0.17-D 6/6 preserved
```

Exact C files:

```text
fabric0_persistent_wrench_graph_v1.gd
blob   b8de00010fd227104898a6b17b7aac9aad5eec17
sha256 def2ea1a2177fd7911cf3525fd084739dcd02533da3809842639599023a1ab98

fabric0_persistent_wrench_graph_experiments_v1.gd
blob   d051401b24c72954e10be125110e5314012a7a91
sha256 5098d07aebd2ec6d621a85f2eb0170c30b545bae2a9a635cdfbb2a771166558b

fabric0_persistent_wrench_graph_acceptance.gd
blob   3e65306655f6dc797062b4bda06d3ba56b66ae2a
sha256 5b90533df23e9388084b71c2a4d6d8dd6e09ba6890f23492253312b17d685b17

fabric0_persistent_wrench_graph_playground.gd
blob   7ec0277958810969506da9651f7021d3fd5b5e85
sha256 9f0c77062e8beda3bbf086935a552c847b635517e61ef893ce3283194abd0fda
```

### 9.10 C non-claims

C proves one dynamic rigid body coupled against multiple fixed-anchor persistent patches.

It does not yet prove:

- unified impact → persistent → localized mode-transition → separation trajectory;
- B event localization integrated into a live C trajectory;
- arbitrary multi-dynamic-body persistent wrench graphs;
- pressure-distribution wrench cones;
- compliant/Hertz contact;
- production sparse backend;
- FABRIC0.18 closure;
- production acceptance.

Next declared slice:

`FABRIC0.18-D — UNIFIED PERSISTENT CONTACT TRAJECTORY`.


### 9.11 Project Control

Repository-level gate on the 0.18-C evidence boundary:

```text
Project Control #1893
run id 33371423075
SUCCESS
```

All control steps passed, including architecture/ownership compatibility, H0.2, V0 product checkpoint, generation-80 authorization safety, canonical-main PC0 and directional watch.

This qualifies 0.18-C as an implemented candidate. FABRIC0.18 remains IN PROGRESS; 0.18-D is still required for the parent closure decision.


## 10. 0.18-D — Unified Persistent Contact Trajectory

Exact-tested executable:

```text
HEAD
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc

TREE
c051cabd50343603efc509887f32fadf479f0f54
```

Status:

```text
FABRIC0.18-D
UNIFIED PERSISTENT CONTACT TRAJECTORY

IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
113/113 PASS
REMOTE BYTE IDENTITY 4/4 PASS
PROJECT CONTROL PASS
FABRIC0.18 CLOSURE-READY
NOT PRODUCTION ACCEPTED
```

### 10.1 Unified timeline

D composes A+B+C into one bounded fixed-anchor persistent-contact trajectory.

```text
FREE FLIGHT
    ↓
IMPACT / PERSISTENT SUPPORT ACQUISITION
    ↓
STICK
    ↓
STICK → SLIDE
    ↓
STICK → ROLL
    ↓
STICK → SPIN
    ↓
LEFT SUPPORT LOSS / SEPARATION
    ↓
RIGHT SUPPORT REMAINS ACTIVE
SLIDE + ROLL + SPIN
```

Canonical timeline at root tolerance `1e-9`:

```text
impact:ACQUIRE_PERSISTENT_SUPPORT  0.10000000000000
tangent:STICK_TO_SLIDE             0.48125000086923
rolling:STICK_TO_ROLL              0.49970956301937
torsion:STICK_TO_SPIN              0.69090909902006
support:SUPPORT_TO_SEPARATION      1.14444444458932
```

The first impact is localized from the free-flight height guard. All persistent mode/support events are localized by B on signed KKT/feasibility guards derived from live C graph solves.

### 10.2 Impact → persistent support acquisition

Reference body:

```text
mass = 10
initial height = 0.1
initial vy = -1
```

At impact:

```text
L normal impulse ≈ 5
R normal impulse ≈ 5

post |v| < 2e-11
post |w| < 2e-11

kinetic:
5 → ~0

energy ledger error < 1e-14
```

Both A persistent states start as:

`stick / stick / stick`.

### 10.3 Live C/B event surface

D does not reuse the synthetic B ramp stand.

At every B probe time it executes the C multicontact graph and derives a signed left-contact guard from the solved KKT state:

```text
tangent:
  current tangent capacity
  - accepted |Pt|
  + mode velocity tolerance
  - post-solve tangent speed

rolling:
  current rolling capacity
  - accepted |Mroll|
  + tolerance
  - post-solve rolling speed

torsion:
  current torsion capacity
  - accepted |Mtors|
  + tolerance
  - post-solve spin speed

support:
  Pn - max(0, opening normal velocity)
```

B then performs its normal root bracketing/refinement and A validates the semantic state around the localized boundary.

Acceptance independently checks that each live guard is positive at `event_time-1e-6` and negative at `event_time+1e-6`.

### 10.4 Canonical fresh-physics / history rule

Near a mode boundary, a tolerance-level warm start can otherwise delay the visible classification by a small amount.

D therefore makes the A invariant explicit at trajectory level:

```text
canonical zero-init C solve
        ↓
fresh accepted physics / event surface
        ↓
ONLY AFTER acceptance
apply previous A persistent state
        ↓
identity/age/history update
```

Persistent history is never allowed to own the physical event surface.

This does not rewrite C. It is a D orchestration rule enforcing A's original contract:

`history = solver assistance / continuity, not physical truth`.

### 10.5 Event-resolved persistent states

After slide root:

```text
L = slide / stick / stick
R active
```

After rolling root:

```text
L = slide / roll / stick
R active
```

After torsion root:

```text
L = slide / roll / spin
R active
```

After support-loss root:

```text
L inactive
L = open / open / open
R active
```

At final `t=1.2`:

```text
L inactive / open
R active = slide / roll / spin
R normal support > 1.05
open-contact normal velocity > 0.01
```

Contact identity remains in epoch 0 and first-seen time remains the impact boundary.

### 10.6 Refinement

Reference trajectory:

`root_tolerance = 1e-11`.

Runs:

`[1e-8, 1e-9, 1e-10]`.

Maximum whole-timeline event-time error:

```text
1e-8  → 4.33793e-9
1e-9  → 5.7092e-10
1e-10 → 6.936e-11
```

Maximum event-resolved/final-state error:

```text
1e-8  → 1.66561e-9
1e-9  → 1.9932e-10
1e-10 → 7.49e-11
```

Both sequences are strictly decreasing.

Every refinement run preserves the exact five-event causal identity.

### 10.7 Determinism

Acceptance verifies:

```text
reverse contact presentation
  signature identical
  state error = 0

reverse event-spec presentation
  signature identical
  state error = 0
```

Timeline times are exact-identical under both presentation reversals.

### 10.8 Energy / complementarity ledgers

Across impact, event-resolution stages and final state:

```text
max energy ledger error < 1e-14
max normal complementarity error ≈ 1.79330578165e-11
max matrix symmetry error = 0
```

Reported:

`contact_dissipation ≈ -5.622853864835`.

This is explicitly the **sum of bounded event-stage contact kinetic deltas** used by the research stand. It is not claimed to be the continuous integral of all external work over the full trajectory.

Every accepted contact graph stage is passive (`kinetic_delta <= 0`).

### 10.9 Fail-closed resolution

D refuses to run with:

- zero/non-finite/negative root tolerance;
- root tolerance coarser than the declared trajectory resolution boundary.

Representative coarse request `1e-3` returns:

`TRAJECTORY_ROOT_TOLERANCE_TOO_COARSE`.

### 10.10 Exact gate

Exact Godot:

`4.7.1.stable.double.custom_build.a13da4feb`

SHA-256:

`bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`

```text
0.18-D 113/113 PASS
0.18-C 153/153 PASS
0.18-B 108/108 PASS
0.18-A  60/60 PASS

D playground PASS
import CLEAN
editor parse/compile CLEAN

D 4/4 exact
C 4/4 preserved
B 4/4 preserved
A 3/3 preserved
0.17-D 6/6 preserved
```

Exact D files:

```text
fabric0_persistent_contact_trajectory_v1.gd
blob   eb8ef239bd887bd31a74e01ede14e76a008712f4
sha256 ca2274552bb0295bca4c3491488130373829460b2c7c1a5932cc942967477c09

fabric0_persistent_contact_trajectory_experiments_v1.gd
blob   112dd6b172cc11d0a328e381c04d2af1456d748f
sha256 bb1a454428edb24283a41dd9fe20ad276a3bb1b16358ca81f96908b135a52e82

fabric0_persistent_contact_trajectory_acceptance.gd
blob   76aac08d43e592b925c1fa21eea9c04dc1e5d0bb
sha256 a44db92a12271ee6a80754fea41aabe1fbeac4e90339fa2593837145c6229893

fabric0_persistent_contact_trajectory_playground.gd
blob   bff0aa79774996a433534771efaa0794d7e4a7c5
sha256 591d5730702140b177eaee29af440e7c96bb5b47ca91e35440b4b50fabeeca42
```

### 10.11 Project Control

Repository-level control on the exact D executable:

```text
Project Control #1899
run id 33373310277
SUCCESS
```

### 10.12 D scope boundary / parent decision

D proves the planned bounded 0.18 composition for:

`one dynamic rigid body + multiple fixed anchors`.

It does not claim:

- arbitrary multi-dynamic-body persistent-contact graphs;
- pressure-resolved wrench cones;
- compliant/Hertz contact;
- a production external-force/work integrator;
- a full continuous external-work integral;
- production sparse backend;
- production acceptance.

All planned A/B/C/D implementation slices are now present and green.

Therefore:

```text
FABRIC0.18
CLOSURE-READY

closure decision:
PENDING EXPLICIT CLOSURE BOUNDARY
```

Do not start an implicit 0.18-E. Before formalizing a post-0.18 successor, perform the planned Physical Core ↔ FABRIC-BAKE / BRIDGE-1 synchronization review.


## 11. FABRIC0.18 closure decision

The bounded A+B+C+D Persistent Contact Wrench Dynamics checkpoint is now closed as a research candidate.

```text
FABRIC0.18
PERSISTENT CONTACT WRENCH DYNAMICS

RESEARCH CANDIDATE CLOSED
EXACT DOUBLE PASS
REMOTE BYTE IDENTITY PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

Exact physics executable remains immutable:

```text
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc
TREE c051cabd50343603efc509887f32fadf479f0f54
```

Closure control carrier:

```text
88ba8b61ec81928aedeae5777ee1380a6458f0f6
Project Control #1902 SUCCESS
run id 33373554642
```

The carrier changes only FABRIC research documentation/validation relative to the exact D executable. All four D executable blobs remain byte-identical, and C/B/A/0.17-D predecessor bytes remain preserved.

### 11.1 Closed claims

FABRIC0.18 research evidence now contains:

- persistent contact identity/age/epoch continuity without treating history as accepted physical truth;
- canonical 0.17 manifold identity bridge with no second contact-identity system;
- localized stick→slide, stick→roll, stick→spin and support→separation event roots;
- explicit temporal-resolution semantics for near-coincident persistent mode events;
- one shared dynamic body coupled against multiple fixed-anchor persistent patches;
- graph-wide normal support redistribution and support opening without tensile reaction;
- mixed persistent modes and active slide/roll/spin generalized wrench channels;
- sequential pair-callback order-dependence falsifier and unified graph order independence;
- bounded 10,000-step physical static-contact no-creep evidence;
- one unified free-flight→impact→persistent support→mode transitions→separation trajectory;
- live B event localization over canonical fresh C physics;
- strict whole-timeline event-time and event-resolved state refinement;
- exact caller/event-spec presentation determinism;
- passive bounded event-stage energy and normal-complementarity audits.

### 11.2 Persistent non-claims

Closure is research-only and does not claim:

- production acceptance;
- arbitrary multi-dynamic-body persistent-contact graphs/trajectories;
- exact pressure-distribution wrench cones;
- compliant/Hertz contact;
- a production external-force/work integrator;
- a continuous full-trajectory external-work integral;
- production sparse backend/broadphase/thread-pool;
- authority, persistence, networking or Construction ownership transfer.

`production_accepted = false`.

No `FABRIC0.18-E` is required for this bounded checkpoint.

### 11.3 Successor boundary

Do not implicitly start `FABRIC0.19`.

Before formalizing the next Physical Core successor, perform the already-declared:

```text
Physical Core ↔ FABRIC-BAKE / BRIDGE-1 synchronization review
```

That review is an integration/roadmap synchronization boundary, not a prerequisite retroactively attached to the closed FABRIC0.18 research evidence.
