# ECO Vegetation Experiment Plan

Цель этой серии — постепенно доказать, что растительность PlanetSimulator может возникать из непрерывной среды, конкуренции, распространения и эволюции, а затем быть сохранена и воспроизведена как дешёвый runtime population model.

Каждый эксперимент должен быть deterministic по seed и иметь headless режим. Визуальная сцена полезна как evidence, но не заменяет численные acceptance criteria.

---

# Общая лаборатория

## Базовый участок

Первая общая fixture:

- размер: `4 km × 4 km`;
- экологическая сетка для первых опытов: `128 × 128` patches;
- одна река, проходящая через участок;
- влажная низина;
- сухое плато;
- солнечный склон;
- более затенённый склон;
- несколько flood-prone patches.

Не требуется production terrain mesh. Environmental fixture может быть аналитической и позже проецироваться на настоящий G surface.

## Первые environmental fields

1. `temperature`;
2. `soil_moisture`;
3. `sunlight`;
4. `nutrients`;
5. `flood_frequency`.

## Первый plant trait vector

1. `height`;
2. `growth_rate`;
3. `root_depth`;
4. `water_preference`;
5. `water_tolerance_width`;
6. `shade_tolerance`;
7. `seed_count`;
8. `seed_dispersal_distance`;
9. `lifespan`.

Дополнительные traits вводятся только когда предыдущий эксперимент показывает, что без них модель систематически не может объяснить нужное поведение.

---

# EXP-V0 — Environmental Field Determinism

## Вопрос

Можем ли мы получить непрерывную, воспроизводимую ecological environment truth без biome labels?

## Реализация

Сгенерировать пять полей для одной fixture. Значение любой точки должно зависеть только от world/sample coordinates, environment revision и seed, а не от camera/LOD/cell presentation.

## Проверки

- одинаковый seed даёт идентичный field hash;
- разный sampling resolution не меняет canonical samples в совпадающих координатах;
- переходы через условные ecological cell boundaries не создают швов;
- влажность закономерно связана с рекой/низиной;
- sunlight закономерно связан со slope/aspect fixture;
- debug visualization не является truth.

## PASS

Все поля детерминированы, seam-safe и пригодны для query по координате.

## Результат

`EnvironmentSampleV0` и visual/debug heatmap lab.

---

# EXP-V1 — Один вид, разные условия

## Вопрос

Работает ли resource model вообще, прежде чем добавлять evolution?

## Реализация

Один фиксированный plant genome размещается во всех patches. Моделируется несколько сезонов/лет без mutation.

Растение получает ресурсы через light/water/nutrients и платит за maintenance, roots, height, reproduction.

## Проверки

- есть зона уверенного роста;
- есть marginal zone;
- есть зона гибели;
- смена moisture или sunlight предсказуемо сдвигает границу;
- изменение root_depth имеет стоимость, а не только бонус.

## Метрики

- biomass per patch;
- births/deaths;
- mean resource surplus;
- survival probability;
- reproductive output.

## PASS

Распределение не является случайным и меняется причинно в ответ на environment/traits.

---

# EXP-V2 — Mutation и локальная адаптация

## Вопрос

Может ли одна ancestral lineage сама адаптироваться к разным частям участка?

## Реализация

Запустить одну общую исходную популяцию с mutation по:

- water_preference;
- root_depth;
- growth_rate;
- shade_tolerance;
- seed_dispersal_distance.

Не вводить explicit species classes.

## Ожидаемый эффект

Со временем distribution traits возле реки и на сухом плато должен статистически расходиться.

## Метрики

- mean/variance каждого trait по region class, вычисленному только для анализа;
- trait-environment correlation;
- ancestry diversity;
- population stability;
- mutation survival rate.

## PASS

После длинного deterministic run различие trait distributions между минимум тремя contrasting environment zones устойчиво превышает начальный шум и воспроизводится на нескольких seeds как тип поведения, хотя конкретные genomes могут отличаться.

---

# EXP-V3 — Конкуренция стратегий

## Вопрос

Может ли модель поддерживать несколько разных жизненных стратегий вместо одного глобального optimum?

## Реализация

Разрешить trade-offs:

- fast growth vs maintenance/lifespan;
- height vs structural cost;
- root depth vs energy cost;
- seed count vs seed survival;
- shade tolerance vs maximum photosynthetic rate.

Начать примерно с 20 ancestral genomes с небольшими вариациями.

## Искомые emergent strategies

Не hardcode, но диагностически искать:

- fast pioneer;
- wet-ground specialist;
- dry-ground specialist;
- shade-tolerant understory;
- tall slow canopy strategy.

## Метрики

- number of persistent trait clusters;
- occupied niche volume;
- dominance ratio;
- coexistence duration;
- extinction rate;
- Shannon diversity по lineage/trait clusters.

## FAIL-паттерны

- один genome захватывает 99% мира независимо от условий;
- бесконечный runaway height/root_depth;
- хаотический extinction всех линий;
- specialization появляется только из hardcoded region rules.

## PASS

Минимум три различимые устойчивые стратегии сосуществуют и занимают разные environmental niches без biome-specific code.

---

# EXP-V4 — Light Competition и сукцессия

## Вопрос

Возникает ли динамика pioneer -> canopy без scripted succession state machine?

## Реализация

Добавить vertical/light interaction:

- высокая растительность уменьшает доступный свет нижнему слою;
- высота имеет biomass/maintenance cost;
- быстрые низкие растения быстрее колонизируют пустую землю;
- долгоживущие высокие формы получают преимущество позже.

Сначала обнулить biomass на части участка и наблюдать recolonization.

## Метрики

- canopy height distribution over time;
- ground light over time;
- lineage turnover;
- biomass recovery curve;
- time to 50% and 90% stable biomass.

## PASS

Восстановление проходит через статистически различимые стадии, но стадии являются результатом взаимодействий, а не запрограммированным списком.

---

# EXP-V5 — Disturbance Mosaic

## Вопрос

Создаёт ли история disturbances устойчивое spatial diversity при одинаковом климате?

## Реализация

Ввести deterministic events:

- локальный fire;
- flood pulse;
- drought interval.

Соседние patches с одинаковыми текущими climate values должны иметь разный age-since-disturbance.

## Метрики

- species/trait composition vs time_since_disturbance;
- recovery trajectory;
- spatial diversity;
- pioneer fraction;
- mature-strategy fraction.

## PASS

После disturbance участки не мгновенно возвращаются к одной и той же статической раскладке; история остаётся заметной в population composition в течение разумного simulated interval.

---

# EXP-V6 — Dispersal и биогеография

## Вопрос

Можно ли добиться ситуации «место подходит виду, но вида там нет», если он туда не добрался?

## Реализация

Разделить карту рекой/барьером/дистанцией на несколько connected components и дать видам разные seed_dispersal_distance.

Добавить редкие long-distance dispersal events отдельно от обычного распространения.

## Проверки

- suitability не создаёт population из ничего;
- colonization идёт фронтом или через редкое migration event;
- isolated region может долго не иметь подходящего вида;
- после случайного успешного crossing начинается local expansion.

## PASS

Population range зависит одновременно от environment и migration history.

Это первый обязательный шаг к эндемикам и островной эволюции.

---

# EXP-V7 — Lineage Split / Proto-Speciation

## Вопрос

Могут ли изолированные популяции общего предка стабильно разойтись?

## Реализация

После initial colonization изолировать две части карты на длинный simulated interval. Mutation/selection продолжаются независимо.

Первый вариант speciation может быть диагностическим: если genetic/trait distance и reproductive isolation criterion устойчиво превышают порог, создаётся новый stable species_id.

## Метрики

- lineage genetic/trait distance;
- within-population variance;
- between-population variance;
- divergence time;
- niche divergence;
- number of stable lineage splits.

## PASS

Возникает минимум одна воспроизводимая lineage split, объяснимая изоляцией и разными условиями, а phylogeny сохраняет common ancestor.

---

# EXP-V8 — SpeciesCatalog Bake

## Вопрос

Можно ли отделить дорогую эволюцию от дешёвого runtime заселения?

## Реализация

После длинного EXP-V2..V7 run экспортировать:

- species IDs;
- traits;
- niche response summaries;
- lineage tree;
- dispersal traits;
- phenotype recipes stub;
- provenance seed/environment revision.

Затем стартовать новый solver без evolution и заселить другую fixture, используя только Environment + SpeciesCatalog + migration priors.

## Метрики

- catalog serialization determinism;
- reloaded catalog hash;
- distribution similarity для эквивалентного environment;
- absence of impossible species;
- runtime cost relative to original evolution run.

## PASS

Catalog воспроизводимо загружается и создаёт экологически правдоподобную population distribution на порядки дешевле длинного evolution run.

Это ключевой переход от research toy к пригодной архитектуре PlanetSimulator.

---

# EXP-V9 — Phenotype Projection

## Вопрос

Можно ли визуально различать полученные стратегии, не делая mesh частью ecological truth?

## Реализация

Сопоставить traits с параметризуемыми archetypes:

- grass;
- low bush;
- tall bush;
- small tree;
- large tree.

Менять внутри archetype:

- scale;
- height/width ratio;
- branch density;
- leaf density;
- leaf size;
- color ranges.

## Правило

`species_id` и ecological traits остаются canonical для ECO research; конкретный mesh/archetype — presentation.

## PASS

Игрок визуально видит различие стратегий, но замена asset pack не изменяет ecological simulation hash.

---

# EXP-V10 — Population Representation LOD

## Вопрос

Можем ли мы перейти от patch population truth к отдельным деревьям без изменения общей численности/структуры?

## Реализация

Для одного региона реализовать representations:

- L0: aggregate biomass/density;
- L1: colonies/vegetation patches;
- L2: deterministic individual tree instances;
- L3: interactive promoted plants.

## Проверки

- переключение LOD не меняет PopulationPatch truth;
- один и тот же seed/revision материализует совместимое распределение;
- promotion отдельного растения не дублирует biomass;
- demotion возвращает изменение в aggregate state.

## PASS

Representation transitions не создают/уничтожают ecological mass/state и не зависят от camera identity.

---

# EXP-V11 — Player Disturbance Probe

## Вопрос

Может ли небольшое действие игрока стать входом ecology solver, а не scripted replacement?

## Первый сценарий

Игрок/fixture вырубает растительность в локальном patch.

Позже:

- fire;
- irrigation;
- dam/hydrology modification;
- imported species.

## PASS

Population truth отражает изменение, recolonization следует существующим competition/dispersal rules, а не специальному сценарию «после вырубки посадить траву».

---

# Рекомендуемый порядок реализации

## Wave A — доказать причинность

1. EXP-V0 Environmental Field Determinism.
2. EXP-V1 Single Species Resource Response.
3. EXP-V2 Mutation and Local Adaptation.
4. EXP-V3 Competition of Strategies.

После Wave A принимается решение, жизнеспособна ли базовая математическая модель вообще.

## Wave B — доказать экологическую историю

5. EXP-V4 Succession.
6. EXP-V5 Disturbance Mosaic.
7. EXP-V6 Dispersal/Biogeography.
8. EXP-V7 Proto-Speciation.

После Wave B должно быть доказано, что одинаковая текущая среда не обязана давать одинаковое сообщество.

## Wave C — сделать результат пригодным проекту

9. EXP-V8 SpeciesCatalog Bake.
10. EXP-V9 Phenotype Projection.
11. EXP-V10 Representation LOD.
12. EXP-V11 Player Disturbance Probe.

---

# Что сознательно не делать в первой серии

Не добавлять до прохождения EXP-V8:

- животных;
- полноценные food webs;
- сложную сексуальную генетику;
- procedural mesh evolution;
- planet-wide authoritative persistence;
- сетевую репликацию каждой особи;
- реальные сезоны всей планеты;
- chemistry beyond simple plant resource model;
- новый global scheduler.

Эти темы очень интересны, но они могут скрыть главный вопрос: **способна ли простая causal plant ecology сама породить устойчивое разнообразие и сохранить его в portable catalog?**

---

# Минимальный набор графиков/диагностики

Для каждого длинного run сохранять:

- population count / biomass over time;
- number of active lineages;
- diversity index;
- trait means/variance;
- trait vs environment scatter;
- extinction count;
- colonization front position;
- per-patch dominant lineage/trait cluster;
- deterministic run hash;
- simulation cost per 1k generations/steps.

Visual lab должна уметь переключать heatmaps environment/population/traits и перематывать snapshots нескольких поколений, но numerical evidence остаётся обязательным.

---

# Первый конкретный milestone

**ECO.P1 — Plant Adaptation Proof** включает EXP-V0..V3.

Он считается успешным, когда:

1. environment query deterministic и seam-safe;
2. один genome причинно реагирует на resource environment;
3. mutation создаёт локально отличающиеся trait distributions;
4. competition поддерживает минимум три устойчивые стратегии на одной heterogeneous fixture;
5. в коде отсутствуют `DESERT_PLANT`, `RIVER_PLANT`, `FOREST_TREE` и аналогичные hardcoded biome roles;
6. повторный run с тем же seed даёт идентичный result hash;
7. несколько разных seeds дают разные конкретные genomes, но сохраняют сам феномен specialization.

Только после ECO.P1 имеет смысл усложнять систему сукцессией, миграцией и speciation.