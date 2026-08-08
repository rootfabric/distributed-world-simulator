# T2 — Station Scale Roadmap

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch family:** `T / Construction`
**Status:** planned continuation after T1 composition
**Purpose:** превратить доказанную сложную базу в универсальный foundation для больших станций, кораблей, городов и мегаструктур без смены canonical Construction model.

## 1. Главная коррекция T-roadmap

T2 больше не трактуется как просто `увеличить part_count`.

Правильная лестница:

```text
T1A Complex Construct Assembly
    ↓
T1B Composition / Failure / Recovery
    ↓
T2.0 Large Static Construct Scale
    ↓
T2.1 Hierarchical Construct Frames
    ↓
T2.2 Moving / Orbital Construct
    ↓
T2.3 Docking / Undocking Composition
    ↓
T2.4 Distributed Station Authority
    ↓
T2.5 Dormancy / Promotion / Work Budgets
    ↓
T2.6 Station Scale Acceptance
    ↓
T5 Matter + Construction Composition
```

T1 остаётся composition-first. T2 добавляет масштаб и пространственную динамику, но не создаёт новую Construction truth.

## 2. Инварианты

```text
station identity != section identity
station identity != server owner
station identity != HLOD artifact
station identity != reference frame instance
construct local frame != authority route
part identity != mesh identity
canonical graph != presentation graph
```

Перемещение, docking, смена LOD, authority rebalance и dormancy не имеют права менять canonical identity объекта только потому, что изменилась его runtime representation или compute placement.

## 3. T2.0 — Large Static Construct Scale

Цель: заменить синтетический C21/C22 scale fixture реальной сложной базой/станцией.

Профили:

```text
S0  10 000+ semantic parts
S1  100 000 semantic parts
S2  1 000 000 semantic parts — research/ceiling probe, не обязательный production gate
```

Переиспользуются:

- C21 large-scale acceptance;
- C22 compiled construct proxies / HLOD;
- C24 GPU-ready proxy mesh backend;
- dirty-section invalidation;
- bounded resource/cache budgets.

Acceptance:

- canonical checksum не зависит от near/mid/far representation;
- локальная mutation не требует полного rebuild объекта;
- distant observer не получает все child presentation identities;
- headless authority работает без mesh assets.

## 4. T2.1 — Hierarchical Construct Frames

Цель: доказать вложенные local/reference frames до начала настоящей orbital station composition.

Минимальная иерархия:

```text
world/body frame
    ↓
station frame
    ↓
dock frame
    ↓
ship frame
    ↓
room / item / player local state
```

Используются существующие C6 Mobile Construct и C7 Spatial Construct contracts. Будущий `Spatial Domain Fabric` остаётся глобальным mapping owner; T2 не создаёт собственный глобальный WorldAddress.

Acceptance:

- child local identities стабильны при движении parent frame;
- attach/detach не пересоздаёт Item/Part identity;
- world position выводится из frame composition, а не хранится как новая конкурирующая truth;
- headless mapping не зависит от renderer.

## 5. T2.2 — Moving / Orbital Construct

Цель: одна и та же станция/корабль может двигаться в world space без смены canonical construct identity.

Проверить:

- translation + rotation parent frame;
- players/items внутри движущегося construct;
- local utilities/rooms/structural state не пересобираются из-за world movement;
- C6 motion policy остаётся domain owner;
- NX7 позже задаёт physics authority profile, но не новую identity model.

## 6. T2.3 — Docking / Undocking Composition

Цель: корабль входит в station frame hierarchy и выходит из неё без identity duplication.

Сценарий:

```text
ship approaches dock
→ docking intent
→ authoritative attach
→ frame hierarchy update
→ shared local interaction
→ undocking intent
→ authoritative detach
→ ship frame moves independently
```

Acceptance:

- ship construct ID не меняется;
- station construct ID не меняется;
- players/items не клонируются;
- reconnect в docked и undocked состояниях восстанавливает тот же hierarchy result;
- transport ordering не определяет canonical outcome.

## 7. T2.4 — Distributed Station Authority

Большая станция не означает `one station = one server`.

Целевая модель:

```text
ONE CANONICAL STATION
├── active dock section       authority A
├── habitat section           authority B
├── industrial section        authority C
├── distant storage           dormant/summary
└── exterior shell            low-detail representation
```

Переиспользуются C17 distributed Construction authority и общие fencing/handoff patterns. T2 не создаёт второй authority registry поверх GLOBAL-P0.

Acceptance:

- authority rebalance не меняет station/part identities;
- split-brain закрывается fail-closed;
- reconnect после migration восстанавливает единый construct revision;
- cross-section operations используют существующий durable operation foundation, а не best-effort RPC chain.

## 8. T2.5 — Dormancy / Promotion / Work Budgets

Миллионы деталей нельзя симулировать каждый tick.

Целевая лестница:

```text
DORMANT SUMMARY
    ↓ observer/activity
PROMOTING
    ↓
ACTIVE FULL / SECTION
    ↓ inactivity
DEMOTING
    ↓
DORMANT SUMMARY
```

Переиспользуется C18 streaming/dormant construct foundation. Будущие NX8 и `World Work / Budget Fabric` задают общий interest/work vocabulary; Construction не создаёт собственный глобальный scheduler identity.

Acceptance:

- dormancy не меняет canonical checksum;
- promotion восстанавливает актуальный state после удалённых mutations;
- inactive rooms/utilities допускают coarse deterministic catch-up вместо per-tick simulation;
- activity budget ограничен и измерим.

## 9. T2.6 — Station Scale Acceptance

Контрольный объект: orbital engineering station с docking, habitat, industrial, storage и utility sections.

Обязательный composition proof:

```text
100k-class semantic parts
+ nested frames
+ moving/orbital parent
+ docked ship
+ distributed authority
+ near/mid/far HLOD
+ dormancy/promotion
+ reconnect/recovery
= one canonical station
```

После этого T-line готова к T5 Matter + Construction composition: добыча, damage, debris, salvage, excavation и construction должны работать через общий WorldOperation/transaction boundary.

## 10. Параллельные программы

На текущем этапе сознательно продолжаются параллельно:

```text
T  Construction / station composition
G  World Generation / geology / fluids
N  Network / realtime tuning and policy
CH Character / clothing / equipment presentation
```

Правило:

```text
parallel implementation is allowed
foundation duplication is forbidden
composition happens only at declared gates
```

T не должен зависеть от случайного текущего implementation head G, Network или CH. Интеграция выполняется через stable contracts и GLOBAL-P0 boundaries.
