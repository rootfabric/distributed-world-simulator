# FABRIC CX-VIS0 / CX-VIS1 — Local Exact Double Verification Evidence

**Verdict:** PASS  
**Date:** 2026-09-03  
**Verification class:** LOCAL_ATTACHED_CANONICAL_DOUBLE_GODOT  
**Code subject HEAD:** `51629722d3d2fc1c915657e1f457531d84554b32`  
**Branch:** `feature/fabric-cx-vis0-powered-observatory-r1`

## Exact source identity

The full source used for verification was recovered from the repository exact-source carrier generated for the same code subject.

```text
source carrier run:
33762331527

artifact:
9896009517

artifact name:
fabric-bake-b0-5-a-exact-source

bundle:
fabric-bake-b0-5-a-exact.bundle

bundle SHA-256:
295ec4666ce1c4cb7d120b04a8cd90561b79d0b557472e897892beb3e97add1e

bundle ref:
51629722d3d2fc1c915657e1f457531d84554b32
refs/heads/fabric-bake-b0-5-a-exact
```

The local checkout was detached/exact at the same commit before execution.

## Canonical attached Godot

User/project attached archive:

```text
godot-4.7.1-linux-double-x86_64-a13da4f.tar(1).gz
```

Resolved executable:

```text
godot.linuxbsd.editor.double.x86_64
```

Identity:

```text
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

This matches the canonical project double-Godot identity expected by the FABRIC workflows.

## Fresh import

A fresh editor import was executed on the exact source checkout before the focused gates.

The project import emitted pre-existing unrelated ecology scene parse diagnostics in older ECO lab scenes. No CX-VIS source or scene appeared in those diagnostics. The focused CX-VIS parser/resource smoke on GitHub is GREEN.

## Gate 1 — canonical COMPLEX0 @ 2000

Exact script:

```text
res://tests/research/fabric_bake0/fabric_bake_complex0_2000_exact_closure.gd
```

Result:

```text
FABRIC-BAKE COMPLEX0 2000 Exact Closure:
PASS

assertions:
25

transaction checksum:
b421928b2a5db9e700476d9d70e2be6b6ecde8bfe778b2511a1efaf85d082ebd

fragments:
[993, 1007]

post-split reduction:
1000.0

max reconstructed state error:
0.00000000000002
```

This proves the visual observatory is based on the already-authoritative 2000-part break / local refinement / split / rebake path, not a visual replica.

## Gate 2 — canonical COMPLEX1A causal baseline

Exact script:

```text
res://tests/research/fabric_bake0/fabric_bake_complex1a_acceptance.gd
```

Result:

```text
FABRIC-BAKE COMPLEX1A Acceptance:
PASS

assertions:
93

causal chain:
mechanical_support
→ functional_connectivity
→ effort_flow
→ load_power
```

This preserves the anti-hardcode baseline for battery/wire/lamp behavior.

## Gate 3 — CX-VIS0 / CX-VIS1 observatory

Exact script:

```text
res://tests/research/fabric_bake0/fabric_bake_cx_vis_observatory_acceptance.gd
```

Result:

```text
FABRIC CX-VIS0/1 Observatory Acceptance:
PASS

assertions:
63

canonical parts:
2000

FULL parts at refinement event:
20

split components:
2

powered causal result:
lamp ON → OFF

event:
topology-event/complex0-2000-break
```

The powered companion binds the functional wire support to the exact COMPLEX0 `break_bond_id` and reuses the exact structural `event_id`.

No visual-only command turns the lamp off.

## Additional branch checks on exact code subject

GitHub checks already GREEN on `51629722d3d2...`:

```text
Project Control                                  PASS
FABRIC CX-VIS0 Portable Parser Smoke             PASS
FABRIC-BAKE Complex Labs Portable Smoke          PASS
FABRIC-BAKE BRIDGE-2-A Portable Smoke            PASS
FABRIC-BAKE B0.5-A Exact Source Carrier          PASS
FABRIC-BAKE supporting exact source carriers     PASS
```

The dedicated self-hosted Linux-double workflow was still queued when this evidence was frozen. Its queue state is not substituted for the local exact result above.

## Qualification

```text
CX-VIS0 implementation                           ✅
2000-part exact physical predecessor             ✅
real refinement guard consumption                ✅
20-part local FULL observability                  ✅
canonical exactly-once break observability       ✅
STALE rejection observability                     ✅
split / two fresh rebakes                         ✅

CX-VIS1 battery → wire → lamp                    ✅
same structural break bond binding               ✅
same structural event identity                   ✅
FABRIC solve before/after                         ✅
lamp ON → OFF                                     ✅
duplicate event fail-closed                       ✅

LOCAL ATTACHED CANONICAL DOUBLE VERIFICATION     ✅ PASS

SELF-HOSTED LINUX DOUBLE WORKFLOW                ⏳ QUEUED AT FREEZE
```

## Non-claim

This evidence does not claim dynamic debris flight/collision after the split.

The current visual stand shows causal lifecycle state transitions and resulting component ownership. Any future falling/impacting debris visualization must be driven by real post-split physical execution rather than scripted animation.
