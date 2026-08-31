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
