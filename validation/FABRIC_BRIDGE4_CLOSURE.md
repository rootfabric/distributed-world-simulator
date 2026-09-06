# FABRIC BRIDGE-4 — CANONICAL WORLD ↔ FABRIC1 — RESEARCH EXACT CLOSED

**Status:** `RESEARCH EXACT CLOSED` for the bounded canonical-world integration bridge. This is not a `main` product-checkpoint acceptance.

## Exact subject

- Branch: `research/fabric-bridge4-canonical-world-fabric1-r1`
- FABRIC1-SYNC1 predecessor: `336fa62d48f0c9659623b320948a2304989baf84`
- Runtime candidate: `bb86d0b9f97b52727560bff88afc03df0a021668`
- Runtime tree: `95bb1a501f14e205d19336c36a374399cf1a63fb`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Godot SHA-256: `bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7`
- Fresh import: exit `0`, fatal markers `0`

Git compare from the frozen SYNC1 head to the runtime candidate contains exactly five new BRIDGE-4 paths. No frozen FABRIC1/B0.7/COMPLEX3/BRIDGE-3/B0.6 runtime or test path was modified.

## What crossed the bridge

BRIDGE-4 uses the real DWS canonical contracts rather than inventing a research-only source schema:

```text
ConstructSnapshot / ConstructionPartRecord / ConstructionBondRecord
ConstructionConstructMutation / ConstructionConstructStore
MatterMaterialBatch / MatterComposition
                 ↓
RepresentationSourceRevision
CanonicalSourceFrontier
AuthorityEnvelope
                 ↓
generic FABRIC1 graph
                 ↓
BAKED ↔ FULL ↔ REBAKED
```

Construction is the mutable canonical source. Matter is a read-only canonical dependency. The bridge itself records `canonical_writes = 0`.

## Exact canonical object

The acceptance creates a real `ConstructionConstructStore` object:

- 104 canonical Construction parts;
- 104 canonical bonds;
- 104 kg total Construction mass;
- matching 104 kg `MatterMaterialBatch`;
- 2 declared FABRIC boundary parts and 102 internal parts;
- initial Construction revision `0`, state `OPERATIONAL`.

The target bond is `bond/bridge4/link-051-052` with canonical strength 100 N. A 20-strength bypass keeps the damaged successor physically reducible while still changing downstream behavior.

## End-to-end lifecycle

```text
real Construction/Matter
        ↓
outer canonical source binding
        ↓
automatic FABRIC1 BAKE
        ↓
70 N subcritical observation
        ↓
no canonical mutation
        ↓
90 N overload
        ↓
FULL refinement + noncanonical failure proposal
        ↓
Construction store still unchanged
        ↓
EXTERNAL ConstructionConstructMutation(OP_UPDATE)
        ↓
revision 0 → 1 / OPERATIONAL → DAMAGED
        ↓
target bond becomes BROKEN
        ↓
old BAKE fenced
        ↓
FULL successor executes
        ↓
automatic REBAKE
        ↓
derived/discardable restart capsule
        ↓
restore only against authoritative successor
```

The physical layer does not mint canonical damage. Only the external canonical mutation changes `ConstructionConstructStore`.

## Functional consequence

Two fresh-process replays on byte-identical published files:

```text
49 / 49 PASS × 2
BRIDGE4_HASH=c7daed6263058ce016a32b9813ee9a5d8da1798be96cb01e641818bd323458bf
```

Observed boundary flow:

```text
before canonical break = 0.98159509202452
after canonical break  = 0.95238095238093
delta                  = 0.02921413964359
```

So the mutation has a real downstream physical consequence rather than merely changing a checksum.

## Truth / lifecycle falsifiers

The exact acceptance proves:

- subcritical physical observation cannot mutate Construction;
- overload produces `canonical=false`, `write_authorized=false` proposal;
- old BAKE is fenced with `STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN`;
- old Construction snapshot fails with `BRIDGE4_CANONICAL_BINDING_STALE`;
- changed canonical Matter invalidates execution and restart binding;
- old derived capsule against old canonical state fails with `BRIDGE4_CAPSULE_STALE`;
- duplicate canonical event is rejected with `BRIDGE4_CANONICAL_SUCCESSOR_ORDER_INVALID`;
- successor FULL and BAKE remain within exact-double flow/power tolerance;
- restart reproduces the authoritative successor physical result;
- canonical writes by BRIDGE-4 remain exactly zero.

## Remote byte identity

The five exact tested published blobs are:

```text
adapter    94fd8eb9f547668fbb159be1a685a8e139074e5c
runtime    b5d9c2c4b42a6759408c797dc50affd9a5ddff22
fixture    9437ec9fa9942ae50c91d0b2c9912408f04e7a42
acceptance 41e590e0b2c7b99f07ec2a2223452df348c4e7fe
runner     03d5f2ed379573060f68757afecb8db31593145e
```

## Fresh frozen-boundary regressions

```text
FABRIC1-SYNC1 independent gate: 30 PASS
hash = 9fa0138b88d63d8584afdc08972954a6aa86e3e8e32b8a413644c73112559d18

FABRIC1 core: 50 PASS
hash = 0dd739404c2ed0b352abc08e7c93d9100213e7479dd2cd96da8a51f1f9509444

B0.7 fail-closed guard: 14 PASS
hash = 511250652cf907507b79576dffad39ea7dbbf09b64e1cdca021fd4618d795abe
```

## Bounded claim

This bridge proves a real DWS `ConstructionConstructStore` + real `MatterMaterialBatch` can bind into the frozen FABRIC1 execution lifecycle without transferring canonical authority to FABRIC.

The current generic physical mapping uses canonical `ConstructionBondRecord.strength_n` as the generic edge conductance and explicit `part.role == fabric_boundary` as the boundary declaration. Matter is a real canonical dependency and mass-consistency constraint; BRIDGE-4 does not yet claim a general material constitutive-law compiler or arbitrary multi-domain object synthesis. Those remain downstream.

## Project Control attribution

```text
standard PC0 = RED
directional  = GREEN
```

The global RED belongs to unrelated active product lines: G8, ECO, T1B, CH9.6, doctrine, NX and V0. BRIDGE-4 does not claim product/main acceptance.

## Activation

With BRIDGE-4 closed, the next authorized stage is:

```text
COMPLEX4 — REAL WORLD MACHINE LAB
```

Visual/playable lab and broader multi-domain/dynamic/distributed generalization remain downstream of COMPLEX4.

## Closure hash

```text
FABRIC_BRIDGE4_CLOSURE_HASH=2f4fe35ac7f2b92e6fa9cc256373521d298bcf0fac4802f18e1f75a489c438e9
```
