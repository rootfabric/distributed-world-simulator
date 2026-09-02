# FABRIC0 — низкоуровневая композиционная лаборатория

**Статус:** FABRIC0.2 research candidate, local exact-double Godot PASS.  
**Назначение:** проверить, может ли небольшое число локальных примитивов порождать функции, которые ядро заранее не знает как типы объектов, а затем найти минимальную границу перехода к физически связанным сетям.  
**Не является:** новым production foundation, заменой Construction, Matter, Representation LOD или сетевой authority-модели.

## 1. Архитектурная позиция

FABRIC0 проверяет инвариант `CONSTRUCTION_PARADIGM_RU.md`: поведение конструкции должно выводиться из состава и связей, а не только из prefab-класса.

Границы остаются прежними:

- Construction владеет семантической конструкцией, parts/bonds/ports/facets и capability-компиляцией;
- Dynamic Matter Fabric владеет канонической материей мира и переходами matter/fragment/item/construct;
- Representation LOD Fabric владеет сворачиванием представлений, summaries и derived artifacts;
- FABRIC0 только исследует минимальный вычислительный субстрат `Element + Port + Bond + Law + State`.

## 2. Текущая гипотеза

Если ядро содержит небольшой набор универсальных локальных законов и типизированных связей, то разные функции должны собираться композиционно без появления специальных runtime-классов `Lamp`, `Tank`, `Door`, `MotorController` и т. п.

Минимальная модель:

~~~text
Element
  state
  ports
  local law

Port
  direction
  domain

Bond
  endpoint A/B
  domain
  capacity
  active state

Graph
  elements
  bonds
  events
  tick
~~~

Текущий solver остаётся исследовательским. Базовая часть — детерминированный directed scalar dataflow. FABRIC0.2 добавляет первый coupled rotational experiment, но ещё не вводит acausal physical solver.

## 3. Минимальные законы

FABRIC0.1:

~~~text
source
switch
gain
transducer
threshold
gate
integrator
sink
~~~

FABRIC0.2 добавляет два физически более содержательных, но всё ещё общих примитива:

~~~text
rotational_inertia
viscous_load
~~~

`switch` является inline-элементом любого domain: он имеет вход, выход и собственное состояние `closed`. Это не signal source и не специальная логика лампы.

## 4. Реализованные эксперименты

### F0.1 — Typed Bond Guard

`power.out -> signal.in` отклоняется по несовместимому domain.

### F0.2 — Inline Switch -> Lamp

~~~text
battery(power=12) -> wall_switch(power) -> lamp(power threshold)
~~~

Наблюдение:

~~~text
switch OPEN   -> lamp power=0,  lit=false
switch CLOSED -> lamp power=12, lit=true
switch OPEN   -> lamp power=0,  lit=false
~~~

Важно:

- `wall_switch` — самостоятельный stateful Element;
- в kernel нет `Lamp` op: элемент `lamp` построен существующим generic threshold-law;
- тот же `Switch` дальше используется в torque domain.

### F0.3 — Cross-domain Conversion

~~~text
100 electric_power
       |
 converter(0.80)
       |
 rotational_power
       |
 gear_loss(0.90)
       |
      72
~~~

### F0.4 — Topology Is State

~~~text
source(load=10) -- weak_bond(capacity=5) --> receiver
~~~

После перегрузки bond ломается, нагрузка исчезает, connected components меняются `1 -> 2`.

### F0.5 — Closed-loop Auto Fill

~~~text
2 -> 4 -> 6 -> 8 -> 8 -> 8 -> ...
~~~

### F0.6 — Same Feedback Pattern / Heater

Тот же `build_regulated_accumulator` в другом domain:

~~~text
18 -> 19 -> 20 -> 21 -> 22 -> 22 -> ...
~~~

### F0.7 — Proximity Door

~~~text
proximity(signal) -> gate
                     ^
drive_rate ---------+----> position(integrator)
~~~

Без сигнала position=0; после двух активных шагов position=2.

### F0.8 — Deterministic Replay

Два одинаковых графа с одинаковыми inputs дают одинаковый canonical SHA-256.

### F0.9 — Coupled Rotational Wall

Первый шаг за пределы чистого однонаправленного toy-dataflow:

~~~text
motor torque
    |
    v
motor_switch -----> flywheel inertia
                       |
                       | angular_velocity
                       v
                  viscous_load
                       |
                       | reaction_torque
                       +-------------> flywheel torque input
~~~

Параметры эксперимента:

~~~text
motor torque     = 4
inertia J        = 2
viscous c        = 1
initial omega    = 0
step dt          = 1
~~~

Скорость:

~~~text
2
3
3.5
3.75
3.875
3.9375
3.96875
3.984375
~~~

Reaction torque автоматически растёт:

~~~text
-2
-3
-3.5
...
-3.984375
~~~

То есть load читает скорость маховика и возвращает реакцию в torque input того же маховика. Net torque уменьшается без Motor-specific controller.

Открытие того же generic `Switch`, который использовался в лампе, теперь в domain `torque` даёт:

~~~text
drive torque: 4 -> 0
omega: 3.984375 -> 1.9921875
~~~

Маховик не останавливается мгновенно: inertia state сохраняет скорость, а load продолжает тормозить его.

### F0.10 — Local Discrete Work/Energy Identity

Для `rotational_inertia` используется шаг с piecewise-constant net torque:

~~~text
alpha       = torque / J
delta_angle = omega*dt + 0.5*alpha*dt^2
omega_next  = omega + alpha*dt
E           = 0.5*J*omega^2
work        = torque*delta_angle
~~~

На каждом inertia-step автоматически проверяется:

~~~text
last_work == last_delta_energy
~~~

На втором шаге:

~~~text
drive torque       = +4
load reaction      = -2
net torque         = +2
delta angle        = 2.5
drive work         = +10
load work          = -5
net work           = +5
kinetic delta      = +5
~~~

Это уже полезный conservation-like локальный инвариант, но ещё не глобальная conservation-модель мира.

## 5. Что теперь доказано

FABRIC0.2 показывает:

- typed compatibility;
- самостоятельный inline Switch с собственным state;
- один Switch работает в разных domains (`power`, `torque`);
- лампа загорается только через реальный путь `battery -> switch -> lamp`;
- generic transformations и feedback patterns переиспользуются;
- topology failure остаётся общим механизмом;
- inertia хранит физическое состояние после отключения источника;
- load reaction возвращается через отдельный torque bond;
- скорость и reaction torque образуют coupled feedback cycle;
- локальный дискретный work/kinetic-energy balance совпадает;
- rotational experiment детерминированно replayable.

Это сильнее FABRIC0.1: модель `Port/Bond/Law/State` пережила первый переход к сопряжённым физическим величинам, не потребовав device-specific `Motor`, `FlywheelController` или `Lamp` закона.

## 6. Что всё ещё НЕ доказано

FABRIC0.2 не доказывает:

- настоящий acausal effort/flow solver;
- Kirchhoff/junction equations;
- source impedance, back-EMF и динамику реального электромотора;
- формальную систему физических units/dimensions;
- глобальное conservation of energy/mass/charge;
- stiff integration и stability contracts;
- rigid-body constraints и spatial joints;
- pressure/flow или heat transfer;
- FieldCoupler;
- production Construction/Item Graph/network integration;
- reduction/expansion compiler;
- масштабирование на большие графы.

Важно: rotational graph является **coupled directed feedback**, а не acausal bond-graph solver. Это намеренная промежуточная ступень.

## 7. Критерии фальсификации

Идея должна меняться, если:

1. каждый новый механизм требует device-specific op;
2. физическая реакция требует обходного доступа к чужому state вместо bonds;
3. разные domains нельзя свести к небольшому числу универсальных port laws;
4. conservation требует отдельной ручной логики для каждого устройства;
5. deterministic replay ломается;
6. связанный solver невозможно локализовать по компонентам графа;
7. переход к более строгой физике требует выбросить `Port/Bond/State`, а не расширить их.

## 8. Следующие эксперименты

### FABRIC0.3 — Two-source / Junction Wall

Два источника воздействуют на общий физический узел. Цель — заставить текущий directed solver встретиться с junction/conservation constraint и определить минимальный контракт для acausal solving.

### FABRIC0.4 — Structural Redistribution

Минимальная ферма с несколькими load paths. Разрыв связи должен перераспределить нагрузку и потенциально вызвать каскадный failure.

### FABRIC0.5 — Motor as Composition, not Primitive

Собрать электромеханический привод из electrical source + switch + conversion + inertia + load + feedback, не добавляя `motor` как kernel law. Следующий ключевой вопрос — back-EMF и источник реакции со стороны механики обратно в электрический domain.

## 9. Promotion gate к FABRIC1

~~~text
>= 3 неизвестных заранее конструкции
без device-specific kernel code
AND
feedback pattern reused across domains
AND
physical reaction cycle proven
AND
junction/conservation experiment has explicit equations
AND
replay/conservation tests exist
AND
Construction remains canonical owner of construct semantics
~~~

Первые три условия теперь имеют положительное evidence. Главный незакрытый барьер — junction/acausal conservation semantics.

## 10. Текущий вывод

FABRIC0.2 усиливает исходную гипотезу:

> устройство может быть не классом движка, а устойчивой конфигурацией универсальных элементов, связей и локальных законов.

Особенно важен `Switch`: один и тот же элемент сначала буквально включает лампу, затем тем же законом отключает torque source от инерционного механизма. Это простой, но очень наглядный пример того, что семантика предмета может жить выше универсальной физической грамматики.
