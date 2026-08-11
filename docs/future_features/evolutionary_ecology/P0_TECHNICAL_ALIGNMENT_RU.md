# ECO — P0 Technical Alignment

## Статус

Ветка `feature/eco-evolutionary-ecology` создаётся от canonical `main` как **RESEARCH/DESIGN FRONTIER**.

Она не объявляет production runtime ownership и не обходит текущий PC0/harness порядок. На момент создания canonical architecture revision — `GLOBAL-P0-2026-08-10-R2`, control plane revision — `PC0-2026-08-10-R1`.

Новые autonomous runtime frontiers сейчас должны ждать соответствующего harness gate. Поэтому ECO на этом этапе ограничивается research contracts, deterministic simulations, offline bake experiments, evidence и presentation-only labs.

---

## Архитектурные инварианты

ECO обязана сохранять существующие глобальные правила:

- `CANONICAL_WORLD_NE_PRESENTATION`;
- `CANONICAL_WORLD_NE_TRANSPORT`;
- `CANONICAL_WORLD_NE_COMPUTE`;
- `IDENTITY_NE_LOD`;
- `FEATURE_NE_CELL`;
- `SPATIAL_LOCATION_NE_AUTHORITY_ROUTE`;
- `AUTHORITY_OWNERSHIP_NE_COMPUTE_ASSIGNMENT`;
- `TRANSPORT_SEMANTICS_NE_GAMEPLAY_SEMANTICS`;
- `PROCEDURAL_BASELINE_PLUS_SPARSE_AUTHORITATIVE_MUTATIONS_EQUALS_CURRENT_WORLD_TRUTH`.

Для ECO особенно важны два следствия:

1. mesh/vegetation instance не является ecology truth;
2. запуск evolution compute worker в будущем не делает worker владельцем authoritative population state.

---

## Модель владения

### ECO может владеть

На research этапе:

- ecology research contracts;
- plant genome/trait research model;
- population/cohort research model;
- niche response research model;
- evolution/bake algorithms;
- species catalog format candidate;
- ecology experiment fixtures;
- metrics/evidence;
- presentation-only ecology labs.

После отдельного canonical approval в будущем возможно владение domain-specific ecological population truth, но только поверх общих world/authority/persistence contracts.

### ECO не может владеть

- WorldAddress / Spatial Domain Fabric;
- canonical geology;
- canonical terrain/surface identity;
- hydrology truth;
- Material Ontology;
- Matter mutation storage;
- global transaction model;
- server authority foundation;
- network transport policy;
- generic persistence/durability foundation;
- global World Query Fabric;
- global World Work Budget;
- representation cell identity;
- camera/LOD as source of truth.

---

# Интеграция с программой G — World Generation

Текущий G frontier занимается geomorphology. ECO не должна создавать параллельный terrain/environment generator, который расходится с G.

Целевая зависимость:

`G/Matter/Planet Parameters -> Environment Projection -> ECO`.

ECO может на ранних EXP-V0..V8 использовать аналитическую research fixture, но эта fixture обязана быть явно маркирована как лабораторная и заменяемая.

Когда canonical G contracts готовы, Environment adapter должен читать их через стабильный query/projection layer.

ECO не меняет:

- river centerline;
- terrain elevation;
- geomorphology deformation;
- geology/matter composition.

Она использует производные экологические факторы:

- moisture;
- flood frequency;
- slope/aspect;
- substrate projections;
- water proximity;
- climate variables.

---

# Интеграция с Matter / Material Ontology

В ранних опытах `nutrients`, `soil pH`, `soil_depth` и похожие параметры допустимы как research fixture values.

В production они не должны превращаться в отдельную несовместимую таблицу материалов ECO.

Целевое правило:

`canonical material/matter truth -> ecology-specific substrate/nutrient projection`.

Изменения мира игроком идут через существующие/будущие Matter/Construction transactions, а ECO наблюдает их последствия через query/projection.

---

# Интеграция с Construction

Construction не пишет напрямую `forest = false` или `wetland = true`.

Пример причинной цепочки:

`dam construction -> canonical hydrology/environment change -> ecology environment projection changes -> populations respond`.

Вырубка/сбор растений в будущем должна оформляться как domain operation с ясной границей между promoted interactive individual и aggregate population truth.

---

# Интеграция с Network / Authority

Network transport не должен знать semantics каждого ecological trait.

Будущий authoritative ecology replication должен передавать domain state компактно:

- ecology region/revision;
- population summaries;
- promoted durable individuals;
- disturbance operations/results.

Клиент может детерминированно материализовывать vegetation presentation из authoritative summary + stable procedural data.

Запрещено делать каждое дерево replicated entity по умолчанию.

---

# Интеграция с Distributed Compute

Evolution incubator — хороший будущий workload для S1-like proposal compute.

Но правило остаётся:

`compute proposes / evaluates; authoritative owner commits`.

Дорогой evolution search может выполняться:

- локально;
- offline;
- worker pool;
- future distributed compute.

Результат должен иметь provenance:

- input environment revision;
- algorithm revision;
- seed;
- run configuration;
- deterministic/result hash;
- SpeciesCatalog output hash.

---

# Интеграция с World Query Fabric

Research API можно начать с локальных интерфейсов:

- `environment_at(position, time)`;
- `population_at(region)`;
- `species_candidates(environment, history)`;
- `materialize_population(region, representation_level)`.

Но ECO не должна объявлять эти локальные функции новым глобальным query foundation.

Когда canonical World Query Fabric появится, ECO становится domain adapter/provider.

---

# Интеграция с World Work Budget

Planet-wide ecology update нельзя делать каждый frame для всех регионов.

Будущая модель должна поддерживать:

- dormant aggregate populations;
- coarse scheduled regional updates;
- promotion near active observers/interactions;
- event-driven disturbance propagation;
- budget-aware background simulation.

Однако ECO не создаёт собственный конкурирующий global scheduler. До canonical work-budget contracts всё это остаётся research requirement.

---

# Representation rule

Целевая hierarchy:

- `ECO L0`: planet/region population aggregates;
- `ECO L1`: colonies/patches/territories;
- `ECO L2`: deterministic local individuals;
- `ECO L3`: interactive promoted entities.

Переход LOD/representation не должен менять species identity или aggregate population truth.

Это повторяет общую идеологию проекта: canonical state отделён от способа отображения/исполнения.

---

# Persistence rule

На research этапе persistence может быть experiment-local serialization.

Production ECO не должна изобретать собственную durability foundation.

Будущий durable state, вероятно, включает только то, что нельзя восстановить из procedural baseline/catalog:

- ecology revision/epoch;
- population deltas/state summaries;
- disturbances;
- introductions/extinctions;
- player-caused ecological mutations;
- promoted individuals with durable significance.

Это соответствует глобальному принципу procedural baseline + sparse authoritative mutations.

---

# Merge / promotion gates

Исследовательские документы и pure research experiments могут развиваться в этой ветке.

Перед production runtime integration требуется отдельная convergence ветка от then-current `main` и PC0/harness review.

Минимальные условия для запроса runtime promotion:

1. `ECO.P1 Plant Adaptation Proof` принят;
2. deterministic/replay evidence есть;
3. SpeciesCatalog bake доказан минимум EXP-V8;
4. нет duplicate ownership G/Matter/Authority/Persistence/Query/Work Budget;
5. определён adapter к актуальным canonical environment queries;
6. representation truth separation доказана;
7. branch passport/registry обновлены через canonical control process;
8. runtime work стартует только с разрешённого harness checkpoint.

---

# Текущие зависимости и блокеры

Research EXP-V0..V8 может идти практически независимо на synthetic fixture.

Production integration сознательно ждёт:

- canonical environment/query contracts от развития G/архитектуры;
- material ontology/substrate projection для богатой почвенной модели;
- разрешённый runtime frontier после harness gates;
- authoritative population/persistence design review.

Это не блокирует исследование математики растительности; наоборот, позволяет доказать её отдельно и не разнести архитектуру проекта новой параллельной foundation.