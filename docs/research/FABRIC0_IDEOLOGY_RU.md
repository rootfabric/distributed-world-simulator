# FABRIC0 — идеология, парадигмы и архитектурные аксиомы

## 0. Зачем существует эта линия

Distributed World Simulator хочет моделировать мир, в котором игрок или агент может собрать устройство, не предусмотренное разработчиком как отдельный gameplay class.

Обычная архитектура симулятора склонна расти так:

```text
Lamp
Switch
Motor
Generator
Gearbox
Pump
Valve
Door
Furnace
Battery
...
```

Каждый следующий объект получает собственные callbacks и специальные взаимодействия.

Это удобно локально, но плохо масштабируется к миру, где комбинации почти бесконечны.

FABRIC исследует противоположную гипотезу:

> Можно ли найти небольшую физическую грамматику, которая позволяет устройствам возникать как устойчивым patterns композиции?

## 1. Главная онтологическая граница

### Semantic identity != physical execution

Construction отвечает на:

```text
что это за construct?
кому он принадлежит?
из каких частей состоит?
какие persistent identities у частей?
какая его revision/history?
```

FABRIC отвечает на:

```text
какие physical constraints возникают из этой topology?
какие состояния допустимы?
какие flows/reactions следуют из local laws?
как topology влияет на уравнения?
```

Поэтому:

```text
Construction = semantic canonical truth
FABRIC       = derived physical execution fabric
```

Это нельзя смешивать.

## 2. Объект не должен быть обязательной единицей поведения

Фундаментальная мысль:

> Объект может быть именем, интерфейсом или семантическим prefab, но физическое поведение не обязано принадлежать объектному классу.

В идеальном FABRIC:

```text
"motor"
=
pattern(
  electrical port,
  power-preserving relation,
  rotational port,
  storage,
  losses,
  topology
)
```

а не:

```text
class Motor:
    apply_torque()
    consume_current()
```

## 3. Port — фундаментальная поверхность композиции

Physical Port — место, где construct проявляет сопряжённые физические величины.

Не обычный message channel.

Physical port должен позволять:

- reaction;
- role reversal;
- conservation;
- topology-derived equations;
- bidirectional energy exchange.

В data/control domain directed input/output остаётся нормальным.

Но physical topology acausal.

## 4. Domain — не тип устройства, а энергетический контракт

Domain задаёт пару:

```text
common_quantity
balance_quantity
```

и обязательный инвариант:

```text
common * balance = power
```

Примеры:

```text
electrical:
  voltage * current

rotational:
  angular_velocity * torque

translational:
  velocity * force

fluid:
  pressure * volume_flow
```

Это позволяет solver быть domain-neutral.

## 5. Topology сама становится программой

Ключевой поворот FABRIC0.3:

> Bond topology не просто хранит список соединений. Она компилируется в физическую систему equations.

Connected physical ports образуют Conservation Cell.

Для cell:

```text
common_1 = common_2 = ...
sum(balance_i)=0
```

Следовательно идеальная cell сама сохраняет power.

Разрыв bond меняет equation topology без device-specific rebuild callback.

## 6. Source и sink — роли состояния, не классы

Local equilibrium law:

```text
balance = response_gain * (preferred_common - common)
```

может отдавать или поглощать поток в зависимости от solved common.

Поэтому один элемент способен менять роль:

```text
source → consumer
motor → generator
```

без смены класса.

Это принцип emergent role.

## 7. Power-preserving relation выше domain

FABRIC0.4 ввёл Power Map:

```text
Aq = 0
b = -A^T lambda
```

Отсюда:

```text
q^T b = 0
```

Power preservation становится свойством constraint geometry.

Один primitive выразил:

- electromechanical transduction;
- reverse generation;
- differential-like kinematics.

Это сильнее device-specific transformer.

## 8. Stored state должен быть generic

Storage не должен быть только Inertia или Capacitor.

Общая идея:

```text
state
energy
constitutive storage relation
integration policy
```

Конкретная семантика возникает из domain + parameter dimensions.

Численный интегратор обязан отдельно показывать numerical dissipation.

## 9. Dimensions — исполняемая физическая типизация

Units/dimensions не комментарий.

FABRIC0.5 использует SI base-dimension exponent algebra.

Проверяются:

- power-conjugacy domain;
- add/sub compatibility;
- transcendental dimensionless arguments;
- Power Map coefficient dimensions;
- reset/flow dimensions в будущей hybrid-time модели.

Принцип:

> Dimension error — compile-time physical type error.

## 10. Constitutive law — residual, не алгоритм

Вместо:

```text
device.update()
```

используется:

```text
F(common, balance, state, parameters)=0
```

Это даёт:

- acausal composition;
- единый island solve;
- automatic differentiation;
- роль реакции как неизвестной;
- возможность nonlinear laws.

## 11. Производная принадлежит математике закона

Ручной Jacobian легко рассинхронизировать с residual.

Поэтому expression tree распространяет value + gradient.

Принцип:

> Law и derivative должны иметь один источник истины.

## 12. Нулевой residual ещё не означает физическое решение

Очень важный урок FABRIC0.5.

Если:

```text
F(x)=0
```

но tangent Jacobian rank-deficient, состояние может быть недоопределённым.

Поэтому acceptance:

```text
small residual
AND
locally determined solution manifold
```

Floating physics должна fail-closed.

## 13. Nonsmooth physics — union of manifolds

FABRIC0.6:

```text
HybridRelation
=
union(branch_i)
```

где branch:

```text
residuals=0
inequalities>=0
```

Complementarity:

```text
a>=0 ⟂ b>=0
```

компилируется в union:

```text
a=0,b>=0
OR
b=0,a>=0
```

Преимущество: dimensions `a` и `b` не смешиваются.

## 14. Contact/friction должны быть законами допустимости

Contact не обязан быть callback collision engine.

Friction не обязана быть procedural clamp.

Они могут быть set-valued physical relations:

```text
contact:
  open OR closed manifold

friction:
  stick OR slide+ OR slide-
```

Solver выбирает admissible branch из общей системы.

## 15. Discrete state — часть физической истории

Если branch меняется:

```text
stick → slide
open → closed
blocked → conducting
```

это causal event.

Его нужно:

- идентифицировать;
- детерминированно воспроизводить;
- хранить в истории;
- в будущем синхронизировать/реплицировать через существующие authority boundaries.

## 16. Время нельзя моделировать только большими шагами

FABRIC0.7 должен придерживаться:

> Событие происходит в физический момент crossing, а не «в конце кадра, где мы заметили условие».

Поэтому нужен event localization внутри timestep.

Макро-шаг:

```text
t0 ---------------- t1
          ^
       event
```

должен быть разбит:

```text
flow t0→te
jump/reset at te
flow te→t1
```

## 17. Reset — одновременное отображение pre-state → post-state

Reset map нельзя исполнять строка за строкой с побочными эффектами.

Все RHS должны вычисляться из одного pre-event snapshot.

Потом все assignments commit одновременно.

Это исключает order dependence.

## 18. Topology mutation — транзакция

Break/fuse/latch могут менять bonds.

Нельзя:

```text
disable bond A
fail on bond B
leave half-applied topology
```

Нужно:

```text
validate entire topology transaction
then commit all
or commit nothing
```

## 19. Event identity должна быть детерминированной

Для persistent/distributed world событие должно иметь:

- sequence;
- transition identity;
- event time;
- pre-state identity/hash;
- post-state identity/hash;
- topology revision;
- deterministic ordering.

Это будущий мост к time identity / action identity / observed-state identity, но FABRIC пока не владеет network authority.

## 20. Нужна защита от Zeno/event storms

Hybrid systems могут генерировать бесконечно много jumps за конечное время.

Research solver должен иметь cap и fail-closed diagnostic.

Нельзя зависнуть.

Нельзя молча потерять события.

## 21. Prefab — шаблон графа, не магический behavior owner

Будущий prefab может сказать:

```text
создай такие elements
такие ports
такие bonds
такие parameters
```

Но его поведение должно происходить из FABRIC laws.

Prefab name может быть `motor`.

Kernel class `Motor` для этого не требуется.

## 22. Unknown Machine Test

Ключевой falsification test FABRIC:

> Может ли новый механизм, которого мы не закладывали как класс, быть выражен только существующей grammar?

Хорошие примеры уже получены:

- motor/generator duality;
- differential;
- same one-way relation in 3 domains;
- exact stick/slip.

Следующие unknown-machine tests должны комбинировать stateful events и topology mutation.

## 23. Красота не является достаточным доказательством

FABRIC должен сохранять инженерную скромность.

Каждый design note обязан иметь:

```text
what is proven
what is not proven
what failed
what was deliberately postponed
```

## 24. Отвергнутые направления

### Device-class proliferation

Отвергнуто как основная физическая архитектура.

### Directed physical signal graph

Подходит для control/data, но недостаточен для reaction/conservation.

### Hidden unit conversions

Запрещены dimension contract.

### One scalar NCP function regardless of units

Не принят как canonical representation; branch manifolds сохраняют dimensions раздельно.

### Heuristic repair of singular physics

Запрещён.

### Pretending numerical loss is physical

Запрещено.

### Rewriting predecessor solvers in-place

Исторические research implementations сохраняются как immutable evidence; successor создаётся отдельно.

## 25. Дух разработки

Не стремиться быстро собрать полный «движок физики».

Каждый checkpoint должен атаковать **один фундаментальный барьер** и пытаться сломать гипотезу.

Если гипотеза переживает новый тип сложности без появления device-specific exceptions — это meaningful evidence.

FABRIC строится не от списка фич, а от последовательности falsification walls.


## 26. FABRIC0.7 подтвердил temporal triad

После реализации FABRIC0.7 прежние пункты о времени перестали быть только design намерением.

Экспериментально подтверждена триада:

```text
FLOW
JUMP
TOPOLOGY TRANSACTION
```

Это теперь одна из центральных аксиом FABRIC.

### FLOW

Изменяет continuous state во времени.

Не меняет discrete mode сам по себе.

### JUMP

Происходит в локализованный event instant.

Имеет immutable pre-state и explicit post-state.

### TOPOLOGY TRANSACTION

Изменяет структуру physical graph.

Обязана быть atomic.

Эти категории имеют разную семантику causal history, поэтому kernel не должен снова склеить их в общий `update()`.

## 27. Macrostep должен быть rollback boundary

FABRIC0.7 показал практически важный принцип:

> Временной macrostep является транзакционной recovery unit.

Если event jump не может быть корректно завершён, нельзя сохранять flow, который привёл к событию, оставив неисполненный jump.

Поэтому текущая research semantics:

```text
advance(dt)
=
all committed
OR
initial macrostep state restored
```

В production граница snapshot может быть оптимизирована через journal/delta transactions, но semantic atomicity должна сохраниться.

## 28. Event time является физическим state coordinate

Event timestamp не является telemetry metadata.

Он определяет:

- какой pre-state участвует в reset;
- сколько remaining flow остаётся;
- порядок причинных событий;
- будущую reproducibility/authority semantics.

Поэтому event localization является частью физической корректности.

## 29. Reset map является математическим отображением, не script body

Правильная модель:

```text
R : pre_state -> post_state
```

а не последовательность mutable statements.

Это позволяет:

- order-independent assignments;
- deterministic replay;
- validation до commit;
- будущую symbolic/dimension analysis.

## 30. History-dependent behavior не требует device class

Schmitt experiment подтвердил:

```text
same continuous variable
+
discrete mode
+
different event surfaces
=
hysteresis
```

То есть память устройства может быть состоянием общей hybrid grammar.

## 31. Failure может быть topology, а не флагом объекта

Breaker experiment подтвердил важный архитектурный сдвиг.

Failure не обязательно:

```text
device.broken = true
```

Он может быть:

```text
continuous degradation
→ event
→ mode transition
→ topology transaction
```

Это особенно важно для будущих:

- fuse;
- structural bond break;
- latch release;
- cable failure;
- material yield/failure.

## 32. FABRIC0.7 выявил новую границу композиции

До 0.7 FABRIC постепенно унифицировал:

```text
topology
algebraic constraints
energy
dimensions
nonlinear laws
nonsmooth modes
```

0.7 добавил time, но temporal solver пока не является одним solver с algebraic fabric.

Следующая красивая архитектура должна не строить «ODE subsystem рядом с circuit/contact subsystem», а приблизиться к:

```text
hybrid DAE fabric
=
continuous differential state
+
algebraic conservation constraints
+
nonsmooth admissible manifolds
+
event surfaces
+
jump maps
+
mutable topology
```

Это текущий главный исследовательский горизонт.

## 33. Сила FABRIC измеряется исчезновением special cases

Каждый следующий checkpoint оценивается не числом добавленных behaviors, а тем, сколько разных явлений выразил один общий primitive.

Хороший результат:

```text
one law
→ many recognizable machines
```

Плохой результат:

```text
one new behavior
→ one new kernel class
```

Этот критерий должен сохраняться при FABRIC0.8 и далее.


## 34. Differential и algebraic state — один физический timestep problem

FABRIC0.8 подтвердил новую аксиому:

> Reaction, которая влияет на trajectory, не должна вычисляться после движения. Она должна участвовать в вычислении derivative.

Поэтому правильная форма:

```text
solve F(x,y)=0
then evaluate xdot=f(x,y)
```

на каждой integration stage.

Это сохраняет causal связь между constraints/reactions и continuous motion.

## 35. Topology — вход математической программы

Bond active/inactive больше нельзя считать только metadata.

Topology определяет active equation structure.

FABRIC0.8 экспериментально показал:

```text
bond changes
→ algebraic equation changes
→ solved reaction changes
→ future trajectory changes
```

Следовательно topology mutation должна приводить к recompile/re-solve physics до продвижения времени.

## 36. Impulse — reaction integrated across jump

В continuous physics constraint reaction выражается force/flow balance.

В impact jump аналогичная роль принадлежит impulse.

Не:

```text
object.apply_impulse(value)
```

а:

```text
solve impulse as unknown
subject to
momentum + restitution + friction constraints
```

Это сохраняет device-agnostic grammar через continuous и discontinuous regimes.

## 37. Event instant — это вычисление fixed point

FABRIC0.7 ввёл localized jump.

FABRIC0.8 уточнил:

> Один timestamp не обязательно означает один transition.

Jump может изменить state; state может активировать condition; condition может изменить topology; topology меняет algebraics; algebraics могут изменить новые guards.

Поэтому event instant — локальный iteration problem:

```text
solve
→ transition
→ re-solve
→ transition
→ re-solve
→ fixed point
```

Только после fixed point continuous time может продолжиться.

## 38. Conservation audit через jump отделён от power audit во flow

Continuous power relation:

```text
common * balance = power
```

не надо механически переносить на instantaneous impact, где natural integrated quantity — impulse.

Для jump важны отдельные invariants:

- linear/angular momentum balance;
- restitution law;
- friction admissibility;
- noncreation of energy при dissipative law.

FABRIC должен иметь explicit audit semantics для flow и jump, а не одну универсальную числовую проверку.

## 39. Geometry должна стать генератором constraints, а не владельцем поведения

FABRIC0.8 пока вручную задаёт scalar gap.

Следующий шаг должен сделать:

```text
geometry
→ contact manifold
→ Jacobians
→ generic constraints
→ solve
```

а не:

```text
CollisionObject
→ special collision callback
```

Geometry сообщает, где constraint возникает. Solver определяет reaction.

## 40. Order invariance — новый критерий физической истины

Для multi-contact мира порядок обхода contacts является implementation detail.

Если:

```text
[A,B,C]
```

и:

```text
[C,A,B]
```

дают разные physical state при той же topology/geometry, это numerical/architectural defect, а не допустимая semantics.

FABRIC0.9 должен сделать order-invariance явным acceptance criterion.

## 41. Текущий образ FABRIC

После FABRIC0.8 наиболее точный образ уже не:

```text
collection of generic components
```

а:

> compiler of mutable semantic/physical topology into a dimension-aware hybrid differential-algebraic program with explicit continuous flows, reactions, jumps and structural transactions.

Это остаётся research hypothesis. Production promotion требует масштабирования, ownership integration и гораздо более тяжёлых unknown-machine tests.


## 42. Geometry генерирует constraints; solver владеет reaction solve

FABRIC0.9 превратил прежний design principle в executable evidence.

Правильная граница:

~~~text
geometry
→ manifold
→ Jacobians
→ constraints
→ solve reactions
~~~

Geometry не должна владеть device-specific collision behavior.

## 43. Contact space является локальной физической системой координат

Каждый contact должен иметь:

~~~text
normal
+
tangent basis
~~~

Friction является ограничением в этом contact space, а не набором world-axis hacks.

В 3D:

~~~text
(j_n, j_t1, j_t2)
~~~

является более фундаментальной формой, чем friction_x / friction_z.

## 44. Coulomb friction — геометрия admissible reaction set

FABRIC0.9 использует:

~~~text
||j_t|| <= mu*j_n
~~~

как cone.

Это важная смена мышления:

> Friction law — не procedural clamp, а геометрия множества допустимых reactions.

Stick/sliding могут возникать как interior/boundary cone state.

## 45. Multi-contact надо решать globally

Если несколько contacts принадлежат одному rigid-body/contact island, последовательный object order не должен становиться частью физики.

Новая аксиома:

> Сначала собрать coupled problem; затем решить его. Не решать physical truth callback-за-callback.

Local iterative numerical method допустим только если его result semantics инвариантна к input enumeration или эта зависимость явно признана approximation.

## 46. Order invariance — обязательный falsification gate

После 0.9 любое multi-contact/multi-body checkpoint должен проверять permutations.

Минимально:

~~~text
same geometry/topology
different enumeration
→ same canonical physical observables
~~~

Если нет — solver implementation detail просочился в world semantics.

## 47. Deterministic не означает unique

Это один из важнейших уроков 0.9.

Redundant contact manifold может иметь много reaction vectors, дающих один и тот же generalized motion.

Поэтому:

~~~text
canonical algorithm
+ stable sorting
+ deterministic initial state
=
deterministic representative
~~~

но не:

~~~text
proof of unique physical reaction distribution
~~~

Для persistent world canonicalization должна применяться осторожно.

Можно канонизировать representation, не объявляя внутреннюю gauge-like variable фундаментальной сущностью.

## 48. Physical observables имеют уровни значимости

При redundant contact solve полезно различать:

### Strong observables

- body generalized state;
- total impulse/momentum change;
- total torque impulse;
- contact admissibility;
- topology/mode changes;
- conservation/dissipation audit.

### Internal solve evidence

- конкретное распределение impulse между redundant contact coordinates;
- dual/ADMM variables;
- numerical splitting state.

Не всё, что solver вычисляет, обязано становиться persistent canonical state.

## 49. Numerical parameters не являются physics

ADMM rho, iteration count, factorization strategy и warm-start policy — numerical machinery.

Они не должны менять declared physical laws.

Если изменение numerical parameter materially меняет accepted physical observable, это diagnostic повод проверить convergence/conditioning/model ambiguity.

## 50. Contact identity нужна не только deterministic sorting

Stable identity станет фундаментом для:

- contact lifecycle;
- warm start;
- event correlation;
- historical evidence;
- sparse island caching;
- deterministic distributed replay.

Но identity должна происходить из stable geometry/semantic features, а не из transient array index.

## 51. Следующая зрелая форма — persistent contact graph

После 0.9 contact нельзя рассматривать только как мгновенный impact record.

Нужен graph:

~~~text
bodies
↕ contacts
bodies
~~~

с lifecycle:

~~~text
appear
persist
change mode
disappear
~~~

и decomposition:

~~~text
global world
→ independent contact islands
→ local sparse solves
~~~

Это главный путь FABRIC0.10.


## 52. Contact является persistent relation, а не transient callback

FABRIC0.10 подтверждает:

> Если физическая связь живёт между timesteps, её identity и lifecycle должны существовать отдельно от конкретного solver invocation.

Contact может:

```text
appear
persist
change reaction/mode
disappear
```

Это causal history.

## 53. Contact identity и numerical cache — разные уровни истины

Stable contact identity имеет physical/history смысл.

Previous impulse warm cache — numerical continuity.

Поэтому:

```text
contact identity
!=
warm-start value
```

Identity может участвовать в history/replay.

Warm impulse не должен автоматически становиться canonical semantic state.

## 54. Warm start следует relation identity, а не solver partition

Islands могут merge/split.

Если contact продолжает существовать, его numerical continuity не должна исчезать только потому, что поменялся island id.

Новая аксиома:

> Persistent numerical hints привязываются к stable physical relation identity, а не transient computational partition.

## 55. Static boundary не является dynamic graph connectivity

Shared floor не должен связывать все resting objects в один global island.

Static environment задаёт boundary constraints.

Dynamic graph connectivity возникает от relations между dynamic DOF sets.

Это фундаментально для world-scale locality.

## 56. Island decomposition — не только optimization

FABRIC0.10 проверяет independent-island equivalence:

```text
unrelated island mutations
do not change local trajectory
```

Следовательно island decomposition выражает physical conditional independence, а не только performance trick.

## 57. Sparse structure должна следовать topology

Contact graph sparse.

Jacobian sparse.

Effective-mass coupling sparse/block-local.

Правильная numerical architecture должна сохранять эту sparsity как можно глубже.

FABRIC0.10 пока только:

```text
sparse assembly
→ dense island-local factorization
```

Это переходный checkpoint.

Нельзя объявлять его full sparse backend.

## 58. Lifecycle events являются частью causal evidence

```text
appeared
persisted
disappeared
```

не просто debugging labels.

Они важны для:

- event history;
- warm-start remap;
- persistence;
- future replication;
- explainability;
- deterministic replay.

При production integration они должны стыковаться с уже существующими authority/time identity foundations, а не создавать второй owner.

## 59. Persistent resting contact отличается от impact

Impact law и resting constraint используют одну reaction grammar, но разные temporal regimes.

Impact:

```text
finite impulse across jump
```

Resting contact:

```text
repeated constrained time steps
supporting load
```

Нельзя считать, что хороший impact solve автоматически доказывает долгосрочную resting stability.

FABRIC0.10 впервые проверяет второй режим отдельно.

## 60. Event time и persistent graph должны быть одной будущей semantics

FABRIC0.10 event bridge показывает правильную causal форму:

```text
continuous flow
→ exact geometry crossing
→ contact appears at te
→ graph recompile
→ constrained remaining flow
```

Но contact-free precondition показывает, что temporal и persistent graph solvers ещё не полностью слиты.

Следующий mature form должна локализовать new events, пока old islands остаются constrained.

## 61. Fail-closed limitation лучше ложной универсальности

Если architecture ещё не умеет корректно локализовать event внутри already-constrained world, правильный результат:

`EVENT_BRIDGE_REQUIRES_CONTACT_FREE_START`.

Неправильный:

- временно отключить old contacts;
- snap event к frame end;
- silently penetrate;
- приблизительно «починить» topology после шага.

FABRIC должен сохранять epistemic honesty даже ценой narrower API.

## 62. Computational partitions не являются semantic owners

Island ID, sparse matrix layout, Cholesky ordering, ADMM dual state — implementation structures.

Они не должны становиться владельцами semantic construct/contact truth.

Canonical semantic ownership остаётся выше в Construction и stable physical relation identities.

## 63. Текущий образ contact fabric

После FABRIC0.10:

```text
geometry
→ stable contact relations
→ persistent contact graph
→ dynamic islands
→ sparse constraint assembly
→ warm-started nonsmooth solve
→ physical state
→ lifecycle history
```

Это уже похоже на долгоживущую physical substrate, но всё ещё research-only.

Следующая проверка — сможет ли эта форма пережить event-localized graph merge при уже активных contacts.


## 64. Event localization не имеет права временно отменять существующую физику

Если macrostep начинается с active constraints, candidate trajectory для event search обязана учитывать эти constraints.

Неправильно:

```text
disable old contacts
→ find new collision
→ restore old contacts
```

Правильно:

```text
old constrained graph
→ constrained candidate flow
→ topology predicate
→ localized event
```

FABRIC0.11 делает этот принцип executable.

## 65. У event localization есть несколько уровней точности

Нельзя одной цифрой описывать всю accuracy.

Минимально различаются:

### Root-search tolerance

Насколько точно найден crossing **данной trajectory**.

### Integration error

Насколько сама trajectory близка к continuous physical solution.

### Constitutive/contact solve error

Насколько точно решены algebraic/nonsmooth constraints.

Поэтому:

```text
bisection 1e-11
```

не означает:

```text
physical event time accurate to 1e-11
```

если time integrator использует coarse substeps.

Это теперь hard documentation rule.

## 66. Sparse topology должна оставаться sparse through numerical solve

Недостаточно хранить graph sparse, а затем делать:

```text
compile sparse
→ densify everything
```

как постоянную архитектуру.

FABRIC0.11 закрепляет целевую форму:

```text
sparse graph
→ sparse Jacobian
→ sparse effective mass
→ sparse matvec / solve
```

Current PCG — research backend, но boundary теперь правильная.

## 67. Preconditioner является numerical policy, не physical law

Jacobi PCG chosen in 0.11.

Future можно заменить на:

- block Jacobi;
- incomplete Cholesky;
- multigrid;
- domain decomposition.

Если converged physical observables сохраняются, это numerical implementation choice.

Preconditioner state не становится canonical world state.

## 68. Event-time graph mutation требует warm-state remap до продолжения времени

Если persistent contacts пережили graph merge:

```text
identity preserved
→ numerical continuity may be preserved
```

New contacts:

```text
new identity
→ cold numerical state
```

Это должно происходить в event instant, до remaining flow.

## 69. Same-time graph recompile является physical transaction boundary

New geometry relation может изменить contact island membership без продвижения clock.

Поэтому:

```text
te:
detect
→ compile
→ remap
→ solve
→ commit
```

является одной causal event transaction.

Solver не должен продвинуть `t`, а затем поздно «заметить» новый island.

## 70. Parallelism разрешён только после доказательства schedule invariance

Independent islands естественно parallelizable.

Но actual parallel implementation нельзя считать semantic-neutral автоматически.

Перед parallel workers нужен gate:

```text
forward schedule
reverse schedule
other valid schedules
→ same accepted state
```

FABRIC0.11 доказал prerequisite, но actual threads ещё не реализует.

## 71. Solver iteration history является evidence, а не world state

PCG calls, ADMM iterations, residual histories полезны как:

- observability;
- numerical regression;
- performance evidence;
- conditioning diagnostics.

Но это не physical canonical state.

Два backend implementation могут иметь разный iteration count и одинаковый accepted physical solution.

## 72. Fail-closed на unsupported multi-event topology лучше sequential guess

0.11 fail-closed, если old contact disappears during current new-event search.

Это правильно до появления general event iteration.

Нельзя silently решить:

```text
first array event
then second array event
```

если mathematical result может зависеть от такого порядка.

## 73. Следующая цель — convergence, а не ещё более маленькая bisection tolerance

После 0.11 bottleneck event accuracy — не root finder.

Он — constrained integration.

Поэтому FABRIC0.12 должен проверять:

```text
refine time integration
→ event time converges
→ post-event state converges
```

а не просто уменьшать `EVENT_TIME_TOLERANCE`.

## 74. Текущая temporal-contact форма

После FABRIC0.11:

```text
persistent constrained graph
→ sparse constrained flow
→ event localization
→ same-time graph mutation
→ sparse reaction solve
→ remaining constrained flow
```

Это уже единая research causal path.

Следующая зрелость требует adaptive multi-event manifold semantics.


## 75. Convergence under refinement является частью physical evidence

FABRIC0.11 показал, что tiny event-root tolerance может сосуществовать с coarse trajectory error.

FABRIC0.12 therefore adds a stronger rule:

> Если observable physical result зависит от numerical resolution, checkpoint должен показывать convergence under systematic refinement или честно объявлять отсутствие convergence evidence.

Не достаточно:

```text
solver residual small
```

Нужно смотреть:

```text
refine integration
→ physical observable converges
```

где это возможно.

## 76. Error budget нужно раскладывать по источникам

Минимально:

- integration truncation error;
- event localization error;
- algebraic/contact solve error;
- geometric feature tolerance;
- iterative linear-solve error;
- floating-point roundoff.

Одна цифра `tolerance` не описывает correctness мира.

FABRIC docs/evidence должны сохранять это decomposition.

## 77. Same-time manifold event может требовать topology fixed point

At degenerate geometry exact contact set может быть neither left-limit nor right-limit manifold.

Поэтому event semantics может требовать:

```text
pre manifold
→ degenerate manifold
→ directed/post manifold
→ recompile
→ fixed point
```

Это не лишняя procedural сложность.

Это physical consequence geometry degeneracy.

## 78. Feature identity является lineage graph, а не только stable string

Stable exact ID works while same feature survives.

Но real geometry can:

```text
vertex
→ edge
→ face

or

face
→ several child features
```

Persistent relation identity therefore needs ancestry/overlap semantics.

String equality is one special case of identity continuity.

## 79. Warm-state remap должен быть conservative where the quantity permits it

Если numerical hint represents an additive reaction-like quantity and one feature splits, preserving total value across descendants is a useful default research contract.

If features merge, compatible child values can aggregate.

Но не every solver variable is additive.

Therefore lineage remap policy must be quantity-aware in future systems.

0.12 demonstrates only scalar additive warm hints.

## 80. Cache key describes numerical structure, not physics

Sparse pattern cache may key on:

```text
island identity
+
nonzero matrix structure
```

Coefficient values can change while pattern stays same.

Therefore cache hit means:

```text
reuse numerical preparation
```

not:

```text
reuse solved physical answer
```

FABRIC0.12 explicitly verifies result changes under coefficient change.

## 81. Real concurrency needs deterministic prepare and commit boundaries

Actual worker threads introduce nondeterministic completion order.

Physical semantics must not follow finish order.

Research contract:

```text
canonical prepare
→ concurrent solve
→ join
→ canonical commit/order
```

Threads can race in wall-clock completion, but not in semantic commit.

## 82. Parallel reproducibility не означает deterministic performance

FABRIC can require deterministic physical output.

It should not claim:

- same thread scheduling;
- same solve duration;
- same cache timing;
- same OS wake order.

Performance nondeterminism is compatible with physical determinism if computational state remains separated.

## 83. Sleep/wake — derived scheduler state

Sleeping object/island is not physically frozen because «sleep=true is world truth».

Instead:

```text
physical observables satisfy quiet criteria
→ scheduler may skip/reduce work
```

Any physical stimulus must wake/revalidate it.

Sleep should remain reconstructible from physical state/history or disposable without changing canonical truth.

## 84. Reduced models are legitimate falsification tools only with explicit scope

A simplified model can isolate one architecture question better than the whole engine.

Но запрещено делать:

```text
reduced proof
→ silently claim full 3D production property
```

FABRIC0.12 explicitly proves adaptive/manifold semantics in reduced orientation-aware geometry.

The full 3D persistent contact integration remains open.

## 85. Analytical references are gold when available

For synthetic research laws where exact solution exists, acceptance should use it.

Analytic zero crossings in 0.12 give much stronger evidence than comparing one numerical run with another.

When exact reference unavailable, future checkpoints should use:

- refinement studies;
- invariant audits;
- cross-method comparison;
- manufactured solutions.

## 86. Multiple events must restart time integration from each event fixed point

Wrong:

```text
take large candidate step
find event A
record it
continue using end state from pre-event candidate
```

Right:

```text
localize A
→ event fixed point
→ restart flow
→ later discover B
```

FABRIC0.12 processes two physical event instants this way.

## 87. Adaptive work itself is evidence

More accurate physical answer can require more accepted/rejected steps.

Therefore validation should preserve:

- accepted steps;
- rejected steps;
- min/max step;
- solver work;
- event localization iterations.

Performance is not separate from numerical architecture.

## 88. Unified integration is now the next architectural test

FABRIC has two strong but partially separate lines:

### Full contact graph line

0.9–0.11:

```text
persistent sparse multi-body contacts
event-time graph mutation
PCG
```

### Adaptive manifold line

0.12:

```text
adaptive convergence
multiple events
feature lineage
actual threads
```

Next architecture must combine them.

If they cannot be combined cleanly, the abstraction boundary is incomplete.

## 89. Текущий образ FABRIC после 0.12

```text
semantic topology
→ physical relation graph
→ dimension/law compilation
→ adaptive hybrid DAE flow
→ geometry manifold events
→ lineage-preserving topology iteration
→ sparse parallel numerical execution
→ causal evidence/history
```

This remains a research hypothesis.

Production ownership stays with Construction.


## 90. Integration of proven research lines is itself a falsification gate

Separate checkpoints can each be locally convincing and still be mutually incompatible.

Therefore:

```text
A works
+
B works
```

does not imply:

```text
A+B works
```

FABRIC0.13 treats integration as a first-class scientific test.

If convergence, identity or conservation discipline disappears after composition, the architecture is incomplete.

## 91. Convergence must survive topology mutation, not only smooth flow

Adaptive convergence evidence is stronger when the refined trajectory crosses:

- impact;
- graph merge;
- velocity projection;
- manifold feature mutation;
- sparse solve.

A smooth-only convergence test cannot validate a hybrid contact architecture.

FABRIC0.13 therefore compares both event times and final state after multiple topology events.

## 92. Persistent support history must survive island merge

When a new body joins an already constrained graph:

```text
old relation identity survives
→ old relation-local numerical continuity may survive
```

The new island is not a replacement universe.

Graph merge should preserve history for relations whose physical identity did not disappear.

## 93. Rotational geometry must enter the constraint Jacobian

If contact location depends on orientation, solving translation while using rotation only for rendering/feature labels is incomplete.

The local law needs sensitivity such as:

```text
dr / dtheta
```

inside `J`.

For acceleration-level constraints, geometry curvature may also contribute:

```text
d2r/dtheta2 * omega^2
```

This is a general lesson beyond the specific 0.13 one-axis stand.

## 94. Multipoint feature changes belong to the topology transaction layer

An edge becoming a face and then another edge is not merely a numerical row-count resize.

It changes persistent physical feature identity.

Therefore the event transaction must own:

```text
detect
→ feature topology compile
→ lineage remap
→ reaction/velocity solve
→ fixed point
→ commit
```

Sparse matrix resizing is a consequence, not the semantic event itself.

## 95. Exact-byte evidence includes formatting bytes

If validation records:

```text
SHA-256
git blob SHA
remote byte identity
```

then the evidence object is the exact byte stream.

A trailing newline is therefore material to that evidence claim.

This does not make source formatting physical truth.

It makes repository reproducibility exact.

Rule:

> Do not say remote/local bytes are identical until the repository blob hash actually matches the tested local blob hash.

## 96. Thread audits must not mutate physical state as a side effect

Parallel solver experiments should consume an explicit snapshot or copied task data.

A diagnostic parallel solve that changes canonical world state would mix:

- performance test;
- physical transaction.

FABRIC0.13 verifies that parallel island audit leaves physical world hash unchanged.

## 97. Quaternion representation is not equivalent to general 6DOF dynamics

A normalized quaternion proves a representation invariant.

It does not prove:

- three-axis angular velocity integration;
- inertia tensor coupling;
- gyroscopic term;
- arbitrary-axis contact reaction;
- robust normalization under long trajectories.

Claims must state which rotational degrees of freedom were actually exercised.

## 98. Algebraic projection is legitimate only when documented as a reduced boundary

Research stands may project known support coordinates to isolate another question.

But then one must not claim:

```text
fully free rigid body
```

FABRIC0.13 partially projects A/B support coordinates.

This is explicitly a research simplification.

The next checkpoint must remove more of it.

## 99. Contact force positivity is an evidence observable, not sufficient unilateral semantics

Seeing positive normal reactions along an accepted trajectory is useful.

It can catch a bad constrained solution.

But:

```text
lambda > 0 in one trajectory
```

does not replace general unilateral complementarity:

```text
gap >= 0
lambda >= 0
gap * lambda = 0
```

FABRIC0.14 must restore the stronger nonsmooth law in the unified adaptive path.

## 100. The next frontier should remove physical simplifications, not add ornamental infrastructure

After 0.13 the architecture already has:

- persistent relations;
- adaptive events;
- lineage;
- sparse PCG;
- parallel boundary;
- recovery/evidence.

The biggest unknowns are now physical:

```text
full 6DOF
+
inertia tensor
+
unilateral normal contact
+
Coulomb friction
+
general convex feature manifolds
```

Therefore 0.14 should prioritize those rather than another isolated scheduler/cache abstraction.

## 101. Текущий образ FABRIC после 0.13

```text
Construction semantic truth
        ↓
persistent physical relation graph
        ↓
adaptive constrained DAE flow
        ↓
event-time graph merge/split
        ↓
orientation-sensitive multipoint feature topology
        ↓
lineage-preserving manifold fixed point
        ↓
sparse parallel numerical solve
        ↓
canonical causal physical history
```

This is now one integrated research path rather than two separate demonstrations.

Production ownership still remains with Construction.


## 102. Coordinate frame is part of the executable physics contract

A solver can be algebraically correct and physically wrong if its coordinate convention is implicit or inconsistent.

FABRIC0.14 exposed this through a real bug:

```text
Godot UP = Y

research world UP = Z
```

The wrong plane normal produced impossible geometry and artificial energy gain.

Therefore every physical subsystem must make explicit:

- world up axis;
- handedness;
- frame in which inertia/material tensors live;
- frame in which contact normals/tangents are expressed;
- conversions between body and world frames.

## 103. Invariant failure should be treated as a search for missing semantics

When a discrepancy does not shrink under refinement:

```text
refine timestep
→ discrepancy stays
```

the default hypothesis should not be “need even smaller tolerance”.

Likely classes of cause include:

- missing jump;
- wrong frame;
- wrong sign;
- missing work term;
- hidden projection;
- incorrect topology semantics.

FABRIC0.14 used this discipline twice.

## 104. Numerical projection cannot hide a physical impulse

A projection that changes velocity changes momentum.

Therefore:

```text
velocity projection with momentum change
=
physical jump
```

It must have:

- event identity;
- impulse value;
- momentum audit;
- energy audit;
- causal ordering.

Projection is allowed only after the physical jump that makes the projected constraint valid.

## 105. Energy ledger must include continuous and discrete dissipation

Hybrid frictional dynamics has at least two loss channels:

### Flow loss

```text
integral of Coulomb friction power
```

### Jump loss

```text
impact / feature-transition kinetic loss
```

Therefore:

```text
-energy_delta
=
continuous dissipation
+
discrete jump losses
+
numerical residual
```

A ledger that ignores one class can look plausible while hiding physical work.

## 106. Full 6DOF requires more than a quaternion

A real 6DOF research claim needs:

- three translational coordinates;
- three linear velocity components;
- quaternion orientation;
- three angular velocity components;
- anisotropic inertia;
- gyroscopic coupling;
- tests that excite all three rotation axes.

A normalized quaternion alone proves only representation hygiene.

## 107. Torque-free motion is a strong independent rotational audit

Contact can mask bad rotational equations through reaction/stabilization.

Therefore a full rigid-body checkpoint should include a contact-free torque-free test.

Useful invariants:

```text
linear momentum
world angular momentum
rotational kinetic energy
quaternion norm
```

This separates rigid-body integration correctness from contact correctness.

## 108. Unilateral contact means the world cannot pull through a support constraint

Normal reaction must satisfy:

```text
normal >= 0
```

If the constrained solution requires tensile normal force, the semantic result is separation.

Returning a negative support force and continuing constrained flow is not merely a numerical oddity; it violates the contact law.

## 109. Stick and slide are solved modes of one law

Avoid device-like branches such as separate “static friction component” and “sliding friction component”.

The generic contact law should decide:

```text
stick candidate inside cone
→ stick

otherwise
→ slide on cone boundary
```

Mode is an emergent solved state.

## 110. Feature hierarchy is physical topology, not collision-render metadata

For convex support:

```text
vertex
edge
face
```

are different persistent physical relation structures.

Changing between them can change:

- contact point multiplicity;
- effective mass;
- admissible impulse/reaction;
- warm-state lineage;
- event history.

Therefore feature classification belongs to the physical topology layer.

## 111. A physical event can contain both lineage continuity and a new impulse

When feature identity changes:

```text
old numerical history
→ lineage remap
```

and simultaneously:

```text
new kinematic constraint
→ physical transition impulse
```

These are different things.

Warm-state continuity does not replace the physical impulse.

The new warm impulse may be:

```text
remapped historical hint
+
new physical event impulse
```

## 112. Multiple evidence families reduce self-deception

A single scenario can accidentally validate itself through the same bug in both model and test.

FABRIC0.14 deliberately uses:

- sliding adaptive contact;
- oblique impact;
- torque-free rotation;
- static stick probe;
- separation probe;
- feature hierarchy probe;
- parallel audit.

Future checkpoints should prefer orthogonal evidence families when feasible.

## 113. Exact predecessor runtime regression is stronger than byte preservation

Preserved predecessor blobs prove that old code was not edited.

They do not prove the current environment still executes it correctly.

When the successor lab can materialize the predecessor suite, run it.

FABRIC0.14 therefore upgrades predecessor evidence to:

```text
FABRIC0.13 bytes preserved
+
FABRIC0.13 95/95 runtime PASS
```

on the same exact engine.

## 114. Next complexity should come from graph coupling, not another local law

After FABRIC0.14, a single local rigid-body/plane law already supports:

- 6DOF;
- anisotropic inertia;
- unilateral contact;
- stick/slide;
- impacts;
- feature lineage;
- adaptive events;
- energy/momentum evidence.

The biggest unknown is no longer the local law.

It is the coupled graph:

```text
many free bodies
+
many simultaneous contacts
+
coupled complementarity
+
coupled friction cones
+
island merge/split
```

Therefore FABRIC0.15 should attack graph-wide nonsmooth coupling.

## 115. Текущий образ FABRIC после 0.14

```text
Construction semantic truth
        ↓
persistent physical relation graph
        ↓
full rigid-body 6DOF local state
        ↓
adaptive smooth flow
        ↓
unilateral / frictional contact law
        ↓
explicit impact and feature-transition jumps
        ↓
lineage-preserving topology fixed point
        ↓
continuous + discrete energy ledger
        ↓
parallel numerical execution
        ↓
canonical causal physical history
```

Production ownership remains with Construction.
