# FABRIC0.17 — SIMULTANEOUS MULTI-IMPACT + GENERALIZED CONTACT WRENCH

## Статус

```text
FABRIC0.17
IN PROGRESS

0.17-A — SIMULTANEOUS IMPACT EVENT SET
IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
REMOTE BYTE IDENTITY PASS
NOT CLOSED
```

**Branch:** `research/fabric0-17-simultaneous-impact-event-set-r1`  
**Predecessor:** `FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP`  
**FABRIC0.16 closure HEAD:** `ae781ab78f2e0688641f6a332a131b3fb759994f`  
**FABRIC0.16 exact-tested executable:** `3307d553c1c3c79cd9c15a5c565af7fef3f0400c`  
**0.17-A executable HEAD:** `9139a213ccee64d3bf1bb95ea32170027421b3b3`.

FABRIC0.17 продолжает именно Physical Core. FABRIC-BAKE остаётся sibling research axis и может развиваться независимо.

## 1. Fundamental wall

FABRIC0.16 доказал отдельные general-convex contact events и unified graph topology mutation, но сознательно не заявил simultaneous multi-impact closure.

Новая стена:

```text
several independently localized impact candidates
                ↓
same physical instant / unresolved temporal neighborhood
                ↓
one deterministic event set
                ↓
one coupled post-impact solve
```

0.17-A атакует только первые три строки.

## 2. Checkpoint decomposition

```text
0.17-A
SIMULTANEOUS IMPACT EVENT SET

0.17-B
COUPLED SIMULTANEOUS IMPACT SOLVE

0.17-C
GENERALIZED CONTACT WRENCH
normal + tangential + rolling + torsional

0.17-D
UNIFIED MULTI-IMPACT WRENCH TRAJECTORY
+ refinement
+ momentum/energy
+ determinism
+ closure decision
```

Это разбиение специально не смешивает temporal identity события и physical jump solve.

## 3. 0.17-A semantics

Новый primitive:

`Fabric0SimultaneousImpactEventSetV1`.

Pipeline:

```text
body set
→ conservative swept candidate pairs
→ S2 contact-appearance root localization for every candidate
→ impact kinematics audit
→ canonical time/id ordering
→ earliest temporal cluster
→ deferred later impact roots
```

Contact appearance входит в impact set только если на локализованной границе:

```text
approach_speed > min_approach_speed
```

Approach speed вычисляется из full point velocity:

```text
v_point = v + omega × r
```

и oriented contact normal.

Таким образом простое появление contact relation без сближения не объявляется impact.

## 4. Что означает simultaneous

Запрещено определять simultaneity как:

```text
float_time_a == float_time_b
```

0.17-A использует локализованные root intervals:

```text
event_i =
[lo_i, hi_i]
+
reported midpoint time_i
```

События относятся к одному earliest event set, если distance их localization intervals от anchor interval не превосходит explicit `simultaneous_resolution`.

Результат означает: impacts are indistinguishable at the declared temporal resolution.

Это не математическое доказательство exact equality реальных корней.

Observable classification:

```text
INTERVAL_COINCIDENT
RESOLUTION_EQUIVALENT
```

и поля `root_tolerance`, `simultaneous_resolution`, `common_lo/common_hi`, `union_lo/union_hi`, `temporal_spread`, `uncertainty_span` делают numerical policy частью evidence.

## 5. Main falsifier

Пять одинаковых convex boxes:

```text
L ---> C <--- R

P ---> Q
```

Истинные roots:

```text
C|L = 0.5
C|R = 0.5

P|Q = 0.5002
```

То есть два impact действительно simultaneous, третий физически очень близок, но позже.

### Coarse resolution

При `1e-3`:

```text
[C|L, C|R, P|Q]
```

Все три roots ещё неразличимы в текущем temporal uncertainty.

### Refinement

Начиная с `1e-5`:

```text
event set:
[C|L, C|R]

deferred:
[P|Q]
```

Reference `1e-11`:

```text
simultaneous event:
0.50000000000146

deferred P|Q:
0.50019999999931
```

Event-time errors относительно reference:

```text
1e-5 -> 1.5258774510584772e-6
1e-7 -> 1.192238407998758e-8
1e-9 -> 9.167711034763215e-11
```

Strictly decreasing.

## 6. Determinism

Canonical event-set signature:

```text
SIMULTANEOUS_IMPACT_SET[C|L,C|R]
```

Полный reverse input body order даёт те же pair_ids, signature, event time и deferred pair/time.

## 7. Fail-closed boundaries

0.17-A явно отвергает:

- меньше двух bodies;
- empty/duplicate body IDs;
- bad time interval;
- non-positive root tolerance;
- negative simultaneous resolution;
- bad iteration budget;
- bad pair budget;
- pair count above bounded budget;
- negative impact approach threshold;
- localization/impact-kinematics failure.

Если impact roots отсутствуют: `NO_IMPACT_EVENT`.

Pair enumeration остаётся bounded research implementation. По умолчанию `max_pairs = 4096`.

## 8. Exact validation

Engine: `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

```text
0.17-A acceptance 77/77 PASS
0.17-A playground PASS
0.16 S3 regression 101/101 PASS
0.16 S2 regression 102/102 PASS
0.16 S1 regression 110/110 PASS
editor parse/compile CLEAN
remote byte identity 4/4 PASS
```

Exact files:

```text
event set
blob   593cd671c9144819199685eeb222df7b06399c76
sha256 4c4ecddb1675b65d52308490854bcd9334bce90291d215d8a98ba4c3950ca0d6

experiments
blob   a76d2e99165c69058e2d4da5a859a6cbc32f2bc0
sha256 276d5354ad2a090c31b9fc9b73d3500641618f3791f081c1bfbc3b644701051c

acceptance
blob   440ce7a1e1c48456d33a8d43aeb776a979afe02e
sha256 e1fc369b8342dc4a43b847c60a99aa7ed26d2813faf7ddcf1f1db94f38284da8

playground
blob   ecf16b7e6c87f50038357443d2fd0b82e4fc73c9
sha256 83bcb3365f0b3a450de38c0d9f5a14361d0af3a26937bf8b17cbba27dd6b0985
```

## 9. 0.17-A non-claims

0.17-A does **not** solve impact impulses.

Not claimed:

- coupled simultaneous post-impact velocity solve;
- restitution law across a multi-contact event set;
- unique/maximum-dissipation impact solution;
- same-time topology fixed point after impulses;
- rolling or torsional friction;
- exact mathematical equality of impact root times;
- transient appear+disappear detection when both macro-interval endpoints have the same contact state;
- production broadphase;
- sub-quadratic pair discovery;
- production acceptance.

Current event finder localizes bracketed appearance roots over an interval.

## 10. Next slice — 0.17-B

```text
SIMULTANEOUS_IMPACT_EVENT_SET
        ↓
materialize all event-set manifolds at one event boundary
        ↓
assemble one coupled impulse graph
        ↓
solve all normal impact impulses together
        ↓
optional restitution target
        ↓
audit pair-order independence
+ momentum conservation
+ energy/restitution ledger
+ complementarity
+ refinement
```

Critical requirement: sequentially applying pair impacts is not accepted as the 0.17-B reference semantics.

Construction remains canonical semantic owner. FABRIC0.17 remains research-only.
