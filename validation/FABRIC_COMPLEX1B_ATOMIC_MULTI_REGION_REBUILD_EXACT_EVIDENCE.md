# FABRIC COMPLEX1B — Atomic Multi-Region Rebuild Exact Evidence

**Verdict:** PASS  
**Verification class:** LOCAL_ATTACHED_CANONICAL_DOUBLE_GODOT  
**Exact executable code subject:** `6eeba52b550f2d9e8fff8c4fd3c571fa88fbcfb8`  
**Exact TREE:** `92b4548f4cf70bd86087a47d949d2753a79ed08d`  
**Branch:** `feature/fabric-complex1b-visual-mixed-e2e-r1`

## Source identity

Exact source was recovered from the GitHub Actions BRIDGE-2 exact-source carrier for the same code subject.

```text
run:      33852110819
artifact: 9928724471
name:     fabric-bridge2-exact-source
digest:   sha256:788abb3ca1b6c0ff9d7de1561a0547a5e2faf85a3abecd7040ee1829a7aefcc2
bundle head:
6eeba52b550f2d9e8fff8c4fd3c571fa88fbcfb8 refs/heads/fabric-bridge2-exact
```

Bundle SHA verification passed before checkout. Checkout identity was asserted:

```text
HEAD=6eeba52b550f2d9e8fff8c4fd3c571fa88fbcfb8
TREE=92b4548f4cf70bd86087a47d949d2753a79ed08d
```

## Canonical attached Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

The executable was extracted from the user/project attached archive:

```text
godot-4.7.1-linux-double-x86_64-a13da4f.tar(1).gz
```

Godot was executed as the ordinary `oai` user because this custom build can crash during project startup when run as root inside the verification container.

## Falsifier reproduced before patch

A single canonical break changes both derived projection dependencies:

```text
region/impact
region/stable-structure
```

The existing closed BRIDGE-2 `Runtime.rebuild_region()` is intentionally a one-region operation. Sequentially rebuilding only `region/impact` attempts to validate a registry where `region/stable-structure` is still stale relative to the new master frontier.

Expected fail-closed result:

```text
BRIDGE2_REBUILD_REGISTRY_FAILED
```

COMPLEX1B now retains this as a negative acceptance probe.

## Patch behavior

The integration layer now performs:

```text
canonical BOND_BREAK
  ↓
Runtime.apply_master_update()
  ↓
affected = [region/impact, region/stable-structure]
  ↓
Runtime.step() blocked while stale
  ↓
build fresh FULL impact adapter
build fresh STRUCTURAL_BAKE stable adapter
  ↓
one Registry.create() over complete affected set
  ↓
one registry_hash transition
  ↓
clear both invalidation buckets
  ↓
zero-error state handoff for both regions
  ↓
all five representation regions executable
  ↓
mixed FLOW resumes
```

Closed BRIDGE-2 core files were not modified by this patch.

## Gate 1 — COMPLEX1B exact acceptance

Exact script:

```text
res://tests/research/fabric_bake0/fabric_bake_complex1b_mixed_powered_e2e_acceptance.gd
```

Result:

```text
FABRIC COMPLEX1B Mixed Powered E2E Acceptance:
PASS (57 assertions)
atomic_rebuild=impact+stable
mixed=FULL_REFERENCE
```

Key accepted facts:

```text
canonical subject                     2000 parts
active event evaluator                FULL
STRUCTURAL_BAKE observer              yes
CONTACT_BAKE observer                 yes
DYNAMIC_ROM                           executable
HYBRID_BAKE                           executable
projection mutable sources            0
projection readonly sources           5
single-region rebuild probe           fail-closed
atomic rebuild regions                impact + stable
impact state handoff error            0
structural state handoff error        0
mixed/FULL max state delta            <= 1e-12
same canonical BOND_BREAK             yes
same functional support loss          yes
lamp                                  ON -> OFF
exactly-once duplicate rejection      yes
```

## Gate 2 — closed BRIDGE-2 regression

Exact script:

```text
res://tests/research/fabric_bake0/fabric_bridge2_mixed_generic_machine_r1_acceptance.gd
```

Result:

```text
BRIDGE-2 initial mixed-flow max FULL delta=0
FABRIC BRIDGE-2 Mixed Generic Machine R1 Acceptance:
PASS (125 assertions)
```

This confirms the patch did not require modifying or weakening the closed BRIDGE-2 runtime contract.

## GitHub control evidence

For exact code subject `6eeba52b...`:

```text
Project Control                         SUCCESS
FABRIC BRIDGE-2 Exact Source Carrier    SUCCESS
CX-VIS0 Portable Parser Smoke           SUCCESS
Complex Labs Portable Smoke             SUCCESS
BRIDGE-2-A Portable Smoke               SUCCESS
```

Dedicated self-hosted Linux-double workflow was queued at the time of this evidence. Its queue state is not substituted for the local exact result above.

## Qualification

```text
COMPLEX1B atomic multi-region rebuild       ✅
single-region ordering falsifier retained  ✅
zero-error two-region handoff               ✅
all five mixed representations executable  ✅
FULL reference equality                     ✅
powered causal equality                     ✅
closed BRIDGE-2 regression                  ✅
LOCAL ATTACHED CANONICAL DOUBLE             ✅ PASS
```

This evidence does not claim production acceptance, B0.6 adaptive fidelity, or post-split debris dynamics.
