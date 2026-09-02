# FABRIC0.11 — GENERAL EVENT-LOCALIZED CONTACT ISLANDS + SPARSE BACKEND

**Статус:** research-only successor к FABRIC0.10.  
**Parent research head:** `b1730170058d31c7fb53b1e42ff8425661797f01`.

## 1. Исследовательский барьер

FABRIC0.10 доказал persistent contact graph:

```text
stable contact identity
+
appear / persist / disappear
+
warm start
+
contact islands
+
sparse assembly
```

Но оставались два крупных shortcut:

1. event-aware bridge работал только когда macrostep начинался без активных contacts;
2. sparse graph/J/A в конце превращался в dense island-local matrix для Cholesky.

FABRIC0.11 атакует обе границы одновременно.

Критический вопрос:

> Может ли уже constrained persistent island продолжать участвовать в физике во время localization нового contact event, после чего graph merge/recompile произойдёт в том же physical instant, old warm-start state remap-ится, а linear numerical path останется sparse до самого solve?

Research prototype отвечает: **да для текущего sphere/plane contact grammar и одного первого topology-change event внутри macrostep**.

---

## 2. Новая causal sequence

Главная форма FABRIC0.11:

```text
persistent constrained island
        ↓
candidate constrained flow
        ↓
geometry topology predicate
        ↓
bisection event localization
        ↓
advance old graph exactly to te
        ↓
compile full contact graph at te
        ↓
same-time graph merge/recompile
        ↓
warm-start remap by stable contact id
        ↓
sparse cone solve at same te
        ↓
remaining constrained flow
```

Старые contacts **не выключаются** во время localization.

Это принципиальное отличие от эвристики:

```text
temporarily ignore resting contacts
→ estimate impact
→ repair stack afterwards
```

---

## 3. Event localization with active islands

На старте macrostep FABRIC фиксирует set активных contact IDs:

```text
S0
```

Для каждой bisection probe:

1. создаётся trial copy world state;
2. world продвигается до candidate time;
3. на каждом research substep решаются только contacts из `S0`;
4. old geometry relations пересобираются, чтобы их point/r/gap не были stale;
5. full provider graph проверяется в конце probe;
6. если full contact-ID set изменился — topology event уже произошёл.

Predicate:

```text
contact_ids(t) == S0
```

или:

```text
contact_ids(t) != S0
```

Bisection tolerance:

`1e-11 s`.

Maximum localization iterations:

`64`.

---

## 4. Очень важное различие двух точностей

Bisection tolerance **не равна** полной physical trajectory accuracy.

Current constrained probe integrator использует semi-implicit velocity-level substeps:

`max_substep = 0.01 s`.

Поэтому существуют два error layers:

### Event root inside current discrete trajectory

Локализуется до порядка:

`1e-11 s`.

### Discrete trajectory vs continuous reference

Имеет integration discretization error порядка current substep.

Это специально observable.

Main experiment:

```text
event_dt_discrete =
0.35709945939307

continuous free-fall reference =
0.3609505622728941
```

Offset:

```text
-0.0038511028798241 s
```

Этот offset **не является bisection error**.

Он является current time-integrator artifact.

FABRIC0.11 не скрывает его.

---

## 5. Existing constraints действительно остаются constrained

Main event instant audit:

```text
pair:A|B gap
~= 3.44e-12

plane:floor|body:A gap
~= 5.54e-12
```

То есть while incoming body C ищет первый contact, старый A/B stack не «отпускается» solver’ом.

Новый contact:

```text
pair:B|C
```

компилируется при:

```text
gap ~= 9.997662e-8
```

при declared geometry tolerance:

`1e-7`.

---

## 6. Main falsification experiment

До macrostep уже существует resting stack:

```text
B
↕ pair:A|B
A
↕ floor
```

Перед event sequence stack прогревается четыре contact steps.

Then dynamic body C добавляется:

```text
C:
center y = 3.5
radius   = 0.5
vy       = -1
```

Macrostep:

`dt = 0.6 s`.

Macrostep begins at world time:

`0.04 s`.

Existing contact IDs:

```text
pair:A|B
plane:floor|body:A
```

---

## 7. Localized graph mutation

Bisection probes:

`36`.

Relative event time:

`0.35709945939307 s`.

Absolute world event time:

`0.39709945939307 s`.

New relation:

`pair:B|C`.

No old contact disappears.

Graph changes:

```text
before:

island:A
bodies = [A,B]

contacts:
pair:A|B
plane:floor|body:A
```

to:

```text
at te:

island:A
bodies = [A,B,C]

contacts:
pair:A|B
pair:B|C
plane:floor|body:A
```

То есть free body C становится частью уже существующего constrained island **в physical event instant**.

---

## 8. Warm-start remap across same-time island merge

До event old stable relations имеют cached impulses.

После graph recompile old identities сохраняются:

```text
pair:A|B
plane:floor|body:A
```

New:

`pair:B|C`

стартует cold.

Event sparse solve reports:

```text
warm_start_contacts = 2
```

Это доказывает:

> Warm-start continuity следует stable relation identity, а не transient island shape.

---

## 9. Event impulse проходит через весь existing stack

Same-time solve имеет три active contacts:

```text
pair:B|C
pair:A|B
floor|A
```

Normal impulses всех трёх > 4 N*s в demonstrated impact.

То есть incoming C не получает локальный «collision response» только с B.

Impulse reaction распространяется через coupled sparse island до floor boundary.

После same-time event resolve velocities A/B/C near zero:

`< 2e-8`.

Это ограниченный inelastic stack-impact experiment.

---

## 10. True sparse numerical backend

FABRIC0.10 имел:

```text
sparse assembly
→ dense island matrix
→ Cholesky
```

FABRIC0.11 replaces linear subproblem with:

```text
sparse A rows
+
rho diagonal
+
Jacobi-preconditioned Conjugate Gradient
```

inside ADMM.

No dense effective-mass matrix is created.

No dense Cholesky is used by FABRIC0.11 successor.

Runtime evidence field:

```text
linear_backend = SPARSE_PCG

dense_materializations = 0
```

---

## 11. Sparse PCG contract

ADMM linear subproblem:

```text
(A + rho I) lambda
=
rho (z-u) - b
```

where:

`A = J M^-1 J^T`.

`A + rho I` is SPD for positive rho in the intended research solve.

PCG uses:

- sparse row dictionaries;
- sparse matvec;
- Jacobi diagonal preconditioner;
- previous ADMM lambda as PCG initial guess;
- deterministic row/contact ordering.

Independent unit gate:

```text
[4 1] [x0] = [1]
[1 3] [x1]   [2]
```

PCG gives:

```text
x =
[1/11, 7/11]
```

in exactly:

`2 iterations`

with zero reported residual at exact-double precision.

---

## 12. Sparse event-island evidence

At A/B/C event:

```text
contacts = 3
contact rows = 9

sparse effective-mass entries = 21
dense capacity                 = 81
```

Event ADMM:

```text
iterations = 31
PCG calls  = 31
PCG total iterations = 93
max PCG iterations in one call = 3
```

Dense materializations:

`0`.

---

## 13. Remaining constrained flow

After same-time event solve:

```text
remaining_dt =
0.24290054060693 s
```

Current research continuation uses:

`25 constrained substeps`.

Aggregate:

```text
island solves = 25
max islands   = 1

PCG calls      = 80
PCG iterations = 234

dense materializations = 0
```

At final world time:

`0.64 s`.

Bodies remain in near-rest stack:

```text
A y ~= 0.50000000002449
B y ~= 1.50000000004311
C y ~= 2.50000010002817
```

All linear velocity norms:

`< 2e-8`.

---

## 14. Lifecycle event is not duplicated

At exact `te`, contact history has one topology record:

```text
appeared:
pair:B|C

persisted:
pair:A|B
plane:floor|body:A
```

Remaining flow does not create an artificial second same-time `persist` history entry.

This matters because lifecycle history should describe causal topology, not internal solver call count.

---

## 15. Independent-island scheduling contract

FABRIC0.11 does not yet launch worker threads.

Instead it proves the required semantic prerequisite:

> Independent islands may be solved in a different schedule and committed by canonical body identity without changing physical result.

Two independent stacks:

```text
A/B

D/E
```

Two solver schedules:

1. forward;
2. reversed island schedule + reversed body insertion + reversed provider contact order.

Exact-equal world hash:

`e50cceb70dc4ecbd0100e5207ca5a58a2285c90a5085a6556b19db8ce8699078`.

Thus actual parallel execution is future numerical infrastructure, not a new physical semantics.

---

## 16. Full event-history order invariance

Main A/B/C event experiment is repeated with:

- reversed body insertion;
- reversed provider contact input;
- reversed independent-island schedule.

Exact-equal:

- event time;
- appeared contact;
- event island signature;
- contact history JSON;
- final body states;
- final world hash.

Final hash:

`86d76fc7a4b93bdd27030e1b343151d008e2c2e62ddfa72bdc11cf46d4f6133b`.

---

## 17. Fail-closed boundaries

### No existing island

General 0.11 event API expects an already constrained start.

Contact-free world gets:

`EVENT011_REQUIRES_EXISTING_CONTACT_ISLAND`.

FABRIC0.10 contact-free bridge remains historical evidence for that case.

### Old contact disappears during probe

If a member of old active set disappears while 0.11 is searching for a new event:

`EVENT011_OLD_CONTACT_DISAPPEARED_DURING_PROBE`.

Current implementation does not silently fold appear+disappear event iteration into one guess.

### Invalid sparse backend config

For example:

`pcg_max_iterations = 0`

fails:

`BAD_SPARSE_SOLVER_OPTIONS`.

---

## 18. Exact validation

Runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Focused acceptance:

`120/120 PASS`.

Playground:

`FABRIC0_11_EVENT_SPARSE_ISLANDS_PLAYGROUND_PASS`.

FABRIC0.10 runtime regression rerun in the same exact-double lab:

`97/97 PASS`.

Editor parse/compile/SCRIPT scan:

`CLEAN`.

Executable local/GitHub byte identity:

```text
fabric0_event_sparse_islands_v1.gd
87647dac2d46836800ba39f0fe098c08e88c5722

fabric0_event_sparse_islands_experiments_v1.gd
b62ffed0f0657187033bf595321af8e89c8851da

fabric0_event_sparse_islands_acceptance.gd
49db9e2cf6b6f08eebc219e0c2deddc30f84c900

fabric0_event_sparse_islands_playground.gd
17e33ad106a9fb54ddde69ba7d620187b4460a47
```

SHA-256:

```text
solver:
037d6729db40f74562040333ac59ae38ca58ea297a0ec8164285cc19cf9962c9

experiments:
b392e9e60139e1ee6334dd3d77ad10f8580dfe78b9b8d6906429552fa97e01bd

acceptance:
5bfad421ea7fac8a41f77f2a368ade94809d29118e771b844e02e1ada64ed085

playground:
bc2c9f8f6b9cfde513b0bc14575d231562ed0ed4118c3d5a21e089a2b30a9112
```

---

## 19. Что доказано

FABRIC0.11 показывает:

- new contact event можно локализовать while old persistent island remains constrained;
- old contact gaps остаются near zero during demonstrated localization;
- dynamic body can merge into active contact island at exact event timestamp;
- stable warm-start identities remap across island topology change;
- same-time event solve transmits incoming impulse through the pre-existing stack;
- sparse contact matrix stays sparse through actual linear solve;
- PCG linear backend independently verified on SPD system;
- dense materialization count is zero in successor;
- remaining macrostep continues through recompiled constrained island;
- causal lifecycle record exists once at event timestamp;
- independent island solve order can change without physical result;
- full event history and final state remain invariant under tested input/schedule permutations;
- FABRIC0.10 acceptance remains green on exact-double runtime.

---

## 20. Что НЕ доказано

FABRIC0.11 остаётся research prototype:

- geometry provider still sphere-sphere + sphere-plane;
- only first contact-set change per `advance_event_localized` is localized;
- old contact disappearance during localization is fail-closed, not yet a general simultaneous event;
- multiple same-time appear/disappear topology changes are not iterated to a general fixed point;
- constrained probe integrator is fixed semi-implicit substepping, not adaptive/error-controlled DAE integration;
- event time therefore has observable integration-discretization offset;
- no arbitrary convex/mesh persistent feature manifold;
- no orientation-integrated manifold tracking;
- no CSR/CSC compact storage; sparse representation is research dictionaries;
- PCG preconditioner is Jacobi only;
- no incomplete-Cholesky / multigrid / block preconditioner;
- no actual worker-thread parallel island execution;
- no sleep/wake state;
- no sparse symbolic-pattern caching;
- no broadphase;
- no production Construction / authority / persistence / replication integration;
- no full materialized DWS regression.

---

## 21. Следующий falsification wall

### FABRIC0.12 — ADAPTIVE MULTI-EVENT MANIFOLD DAE

FABRIC0.11 removed the two shortcuts promised by 0.10, but exposed the next ones.

Need:

```text
adaptive / error-controlled constrained integration
event-time convergence under timestep refinement
multiple appear/disappear events in one macrostep
same-time contact topology event iteration
persistent geometry feature matching
orientation-aware multi-point manifolds
warm-start remap when manifold features split/merge
sparse pattern/preconditioner caching
actual parallel island execution with deterministic commit
sleep/wake as derived computational state
```

Critical falsification experiment:

```text
resting multi-contact structure
+
tumbling dynamic body
+
one old contact disappears
while two new feature contacts appear
inside one large macrostep
+
event iteration reaches stable manifold
+
adaptive timestep refinement converges event time/state
+
parallel/reordered island execution gives same accepted result
```

---

## 22. Архитектурный вывод

> FABRIC0.11 впервые связывает persistent constrained contact graph, event-time topology mutation и genuinely sparse numerical solve в одну causal path.

При этом three truths остаются раздельны:

```text
semantic truth
    owned by Construction

physical relation/history
    represented by FABRIC contact identity + state

numerical machinery
    PCG / ADMM / warm cache / scheduling
```

Ни sparse matrix layout, ни PCG iteration history, ни warm cache не становятся новым canonical owner мира.

Это research evidence, не production promotion.
