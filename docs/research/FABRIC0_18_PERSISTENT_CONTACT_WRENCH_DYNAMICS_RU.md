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
ee8658eefb8abe2e66e199678380c32b71c1f8dd

TREE
15afdfdfaa6316afa4bf723c32bef9c3957ba5d3
```

Files:

- `scripts/research/fabric0/fabric0_persistent_wrench_contact_state_v1.gd`
- `tests/research/fabric0/fabric0_persistent_wrench_contact_state_acceptance.gd`
- `tests/research/fabric0/fabric0_persistent_wrench_contact_state_playground.gd`

Exact engine:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Gate:

```text
0.18-A acceptance 53/53 PASS
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
git blob 2014791d77ed341c09820f19e8bae052ecf4eff1
sha256 b5839e45755e9921b9f844286b253810c2c2d03c44b4eb7e8cbe47e1de9de8d3

acceptance
git blob 5f5ab3958b4148e92134e2d5b70400ce93226d23
sha256 1ceecc9063a7560dd6e2c38849365d8cb1fae4961caa82783373229fde72e308

playground
git blob a27c8148ba4bcac7ad265844069d569206672e88
sha256 8693926c99e5cf8f9feee51aba4cdb2bbf37dbe8682273732e9b091c82fc174e
```

## 7. 0.18-A non-claims / next wall

0.18-A does not solve persistent contact forces through time, does not localize stick/slide/roll/spin transitions, does not prove physical no-creep, does not solve a multicontact persistent graph, and does not close FABRIC0.18.

Next wall:

`FABRIC0.18-B — MODE TRANSITION LOCALIZATION`.
