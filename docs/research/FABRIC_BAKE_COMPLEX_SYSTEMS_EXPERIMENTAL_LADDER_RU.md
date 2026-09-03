# FABRIC-BAKE — Complex Systems Experimental Ladder

**Статус:** roadmap companion / experimental stand plan.  
**Канонический predecessor:** B0.5-A EXECUTABLE HYBRID BAKE ✅ CLOSED.  
**Текущая decision boundary:** POST-B0.5-A FABRIC SYNC.  
**Назначение:** фиксировать, когда после очередного архитектурного gate уже можно строить наглядный стенд и проверять не отдельный primitive, а возникновение и сохранение сложности целой системы.

---

## 1. Главный принцип

Нам недостаточно доказать, что сложный предмет можно нарисовать или собрать из большого числа частей.

Нужно доказать более сильное свойство:

~~~text
physical structure
        +
functional dependencies
        +
topology changes
        +
FULL / BAKED / ROM representations
        ↓
same causally meaningful world behavior
~~~

Поэтому COMPLEX-стенды должны проверять не только разрушение геометрии, но и последствия разрушения для других физических подсистем.

Пример:

~~~text
battery ─── wire along fence ─── lamp
                 │
                 │ fence segment breaks
                 ▼
             wire breaks
                 │
                 ▼
          electrical path opens
                 │
                 ▼
             lamp OFF
~~~

Это значительно сильнее простого теста «доска забора отвалилась».

---

## 2. Truth boundary для всех COMPLEX-стендов

Во всех опытах сохраняется существующее правило:

~~~text
canonical Construction / Matter
        =
world truth

FABRIC graph
        =
derived executable physics

PhysicalBakeArtifact
        =
derived optimized executable physics
~~~

Следовательно:

- разрушение, соединение, разъединение и изменение функциональной топологии принадлежат canonical source;
- bake не может скрывать canonical damage;
- stale bake не исполняется;
- потеря bake/cache не должна менять состояние мира;
- FULL baseline остаётся эталоном причинного поведения;
- device-specific solver code нельзя добавлять только ради прохождения стенда.

---

# 3. Экспериментальная лестница

## COMPLEX0 — BREAKABLE STRUCTURE LAB

**Когда открывается:** сразу после B0.5-A CLOSED.  
**BRIDGE-2 не требуется**, потому что первый стенд может работать как один structural lifecycle без mixed-representation graph.

### Базовый объект

~~~text
забор / стена
50 → 100 → 500 → 2000 canonical элементов
~~~

Структура:

~~~text
posts
panels
fasteners / joints
optional braces
~~~

### Что делаем

~~~text
construct FULL
    ↓
structural bake / reduction
    ↓
apply local impact
    ↓
refinement guard / local detail
    ↓
joint or panel failure
    ↓
canonical topology mutation
    ↓
BakeInvalidation
    ↓
topology split
    ↓
reconstruction / local FULL
    ↓
rebake stable fragments
~~~

### Что стенд обязан доказать

1. локальное разрушение не требует уничтожать весь canonical object;
2. старый bake становится STALE и не исполняется;
3. topology split отражается в canonical truth;
4. отделившийся фрагмент получает корректную независимую физическую судьбу;
5. спокойные остатки можно снова запечь;
6. replay одного и того же удара детерминирован;
7. FULL baseline и bake lifecycle дают одинаковый факт разрушения в пределах declared envelope.

### Почему это первый стенд

Он проверяет фундамент:

~~~text
complex object
→ bake
→ mutation
→ invalidate
→ split
→ reconstruct
→ rebake
~~~

без добавления междоменной сложности.

---

## COMPLEX1A — POWERED BREAKABLE STRUCTURE / FULL CAUSAL BASELINE

**Когда открывается:** вместе с COMPLEX0 или сразу после него.  
**Цель:** до BRIDGE-2 зафиксировать правильную причинную семантику в FULL, чтобы позже сравнивать её с mixed/baked execution.

### Базовый объект

~~~text
battery
  │
  └── wire routed through / along fence
                         │
                         └── lamp
~~~

Критическое условие:

~~~text
fence intact
→ wire electrically continuous
→ lamp ON

critical fence segment destroyed
→ attached wire topology breaks
→ circuit opens
→ lamp OFF
~~~

### Важное требование

Лампа не должна выключаться по специальному правилу вида «если забор сломан — выключить лампу».

Правильная цепочка:

~~~text
mechanical/topology event
        ↓
canonical wire relation changes
        ↓
electrical graph connectivity changes
        ↓
effort/flow solution changes
        ↓
lamp receives no usable power
        ↓
lamp state becomes OFF
~~~

То есть стенд проверяет **возникновение функционального последствия из generic composition**.

### Обязательные варианты

#### C1 — один провод

Разрыв критического сегмента выключает лампу.

#### C2 — разрыв не связанного сегмента

Разрушается другой участок забора, провод цел — лампа остаётся включённой.

#### C3 — резервный путь

~~~text
battery
 ├── path A ──┐
 └── path B ──┴── lamp
~~~

Разрыв только path A не должен выключить лампу, если path B остаётся валиден.

#### C4 — две лампы / две ветви

Разрушение одной ветви должно влиять только на причинно зависимую нагрузку.

Эти варианты защищают от скрытого hardcode вида «любое разрушение забора → lamp off».

---

## COMPLEX1B — POWERED BREAKABLE STRUCTURE / MIXED BAKE

**Когда открывается:** после того, как POST-B0.5-A FABRIC SYNC разрешит executable BRIDGE-2, и сам BRIDGE-2 даст рабочий mixed FULL ↔ BAKED path.

### Цель

Повторить COMPLEX1A, но уже при разных физических представлениях частей одной системы.

Пример:

~~~text
fence structure      → STRUCTURAL_BAKE
local impact zone    → FULL
stable dynamics      → DYNAMIC_ROM
wire/circuit region  → FULL or validated reduced representation
~~~

После удара:

~~~text
local guard
    ↓
local refinement / reconstruction
    ↓
canonical fence + wire topology mutation
    ↓
relevant bake invalidation
    ↓
electrical consequence
    ↓
lamp OFF
~~~

### Главный falsifier

~~~text
FULL baseline outcome
==
mixed FULL/BAKED outcome
~~~

для:

- topology result;
- lamp on/off state;
- exactly-once break event;
- energy/power accounting;
- deterministic replay.

Если bake сохраняет красивую механику, но лампа не гаснет после физического разрыва провода, mixed architecture считается неверной.

---

## COMPLEX2 — MODULAR MACHINE LAB

**Когда открывается:** после BRIDGE-2 CLOSED.

### Размер первого объекта

~~~text
500–2000 canonical elements
20–50 structural modules
4–8 moving subsystems
2–4 active contact zones
1–3 functional energy/signal paths
~~~

### Рекомендуемая форма

Не автомобиль и не готовое устройство, а искусственная generic machine:

~~~text
frame
├── articulated arm
├── rotating shaft
├── spring / compliant section
├── detachable module
├── power path
└── mechanically exposed cable/path
~~~

### Представления внутри одного объекта

~~~text
region A → FULL
region B → STRUCTURAL_BAKE
region C → CONTACT_BAKE
region D → DYNAMIC_ROM
region E → HYBRID_BAKE
~~~

### Опыты

1. нормальное движение;
2. локальный удар;
3. отсоединение модуля;
4. разрушение несущей связи;
5. разрушение functional path;
6. переход A→B hybrid mode;
7. rebake после стабилизации;
8. повторное воздействие на уже перестроенный объект.

### Ключевой результат

Один canonical object должен одновременно иметь разные уровни физической детализации без двойного ownership состояния.

---

## COMPLEX3 — ADAPTIVE DAMAGE + LOCAL UNBAKE LAB

**Когда открывается:** после B0.6 ADAPTIVE PHYSICAL FIDELITY и decisive lifecycle gate BRIDGE-3 FULL → BAKE → guard → UNBAKE → FULL.

### Базовый стенд

Большая стена/ферма:

~~~text
5k → 20k → 100k canonical elements
~~~

Через неё проходят:

- несколько electrical paths;
- optional mechanical linkage;
- несколько functional consumers;
- локальные zones of possible interaction.

### Сценарий

~~~text
most structure BAKED / ROM / dormant
        ↓
projectile or overload
        ↓
guard triggers only local region
        ↓
LOCAL UNBAKE
        ↓
fracture
        ↓
wire/path topology mutation
        ↓
downstream functional state changes
        ↓
debris settles
        ↓
local rebake
~~~

### Что измеряем

- сколько canonical elements существовало;
- сколько элементов реально исполнялось в FULL;
- площадь/объём refinement island;
- rebuild latency;
- number of invalidated artifacts;
- CPU/memory before, during and after damage;
- causal event count;
- FULL-vs-adaptive outcome delta.

Главная идея:

~~~text
world complexity can grow
without runtime physical complexity growing linearly
~~~

---

## COMPLEX4 — UNSEEN FUNCTIONAL MACHINE CHALLENGE

**Когда открывается:** вместе с / после B0.7 UNSEEN MACHINE SCALE CHALLENGE.

Система строится только из уже существующих generic primitives.

Примеры:

- generator → regulator → load;
- rotating source → variable transmission → driven load;
- thermal source → expansion/pressure path → actuator;
- mechanical breaker → electrical path;
- fluid pressure → mechanical motion → electrical switch;
- unnamed machine assembled after kernel freeze.

### Запрещено

- добавлять Motor, Gearbox, Lamp, Fence как специальные solver primitives только ради fixture;
- писать отдельный bake compiler на каждый стенд;
- вручную кодировать ожидаемый failure outcome.

### Требуется

~~~text
generic composition
→ emergent function
→ reduction
→ failure/topology event
→ correct downstream consequence
~~~

---

# 4. Минимальный набор базовых демонстраций

Эти demos должны постепенно появляться в репозитории как постоянная regression ladder.

| ID | Стенд | Что доказывает | Gate |
|---|---|---|---|
| CX0 | Breakable Fence/Wall | bake → damage → split → rebuild | B0.5-A CLOSED |
| CX1A | Battery–Wire–Lamp Fence FULL | физическое разрушение меняет functional topology | B0.5-A CLOSED |
| CX1B | Battery–Wire–Lamp Fence Mixed | bake не теряет междоменную причинность | BRIDGE-2 executable |
| CX2 | Redundant Power Fence | нет hardcode: резервный путь сохраняет питание | BRIDGE-2 executable |
| CX3 | Modular Generic Machine | разные fidelity внутри одного object | BRIDGE-2 CLOSED |
| CX4 | Adaptive Damage Field | локальный unbake вместо раскрытия всего объекта | B0.6 + BRIDGE-3 |
| CX5 | Large Powered Structure | 10k–100k canonical parts + sparse active physics | B0.6 + BRIDGE-3 |
| CX6 | Unseen Functional Machine | generalization after kernel freeze | B0.7 |

---

# 5. Универсальная acceptance matrix для COMPLEX

Каждый COMPLEX-стенд обязан иметь минимум два режима:

~~~text
REFERENCE:
FULL

SUBJECT:
BAKED / ROM / HYBRID / MIXED / ADAPTIVE
~~~

И сравнивать:

## Canonical outcome

- same topology mutation;
- same detached/attached identities;
- same canonical damage;
- same functional connectivity;
- same final on/off / active/inactive causal result.

## Physical correctness

- declared effort/flow agreement;
- power/energy envelope;
- momentum where applicable;
- no invented impulse/energy;
- no lost/duplicated transition event.

## Lifecycle correctness

- stale artifact never executes;
- exact invalidation scope;
- deterministic reconstruction;
- deterministic rebuild;
- cache identity correctness;
- no nearest-mode guessing;
- exactly-once JUMP.

## Scalability

- canonical element count;
- active FULL element count;
- reduced state count;
- bake/rebuild cost;
- runtime CPU;
- memory;
- event work;
- refinement island size.

---

# 6. Обновлённое направление движения

~~~text
B0.4 Dynamic ROM ✅
        +
B0.5-P0 ✅
        ↓
SYNC-3 ✅
        ↓
B0.5-A Executable Hybrid ✅
        ↓
┌──────────────────────────────────────┐
│ ★ COMPLEX0 / COMPLEX1A LABS OPEN ★  │
│ breakable + causal FULL baselines    │
└──────────────────────────────────────┘
        ↓
════════════════════════════════════
★ POST-B0.5-A FABRIC SYNC — NEXT ★
════════════════════════════════════
        │
        ├── BRIDGE-2 executable authorization?
        └── FABRIC0.19 necessity?
        │
        ▼
BRIDGE-2 executable
        ↓
┌──────────────────────────────────────┐
│ ★ COMPLEX1B / CX2 MIXED LABS ★      │
│ structure + circuit causal coupling  │
└──────────────────────────────────────┘
        ↓
BRIDGE-2 CLOSED
        ↓
┌──────────────────────────────────────┐
│ ★ COMPLEX2 MODULAR MACHINE LAB ★    │
│ mixed fidelity inside one object     │
└──────────────────────────────────────┘
        ↓
B0.6 ADAPTIVE PHYSICAL FIDELITY
        +
BRIDGE-3 LOCAL UNBAKE / FULL CYCLE
        ↓
┌──────────────────────────────────────┐
│ ★ COMPLEX3 / CX5 SCALE LABS ★       │
│ sparse local detail in huge systems  │
└──────────────────────────────────────┘
        ↓
B0.7 UNSEEN MACHINE CHALLENGE
        ↓
┌──────────────────────────────────────┐
│ ★ COMPLEX4 / CX6 GENERALIZATION ★   │
│ unseen functional complex systems    │
└──────────────────────────────────────┘
~~~

---

# 7. Что считается конечным успехом этой лестницы

Не просто:

~~~text
100000 parts can exist
~~~

а:

~~~text
100000 canonical parts can exist
+
only causally important regions need expensive physics
+
damage can locally reveal detail
+
functional consequences propagate correctly
+
stable regions can be baked again
+
FULL and reduced execution agree on causally meaningful outcomes
~~~

Именно это является мостом от отдельных FABRIC-BAKE checkpoints к сложным машинам, зданиям, инфраструктуре, разрушаемым системам и далее к большим живым/техническим системам мира.
