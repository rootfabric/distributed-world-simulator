# FABRIC0 — низкоуровневая композиционная лаборатория

**Статус:** research-only proof of concept.  
**Назначение:** проверить, может ли небольшое число локальных примитивов порождать функции, которые ядро заранее не знает как типы объектов.  
**Не является:** новым production foundation, заменой Construction, Matter, Representation LOD или сетевой authority-модели.

## 1. Архитектурная позиция

FABRIC0 проверяет уже зафиксированный инвариант CONSTRUCTION_PARADIGM_RU.md: поведение конструкции должно выводиться из состава и связей, а не только из prefab-класса.

Границы остаются прежними:

- Construction владеет семантической конструкцией, parts/bonds/ports/facets и capability-компиляцией;
- Dynamic Matter Fabric владеет канонической материей мира и переходами matter/fragment/item/construct;
- Representation LOD Fabric владеет сворачиванием представлений, summaries и derived artifacts;
- FABRIC0 только исследует минимальный вычислительный субстрат Element + Port + Bond + Law + State.

## 2. Гипотеза

Если ядро содержит небольшой набор универсальных локальных законов и типизированных связей, то разные функции должны собираться композиционно без появления специальных runtime-классов Lamp, Fuse, Tank, Motor, Fridge и т. п.

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

Текущий solver намеренно очень простой: детерминированный directed scalar dataflow с локальным settle. Это не физический bond-graph solver и не заявка на production physics.

## 3. Минимальные законы v1

~~~text
source       — выдаёт величину;
gain         — масштабирует вход;
transducer   — меняет domain через явный элемент с коэффициентом;
threshold    — переводит величину в сигнал;
gate         — пропускает поток по сигналу;
integrator   — хранит состояние и интегрирует входной поток;
sink         — терминальная нагрузка/наблюдатель.
~~~

Связь допускается только между out -> in портами одинакового domain. Несколько входящих связей суммируются. У bond может быть capacity; превышение локально переводит bond в broken state и меняет топологию графа.

## 4. Реализованные эксперименты

### F0.1 — Typed Bond Guard

Попытка соединить power -> signal отклоняется без специальных знаний об устройстве.

### F0.2 — Switchable Function

~~~text
battery(power=12)
      |
      v
 power_gate ----> indicator
      ^
      |
 switch(signal)
~~~

switch=0 даёт 0; switch=1 даёт 12. В kernel нет класса Lamp.

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

Функция возникает из цепочки локальных преобразований, включая явную границу доменов.

### F0.4 — Topology Is State

~~~text
source(load=10) -- weak_bond(capacity=5) --> receiver
~~~

До перегрузки граф имеет одну connected component. После шага bond ломается, нагрузка исчезает, граф имеет две connected components и публикует bond_broken event.

### F0.5 — Closed-loop Auto Fill

~~~text
 source(flow=2) -> gate -> store(level)
                    ^          |
                    |          v
                 signal <- controller
~~~

Уровень:

~~~text
2 -> 4 -> 6 -> 8 -> 8 -> 8 -> 8 -> 8
~~~

В kernel нет TankController.

### F0.6 — Same Feedback Pattern / Regulated Heater

Тот же generic build_regulated_accumulator, без изменения kernel, используется с другими domain и параметрами:

~~~text
18 -> 19 -> 20 -> 21 -> 22 -> 22 -> 22 -> 22
~~~

Бак стабилизируется на 8, условный heater — на 22.

Это принципиально важнее одиночного demo: один topology pattern уже переиспользуется для двух семантически разных процессов.

### F0.7 — Proximity Door

~~~text
proximity(signal) ----+
                      v
drive_rate -> gate -> position(integrator)
~~~

Без proximity позиция остаётся 0. После включения сигнала и двух шагов позиция становится 2.

В kernel нет Door, DoorController или actuator-specific op.

### F0.8 — Deterministic Replay

Два независимо построенных одинаковых графа после восьми одинаковых шагов дают одинаковый SHA-256 canonical state hash.

## 5. Что доказано

FABRIC0 v1.1 показывает, что одним маленьким неизменённым ядром уже можно выразить:

- типизированную совместимость связей;
- включение/выключение функции;
- последовательное преобразование величины;
- переход между доменами через явный transducer;
- state accumulation;
- feedback loop;
- переиспользование одного feedback topology pattern в разных domains;
- control + accumulated state на примере proximity door;
- локальный failure;
- split топологии;
- детерминированный replay.

Это достаточный положительный сигнал, чтобы продолжать исследование.

## 6. Что НЕ доказано

FABRIC0 v1.1 не доказывает:

- conservation of energy/mass/charge;
- acausal effort/flow solving;
- двустороннюю физическую связь;
- rigid-body dynamics, torque/inertia или реальные joints;
- электрические Kirchhoff networks;
- fluid pressure networks;
- heat transfer;
- FieldCoupler с воздухом/водой/гравитацией;
- production Construction integration;
- Item Graph identity;
- authoritative graph transactions;
- network replication;
- reduction/expansion compiler;
- масштабирование на тысячи/миллионы элементов.

Текущий solver следует считать исследовательским микроскопом, а не будущим физическим ядром.

## 7. Критерии фальсификации идеи

Исследование должно менять направление, если:

1. Каждый новый неизвестный механизм требует нового device-specific op в kernel.
2. Обратная связь требует обходного произвольного доступа к чужому state.
3. Typed ports не могут отсекать бессмысленные соединения без знания конкретных устройств.
4. Поломки требуют отдельного сценария для каждого класса устройства.
5. Один и тот же graph + inputs не воспроизводится детерминированно.
6. Композиция возможна только при постоянной полной детализации.
7. Переход к настоящим физическим сетям требует выбросить Port/Bond/State вместо расширения этой модели.

## 8. Следующие намеренно сложные эксперименты

Первые два опыта Unknown Machine Pack — reuse feedback pattern и proximity door — уже закрыты без изменения kernel. Дальше надо не добавлять каталог игрушек, а искать границу модели.

### U3 — каскадное разрушение простой фермы

Несколько load bonds; разрыв одного перераспределяет нагрузку и может вызвать следующий.

Цель: проверить emergent failure и честно выявить предел текущего directed solver.

### U4 — две конкурирующие источниковые ветви

Два источника питают общую физическую сеть.

Это намеренно трудный эксперимент: здесь должен проявиться предел scalar dataflow и потребность в conservation/acausal solver.

### U5 — минимальный привод

energy source -> transducer -> rotational storage/inertia -> load.

Для него нужно перейти от одного scalar к сопряжённым величинам и проверить, сохраняется ли модель Port/Bond/Law.

## 9. Promotion gate к FABRIC1

FABRIC не должен переходить в production-архитектуру только потому, что demo выглядит красиво.

Минимальные условия следующего design checkpoint:

~~~text
>= 3 неизвестных заранее конструкции
собраны без device-specific kernel code
AND
одна feedback-система переиспользована в двух разных domains
AND
одна сеть с двусторонней физической связью доказана
AND
conservation/replay invariants имеют автоматические тесты
AND
ясно, как эта модель становится consumer существующего Construction,
а не вторым owner конструкции
~~~

Первое и второе условия уже частично подтверждены FABRIC0 v1.1; главный следующий барьер — двусторонняя физическая сеть и conservation.

## 10. Главный вывод FABRIC0 v1.1

Первый цикл не доказывает универсальный симулятор, но уже подтверждает низкоуровневую интуицию:

> функция устройства может быть следствием топологии, локальных законов и состояния, а не заранее известного движку класса объекта.

Следующий полезный шаг — специально атаковать гипотезу случаями, где текущий простой solver обязан сломаться. Именно место его честного слома подскажет минимальную форму настоящего FABRIC solver.
