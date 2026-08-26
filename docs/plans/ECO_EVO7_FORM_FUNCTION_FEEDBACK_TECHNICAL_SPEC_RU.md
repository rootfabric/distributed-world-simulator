# ECO.EVO7 — Form / Function / Feedback
## Техническое задание на морфологическую эволюцию и экологические обратные связи

**Статус:** `DIRECTOR_REQUESTED_TECHNICAL_SPEC / RESEARCH_IMPLEMENTATION_PLAN / NON_CANONICAL_UNTIL_ACCEPTED`  
**Дата:** 2026-08-23  
**Базовая ветка при создании:** `feature/eco-evo6-water-selection-r1`  
**Базовый HEAD:** `c22c801b5ba2ee30fcdfe57cba64f532098a7215`  
**Предшественники:** `ECO.PH`, `ECO.EVO4`, `ECO.EVO6`, `ECO.EVO6-WATER`.

Этот документ задаёт следующий исследовательский слой после доказанного water-driven selection. Он не авторизует merge в main и не переводит research-layer в production authority без обычного review/verifier/control пути.

---

# 0. Цель

Перейти от модели:

```text
среда -> fitness -> отбор
```

к замкнутому эко-эволюционному контуру:

```text
ГЕНОТИП
   |
   v
ПОТЕНЦИАЛ ФОРМЫ
   |
   +--------------------+
   |                    |
   v                    v
СРЕДА + ВОЗРАСТ + ИСТОРИЯ + INDIVIDUAL SEED
   |
   v
РЕАЛИЗОВАННЫЙ ФЕНОТИП
   |
   +--> захват света
   +--> потребление воды
   +--> рост / стоимость поддержания
   +--> размножение
   +--> litter / корневая деятельность
   |
   v
PLANT ENVIRONMENT EFFECTS
   |
   v
ИЗМЕНЁННАЯ СРЕДА
   |
   +--> свет соседям
   +--> вода соседям
   +--> почва / establishment
   |
   v
НОВЫЙ FITNESS LANDSCAPE
   |
   v
ОТБОР ПОТОМКОВ
   |
   +---------------------> следующее поколение
```

Целевой результат: различные среды должны порождать не только разные значения `water_preference`, но **различимые наследуемые стратегии формы**: высоту, крону, листья, корни, структурную инвестицию и распределение ресурсов. Эти формы затем обязаны сами становиться факторами среды.

---

# 1. Главный биологический и архитектурный принцип

## 1.1. Не допускать прямого `environment -> genome`

Среда **не записывает** форму в наследственность.

Правильная причинная цепь:

```text
genotype -> phenotype under environment -> performance -> descendants
```

Допустима фенотипическая пластичность:

```text
realized_trait = genetic_potential * plastic_response(environment, age, history)
```

но генотип потомка меняется только через принятый lineage/mutation path.

**Запрещено:**

```text
if soil_is_dry:
    child_genome.root_depth += 1.0
```

**Разрешено:**

```text
сухая среда
  -> глубокие корни дают больший доступ к воде
  -> такие особи получают больший reproductive success
  -> их потомки статистически становятся многочисленнее
```

## 1.2. Разделить наследуемый потенциал и реализованный фенотип

Наследуемое:

```text
height_potential
crown architecture
leaf strategy
root strategy
structural strategy
allocation strategy
```

Реализованное:

```text
realized_height
realized_crown
realized_leaf_area
realized_root_system
current_growth
current_transpiration
current_shade
current_litter
```

Один генотип обязан уметь выглядеть по-разному в разных условиях, сохраняя один и тот же genome hash.

---

# 2. Что уже есть и должно быть переиспользовано

## 2.1. ECO.PH — не создавать второй морфогенетический стек

Принятый трек `ECO.PH` уже содержит:

- Development Trait Contract;
- environment-coupled development;
- deterministic individual seed;
- GrowthGraph / derived phenotype representation;
- `PlantRenderDescription -> RendererProfile -> Multi-Scale`;
- инвариант `Phenotype = Genome × Environment × Age × History × Seed`;
- запрет превращать рендер в ecological truth.

**EVO7 обязан переиспользовать эти поверхности.**

На этапе FFF0 выполняется точный mapping audit: каждому EVO7 functional trait сначала ищется существующий PH0 developmental trait. Новый trait/schema вводится только если доказан semantic gap.

## 2.2. EVO6 — правила среды

EVO6 уже даёт детерминированный DSL:

```text
when × target × effect
```

EVO7 расширяет не синтаксис ради синтаксиса, а семантические входы/выходы:

- правила могут читать functional phenotype;
- правила могут ограничивать realized phenotype или performance;
- правила не имеют права напрямую переписывать hereditary potential.

## 2.3. EVO6-WATER — первая причинная поверхность

Уже доказан контур:

```text
water observations
  -> water fitness
  -> same mutation pool
  -> different selected descendants
```

EVO7 использует этот тест как baseline causality pattern.

## 2.4. Существующий PlantGenome v1

Уже полезны:

- `height_m`;
- `growth_rate`;
- `root_depth_m`;
- `water_preference`;
- `water_tolerance_width`;
- `shade_tolerance`;
- `seed_count`;
- `seed_dispersal_distance_m`;
- `lifespan_years`.

**Нельзя менять schema v1 in-place.** Если существующий PH Development Trait Contract не закрывает новые наследуемые признаки, вводится versioned additive extension / successor contract.

---

# 3. Functional trait space

Нужны не десятки декоративных генов, а небольшой набор сильных функциональных осей.

## 3.1. Обязательные оси первого цикла

| Ось | Наследуемый потенциал | Видимый фенотип | Выигрыш | Цена / trade-off |
|---|---|---|---|---|
| Stature | maximum height / internode strategy | высота | доступ к свету, тень соседям | вода, структурная масса, время роста |
| Crown spread | branch spread / apical dominance | ширина и силуэт кроны | перехват света, локальная тень | транспирация, maintenance, self-shading |
| Crown density | branching/foliage density | плотность кроны | высокий light capture | водный спрос, стоимость листьев |
| Leaf economics | SLA/leaf thickness proxy | размер/толщина/плотность листьев | быстрый рост в богатой среде | drought sensitivity / turnover |
| Structural investment | wood density proxy | толщина/стройность ствола | survival/longevity/mechanical tolerance | более медленный рост |
| Root depth | `root_depth_m` | глубина корней | доступ к воде при засухе | construction cost |
| Root spread | lateral root extent | ширина корневой системы | захват локальных ресурсов | construction cost / neighbour competition |
| Root-shoot allocation | biomass allocation | отношение кроны и корней | специализация под ресурсы | меньше ресурсов другой части растения |

Названия полей в таблице — семантические. FFF0 обязан привязать их к реальным принятым PH0 именам и не плодить синонимы.

## 3.2. Второй цикл, не блокирует FFF1–FFF4

- leaf angle / orientation;
- leaf longevity;
- dormancy / phenology;
- seed size ↔ seed count budget;
- defense allocation;
- bark / fire strategy;
- nutrient acquisition / mycorrhizal strategy.

---

# 4. Инвариант trade-off: «больше» не должно всегда означать «лучше»

EVO7 считается архитектурно неудачным, если эволюция просто максимизирует все параметры.

Каждая функциональная ось должна иметь минимум один benefit и один cost.

Примеры:

```text
больше height
  + больше доступного света
  + сильнее затенение конкурентов
  - больше structural cost
  - больше water demand
  - медленнее достижение reproductive maturity

больше crown_density
  + больше photosynthetic surface
  + сильнее shade output
  - больше transpiration
  - больше maintenance

больше root_depth
  + drought access
  - root construction cost
  - меньше доступного бюджета на shoot

высокий SLA / быстрые листья
  + быстрый gain при хорошем water/light/nutrients
  - хуже drought persistence
  - выше turnover
```

Для первого research slice разрешены нормализованные dimensionless cost-функции. Не требуется симулировать полный углеродный цикл, но знаки и бюджеты должны быть причинными и проверяемыми.

---

# 5. Новый derived контракт: PlantFunctionalPhenotype

Рабочее имя:

```text
distributed_world_simulator.ecology.plant_functional_phenotype.v1
```

Это **derived read-only representation**, не population truth.

Минимальный состав:

```json
{
  "genome_hash": "...",
  "environment_hash": "...",
  "individual_seed": 0,
  "age_fraction": 1.0,

  "realized_height_m": 0.0,
  "realized_crown_radius_m": 0.0,
  "realized_crown_density": 0.0,
  "leaf_area_index_proxy": 0.0,
  "leaf_size_proxy": 0.0,
  "leaf_conservative_strategy": 0.0,
  "structural_investment": 0.0,

  "realized_root_depth_m": 0.0,
  "realized_root_spread_m": 0.0,
  "root_shoot_ratio": 0.0,

  "photosynthetic_gain_proxy": 0.0,
  "maintenance_cost_proxy": 0.0,
  "transpiration_demand_ppm": 0,
  "shade_output_ppm": 0,
  "litter_flux_ppm": 0,
  "establishment_capacity": 0.0,

  "phenotype_hash": "..."
}
```

Точные units/поля замораживаются на FFF1 после audit существующих PH surfaces.

## 5.1. Детерминированность

При одинаковых:

```text
genome + environment + age + history + individual_seed
```

`PlantFunctionalPhenotype` обязан быть byte-identical / hash-identical.

---

# 6. Phenotype expression

Базовая модель:

```text
realized_height =
    height_potential
    * age_curve
    * water_growth_factor
    * light_growth_factor
    * nutrient_factor
    * structural_factor
```

Аналогично для кроны/листьев/корней.

Ключевой принцип: стресс обычно сначала уменьшает **realized expression**, а эволюция уже меняет **heritable potential** через отбор поколений.

Пример для дерева в засухе:

```text
один и тот же genotype:
  mesic -> 8 m realized height
  dry   -> 4.5 m realized height

через поколения:
  dry population -> selected genotypes may also shift
                    toward lower height potential,
                    deeper roots and lower leaf area
```

Это позволяет одновременно получить plasticity и evolution.

---

# 7. Plant -> Environment: эффект растения становится частью мира

Растение не должно напрямую мутировать Environment state. Оно публикует детерминированный effect record.

Рабочий контракт:

```text
distributed_world_simulator.ecology.plant_environment_effect.v1
```

Минимум:

```json
{
  "plant_identity": "...",
  "cell_identity": "...",
  "tick_or_generation": 0,
  "shade_ppm": 0,
  "water_uptake_ppm": 0,
  "evaporation_suppression_ppm": 0,
  "litter_input_ppm": 0,
  "soil_binding_ppm": 0,
  "source_phenotype_hash": "...",
  "effect_hash": "..."
}
```

Агрегатор среды применяет эффекты в стабильном canonical order по identity.

**Запрещены:**

- unordered accumulation с platform-dependent float drift;
- прямой write растения в соседнюю plant state;
- отрицательная почвенная вода;
- создание воды/питания из ничего без явно объявленного источника;
- зависимость результата от порядка обхода SceneTree.

---

# 8. Первый замкнутый feedback: свет

Свет — лучший первый feedback-loop: он видим, локален и биологически силён.

## 8.1. Выход растения

```text
canopy geometry
+ crown density
+ leaf area
+ height
-> shade contribution
```

## 8.2. Агрегация

Для research layer использовать Beer-Lambert-подобную монотонную модель:

```text
transmittance = exp(-k * overlapping_leaf_area_proxy)
understory_light = base_light * transmittance
```

Высотная структура обязательна:

```text
высокая крона -> может затенять более низкую
низкое растение -> не должно симметрично затенять вершину высокого дерева
```

## 8.3. Обратный отбор

```text
understory_light
  -> photosynthetic gain
  -> growth / establishment
  -> shade_tolerance advantage
  -> descendants
```

## 8.4. Контрольный эксперимент

Одни и те же начальные растения + один mutation stream:

```text
A: canopy feedback ON
B: canopy feedback OFF
```

Через N поколений должны различаться selected populations.

После удаления верхнего яруса light field обязан восстановиться, и направление selection должно измениться.

---

# 9. Второй feedback: вода

Использовать уже существующую water-selection поверхность, но сделать её двусторонней.

## 9.1. Transpiration demand

Минимальная модель:

```text
transpiration_demand
  ~ leaf_area
  * activity/growth
  * atmospheric/light demand proxy
```

Фактический uptake ограничен доступной водой и root access:

```text
actual_uptake <= available_water
```

## 9.2. Корни

```text
root_depth
  -> доступ к более устойчивой water-access component

root_spread
  -> площадь локального water capture
```

До появления отдельной groundwater authority нельзя изобретать новый канонический водоносный слой: используются существующие water observations / soil moisture и явно research-derived access modifiers.

## 9.3. Крона создаёт встречный эффект

Большая крона одновременно:

```text
- увеличивает transpiration loss
+ уменьшает bare-soil evaporation через shade
```

Это создаёт полезный нелинейный trade-off вместо правила «большая крона всегда сушит».

## 9.4. Soil texture

Добавить как environmental selector минимум:

```text
sand
loam
clay
```

На первом этапе это не новая геология, а versioned ecological input / fixture channel.

Ожидаемая направленность:

```text
sand + drought
  -> раньше water limitation
  -> высокая цена большой листовой массы
  -> advantage: compact crown + deep/root allocation

loam + mesic
  -> допускает tall/high-leaf-area strategies
```

---

# 10. Третий feedback: litter / soil legacy

После замыкания light+water добавить медленный soil feedback.

```text
leaf turnover / mortality
  -> litter_input
  -> organic matter proxy
  -> moisture retention / nutrient availability / establishment
```

Позже отдельным этапом допускается `soil_biotic_legacy`, но первая версия не должна моделировать микробиом сущностями.

Ключевой эффект:

```text
растение меняет участок
-> на изменённом участке иначе растёт следующее поколение
```

Это создаёт ecological memory и основу сукцессии.

---

# 11. Fitness: перейти от одной цифры к компонентам

Внутри можно по-прежнему выдавать итоговый scalar fitness для selection bridge, но он должен иметь audit-able decomposition:

```text
water_component
light_component
carbon_gain_component
maintenance_cost_component
stress_survival_component
reproduction_component
establishment_component
```

Рабочая схема:

```text
net_resource_proxy =
    photosynthetic_gain
    - shoot_maintenance
    - root_maintenance
    - structural_cost

fitness = clamp(
    survival_factor
    * establishment_factor
    * reproduction_factor(net_resource_proxy),
    MIN_FITNESS,
    MAX_FITNESS
)
```

Каждый component сохраняется в evidence, чтобы сильное изменение результата нельзя было спрятать внутри одной магической формулы.

---

# 12. Эволюция developmental traits

## 12.1. Не создавать второй mutation kernel

Новые morphological/developmental traits должны войти в **одну lineage/mutation authority**.

Если текущий `plant_mutation_lineage_kernel_v1.gd` не может безопасно вместить новые traits без изменения v1 semantics:

- v1 не ломается;
- вводится versioned successor/extension;
- lineage identity и deterministic mutation semantics сохраняются;
- migration/compatibility тестируется;
- параллельный «быстрый EVO7 mutator» запрещён.

## 12.2. Mutation policy

Для каждого нового trait:

```text
min
max
step
mutation_probability / shared gate policy
canonical order
```

Должны быть зафиксированы в schema/registry, а не спрятаны в визуальном коде.

---

# 13. Пространственная модель и производительность

Нельзя считать feedback через полный all-pairs `O(N^2)` scan.

Минимальная архитектура:

```text
plants
  -> spatial buckets / ecological cells
  -> local canopy/root contributions
  -> per-cell aggregate fields
  -> neighbour sampling only from intersecting buckets
```

Требования:

- complexity около `O(N + C + local_interactions)`;
- deterministic bucket membership;
- stable accumulation order;
- одинаковый результат при разном порядке добавления Node/plant records;
- benchmark фиксируется, но hardware-specific hard latency gate вводится только после baseline measurement.

---

# 14. Визуальная материализация

Цвет остаётся debug channel, но больше не является главным доказательством различий.

Новый visual adapter обязан читать `PlantFunctionalPhenotype`:

```text
realized_height       -> высота ствола / число сегментов
crown_radius          -> ширина кроны
crown_density         -> количество/плотность foliage clusters
leaf_size             -> размер leaf clusters
leaf strategy         -> форма/толщина визуального листа
structural investment -> толщина/конусность ствола
root_depth            -> вертикальная root extent
root_spread           -> lateral root extent
apical dominance      -> силуэт: vertical vs spreading
```

## 14.1. Обязательный geometry-only proof

Лаба должна иметь режим:

```text
C = neutralize debug colors
```

При нейтральном одинаковом материале observer/test всё равно должен различать evolved populations по geometry feature vector.

Это главный визуальный gate против ложного «разнообразия цветом».

---

# 15. Новый полигон EVO7

Рабочая сцена:

```text
res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn
```

Минимальные зоны:

```text
1. FLOODED
2. RIPARIAN
3. MESIC_LOAM
4. DRY_SAND
5. UNDER_CANOPY
6. CANOPY_GAP
```

Все основные evolution comparisons стартуют с:

- одного ancestor genome/development genome;
- одинакового population size;
- одного lineage seed;
- одинакового generation-one mutation candidate pool.

Различаться должны только environment/feedback surfaces.

## 15.1. Управление лабой

```text
SPACE  initial / final generation
F      plant feedback ON / OFF counterfactual
C      debug colors ON / neutral geometry-only
1      light overlay
2      soil moisture overlay
3      shade output overlay
4      transpiration overlay
5      fitness components overlay
R      reset deterministic replay
```

HUD показывает:

```text
mean height
mean crown radius
mean LAI proxy
mean root depth/spread
mean water preference
mean shade output
mean transpiration
mean fitness
unique genomes
morphology cluster count
```

---

# 16. Acceptance gates

## G1 — Deterministic phenotype

Одинаковые inputs → одинаковый `phenotype_hash`.

## G2 — Plasticity without Lamarckian write

Один genome в wet и dry:

- realized phenotype различается;
- genome checksum не меняется;
- lineage не создаётся от простого изменения среды.

## G3 — Heritable morphology

Контролируемое изменение одного developmental trait даёт ожидаемое направление geometry/function без изменения несвязанных признаков сверх объявленной coupling.

## G4 — Common mutation pool causality

Все environmental scenarios имеют одинаковый generation-one candidate pool; final selected populations различаются.

## G5 — Geometry divergence

При `C=neutral colors` минимум три среды после evolution имеют статистически различимый morphology feature vector.

Минимальный feature vector:

```text
height
crown_radius
crown_density
leaf_area_proxy
root_depth
root_spread
structural_investment
```

## G6 — Tall canopy changes light

Добавление tall/dense canopy уменьшает understory light в пересекающихся cells; removal восстанавливает свет.

## G7 — Light changes descendants

Feedback ON/OFF при одинаковом mutation stream меняет selected descendants; shade-tolerant/understory strategy получает преимущество под canopy.

## G8 — Water engineering

Высокая leaf area / transpiration demand при прочих равных уменьшает soil moisture сильнее control, но:

- uptake не превышает available water;
- moisture не уходит ниже нуля;
- canopy evaporation suppression учитывается отдельно.

## G9 — Sand vs loam

В dry-sand высокий water-demand/tall-canopy strategy должен проигрывать компактной/root-heavy стратегии; в mesic-loam tall strategy не должна искусственно запрещаться.

## G10 — Closed-loop causality

Через минимум два feedback cycles:

```text
plants(t0)
 -> environment(t1)
 -> selection(t1)
 -> plants(t2)
```

результат отличается от frozen-environment counterfactual.

## G11 — Trade-off anti-runaway

В умеренной смешанной среде не допускается решение, где все evolvable traits стабильно упираются в maximum bound как единая доминирующая стратегия.

## G12 — Order invariance

Перемешивание порядка plant records перед aggregation не меняет итоговые field hashes.

## G13 — No second mutation path

Source/evidence gate доказывает единственную lineage/mutation authority.

## G14 — Existing regression

EVO6, EVO6-WATER, ECO.PH focused gates остаются зелёными.

## G15 — Visual truth boundary

Renderer не пишет назад в genome, phenotype truth или environmental authority. Presentation settings не меняют ecological result hash.

---

# 17. Главные контрольные эксперименты

## Experiment A — «Большое дерево создаёт нишу»

1. mesic-loam позволяет tall canopy;
2. canopy снижает light beneath;
3. low light подавляет light-demanding seedlings;
4. shade-tolerant lineage растёт в understory;
5. после удаления canopy возникает gap;
6. pioneer/light-demanding lineage снова получает преимущество.

Это первый полноценный succession-like loop.

## Experiment B — «Песок не запрещает дерево правилом, а делает его дорогим»

Запрещено:

```text
if soil == sand:
    max_height = 1.0
```

Нужно:

```text
sand
 -> lower effective water persistence
 -> large leaf/crown strategy incurs water stress
 -> growth/reproduction drops
 -> compact/root-heavy descendants win
```

Так форма возникает из trade-off, а не из ручного archetype switch.

## Experiment C — «Растительность сама сушит участок»

Сравнить одинаковый участок:

```text
A: sparse low-LAI vegetation
B: dense high-LAI vegetation
```

При feedback ON B должна сильнее draw water через transpiration, одновременно иметь evaporation reduction от shade. Итоговый знак определяется балансом компонентов и фиксируется evidence.

## Experiment D — «Ecological memory»

После FFF5:

1. одна популяция растёт несколько cycles;
2. создаёт litter/soil legacy;
3. исходные растения удаляются;
4. новый одинаковый seed pool запускается на modified и pristine soil;
5. establishment/divergence различаются.

---

# 18. Запрет hardcoded species archetypes

В ecological selection запрещены ветки вида:

```text
if species_class == TREE: ...
if species_class == BUSH: ...
if species_class == GRASS: ...
```

`TREE/BUSH/GRASS` допустимы только как **diagnostic cluster labels**, вычисленные постфактум из trait space.

Система должна порождать функциональные формы из continuous/discrete traits, а не выбирать заранее заготовленный вид.

---

# 19. Этапы реализации

## FFF0 — Contract Mapping Checkpoint

**Цель:** не продублировать ECO.PH.

Сделать:

- inventory PH0 developmental traits;
- mapping таблицу `EVO7 semantic axis -> accepted PH field`;
- inventory current mutation authority;
- inventory environment fields: water/light/nutrients/soil texture availability;
- freeze exact ownership boundaries.

**Exit:** design checkpoint PASS; список реально новых contract fields минимален.

## FFF1 — Functional Phenotype R1

Сделать:

- `PlantFunctionalPhenotype` derived representation;
- deterministic compiler/adapter из accepted genome+PH data;
- component costs/gains;
- no environment feedback yet.

**Exit:** G1–G3 PASS.

## FFF2 — Morphology Evolution R1

Сделать evolvable subset developmental traits через единственную mutation authority.

Первый subset:

```text
height potential
crown spread/apical dominance
crown density/leaf area strategy
root depth
root spread/allocation
structural investment
```

**Exit:** common mutation pool -> >=3 geometry-distinct final populations; G4–G5, G13 PASS.

## FFF3 — Light Feedback R1

Сделать:

- canopy spatial projection;
- shade aggregation;
- understory light field;
- light component in functional fitness;
- canopy removal counterfactual.

**Exit:** G6–G7, G10, G12 PASS.

## FFF4 — Water + Soil Texture Feedback R1

Сделать:

- transpiration demand;
- bounded water uptake;
- evaporation suppression from canopy shade;
- root access;
- sand/loam/clay ecological input.

**Exit:** G8–G9, water conservation/bounds PASS.

## FFF5 — Soil/Litter Memory R1

Сделать:

- litter flux;
- organic matter proxy;
- slow moisture/nutrient/establishment feedback;
- modified-vs-pristine soil experiment.

**Exit:** Experiment D causality PASS.

## FFF6 — Closed Community Evolution / Succession Lab

Собрать light + water + soil feedback в один controlled landscape.

Минимум 100 generation-equivalents / cycles для stability evidence.

**Exit:**

- несколько устойчивых функциональных стратегий;
- canopy/understory/gap transitions наблюдаемы;
- anti-runaway gate;
- deterministic replay;
- geometry-only visual proof.

## FFF7 — Scale / XFER Readiness

Только после research acceptance:

- profiling;
- aggregation LOD;
- persistence boundary;
- production environment write authority;
- network/read-only projection implications.

Не входит в первую реализацию.

---

# 20. Что сознательно НЕ входит в первую волну

- полноценная биохимия фотосинтеза;
- explicit carbon atoms / exact carbon budget;
- полноценный groundwater simulator;
- сущности микробов/грибов;
- генетическая рекомбинация / sexual genetics;
- пожары;
- herbivores/predators;
- neural morphology generation;
- production persistence/network replication.

Это защищает эксперимент от преждевременной сложности.

---

# 21. Research basis

Техническая модель не обязана численно копировать конкретные виды, но направление trade-offs опирается на наблюдаемую functional ecology:

1. **Kunstler et al., Nature (2016), Plant functional traits have globally consistent effects on competition.** Maximum height, wood density и SLA связаны с ростом и конкурентными взаимодействиями. DOI: `10.1038/nature16476`.
2. **Wright et al., Nature (2004), The worldwide leaf economics spectrum.** Глобальный fast-slow spectrum листовых стратегий. DOI: `10.1038/nature02403`.
3. **Eskelinen et al., Nature (2022), Light competition drives herbivore and nutrient effects on plant diversity.** Прямое экспериментальное подтверждение важности competition for light. DOI: `10.1038/s41586-022-05383-9`.
4. **Wankmüller et al., Nature (2024), Global influence of soil texture on ecosystem water limitation.** Soil texture, особенно sand fraction, существенно меняет onset water limitation. DOI: `10.1038/s41586-024-08089-2`.
5. **Forero et al., Communications Biology (2021), Plant-soil feedbacks help explain biodiversity-productivity relationships.** Растения создают soil legacies, меняющие subsequent growth. DOI: `10.1038/s42003-021-02329-1`.
6. **Liu et al., Communications Earth & Environment (2025), Global greening drives significant soil moisture loss.** Vegetation transpiration способна заметно менять soil moisture. DOI: `10.1038/s43247-025-02470-3`.

Эти источники задают qualitative direction. Коэффициенты симулятора должны калиброваться отдельными controlled experiments и sensitivity gates, а не копироваться без проверки.

---

# 22. Definition of Done для EVO7 research layer

EVO7 считается исследовательски состоявшимся только когда одновременно доказано:

```text
1. одинаковые предки + одинаковые мутации + разные среды
   -> разные наследуемые functional strategies;

2. различия видны геометрически при выключенном debug-color;

3. форма меняет свет/воду/почву вокруг себя;

4. изменённая растениями среда меняет selection следующего поколения;

5. feedback ON и feedback OFF дают разные descendants;

6. ни environment, ни renderer не переписывают genome напрямую;

7. нет второго mutation/lineage kernel;

8. deterministic replay сохраняется;

9. существующие EVO6-WATER и ECO.PH invariants не ломаются.
```

Финальный целевой феномен:

```text
не «мы нарисовали лес»,
а
«лес возник как устойчивая стратегия,
изменил собственную среду,
создал подлесок и новые ниши,
а затем сам стал причиной следующего этапа отбора».
```
