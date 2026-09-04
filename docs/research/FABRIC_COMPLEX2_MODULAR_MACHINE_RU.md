# FABRIC COMPLEX2 — Modular Machine Lab

**Статус:** ✅ **RESEARCH CLOSED**  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**PR:** #534 — historical integration / CI carrier  
**Predecessor:** `COMPLEX1B` ✅ RESEARCH CLOSED

Formal closure:

```text
validation/FABRIC_COMPLEX2_CLOSURE.md
```

Exact closure executable subject:

```text
HEAD 4cf6d45f35b16db0cead220768b399f0ea5c75ef
TREE 923f9f59730da43f8be6d738b7e1dc4a23ec7764
```

Canonical Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
sha256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Закрытая лестница

```text
COMPLEX1B mixed powered E2E               ✅ RESEARCH CLOSED
        ↓
COMPLEX2-A Modular Composition            ✅ EXACT VERIFIED
        ↓
COMPLEX2-B Compliant / Spring Response    ✅ EXACT VERIFIED
        ↓
COMPLEX2-C Articulated + Rotating Motion  ✅ EXACT VERIFIED
        ↓
COMPLEX2-D Independent Structural Failure ✅ EXACT VERIFIED
        ↓
COMPLEX2-E Settle → Rebake → Re-impact    ✅ EXACT VERIFIED
        ↓
COMPLEX2-PERF 500 / 1000 / 2000           ✅ EXACT VERIFIED
        ↓
COMPLEX2-CLOSE                             ✅ EXACT VERIFIED
```

## Общая машина

Canonical close subject:

```text
2000 canonical parts
25 structural modules
6 moving subsystems
3 active contact zones
2 functional energy paths
5 BRIDGE-2 execution regions
```

Five simultaneous representation kinds remain:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

25 logical modules are distributed over those five execution partitions. No COMPLEX2 stage introduces a sixth representation owner or a competing canonical writer.

```text
FRAME modules 0..7
DYNAMIC modules 8..11
  shoulder / elbow / shaft / carriage
FULL modules 12..14
CONTACT modules 15..18
HYBRID modules 19..24
  compliant module 20
  detachable module 24
```

At the canonical close scale each module contains 80 canonical parts.

# COMPLEX2-A — Modular Composition

**Статус:** ✅ EXACT VERIFIED

A establishes the initial 2000-part modular machine and mixed-representation execution:

```text
normal mixed movement == FULL
local CONTACT event
detach module 24
HYBRID invalidation/rebuild
functional branch A loss
FULL ↔ HYBRID swap
second distinct support event
DYNAMIC invalidation/rebuild
functional branch B loss
```

Exact acceptance:

```text
PASS 2115 assertions
hash 7017c4acf32ff0f8e75165e1bd8a9c9c45e111ba767776f9ab8b486a52cae541
```

Evidence:

```text
validation/FABRIC_COMPLEX2_A_EXACT_EVIDENCE.md
```

# COMPLEX2-B — Compliant / Spring Response

**Статус:** ✅ EXACT VERIFIED

B extends the existing HYBRID owner for `module/complex2-20`:

```text
80 canonical spring/damper fibers
        ↓ coherent projection
1 reduced Kelvin-Voigt state q
```

Exact physical envelope:

```text
K = 720 N/m
C = 116 N*s/m
max FULL/HYBRID delta = 4.996003610813204e-16
energy residual = 0
PASS 65 assertions
```

Evidence:

```text
validation/FABRIC_COMPLEX2_B_COMPLIANT_RESPONSE_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2B_COMPLIANT_RESPONSE_RU.md
```

# COMPLEX2-C — Articulated + Rotating Coupled Motion

**Статус:** ✅ EXACT VERIFIED

C turns shoulder / elbow / shaft / carriage into one reciprocal four-DOF assembly:

```text
q[4] + v[4]
shoulder ↔ elbow ↔ shaft ↔ carriage
        ↖──── frame closure ────↙
```

DYNAMIC_ROM uses compiled `M/K/C`; FULL reference rebuilds from canonical coupling records. Mid-motion:

```text
DYNAMIC_ROM → FULL → DYNAMIC_ROM
```

preserves physical state with zero handoff error.

Exact result:

```text
max ACTIVE/FULL delta = 0
max energy residual = 5.273559366969494e-16 J
representation swaps = 2
handoff error = 0
PASS 66 assertions
hash 433345db30f8b59e5da67d83cc3a737f546305563029f0f38ca583988e96a995
```

Evidence:

```text
validation/FABRIC_COMPLEX2_C_COUPLED_MOTION_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2C_COUPLED_MOTION_RU.md
```

# COMPLEX2-D — Independent Structural Failure

**Статус:** ✅ EXACT VERIFIED

Independent brace failure:

```text
brace/complex2-12-16
```

is distinct from detach support `23-24` and functional support `10-11`.

The redundant structural path redistributes load rather than detaching the machine:

```text
brace force before = 61.608243 N
tip before = 0.123216486 m
tip after  = 0.320945163 m
chain force ratio = 2.604726
equilibrium residual ≈ 2.84e-14 N
component count after = 1
```

Canonical failure invalidates exactly FULL+CONTACT. Partial sequential rebuild is rejected; atomic two-region rebuild restores execution with zero handoff and mixed==FULL.

Exact result:

```text
PASS 50 assertions ×2
hash 5dcc2f802c5aaf444eeca2c910aab9973205ab7ab2d4c3b2caada3257b27b580
```

Evidence:

```text
validation/FABRIC_COMPLEX2_D_INDEPENDENT_STRUCTURAL_FAILURE_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2D_INDEPENDENT_STRUCTURAL_FAILURE_RU.md
```

# COMPLEX2-E — Settle → Rebake → Re-impact

**Статус:** ✅ EXACT VERIFIED

E continues the already damaged D machine:

```text
FIRST IMPACT
    ↓
RINGDOWN
    ↓
SETTLED
    ↓
DYNAMIC_ROM REBAKE generation 6
    ↓
new exactly-once RE-IMPACT
    ↓
coupled + CONTACT response
```

Settled gate:

```text
energy <= 0.0025 J
max path speed <= 0.020 m/s
```

Exact values:

```text
settle step = 549
settled energy = 0.0024826531871402274 J
rebake q/v handoff = 0
re-impact peak energy = 0.612677432 J
CONTACT delta = 0.008322890093712065
```

Rebake changes only the derived DYNAMIC backend. The source slice is unchanged, so settle is not misrepresented as a canonical mutation. Structural topology from D remains unchanged through rebake/re-impact.

Exact result:

```text
PASS 47 assertions ×2
hash 77c3c1e792d082391c8901d9c61946b0655c4abd332f71dc4554ef479fc9a5f8
```

Evidence:

```text
validation/FABRIC_COMPLEX2_E_SETTLE_REBAKE_REIMPACT_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2E_SETTLE_REBAKE_REIMPACT_RU.md
```

# COMPLEX2-PERF — 500 / 1000 / 2000

**Статус:** ✅ EXACT VERIFIED

PERF materializes real scaled canonical part arrays and executes D failure, E settle/re-impact, 16 mixed/FULL steps, then local DYNAMIC rebake.

Exact attached-Godot matrix:

```text
500:  total 6.027 s | scan 1.315 ms | local rebake 86.552 ms
1000: total 6.130 s | scan 2.503 ms | local rebake 88.082 ms
2000: total 5.993 s | scan 4.952 ms | local rebake 85.493 ms
```

Budgets:

```text
total <= 12 s per case
local rebake <= 250 ms
mixed/FULL <= 1e-12
rebake handoff = 0
```

Deterministic timing-independent identity:

```text
COMPLEX2PERF_MATRIX_HASH=
698486abd097e6ee12731b0afb1c6e28ed24bf72b52d8d940c9f5b7336498607

PASS 62 assertions
```

Evidence:

```text
docs/research/FABRIC_COMPLEX2_PERF_SCALING_RU.md
validation/FABRIC_COMPLEX2_PERF_EXACT_EVIDENCE.md
```

# COMPLEX2-CLOSE

**Статус:** ✅ EXACT VERIFIED / RESEARCH CLOSED

Exact source carrier:

```text
run 33889807380 — SUCCESS
artifact 9943356404
artifact digest sha256:8cce468fd3a1865a1e21b1d71369eed217e6672ca64c4cf457dc9862ff77b055
```

Two independent exact-source closure invocations:

```text
COMPLEX2_CLOSE_HASH=
f429d2743dab5f31fed87901186b03868039b13c2e087a86f3473f84e5b60855

COMPLEX2_PERF_HASH=
698486abd097e6ee12731b0afb1c6e28ed24bf72b52d8d940c9f5b7336498607

FABRIC COMPLEX2-CLOSE Acceptance: PASS (44 assertions) A+B+C+D+E+PERF
```

Project Control on exact executable subject:

```text
run 33889807533 — SUCCESS
```

The earlier D/E global passport RED is superseded by this successful final closure-subject Project Control run; the historical D/E evidence remains accurate for those older SHAs.

Formal evidence:

```text
validation/FABRIC_COMPLEX2_CLOSURE.md
```

# Architectural conclusion

COMPLEX2 demonstrates that one canonical modular object can simultaneously contain structural, compliant, coupled dynamic, contact and hybrid physical behavior; undergo independent structural failure; settle and rebuild a derived dynamic representation; receive a new exactly-once impact; and preserve mixed-vs-FULL reference equivalence across 500/1000/2000 scale cases.

No new generic FABRIC0 primitive was required.

`FABRIC0.19` remains **NOT AUTHORIZED**.

# Следующая ступень

COMPLEX3 is not yet authorized. Its roadmap gate is:

```text
B0.6 ADAPTIVE PHYSICAL FIDELITY
        +
BRIDGE-3 FULL → BAKE → guard/validity exit → LOCAL UNBAKE → FULL
        ↓
COMPLEX3 ADAPTIVE DAMAGE + LOCAL UNBAKE LAB
```

Therefore the next foundation item after COMPLEX2 closure is **B0.6 Adaptive Physical Fidelity**.