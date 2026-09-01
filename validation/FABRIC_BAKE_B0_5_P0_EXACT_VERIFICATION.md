# FABRIC-BAKE B0.5-P0 — Hybrid Mode / Transition / Lazy Cache — Exact Verification

## Qualification

```text
B0.5-P0
HYBRID MODE SIGNATURE / TRANSITION / LAZY CACHE CONTRACTS

CLOSED
EXACT DOUBLE PASS
PROJECT CONTROL PASS

B0.5 EXECUTABLE HYBRID REDUCTION:
NOT AUTHORIZED

NOT PRODUCTION ACCEPTED
```

## Boundary

```text
predecessor:
FABRIC.SYNC2 closure
be419fb695221917df0f6026ed335e1355f72840

branch:
research/fabric-bake0-5-hybrid-bake-preflight-r1

exact implementation/test HEAD:
8c2a7db2a10e721546540e97ef8d2876f3dd41b4

TREE:
82d2819ac3c06ee34494d98eecf236a2664c052e
```

Fresh verifier source was reconstructed from the exact GitHub Actions bundle.

```text
source carrier:
33516591916
SUCCESS

artifact:
9803836553

bundle SHA-256:
eaa70c0a808fd6d69a87ce9de8cf8b3f64424a3ab43a8d2891eae0426016f975
```

## Godot identity

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

Fresh detached identity:

```text
HEAD:
8c2a7db2a10e721546540e97ef8d2876f3dd41b4

TREE:
82d2819ac3c06ee34494d98eecf236a2664c052e

branch:
<detached-head>

tracked status:
clean
```

## Implemented contracts

### HybridModeSignature

File:

`scripts/research/fabric_bake0/hybrid_mode_signature_v1.gd`

Binds:

- canonical source frontier hash;
- physical topology hash;
- sorted active physical relation IDs;
- sorted complementarity/active-set IDs;
- physical boundary contract hash;
- sorted dependency/version hashes;
- compiler version;
- deterministic mode hash/checksum.

Properties verified:

- presentation/input order does not change identity;
- source frontier mutation changes identity;
- topology mutation changes identity;
- dependency version mutation changes identity;
- device-specific MOTOR/GEARBOX/CLUTCH/VALVE kernel relation identity is rejected.

### HybridBakeModeDescriptor

File:

`scripts/research/fabric_bake0/hybrid_bake_mode_descriptor_v1.gd`

Binds:

- exact HybridModeSignature;
- existing ValidatedDomain;
- B0.4 Dynamic ROM interface binding;
- build generation;
- deterministic lazy cache key;
- execution qualification.

Two explicit B0.4 states exist:

```text
UNRESOLVED_B0_4_INTERFACE
→ PREFLIGHT_ONLY

PHYSICAL_BAKE_ARTIFACT
→ B0_4_INTERFACE_BOUND
```

An unresolved interface is forbidden from carrying artifact/state-mapping/reconstruction hashes or claiming execution.

### HybridTransitionDescriptor

File:

`scripts/research/fabric_bake0/hybrid_transition_descriptor_v1.gd`

Binds:

- from/to exact mode hashes;
- localized physical guard;
- physical dimension;
- crossing direction;
- mapped source region;
- B0.4-compatible reset/state-handoff interface;
- optional FABRIC topology transaction;
- exactly-once event ownership;
- external canonical-revision ownership;
- deterministic transition identity.

Required ownership is frozen as:

```text
owner:
FABRIC_PHYSICAL_EVENT

semantics:
EXACTLY_ONCE

canonical revision:
EXTERNAL_AUTHORITY_ONLY

commit:
OWNER_COMMITS_ONCE

replay:
REJECT_DUPLICATE_EVENT_ID
```

This prevents FULL/BAKED/cache layers from independently committing the same physical event.

### LazyModeCacheEntry

File:

`scripts/research/fabric_bake0/lazy_mode_cache_entry_v1.gd`

Cache state is explicitly:

```text
derived_only = true
execution_qualification = PREFLIGHT_ONLY
```

The key binds:

- mode hash;
- source frontier;
- topology;
- dependency fingerprint;
- exact B0.4 interface fingerprint;
- build generation.

Supported invalidation reasons:

```text
SOURCE_FRONTIER_CHANGED
TOPOLOGY_CHANGED
DEPENDENCY_CHANGED
B0_4_INTERFACE_CHANGED
B0_4_INTERFACE_UNRESOLVED
```

No stale entry is permitted to become canonical truth.

### HybridBakePreflight

File:

`scripts/research/fabric_bake0/hybrid_bake_preflight_v1.gd`

P0 preflight implements only validation/decision logic.

It does not numerically execute hybrid reduced physics.

Exact cache hit returns:

```text
CACHE_ENTRY_MATCH
execution_authorized = false
```

An unresolved B0.4 interface returns:

```text
FALLBACK
reason = B0_4_INTERFACE_UNRESOLVED
execution_authorized = false
```

An unknown physical mode returns exactly:

```text
FULL
or
NO_SAFE_BAKE
```

with:

```text
nearest_mode_reuse = false
```

No nearest cached active set is guessed.

Duplicate transition ID/hash ownership is rejected fail-closed.

## Existing FABRIC semantic fit

The acceptance suite constructs an existing generic `Fabric0CoupledHybridDAEV1`
system with:

```text
stable mode A
FLOW
    ↓
localized crossing guard
    ↓
JUMP
    ↓
stable mode B
```

The transition succeeds using the existing FABRIC hybrid DAE machinery.

B0.5-P0 introduces no second hybrid runtime/state machine.

## Exact acceptance

Runner:

`RUN_FABRIC_BAKE_B0_5_P0_TESTS.sh`

Result:

```text
FABRIC-BAKE B0.5-P0 Acceptance:
63 / 63 PASS

process exit:
0

fatal B0.5-P0 script/load markers:
0
```

Import:

```text
PASS / exit 0

B0.5-P0 fatal import markers:
0
```

Known historical ECO scene parse diagnostics remain unrelated and non-fatal.

## Project Control

Exact implementation/test subject:

```text
run:
33516591870

conclusion:
SUCCESS
```

## Closure criteria

SYNC-2 P0 gate:

- contract schemas fail closed — PASS;
- identical mode inputs produce identical signatures/cache keys — PASS;
- input/presentation order invariance — PASS;
- source frontier change invalidates cache — PASS;
- topology change invalidates cache — PASS;
- dependency change invalidates cache — PASS;
- B0.4 interface change invalidates cache — PASS;
- unknown mode produces FULL/NO_SAFE_BAKE — PASS;
- nearest-mode cache reuse forbidden — PASS;
- exactly-once event ownership explicit — PASS;
- reset/handoff references B0.4 state mapping/reconstruction interface — PASS;
- device-specific mode/solver identity rejected — PASS;
- unresolved B0.4 interface makes no executable claim — PASS;
- Project Control — PASS;
- exact double Godot contract acceptance — PASS.

## Non-claims

B0.5-P0 does not claim:

- executable hybrid model reduction;
- mode-local Dynamic ROM implementation;
- numerical lazy compilation of ROMs;
- hybrid reduced-state execution;
- BRIDGE-2 mixed execution;
- FABRIC0.19 requirement;
- production acceptance.

## Verdict

```text
VERIFIED

B0.5-P0 CLOSED

B0.5 EXECUTABLE:
STILL BLOCKED

next dependency:
stable executable B0.4 mode-local Dynamic ROM PhysicalBakeArtifact interface
```
