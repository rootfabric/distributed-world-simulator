# FABRIC COMPLEX2 — Modular Machine Lab

**Статус:** 🟡 COMPLEX2 OPEN / ✅ A EXACT / ✅ B EXACT / ✅ C EXACT / ✅ D PHYSICAL EXACT / ✅ E PHYSICAL EXACT  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**PR:** #534  
**Predecessor:** `COMPLEX1B` ✅ CLOSED @ `50574d70a9f7abd5d21e54ab09755a567656f554`

> Для D/E `PHYSICAL EXACT` означает exact source bundle + canonical attached double Godot + independent deterministic replay. Repository-wide Project Control при этом RED из-за отдельного pre-existing ownership/passport drift G/ECO/V0/Matter/P7; это не скрывается и не переименовывается в GREEN.

## Текущая лестница

```text
COMPLEX1B mixed powered E2E               ✅ CLOSED
        ↓
COMPLEX2-A Modular Composition            ✅ EXACT VERIFIED
        ↓
COMPLEX2-B Compliant / Spring Response    ✅ EXACT VERIFIED
        ↓
COMPLEX2-C Articulated + Rotating Motion  ✅ EXACT VERIFIED
        ↓
COMPLEX2-D Independent Structural Failure ✅ PHYSICAL EXACT VERIFIED
        ↓
COMPLEX2-E Settle → Rebake → Re-impact    ✅ PHYSICAL EXACT VERIFIED
        ↓
★ COMPLEX2-PERF 500 / 1000 / 2000 ★      ← NEXT
        ↓
COMPLEX2-CLOSE
```

## Общая машина

```text
2000 canonical parts
25 structural modules
6 moving subsystems
3 active contact zones
2 functional energy paths
5 BRIDGE-2 execution regions
```

Closed BRIDGE-2 R1 остаётся неизменным и содержит ровно один owner каждого representation kind:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

25 logical modules размещаются поверх этих пяти execution partitions; ни A–E не создают competing canonical writers или шестой representation owner.

Logical composition:

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

Каждый module содержит 80 canonical parts: `25 × 80 = 2000`.

# COMPLEX2-A — Modular Composition

**Статус:** ✅ EXACT VERIFIED

```text
code subject 8d10a4e00b616c28e62cd16b4645342dc8256632
TREE         7ce37330e70f5082c7e5d1e6632e0b5982bbcaf4
acceptance   PASS 2115 assertions
hash         7017c4acf32ff0f8e75165e1bd8a9c9c45e111ba767776f9ab8b486a52cae541
```

A доказал базовую композицию машины: mixed movement == FULL, local CONTACT, detach #24, HYBRID rebuild, functional branch A loss, FULL↔HYBRID swap, второй distinct support event, DYNAMIC rebuild и functional branch B loss.

Evidence:

```text
validation/FABRIC_COMPLEX2_A_EXACT_EVIDENCE.md
```

Visual:

```text
res://scenes/labs/fabric/complex2_modular_machine_lab.tscn
```

# COMPLEX2-B — Compliant / Spring Response

**Статус:** ✅ EXACT VERIFIED

```text
physical subject b1f4338b273f0889486553b18bea93d39127bba6
final verify     57204de250cd05af76dbff4a42827a983d056ebb
acceptance       PASS 65 assertions
hash             af5779bddc65a504c9ec14612b3dc62341032e4ed770a885c2df679dcbcd6795
```

B расширяет существующий HYBRID owner для `module/complex2-20`:

```text
80 canonical spring/damper fibers
        ↓ coherent projection
1 reduced Kelvin-Voigt state q

K = 720 N/m
C = 116 N*s/m
max FULL/HYBRID delta = 4.996003610813204e-16
energy residual = 0
```

Projection/reconstruction и refinement guards exact-проверены.

Evidence / design:

```text
validation/FABRIC_COMPLEX2_B_COMPLIANT_RESPONSE_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2B_COMPLIANT_RESPONSE_RU.md
```

# COMPLEX2-C — Articulated + Rotating Coupled Motion

**Статус:** ✅ EXACT VERIFIED

```text
subject    bfc9109a240b513dd6866da04bcad3fd8de4b275
TREE       1a676742b30179967ab7fe5ad4084a3b5cb42b75
acceptance PASS 66 assertions
hash       433345db30f8b59e5da67d83cc3a737f546305563029f0f38ca583988e96a995
```

C связывает shoulder / elbow / shaft / carriage в reciprocal four-DOF assembly:

```text
q[4] + v[4]
shoulder ↔ elbow ↔ shaft ↔ carriage
        ↖──── frame closure ────↙
```

DYNAMIC_ROM использует compiled M/K/C, FULL reference пересобирает их из canonical coupling records. Implicit midpoint даёт exact energy accounting. Mid-motion DYNAMIC_ROM→FULL→DYNAMIC_ROM сохраняет q/v без скачка; shoulder-only falsifier передаёт движение в shaft/carriage только через couplings.

```text
max ACTIVE/FULL delta = 0
max energy residual   = 5.273559366969494e-16 J
representation swaps = 2
handoff error         = 0
```

Evidence / design:

```text
validation/FABRIC_COMPLEX2_C_COUPLED_MOTION_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2C_COUPLED_MOTION_RU.md
```

# COMPLEX2-D — Independent Structural Failure

**Статус:** ✅ PHYSICAL EXACT VERIFIED

Exact executable boundary:

```text
HEAD 3ac206b02c77002fe62bc937105ee67e1ef46260
TREE 64be92fbcb535c973b9eb22935510a016d1cf18d
```

Independent structural failure:

```text
brace/complex2-12-16
```

Он не совпадает с detach support `23-24` и functional support `10-11`.

Redundant subnetwork:

```text
module12 -- 13 -- 14 -- 15 -- module16
   |                              |
   +-------- brace 12↔16 ---------+
```

Under 100 N:

```text
brace force before = 61.608243 N
tip before         = 0.123216486 m
tip after          = 0.320945163 m
chain force ratio  = 2.604726
equilibrium error  ≈ 2.84e-14 N
```

После failure все 25 modules остаются connected; functional topology/solve не меняется. Load перераспределяется по chain path.

Canonical event затрагивает exactly FULL + CONTACT source partitions:

```text
canonical brace failure
        ↓
FULL + CONTACT STALE
        ↓
mixed blocked
        ↓
partial single-region rebuild rejected
        ↓
atomic FULL+CONTACT rebuild
        ↓
zero handoff
        ↓
mixed == FULL
```

Exact source / result:

```text
carrier run 33885515320
artifact    9941665844
artifact digest sha256:6d1f1a871d6501216faff103b7ac7dcceb1b82c868ec11ac4a9cec1ccd75235d
acceptance PASS 50 assertions × 2 independent bundle checkouts
hash 5dcc2f802c5aaf444eeca2c910aab9973205ab7ab2d4c3b2caada3257b27b580
```

Evidence / design:

```text
validation/FABRIC_COMPLEX2_D_INDEPENDENT_STRUCTURAL_FAILURE_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2D_INDEPENDENT_STRUCTURAL_FAILURE_RU.md
```

Visual:

```text
res://scenes/labs/fabric/complex2d_structural_failure_lab.tscn
```

# COMPLEX2-E — Settle → Rebake → Re-impact

**Статус:** ✅ PHYSICAL EXACT VERIFIED

Exact executable boundary:

```text
HEAD b618c449b6dae5a25a14d24bfed87dbc2832d125
TREE ed5450dc71f4b0fb707b18af5c6b1584f73199ef
```

E продолжает уже повреждённую D-machine:

```text
D complete
   ↓
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
coupled response + CONTACT response
```

Settled gate:

```text
energy <= 0.0025 J
max path speed <= 0.020 m/s
```

Exact:

```text
settle step    = 549
settled energy = 0.0024826531871402274 J
q/v packet handoff error = 0
```

Rebake не подделывает canonical mutation:

```text
source slice before == source slice after
DYNAMIC backend before != backend after
artifact generation = 6
registry identity changes
runtime state handoff error = 0
```

Re-impact event:

```text
event/complex2e-reimpact-after-settled-rebake
```

Exactly-once guard работает. Re-impact повторно возбуждает всю coupled system:

```text
peak energy   = 0.612677432 J
CONTACT delta = 0.008322890093712065
physical DYNAMIC == FULL
mixed runtime     == FULL
```

Structural topology D остаётся неизменной через settle/rebake/re-impact; HYBRID compliant backend сохраняется; functional topology не мутирует.

Exact source / result:

```text
carrier run 33886574243
artifact    9942087276
artifact digest sha256:e1c5a6402f7f5f4d08ea431f4e5cc491857bf9c17d54d55ff9621a6c6e8b8a0b
acceptance PASS 47 assertions × 2 independent bundle checkouts
hash 77c3c1e792d082391c8901d9c61946b0655c4abd332f71dc4554ef479fc9a5f8
```

Evidence / design:

```text
validation/FABRIC_COMPLEX2_E_SETTLE_REBAKE_REIMPACT_EXACT_EVIDENCE.md
docs/research/FABRIC_COMPLEX2E_SETTLE_REBAKE_REIMPACT_RU.md
```

Visual:

```text
res://scenes/labs/fabric/complex2e_settle_rebake_reimpact_lab.tscn
```

# Global control-plane caveat after D/E

Project Control is not green on D/E subjects. D run `33885515305` and E run `33886574047` both fail at the repository-wide architecture/ownership passport compatibility regression. Logs report existing RED `CRITICAL_DEPENDENCY_DRIFT` for G/ECO/V0 against Matter/P7/control dependencies outside the COMPLEX2-D/E changes. Exact checkout and checkpoint-session regression pass before that global step.

Therefore:

```text
A/B/C exact physical gates: GREEN
D/E exact physical gates:   GREEN
D/E global Project Control: RED — separate pre-existing control-plane drift
```

No D/E evidence claims otherwise.

# Exact-vs-current branch boundary

The last exact-tested executable subject is:

```text
b618c449b6dae5a25a14d24bfed87dbc2832d125
TREE ed5450dc71f4b0fb707b18af5c6b1584f73199ef
```

Commits after that subject are documentation/evidence-only. No executable D/E file is modified after exact verification.

# Что осталось для COMPLEX2 CLOSED

```text
★ COMPLEX2-PERF — 500 / 1000 / 2000 scaling matrix ★
        ↓
COMPLEX2-CLOSE — final exact closure review
```

`FABRIC0.19` остаётся **NOT AUTHORIZED**. A–E были выражены существующими topology/event, reconstruction/artifact, BRIDGE-2 mixed representation и nested physical backend contracts. Ни D, ни E не обнаружили falsifier, требующий новый foundation primitive.