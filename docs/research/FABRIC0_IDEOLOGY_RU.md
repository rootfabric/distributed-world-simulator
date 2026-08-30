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
