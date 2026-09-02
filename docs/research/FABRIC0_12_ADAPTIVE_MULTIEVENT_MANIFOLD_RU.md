# FABRIC0.12 — ADAPTIVE MULTI-EVENT MANIFOLD DAE

**Статус:** research-only successor к FABRIC0.11.  
**Parent research head:** `9e04333a27d01992be6740d7b817579980a254f0`.

## 1. Исследовательский барьер

FABRIC0.11 связал:

```text
persistent constrained contact graph
+
event-time graph mutation
+
sparse PCG numerical solve
```

в одну causal path.

Но он оставил три искусственные границы:

1. constrained trajectory интегрировалась fixed semi-implicit substeps;
2. за один event-localized advance обрабатывалась только первая смена contact set;
3. persistent geometry feature identity ещё не переживала полноценный manifold split/merge.

FABRIC0.12 атакует именно эти границы.

Главный вопрос:

> Можно ли сделать contact/manifold event semantics не зависящей от выбранного coarse timestep, обрабатывать несколько physical event instants внутри одного macro interval, достигать same-time manifold fixed point и переносить numerical continuity между changing geometric features — при этом сохранив sparse/parallel numerical machinery отделённой от physical truth?

Research prototype отвечает **да на специально ограниченном orientation-aware corner-manifold стенде**.

---

## 2. Почему 0.12 использует отдельный reduced model

FABRIC0.12 не пытается сразу заменить весь 3D persistent contact solver.

Это сознательно отдельный falsification model:

```text
oriented rectangle
inside
floor + wall corner
```

где:

- differential state: orientation `theta`, angular velocity `omega`;
- algebraic state: center position, выводимый из active geometric constraints;
- contact manifold меняется с orientation;
- exact physical event times известны аналитически;
- один large advance содержит несколько topology events;
- feature lineage явно observable.

Такой стенд позволяет проверить именно numerical/manifold semantics, не смешивая finding с mesh collision, broadphase и 3D inertia complexity.

Это **не** production geometry replacement для FABRIC0.11.

---

## 3. Differential + algebraic form

Differential state:

```text
theta_dot = omega

omega_dot =
-frequency^2 * theta
```

То есть research dynamics — harmonic oscillator.

Default:

```text
theta0 = -0.3 rad
omega0 = +1.2 rad/s
frequency = 4 rad/s
```

Rectangle half extents:

```text
hx = 0.5
hy = 0.3
```

Algebraic center `(cx,cy)` вычисляется из orientation и текущей contact support choice так, чтобы active floor/wall feature constraints выполнялись.

Следовательно:

```text
differential orientation
        ↓
geometry feature selection
        ↓
algebraic center
        ↓
zero contact gaps
```

Acceptance максимальный constraint residual:

`0.0` на tested model.

---

## 4. Orientation-aware feature identity

Local rectangle vertices:

```text
BL = (-hx,-hy)
BR = (+hx,-hy)
TL = (-hx,+hy)
TR = (+hx,+hy)
```

При `theta < 0` active manifold:

```text
floor | vertex:BR
wall  | vertex:BL
```

При `theta > 0`:

```text
floor | vertex:BL
wall  | vertex:TL
```

At exact degeneracy `theta = 0`:

```text
floor | edge:bottom
wall  | edge:left
```

Каждый feature record имеет lineage:

```text
vertex:BR -> [BR]

edge:bottom -> [BL,BR]

edge:left -> [BL,TL]
```

То есть stable physical feature ancestry существует отдельно от transient feature ID.

---

## 5. Same-time manifold event iteration

Когда `theta` пересекает zero, FABRIC0.12 не делает один immediate rename.

Event instant проходит fixed-point iteration.

### Iteration 1

Directed vertex manifold:

```text
vertex contacts
```

переходит в exact degenerate manifold:

```text
edge:bottom
edge:left
```

Это первая topology mutation.

### Iteration 2

Direction of crossing выбирает right-limit support manifold.

Edges переходят в directed post-event vertices.

Это вторая topology mutation.

### Iteration 3

Manifold recompilation не меняет contact IDs.

Fixed point достигнут.

Каждый physical event therefore records:

```text
iterations = 3

topology_mutations = 2

fixed_point = true
```

В main interval два physical event instants.

Итого:

`4 same-time manifold topology mutations`.

---

## 6. Multiple events inside one macro advance

FABRIC0.12 advances:

`duration = 1.2 s`.

Для harmonic oscillator exact zero crossings within interval:

```text
t1 = PI / 16
   = 0.19634954084936...

t2 = 5 PI / 16
   = 0.98174770424681...
```

Adaptive solver локализует **оба** event instants в одном call.

На первом:

```text
negative-side vertices
→
degenerate edges
→
positive-side vertices
```

На втором:

```text
positive-side vertices
→
degenerate edges
→
negative-side vertices
```

То есть одна macro interval содержит:

```text
flow
→ event instant #1
→ manifold fixed point
→ flow
→ event instant #2
→ manifold fixed point
→ flow
```

Это устраняет «first topology-change only» shortcut 0.11 для данного reduced model.

---

## 7. Adaptive integration

FABRIC0.12 использует RK4 step doubling.

Для candidate step `h` считаются:

```text
one full RK4 step

vs

two half RK4 steps
```

Difference делится на RK4 Richardson factor:

`15`.

Normalized error uses:

```text
atol
+
rtol * state scale
```

Если:

`error_norm > 1`

step rejected.

Иначе two-half-step state accepted.

Step size next:

```text
h_next =
h * safety * error^(-1/5)
```

with bounded growth/shrink.

Research defaults include:

- initial step;
- min step;
- max step;
- max accepted/rejected work.

Numerical failures remain observable.

---

## 8. Event localization inside accepted adaptive candidate

Если accepted candidate changes sign of `theta`:

```text
theta_start * theta_end < 0
```

solver does not consume the full candidate.

Instead:

1. bisection on time inside candidate;
2. candidate state reconstructed with two-half RK4;
3. zero crossing localized to `EVENT_TIME_TOLERANCE`;
4. world clock moves exactly to localized event;
5. `theta` is snapped to zero manifold coordinate;
6. `omega` remains physical crossing velocity;
7. same-time manifold iteration reaches fixed point;
8. integration restarts from event state.

Crucial principle preserved from 0.7/0.8/0.11:

> Remaining time is never integrated under stale pre-event manifold semantics.

---

## 9. Convergence under refinement

FABRIC0.11 explicitly showed why tiny bisection tolerance does not prove trajectory accuracy.

FABRIC0.12 therefore tests convergence against analytic event times.

Runs:

```text
atol=rtol=1e-5
1e-7
1e-9
1e-11
```

Maximum event-time errors:

```text
1e-5  -> 1.467192298e-5

1e-7  -> 5.7857693e-7

1e-9  -> 1.525088e-8

1e-11 -> 3.8339e-10
```

Errors strictly decrease.

This is qualitatively different from only decreasing root-search tolerance.

It demonstrates:

```text
refine integration tolerance
→
event trajectory converges
```

for the tested system.

---

## 10. Adaptive work is observable

Accepted step counts:

```text
1e-5  -> 14
1e-7  -> 33
1e-9  -> 68
1e-11 -> 167
```

Rejected steps:

```text
1e-5  -> 2
1e-7  -> 1
1e-9  -> 1
1e-11 -> 2
```

Thus higher accuracy is not free.

FABRIC evidence preserves both accuracy and computational cost.

---

## 11. Energy-convergence audit

Harmonic oscillator energy:

```text
H =
0.5 * omega^2
+
0.5 * frequency^2 * theta^2
```

Main energy drift values decrease under refinement.

Representative:

```text
1e-5  ~ -3.402e-5

1e-7  ~ -6.6837e-7

1e-9  = -7.03302e-9

1e-11 ~ -7.051e-11
```

Therefore adaptive convergence is observable not only in event time but also in a conserved invariant.

FABRIC0.12 does not claim exact symplectic/energy-preserving integration.

RK4 step-doubling remains a generic adaptive research integrator.

---

## 12. Exact 1e-9 gate observations

At `atol=rtol=1e-9`:

```text
event #1 =
0.19634954475054

event #2 =
0.98174771949769
```

Analytic:

```text
0.19634954084936

0.98174770424681
```

Errors:

```text
3.90117e-9

1.525088e-8
```

Adaptive work:

```text
accepted = 68
rejected = 1
```

Energy drift:

`-7.03302e-9`.

State hash:

`a0cad2efa4bed9d598fbaac147f177e11e4d2f4e5c8bac6d9876cec7c8ae3263`.

---

## 13. Feature-lineage warm remap

FABRIC0.10/0.11 remapped warm state when contact ID itself survived.

FABRIC0.12 must handle ID change because the geometric feature itself can split/merge.

Generic rule:

```text
old feature lineage
intersect
new feature lineage
```

on the same support plane.

Each old cached value is distributed among overlapping descendants using normalized lineage-overlap weights.

Important:

> Feature ID can change while physical geometric ancestry remains continuous.

Warm-state mapping therefore follows geometric lineage, not string equality alone.

---

## 14. Main event warm remap

Initial numerical hints:

```text
floor old contact = 2

wall old contact = 3
```

At first zero event:

### Vertex -> edge

```text
floor|vertex:BR
→
floor|edge:bottom

wall|vertex:BL
→
wall|edge:left
```

Lineage preserves values.

Then:

### Edge -> post-event vertex

```text
floor|edge:bottom
→
floor|vertex:BL

wall|edge:left
→
wall|vertex:TL
```

Values remain:

```text
floor = 2
wall = 3
```

Second event performs the reverse lineage path and restores warm state to negative-side support vertices.

---

## 15. Explicit split/merge remap gates

Because the main corner event has one selected descendant per plane, acceptance also exercises generic split/merge explicitly.

### Split

Old:

```text
floor|edge:bottom
lineage=[BL,BR]
warm=4
```

New:

```text
floor|vertex:BL
floor|vertex:BR
```

Result:

```text
2
2
```

### Merge

Old:

```text
floor|vertex:BL warm=2
floor|vertex:BR warm=3
```

New:

```text
floor|edge:bottom
```

Result:

`5`.

This proves the remapper is not hard-coded only for the main directed corner path.

---

## 16. Sparse pattern/preconditioner cache

FABRIC0.11 introduced sparse PCG.

FABRIC0.12 adds explicit numerical pattern cache.

Pattern identity uses:

```text
island id
+
sorted nonzero column structure per sparse row
```

Cache stores:

`inverse diagonal preconditioner`.

It does **not** cache the solved physical vector as truth.

Cold solve:

```text
2 pattern misses
0 hits
```

Second solve on same patterns:

```text
2 hits
0 misses
```

---

## 17. Coefficient change with same sparse pattern

A crucial falsification check:

Matrix coefficients are changed while sparsity pattern remains the same.

Pattern/preconditioner cache still hits.

But solver recomputes the actual new solution.

Observed:

- cache hits remain;
- PCG residuals stay <= `1e-11`;
- result hash changes.

Therefore:

```text
cached preconditioner
=
numerical hint

not
cached physical truth
```

This is the same epistemic separation used earlier for warm impulses.

---

## 18. Actual Thread-based parallel island execution

FABRIC0.11 proved schedule invariance but did not start worker threads.

FABRIC0.12 uses actual Godot `Thread`.

Procedure:

1. tasks canonical-sort by island ID;
2. sparse preconditioner cache prepared sequentially in canonical order;
3. one Thread started per independent task;
4. all threads run pure copied PCG task data;
5. threads joined;
6. results canonical-sort by island ID;
7. canonical result hash computed.

Main test has two independent sparse systems:

`alpha` and `beta`.

Cold parallel solve:

```text
threads_started = 2

cache hits   = 0
cache misses = 2
```

Both PCG solves converge in 3 iterations.

Parallel canonical hash:

`40635ad181b0273659ffd0dacae622b7b7249427d5073c2f9ffb5913f43f7fe0`.

---

## 19. Parallel spawn-order invariance

Second solve reverses thread spawn order.

Cache:

```text
hits = 2
misses = 0
```

Canonical output hash remains exact-identical.

Fresh cache + reverse spawn on original tasks also reproduces cold hash.

Therefore actual concurrent execution has an executable deterministic commit boundary for the demonstrated independent tasks.

This is still **not** a production work-stealing/world scheduler.

---

## 20. Example parallel SPD systems

Task `alpha`:

```text
[4 1 0]
[1 3 1]
[0 1 2]
```

rhs:

`[1,2,3]`.

Exact:

```text
[2/9,
 1/9,
 13/9]
```

Parallel PCG acceptance checks exact-double proximity.

Task `beta` is a second independent SPD sparse system with a different pattern.

Thus parallelism is demonstrated on genuinely independent sparse systems, not two aliases of one result.

---

## 21. Derived sleep / wake

FABRIC0.12 adds a deliberately noncanonical sleep tracker.

Input observables:

- speed metric;
- constraint residual;
- number of consecutive quiet updates.

After 3 quiet updates:

```text
sleeping = true
slept = true
```

Then nonzero motion:

```text
sleeping = false
woke = true
quiet_steps = 0
```

Sleep state is **derived computational state**.

It is not included in FABRIC physical system hash.

This protects the architecture from turning an optimization decision into semantic world truth.

---

## 22. Fail-closed policies

Invalid adaptive contract:

```text
atol <= 0
or
rtol <= 0
or
invalid step bounds
```

returns:

`BAD_ADAPTIVE_OPTIONS`.

Sparse pattern cache with nonpositive matrix diagonal returns:

`PATTERN_NONPOSITIVE_DIAGONAL`.

PCG additionally fails closed on:

- nonpositive curvature;
- breakdown;
- no convergence.

Numerical failure remains observable.

---

## 23. Deterministic replay

A fresh `1e-9` run reproduces:

- two event timestamps;
- same event directions;
- same transition records;
- same warm remap;
- same final state hash.

State hash:

`a0cad2efa4bed9d598fbaac147f177e11e4d2f4e5c8bac6d9876cec7c8ae3263`.

Parallel task output hash:

`40635ad181b0273659ffd0dacae622b7b7249427d5073c2f9ffb5913f43f7fe0`.

---

## 24. Exact validation

Runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Focused acceptance:

`115/115 PASS`.

Acceptance marker:

```text
FABRIC0.12 Adaptive Multi-Event Manifold Acceptance: PASS
```

Playground:

`FABRIC0_12_ADAPTIVE_MULTIEVENT_MANIFOLD_PLAYGROUND_PASS`.

Editor parse/compile/SCRIPT scan:

`CLEAN`.

Executable SHA-256:

```text
solver
7f3630e572ff14deb4c8d480c385fa132fcdaf12725a1cfc72527f30afc8089a

experiments
5dedfbbcfe90be1010e3dfb149b97109c25256058ee2ae794bf853d9ce813f12

acceptance
9f850c79636924e53bd2363e1c46cda34878d0a9379af112c84713543a86ed78

playground
6e6e2a99d30073909113aff9cab9b73161d2dd2247f859fb059f32e9f6773577
```

Git blobs:

```text
solver
d88c5e3a30284985e6bf66328921280fafe6990f

experiments
fb4fa7a9bad103ec61ca466ede56a5713eb3139b

acceptance
59ab0eb3acb8b9cef668716e730ff859bdb05208

playground
16d535693a7f54d3d8de17f453c38f33b8605491
```

Все четыре GitHub branch blobs совпадают с exact-tested local `git hash-object`.

---

## 25. Predecessor evidence policy

В isolated FABRIC0.12 lab materialized FABRIC0.11 runtime suite отсутствовал.

Поэтому runtime regression FABRIC0.11 **не заявляется**.

Вместо этого проверено, что все четыре FABRIC0.11 executable blobs на branch остались byte-identical прежнему v11 evidence:

```text
solver
87647dac2d46836800ba39f0fe098c08e88c5722

experiments
b62ffed0f0657187033bf595321af8e89c8851da

acceptance
49db9e2cf6b6f08eebc219e0c2deddc30f84c900

playground
17e33ad106a9fb54ddde69ba7d620187b4460a47
```

То есть:

```text
predecessor bytes preserved
!=
predecessor runtime regression rerun
```

---

## 26. Что доказано

FABRIC0.12 показывает:

- adaptive error-controlled differential integration;
- event-time error decreases systematically under tolerance refinement;
- energy drift decreases under the same refinement;
- multiple physical event instants are processed inside one macro advance;
- each event instant can iterate several same-time manifold topology mutations to a fixed point;
- orientation selects persistent geometric support features;
- algebraic center maintains exact tested contact constraints;
- feature lineage can remap numerical warm state through ID-changing manifold transitions;
- explicit feature split and merge remap are both demonstrated;
- sparse pattern/preconditioner cache can reuse numerical structure without freezing changed physical coefficients;
- actual Godot Threads execute independent sparse PCG tasks concurrently;
- reverse thread spawn order gives the same canonical result;
- derived sleep/wake can remain outside physical canonical state;
- deterministic event and parallel replay are preserved.

---

## 27. Что НЕ доказано

FABRIC0.12 remains a research falsification model.

It does **not** prove:

- arbitrary 3D rigid-body multi-contact manifold integration;
- that FABRIC0.11 sphere contact graph itself has been converted to adaptive integration;
- full 3D orientation quaternion dynamics;
- arbitrary convex/mesh feature matching;
- robust persistent feature tracking under noisy geometric tolerances;
- simultaneous impacts of multiple dynamic bodies;
- general mixed complementarity event fixed point;
- arbitrary contact branch appearance/disappearance beyond the tested corner manifold;
- conservative distribution of every possible warm dual quantity under feature split/merge;
- production-quality thread pool / work stealing;
- deterministic performance across operating systems/thread schedulers;
- CSR/CSC sparse storage;
- advanced block/IC/multigrid preconditioning;
- production sleep/wake policy;
- production Construction ownership integration;
- authority/persistence/replication integration;
- full materialized DWS regression.

Most importantly:

> FABRIC0.12 demonstrates the semantics in a reduced orientation-aware manifold DAE; it does not yet prove those semantics on the full FABRIC0.11 persistent 3D contact graph.

That is a future integration wall.

---

## 28. Следующий falsification wall

### FABRIC0.13 — UNIFIED ADAPTIVE 3D CONTACT GRAPH

The next step should stop adding isolated mathematical capabilities and integrate the two strongest branches:

```text
FABRIC0.11
persistent sparse 3D contact graph

+

FABRIC0.12
adaptive multi-event manifold semantics
```

Need:

```text
adaptive constrained stepping on persistent body graph
3D orientation / inertia update
persistent multipoint geometric feature manifold
feature split/merge lineage in real contact graph
multiple event fixed-point iteration
sparse pattern reuse across real island topology changes
thread-pool island execution
sleep/wake integrated as derived scheduler state
timestep-refinement convergence of real 3D contact events
```

Critical test:

```text
persistent resting multi-body structure
+
rotating/tumbling incoming body
+
real multipoint geometry

during one large macrostep:

old contacts persist/disappear
+
several new contact features appear
+
islands merge/split

and:

adaptive refinement converges
event time + post state
+
feature warm state remaps
+
parallel/reordered solve gives same canonical physical result
```

---

## 29. Архитектурный вывод

FABRIC0.12 strengthens three principles:

### Numerical convergence is part of evidence

A small root-search tolerance is not sufficient.

Physical claim should survive refinement.

### Contact identity needs lineage, not only equality

Persistent physical relation can move through:

```text
vertex
→ edge
→ another vertex
```

without becoming unrelated history.

### Parallel/cache/sleep remain computational policy

Threads, preconditioners, warm values and sleeping flags may accelerate or schedule the solve.

They do not become canonical semantic owners.

Construction remains the canonical owner above FABRIC.
