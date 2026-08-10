# T2 — Station Scale Roadmap

**Global revision:** `GLOBAL-P0-2026-08-10-R2`
**Branch family:** `T / Construction`
**Status:** planned continuation after T1 composition + TS0 scale evidence
**Purpose:** превратить доказанную сложную базу в универсальный foundation для больших станций, кораблей, городов и мегаструктур без смены canonical Construction model.

## 1. Положение TS0 перед T2

Начиная с P0 R2 synthetic scale proof вынесен раньше T2 в параллельный lab:

```text
accepted T1A.3
    ├── T1 composition continues
    └── TS0 Large Structural Visual Lab
            ├── 10k synthetic object
            ├── 100k synthetic object — primary gate
            ├── local mutation / dirty rebuild
            └── 1M research ceiling probe

T1 composition + TS0 evidence
            ↓
          T2.0
```

TS0 не считается T2 acceptance. Он снимает отдельный риск raw representation scale до того, как T2 начнёт масштабировать настоящую сложную станцию.

## 2. Главная лестница T2

```text
T1A Complex Construct Assembly
    ↓
T1B Composition / Failure / Recovery
    +
TS0 synthetic scale evidence
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

T1 остаётся composition-first. TS0 исследует synthetic representation scale. T2 соединяет composition + scale + spatial dynamics.

## 3. Инварианты

```text
station identity != section identity
station identity != server owner
station identity != HLOD artifact
station identity != reference frame instance
construct local frame != authority route
part identity != mesh identity
canonical graph != presentation graph
TS0 section identity != WorldAddress
TS0 lab budget != global Work Budget contract
```

Перемещение, docking, LOD, authority rebalance, dormancy и renderer optimization не меняют canonical identity.

## 4. TS0 evidence, которое T2.0 обязан переиспользовать

До T2.0 желательно иметь:

```text
TS0.1 10k visual proof
TS0.2 ~100k visual scale gate
TS0.3 local mutation / dirty-section rebuild
```

Evidence должно включать минимум:

```text
canonical part count
runtime node count
visible section count
triangle count
draw calls
mesh artifact count
build time
resource/GPU bytes
near/mid/far mode
```

T2.0 не должен повторно изобретать synthetic cube benchmark, если TS0 уже закрыл этот вопрос.

## 5. T2.0 — Large Static Construct Scale

Цель: заменить synthetic TS0/C21/C22 fixture реальной сложной базой/станцией.

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
- TS0 representation evidence;
- dirty-section invalidation;
- bounded local resource/cache budgets.

T2.0 добавляет то, чего нет в TS0:

```text
heterogeneous semantic sections
rooms/openings
interactive parts
real visual classes
utilities where useful
non-uniform local mutation patterns
real station/base geometry
```

Acceptance:

- canonical checksum не зависит от near/mid/far representation;
- локальная mutation не требует полного rebuild объекта;
- distant observer не получает все child presentation identities;
- headless authority работает без mesh assets;
- synthetic TS0 optimizations работают на реальной неоднородной конструкции;
- T2 не создаёт private global scheduler/interest/spatial identity.

## 6. T2.1 — Hierarchical Construct Frames

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

Используются существующие C6 Mobile Construct и C7 Spatial Construct contracts. `Spatial Domain Fabric` остаётся global mapping owner.

Acceptance:

- child local identities стабильны при движении parent frame;
- attach/detach не пересоздаёт Item/Part identity;
- world position выводится из frame composition;
- headless mapping не зависит от renderer.

## 7. T2.2 — Moving / Orbital Construct

Проверить:

- translation + rotation parent frame;
- players/items внутри moving construct;
- local utilities/rooms/structure не пересобираются из-за world movement;
- C6 motion policy остаётся owner;
- NX7 задаёт physics authority profile без новой identity model.

## 8. T2.3 — Docking / Undocking Composition

```text
ship approaches dock
→ docking intent
→ authoritative attach
→ frame hierarchy update
→ shared local interaction
→ undocking intent
→ authoritative detach
→ independent ship frame
```

Acceptance:

- ship/station construct IDs стабильны;
- players/items не клонируются;
- reconnect восстанавливает hierarchy;
- transport ordering не определяет canonical outcome.

## 9. T2.4 — Distributed Station Authority

```text
ONE CANONICAL STATION
├── active dock section       authority A
├── habitat section           authority B
├── industrial section        authority C
├── distant storage           dormant/summary
└── exterior shell            low-detail representation
```

Переиспользуются C17 authority migration и общие fencing/handoff patterns. Новый station-specific authority registry запрещён.

Acceptance:

- rebalance не меняет identities;
- split-brain fail-closed;
- reconnect после migration сходится;
- cross-section operations используют durable operation foundation.

## 10. T2.5 — Dormancy / Promotion / Work Budgets

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

Переиспользуется C18. NX8 и будущий `World Work / Budget Fabric` остаются global owners vocabulary/policy.

TS0 local frame budgets являются только evidence/knobs и не могут стать скрытым T2 scheduler foundation.

Acceptance:

- dormancy не меняет canonical checksum;
- promotion восстанавливает актуальный state;
- inactive systems допускают deterministic coarse catch-up;
- budgets ограничены и измеримы.

## 11. T2.6 — Station Scale Acceptance

Контрольный объект: orbital engineering station с docking, habitat, industrial, storage и utility sections.

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

После этого T-line готова к T5 Matter + Construction composition.

## 12. Параллельные программы

```text
T   Construction / station composition
TS  Construction scale/visual evidence
G   World Generation / geology / fluids
N   Network / realtime policy
CH  Character presentation
```

Правило:

```text
parallel implementation is allowed
foundation duplication is forbidden
composition happens only at declared gates
```

T2 не зависит от случайного implementation head G/Network/CH. Интеграция идёт через stable contracts и GLOBAL-P0 boundaries.

## 13. Stop conditions

T2 останавливается и поднимает P0 вопрос, если потребуется:

```text
private WorldAddress
private authority registry
private global InterestRegion identity
private material ontology
private Work/Budget foundation
renderer artifact as canonical state
best-effort RPC for canonical cross-domain mutation
```
