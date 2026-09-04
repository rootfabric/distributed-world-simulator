# FABRIC BRIDGE-2 — Mixed Generic Machine R1 — Exact Closure

## Qualification

```text
BRIDGE-2 MIXED FULL ↔ BAKED ↔ DYNAMIC ROM ↔ HYBRID BAKE

CLOSED
EXACT DOUBLE PASS
SYNC4→BRIDGE2 CLOSURE CHAIN PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

## Exact implementation/test boundary

```text
branch:
research/fabric-bridge2-mixed-representation-r1

predecessor:
FABRIC.SYNC4 closure
51403977606f6f88fa8d31b3505a6c83361a4a3f

exact implementation/test HEAD:
05fc7b9de77a21239e953d2dfd1a0451f5820caf

TREE:
d9c2070ef2ba49791eb5e890b58bc2acc0f80255

tracked:
clean

git diff --check:
PASS
```

## Exact source carrier

```text
run:
33725617411

conclusion:
SUCCESS

artifact:
9881840731

Git bundle SHA-256:
746c1609591b19f062cca638402702ac61de5c8c1db93031a1f490a92a6c504b

artifact ZIP digest:
fa24b308700cc1f63c1a25fe1ae7f360afcf256f5d1683808bf0603ccbb335fa
```

## Godot

Project-attached canonical double Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## New bridge architecture

BRIDGE-2 adds four runtime contracts:

```text
bridge2_source_slice_v1.gd
bridge2_region_adapter_v1.gd
bridge2_mixed_registry_v1.gd
bridge2_mixed_runtime_v1.gd
```

### Regional source slices

A direct whole-frontier binding would invalidate every PhysicalBakeArtifact after any
local canonical mutation.

BRIDGE-2 therefore introduces a regional source slice:

```text
one master canonical PhysicalSource frontier
        │
        ├── exact slice region A
        ├── exact slice region B
        ├── exact slice region C
        ├── exact slice region D
        └── exact slice region E
```

Each slice:

- contains exact canonical source revisions from the master frontier;
- contains the corresponding exact authority subset;
- is proven against the live master frontier before execution;
- is non-overlapping with every other active region slice.

A derived regional artifact binds its exact slice through the existing common
PhysicalBakeArtifact source binding.

This enables selective invalidation without weakening canonical truth.

## R1 mixed subject

```text
MIXED_GENERIC_MACHINE_R1

region A → STRUCTURAL_BAKE
region B → FULL
region C → CONTACT_BAKE
region D → DYNAMIC_ROM
region E → HYBRID_BAKE
```

All five regions coexist under one master PhysicalSource frontier.

Each region owns exactly one scalar physical state in the R1 orchestration
falsifier.

No state ID and no canonical source key may have two active owners.

## Representation adapters

All non-FULL regions emit common exact PhysicalBakeArtifact adapters.

The adapters bind the already-closed backend contracts:

- BRIDGE-1 structural exact subject;
- B0.3 contact-wrench closure;
- B0.4 Dynamic ROM exact subject;
- B0.5-A executable hybrid exact subject.

The adapter does not replace those solvers.

Its purpose is to provide one common mixed-region lifecycle boundary with:

- regional source binding;
- PhysicalBoundaryContract;
- ValidatedDomain;
- ErrorEnvelope;
- ConservationEnvelope;
- ReconstructionDescriptor;
- StateMapping;
- BakeExecutionGate.

FULL owns no PhysicalBakeArtifact.

## Mixed FLOW

The first bridge falsifier uses a generic passive five-region chain.

Cross-region interactions are declared only through paired
PhysicalBoundaryContract ports.

The physical reference law is shared by FULL and mixed execution so that BRIDGE-2
tests representation orchestration rather than introducing a new physical kernel.

Exact acceptance result:

```text
maximum mixed-vs-FULL state delta:
0
```

for the deterministic R1 passive sequence.

With zero external power, total stored energy is non-increasing and every interface
reports non-negative dissipation.

## FABRIC-owned representation event

The acceptance uses an actual existing Fabric0CoupledHybridDAEV1 localized event at
approximately 0.05 s.

One physical event atomically changes representation ownership:

```text
region B:
FULL → HYBRID_BAKE

region E:
HYBRID_BAKE → FULL
```

The five-kind representation set therefore remains present while ownership moves.

The event creates exactly one mixed event-ledger record and two explicit state
handoffs.

Duplicate consumption of the same FABRIC event ID is rejected.

## Selective canonical invalidation

The acceptance advances only region A canonical source revision.

Result:

```text
master PhysicalSource frontier changes

region A slice:
changed
→ BakeInvalidation
→ STALE
→ execution forbidden

regions B/C/D/E slices:
byte-identical
→ remain executable
```

The complete mixed step is blocked while the required region A is stale, but every
unaffected region independently passes its execution gate.

Region A is then rebuilt against the refreshed exact source slice with generation 2
artifact state.

Physical scalar state handoff error:

```text
0
```

Mixed execution resumes and remains equal to the FULL reference.

## Fail-closed ownership

Acceptance rejects:

- duplicate state ownership;
- duplicate canonical source ownership;
- stale region execution;
- duplicate physical event consumption.

Unknown/uncertifiable representation behavior remains governed by the frozen SYNC4
FULL / NO_SAFE_BAKE policy.

## Exact focused acceptance

```text
FABRIC BRIDGE-2 Mixed Generic Machine R1 Acceptance:
125 / 125 PASS

process exit:
0

fatal script/load markers:
0
```

## Closure chain

Runner:

`RUN_FABRIC_BRIDGE2_CLOSURE_TESTS.sh`

Result:

```text
FABRIC.SYNC4:
122/122 PASS

BRIDGE-2:
125/125 PASS

FABRIC BRIDGE-2 R1 closure chain:
PASS

process exit:
0
```

## Project Control

Exact implementation/test subject:

```text
run:
33725617349

conclusion:
SUCCESS
```

## FABRIC0.19

No new Physical Core primitive was required.

The implementation uses closed FABRIC0.18 FLOW/JUMP/event semantics plus bridge-level
regional ownership/source slicing.

Therefore:

```text
FABRIC0.19
NOT AUTHORIZED
```

## Non-claims

BRIDGE-2 R1 does not claim:

- world-scale production scheduling;
- arbitrary distributed authority;
- all possible cross-domain physical laws;
- adaptive fidelity policy;
- BRIDGE-3 local unbake/full lifecycle;
- production acceptance.

## Verdict

```text
FABRIC.SYNC4 ✅ CLOSED
BRIDGE-2     ✅ CLOSED

mixed FULL / STRUCTURAL_BAKE / CONTACT_BAKE / DYNAMIC_ROM / HYBRID_BAKE
baseline established

FABRIC0.19
⛔ NOT AUTHORIZED

next:
COMPLEX1B mixed causal lab
and then B0.6 ADAPTIVE PHYSICAL FIDELITY
```
