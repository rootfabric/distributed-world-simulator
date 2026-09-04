# FABRIC COMPLEX1B — Formal Closure

**Verdict:** CLOSED  
**Closure class:** RESEARCH_EXACT_LOCAL_CANONICAL_DOUBLE  
**Branch:** `feature/fabric-complex1b-visual-mixed-e2e-r1`  
**Exact executable subject:** `6eeba52b550f2d9e8fff8c4fd3c571fa88fbcfb8`  
**Exact executable TREE:** `92b4548f4cf70bd86087a47d949d2753a79ed08d`

## Closure basis

COMPLEX1B is formally closed against the experimental ladder requirement "POWERED BREAKABLE STRUCTURE / MIXED BAKE".

The closure is based on executable evidence, not presentation-only behavior.

### Exact runtime gates

```text
FABRIC COMPLEX1B Mixed Powered E2E Acceptance
PASS (57 assertions)
atomic_rebuild=impact+stable
mixed=FULL_REFERENCE
```

```text
FABRIC BRIDGE-2 Mixed Generic Machine R1 Acceptance
PASS (125 assertions)
initial mixed-flow max FULL delta=0
```

Canonical attached runtime:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact-source identity:

```text
carrier run: 33852110819
artifact:    9928724471
artifact digest:
sha256:788abb3ca1b6c0ff9d7de1561a0547a5e2faf85a3abecd7040ee1829a7aefcc2
```

Detailed exact evidence:
`validation/FABRIC_COMPLEX1B_ATOMIC_MULTI_REGION_REBUILD_EXACT_EVIDENCE.md`.

## Accepted properties

```text
canonical subject                           2000 parts
canonical truth owner                       Construction / Matter only
active impact evaluator                     FULL
impact observers                            STRUCTURAL_BAKE + CONTACT_BAKE
DYNAMIC_ROM                                 executable
HYBRID_BAKE                                 executable
mixed representation set                    all 5 BRIDGE-2 kinds
projection mutable canonical sources        0
projection readonly derived sources         5
canonical break                             exactly once
Construction revision                       advances once
stale mixed execution                       forbidden
single-region rebuild under multi-change    fail-closed
atomic affected set                         impact + stable
impact state handoff error                  0
structural state handoff error              0
mixed/FULL max state delta                  <= 1e-12
mechanical support loss                     causal
functional topology mutation                SUPPORT_TOPOLOGY_LOST
lamp                                        ON -> OFF
closed BRIDGE-2 regression                  PASS
```

## Falsifier retained

A canonical event that changes both impact and stable projection dependencies may not be recovered by applying the one-region `Runtime.rebuild_region()` sequentially.

The expected negative result remains executable:

```text
BRIDGE2_REBUILD_REGISTRY_FAILED
```

This prevents future changes from accidentally reintroducing partial mixed-registry acceptance.

## Architecture decision

No new canonical ownership layer was introduced.

```text
Construction / Matter
        = world truth

FULL / STRUCTURAL_BAKE / CONTACT_BAKE / DYNAMIC_ROM / HYBRID_BAKE
        = derived executable representations

visual observatory
        = read-only presentation
```

No `FABRIC0.19` primitive was required by this experiment. The observed multi-region ordering issue was expressible and solved at the integration/orchestration layer using existing BRIDGE-2 contracts.

## CI qualification

For the exact executable subject, Project Control and source-carrier/portable regressions were successful. Dedicated self-hosted Linux-double jobs may remain queued because the runner is an external availability constraint; that queue is not represented as a completed result and is not required to replace the exact attached-Godot proof above.

## Closure decision

```text
COMPLEX0   CLOSED
COMPLEX1A  CLOSED
CX2-VIS    EXACT GREEN
BRIDGE-2   CLOSED
COMPLEX1B  CLOSED
```

The next authorized complex-system experiment is:

```text
COMPLEX2 — MODULAR MACHINE LAB
```

COMPLEX2 must increase structural and functional composition rather than merely reskin COMPLEX1B. Initial target envelope:

```text
500–2000 canonical elements
20–50 structural modules
4–8 moving subsystems
2–4 active contact zones
1–3 functional energy/signal paths
FULL + STRUCTURAL_BAKE + CONTACT_BAKE + DYNAMIC_ROM + HYBRID_BAKE
```

Required first-phase experiments:

1. stable multi-module mixed execution against FULL reference;
2. articulated/moving subsystem interaction;
3. local contact event without unrelated module invalidation;
4. detachable module event;
5. structural support failure with bounded affected set;
6. functional path failure with downstream consequence;
7. mixed representation transition/rebuild after stabilization;
8. second event against the already reconfigured machine.

**COMPLEX1B is CLOSED. COMPLEX2 is AUTHORIZED.**
