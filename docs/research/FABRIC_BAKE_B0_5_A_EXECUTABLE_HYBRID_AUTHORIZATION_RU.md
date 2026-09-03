# FABRIC-BAKE B0.5-A — Executable Hybrid Bake — Authorization R1

## Qualification

```text
B0.5-A EXECUTABLE HYBRID BAKE
EXECUTABLE RESEARCH AUTHORIZED
NOT YET IMPLEMENTED
NOT PRODUCTION ACCEPTED
```

Authorized by:
`FABRIC.SYNC3`.

Branch:
`research/fabric-bake0-5-a-executable-hybrid-r1`.

## Scope

B0.5-A turns the closed P0 contracts into one real generic two-mode executable
hybrid reduction.

It must consume B0.4 artifacts. It may not implement a private ROM.

## Required subject

```text
MODE A
B0.4 PhysicalBakeArtifact
        │
        │ FLOW
        ▼
localized guard
        │
        │ JUMP
        ▼
B0.4-compatible reset/handoff
        │
        ▼
MODE B
B0.4 PhysicalBakeArtifact

first encounter B:
lazy compile/cache

repeat encounter B:
exact cache hit

unknown C:
FULL / NO_SAFE_BAKE
```

## Execution ownership

FABRIC owns physical FLOW/JUMP/topology semantics.

B0.5-A owns only derived hybrid-reduction orchestration.

Exactly-once event semantics from P0 remain mandatory.

## Mode-local B0.4 requirements

Every executable mode artifact must expose:

- PhysicalBakeArtifact;
- exact source binding;
- Dynamic ROM descriptor;
- ValidatedDomain;
- ErrorEnvelope;
- RuntimeErrorEstimator;
- RefinementGuard;
- ReconstructionDescriptor;
- StateMapping;
- build generation.

## Lazy cache

Cache key must bind exact:

- HybridModeSignature;
- source frontier;
- topology;
- active relation/complementarity set;
- dependencies;
- boundary contract;
- B0.4 artifact/interface identity.

Cache remains derived-only.

No nearest-mode matching.

## Transition handoff

A→B must prove:

- exactly one physical JUMP commit;
- deterministic crossing localization;
- source revision policy preserved;
- A reduced state reconstructed through A ReconstructionDescriptor;
- reset/handoff applied once;
- B state projected through B StateMapping;
- boundary/conservation/error envelopes satisfied;
- deterministic replay.

## Fail-closed cases

Must route to REFINE/FULL/NO_SAFE_BAKE for:

- stale source;
- stale topology;
- stale dependency;
- stale B0.4 interface;
- unknown mode;
- uncertifiable mode;
- invalid reset/handoff;
- duplicate event;
- B0.4 runtime guard breach.

## Closure gate

B0.5-A closes only when:

- two generic passive executable modes exist;
- both use B0.4 common PhysicalBakeArtifact;
- mode A→B FLOW/JUMP executes;
- B is lazily compiled on first encounter;
- repeated B resolves to exact valid cache entry;
- unknown C does not nearest-match and falls back;
- duplicate physical JUMP is rejected;
- B0.4 StateMapping/ReconstructionDescriptor handoff passes;
- mode-local B0.4 error/passivity guards remain active;
- stale cache/artifact execution fails closed;
- deterministic replay passes;
- exact double Godot acceptance passes;
- Project Control passes.

## Non-claims

B0.5-A does not claim:

- arbitrary hybrid state-space coverage;
- exponential active-set precompilation;
- device-specific motor/gearbox/clutch semantics;
- BRIDGE-2 mixed-world execution;
- FABRIC0.19 requirement;
- production acceptance.

## Canonical B0.5-A branch correction

An older parallel `research/fabric-bake0-5-a-executable-hybrid-r1` branch already
existed from the superseded pre-final B0.4 SYNC-3 attempt (PR #464).

It is not the child of this final SYNC-3 closure and is therefore not canonical.

Canonical authorized branch:

```text
research/fabric-bake0-5-a-executable-hybrid-r2

base:
3cf8e6689b8b7d20593f134a8a1eb0ce79db1ca1
(final FABRIC.SYNC3 closure)
```

PR #464 is closed as superseded by PR #473.
