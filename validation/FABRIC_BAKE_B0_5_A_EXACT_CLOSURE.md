# FABRIC-BAKE B0.5-A — Executable Hybrid Bake — Exact Closure

## Qualification

```text
B0.5-A EXECUTABLE HYBRID BAKE

CLOSED
EXACT DOUBLE PASS
P0→A CLOSURE CHAIN PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

## Exact implementation/test boundary

```text
branch:
research/fabric-bake0-5-a-executable-hybrid-r2

predecessor:
FABRIC.SYNC3 final closure
28fdc16d12ddf1233a82103cb290c831342a3022

exact implementation/test HEAD:
d819fffa0dc86cc09cda0000f20c310aec23c799

TREE:
c92c1ff22c683ba348ac8596d2e6b3212a381b57

tracked status:
clean

git diff --check:
PASS
```

## Exact source carrier

```text
run:
33708036610

conclusion:
SUCCESS

artifact:
9875925635

Git bundle SHA-256:
b8388880e4c2f2a2e1165bb4a9c8cc5532661c8aefb493de07fd3bf190d1bd22

artifact ZIP digest:
dd0042af7a6132f0c300496beb4e45ae9502c2f4ea3cae08424af048e94af4fc
```

The exact source was reconstructed from the bundle into a fresh detached worktree.

## Godot identity

The project-attached canonical double Godot was used:

```text
version:
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

Project import:

```text
exit:
0

B0.5-A fatal script/load markers:
0
```

Known historical ECO scene parse diagnostics remain unrelated and non-fatal.

## Implemented executable layer

New files:

```text
hybrid_executable_mode_v1.gd
hybrid_executable_cache_entry_v1.gd
hybrid_executable_transition_v1.gd
hybrid_bake_executable_runtime_v1.gd
```

P0 files are unchanged.

### Executable mode

The executable mode is a wrapper around an already resolved common B0.4
PhysicalBakeArtifact.

It binds:

- immutable P0 HybridModeSignature / HybridBakeModeDescriptor;
- exact common PhysicalBakeArtifact checksum;
- exact B0.4 ROM descriptor;
- runtime certification;
- real StateMapping;
- real ReconstructionDescriptor;
- build generation.

P0 remains:

```text
B0_4_INTERFACE_BOUND
```

and the new outer layer is explicitly:

```text
B0_5_A_EXECUTABLE
```

### Executable cache

The executable cache wraps the immutable P0 derived cache entry.

It remains:

```text
derived_only = true
```

The cache never becomes canonical physical truth.

The exact cache key still comes from the P0 identity and therefore binds source
frontier, topology, active set, dependencies, boundary contract and B0.4 artifact
interface.

### Executable transition

P0 transition remains:

```text
PREFLIGHT_ONLY
```

B0.5-A creates a separate executable transition wrapper only after exact source and
target executable modes are available.

The wrapper verifies that the P0 reset/handoff hashes match the real B0.4:

- source StateMapping;
- target StateMapping;
- source ReconstructionDescriptor;
- target ReconstructionDescriptor.

R1 reset policy:

```text
IDENTITY_FULL_HANDOFF_R1
```

## Physical event ownership

B0.5-A does not localize or invent the JUMP.

The acceptance creates a real existing `Fabric0CoupledHybridDAEV1` system:

```text
mode/hybrid/a
        │
        │ FLOW
        ▼
phase crossing
at ~0.05 s
        │
        │ localized by FABRIC
        ▼
transition/hybrid/release
        │
        │ JUMP
        ▼
mode/hybrid/b
```

B0.5-A consumes the resulting FABRIC event instant.

P0 ownership remains:

```text
owner:
FABRIC_PHYSICAL_EVENT

semantics:
EXACTLY_ONCE

canonical revision:
EXTERNAL_AUTHORITY_ONLY

replay:
REJECT_DUPLICATE_EVENT_ID
```

A B0.5 session has an explicit event ledger. Reusing the same physical event ID is
rejected before another mode transition can commit.

## B0.4 handoff

Mode A and mode B both use common B0.4 PhysicalBakeArtifact bundles.

On the FABRIC-owned JUMP:

```text
accepted mode-A ROM state
        ↓
A ReconstructionDescriptor
        ↓
FULL handoff
        ↓
IDENTITY reset R1
        ↓
B StateMapping
        ↓
mode-B ROM state
```

The exact acceptance requires the C-norm projection error to remain inside the B0.4
handoff tolerance.

B0.4 mode-local ValidatedDomain / ErrorEnvelope / RuntimeErrorEstimator /
RefinementGuard remain active after transition.

## Lazy mode-B compilation

B0.4 numerical ROM artifacts are inputs to B0.5 and are not re-reduced by the hybrid
layer.

What is lazy in B0.5-A is the executable hybrid-mode wrapper/cache around the
resolved B0.4 interface.

First mode-B encounter:

```text
exact mode-B signature
        ↓
cache miss
        ↓
validate B0.4 PhysicalBakeArtifact
        ↓
compile executable hybrid mode wrapper
        ↓
derived executable cache entry
        ↓
LAZY_COMPILED
```

Second deterministic replay:

```text
same exact cache key
        ↓
VALID derived entry
        ↓
EXACT_CACHE_HIT
```

No nearest-mode matching is used.

## Fail-closed behavior

Verified:

- duplicate FABRIC event → reject;
- stale executable cache → FULL fallback;
- unknown mode C → FULL fallback;
- nearest-mode reuse = false;
- unknown mode execution_authorized = false;
- B0.4 runtime/validity guard breach → REFINE_OR_FULL;
- invalid target StateMapping/handoff fails before committing target mode.

P0 regression continues to cover source/topology/dependency/B0.4-interface cache
invalidation reasons.

## Exact focused acceptance

```text
FABRIC-BAKE B0.5-A Executable Hybrid Bake Acceptance:
67 / 67 PASS

process exit:
0

fatal script/load markers:
0
```

## Closure chain

Runner:

`RUN_FABRIC_BAKE_B0_5_A_CLOSURE_TESTS.sh`

Result:

```text
B0.5-P0:
63/63 PASS

B0.5-A:
67/67 PASS

FABRIC-BAKE B0.5-A closure chain:
PASS

process exit:
0
```

## Project Control

Exact implementation/test subject:

```text
run:
33708036538

conclusion:
SUCCESS
```

## Non-claims

B0.5-A does not claim:

- arbitrary hybrid state-space coverage;
- arbitrary mode-dependent ROM operator generation;
- exponential active-set precompilation;
- nearest-mode approximation;
- device-specific Motor/Gearbox/Clutch/Valve kernel semantics;
- BRIDGE-2 mixed-world execution;
- FABRIC0.19 requirement;
- production acceptance.

The R1 falsifier focuses on executable hybrid orchestration, exact event ownership,
B0.4 state handoff and lazy hybrid-mode cache semantics over two generic passive
B0.4-backed modes.

## Verdict

```text
B0.5-P0 ✅ CLOSED
B0.5-A  ✅ CLOSED

B0.5 executable hybrid baseline:
ESTABLISHED

BRIDGE-2 executable:
STILL NOT AUTHORIZED

FABRIC0.19:
STILL NOT AUTHORIZED

next:
post-B0.5-A FABRIC synchronization / BRIDGE-2 authorization review
```
