# ECO.EVO7 LS4 — Scope Contract

Дата: 2026-09-05

Статус: **SCOPE FROZEN / LS4.1 AUTHORIZED**

## 1. Зачем существует LS4

LS3 доказал пространственную эволюционную экологию, VIS4 — причинно связанное морфологическое представление, STREAM1/PERF2 — bounded deterministic execution, PERF2.CONV — совместную работу симуляции, морфологии, LOD, cache и foreground presentation.

LS4 больше не должен расширять инфраструктуру ради инфраструктуры. Его задача — увеличить **сложность самой экосистемы**.

North Star:

```text
physical WORLD / environment
        ↓
several functional species
        ↓
shared resources
        ↓
inter-species interactions
        ↓
disturbance / succession
        ↓
ecosystem engineering
        ↓
EnvironmentFeedbackProposal
        ↓
WORLD owner applies validated bounded feedback
        ↓
new immutable environment snapshot
        ↓
ECO consumes it
```

Главный переход LS4:

```text
WORLD → ECO
```

становится:

```text
WORLD → ECO → bounded proposal → WORLD owner → WORLD → ECO
```

При этом ECO **не получает право писать WORLD напрямую**.

## 2. Что именно заморожено

LS4 определяется как:

> **Multi-Species Ecosystem + Shared Resources + WORLD↔ECO Feedback**

Не LS4:

- individual animal AI / navigation;
- production ecology authority;
- network/persistence authority;
- hardcoded desired biome placement;
- per-world tuning ради прохождения FINAL;
- прямые ECO writes в canonical WORLD.

## 3. Архитектурная граница authority

Существующая LS3 workbench chain остаётся ecology truth chain и расширяется LS4 поэтапно.

WORLD/environment остаётся внешним owner.

VIS/PLAY остаются presentation-only.

```text
WORLD owner
   │ immutable environment snapshot
   ▼
LS3 + LS4 ecology authority
   │
   ├─ ecology state
   ├─ species/resource/interaction evidence
   └─ EnvironmentFeedbackProposal (derived only)
                               │
                               ▼
                         WORLD owner
```

`EnvironmentFeedbackProposal` не является world state и не может применить себя сам.

## 4. Species Catalog

LS4.1 вводит минимум три функционально отличающихся species.

Каждый species обязан иметь причинные различия минимум по:

- growth strategy;
- water demand;
- light demand;
- nutrient demand;
- stress tolerance;
- reproduction strategy.

Нельзя делать три декоративных color variants одного поведения.

Catalog — frozen research input, identity: `species_catalog_hash`.

Один и тот же catalog используется во всех мирах LS4.FINAL без retuning.

## 5. Interaction Graph

LS4.2 замораживает typed deterministic graph.

Разрешённые kinds:

```text
COMPETITION
HERBIVORY
PREDATION
POLLINATION
SYMBIOSIS
DECOMPOSITION
```

Unknown kind → FAIL CLOSED.

Graph identity: `interaction_graph_hash`.

На LS4.2 необязательно сразу реализовать каждую связь как богатую биологию; контракт фиксирует общую causal seam, после чего конкретные edges должны быть доказаны executable falsifiers.

## 6. Shared Resources

LS4.3 делает явными:

```text
LIGHT
WATER
NUTRIENTS
SPACE
```

Для каждого ресурса обязательны:

- non-negative supply;
- non-negative demand;
- bounded allocation;
- deterministic tie-breaking;
- отсутствие hidden resource creation.

Результат allocation должен реально влиять на survival/reproduction, а не быть diagnostic overlay.

## 7. Trophic Network

LS4.4 вводит population-level trophic causality:

```text
producer
  ↓
herbivore
  ↓
predator
  ↓
mortality / biomass
  ↓
decomposer
  ↓
nutrients
  ↓
producer
```

Это **не LS5 individual animals**. LS4 оперирует cohort/population representations.

## 8. Disturbance

LS4.5 принимает только bounded deterministic events:

```text
DROUGHT
FLOOD
FIRE
FROST
EXCAVATION
IMPACT
```

Каждое событие обязано иметь stable identity, source snapshot binding и bounded region.

Duplicate event → FAIL CLOSED.

Stale source → FAIL CLOSED.

`EXCAVATION` / `IMPACT` на LS4 не дают ECO право менять MATTER/terrain; ECO потребляет внешний disturbance evidence.

## 9. Succession

LS4.6 не вводит scripted succession targets.

Нужна причинная траектория вида:

```text
disturbance
  ↓
resource/environment change
  ↓
selection / recruitment pressure
  ↓
species redistribution
  ↓
new community state
```

Phase labels могут существовать только как derived observation.

## 10. Ecosystem Engineering

LS4.7 разрешает ECO вычислять bounded effects по каналам:

```text
SHADE
WATER_RETENTION
ORGANIC_MATTER
SOIL_STABILITY
SURFACE_ROUGHNESS
```

Но результат — только `EnvironmentFeedbackProposal`.

Обязательные source bindings:

- source ecology state hash;
- source environment hash;
- generation;
- bounded region;
- channels hash.

Unbounded/stale proposal → FAIL CLOSED.

## 11. WORLD↔ECO Feedback

LS4.8 — ключевой architectural challenge.

Правильная схема:

```text
ECO generation N
  ↓
feedback proposal N
  ↓ validate
WORLD owner
  ↓ apply
new immutable environment snapshot N+1
  ↓
ECO consumes snapshot
  ↓
ECO generation N+1
```

Запрещённая схема:

```text
ECO → mutate world directly
```

Так feedback становится настоящим, не создавая второго WORLD owner.

## 12. Frozen roadmap

```text
LS4.1 Multi-Species Ecology
  ↓
LS4.2 Interaction Graph
  ↓
LS4.3 Shared Resource Competition
  ↓
LS4.4 Trophic Network
  ↓
LS4.5 Disturbance Envelope
  ↓
LS4.6 Ecological Succession
  ↓
LS4.7 Ecosystem Engineering
  ↓
LS4.8 WORLD↔ECO Feedback Loop
  ↓
LS4.FINAL Emergent Ecosystem Challenge
  ↓
PLAY1 Living Ecosystem Region
```

Каждый major substage обязан иметь visual evidence:

```text
LS4-VIS1 species distribution
LS4-VIS2 interaction pressure
LS4-VIS3 resource allocation
LS4-VIS4 trophic flow
LS4-VIS5 disturbance footprint
LS4-VIS6 succession timeline
LS4-VIS7 feedback channels
LS4-VIS8 causal WORLD↔ECO loop
PLAY1 final integrated region
```

## 13. Performance inheritance

Accepted PERF2.CONV evidence не переигрывается и не переписывается.

Два правила:

1. Старый predecessor workload остаётся immutable regression baseline.
2. Каждый LS4 substage до acceptance замораживает дополнительный workload/budget для своей новой сложности.

Запрещены unbounded per-generation histories/caches. Любой retained cache/history обязан иметь explicit bound + eviction semantics.

## 14. Deterministic identity

LS4 должен публиковать и валидировать как минимум:

```text
species_catalog_hash
interaction_graph_hash
resource_field_hash
ecology_state_hash
disturbance_event_hash
feedback_proposal_hash
```

Обязательны canonical ordering, generation binding и same-input deterministic replay.

## 15. LS4.FINAL — Emergent Ecosystem Challenge

Минимум три physical worlds.

Во всех трёх неизменны:

- species catalog;
- interaction rules;
- founder setup;
- executable code;
- acceptance criteria.

Минимум 200 generations/world.

Требуется:

- distinct ecosystem outcomes;
- no per-world retuning;
- deterministic replay;
- bounded disturbance challenge;
- recovery/succession after disturbance;
- visual integrated evidence.

Цель FINAL — доказать, что различные экосистемы **возникают из разных физических условий**, а не выбираются заранее.

## 16. Что разрешено после freeze

После принятия этого scope contract разрешён только следующий executable substage:

```text
LS4.1 — Multi-Species Ecology
```

LS4.2+ остаются blocked до acceptance непосредственного predecessor.

## 17. Ближайший executable falsifier LS4.1

Один и тот же physical patch и environment запускается с минимум тремя functionally distinct species.

Нужно доказать одновременно:

1. species identities стабильны и входят в ecology identity;
2. никаких desired-biome coordinates/placements нет;
3. каждая species проходит тот же LS3 dispersal/recruitment/competition chain;
4. при одном и том же input run детерминирован;
5. при physical counterfactual environment species distribution реально меняется;
6. VIS1 показывает species distribution, но не становится authority;
7. predecessor single-species behavior остаётся regression-compatible через explicit compatibility fixture или equivalent frozen oracle.

После этого можно переходить к LS4.2 Interaction Graph.
