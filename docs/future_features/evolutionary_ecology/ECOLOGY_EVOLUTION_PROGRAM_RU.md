# ECO — Evolutionary Ecology Program

## 1. Замысел

PlanetSimulator должен уметь заселять случайную точку любой планеты так, чтобы растительность и животные выглядели не как случайно выбранные ассеты, а как результат условий места и истории экосистемы.

Вместо схемы:

`biome -> asset list -> random scatter`

целевой pipeline:

`planet/world truth -> environmental fields -> evolutionary/ecological solver -> species catalog -> population truth -> representation materialization`.

Ключевой вопрос системы — не «что поставить здесь?», а «какие стратегии жизни могли бы здесь выжить, конкурировать, распространяться и сохраняться?»

---

## 2. Непрерывная среда вместо жёстких биомов

Для точки/patch мира определяется `EnvironmentSample`.

Базовые группы параметров:

### Геометрия и положение

- latitude / longitude или WorldAddress;
- elevation;
- slope;
- aspect;
- distance_to_water;
- groundwater_depth;
- flood_frequency.

### Климат

- temperature_mean;
- temperature_seasonality;
- solar_energy;
- precipitation;
- humidity;
- wind;
- snow_cover;
- drought_frequency.

### Грунт/субстрат

- soil_depth;
- water_capacity;
- drainage;
- pH;
- nitrogen;
- phosphorus;
- organic_matter;
- salinity;
- substrate/material identity projection.

### Планетарные условия

- gravity;
- atmospheric_pressure;
- atmospheric composition;
- radiation;
- day_length;
- seasonal forcing.

### Локальная биотическая среда

- canopy/light occlusion;
- neighboring biomass;
- herbivory pressure;
- competition pressure;
- decomposer activity.

`Forest`, `wetland`, `steppe`, `tundra` могут вычисляться позже как диагностические classifications, но не должны управлять canonical ecology truth.

---

## 3. Организм как набор traits

Первичный прототип растения задаётся не классом `OakTree`, а `PlantGenome`/`PlantTraits`.

Минимальный набор:

- preferred_temperature;
- temperature_tolerance;
- preferred_moisture;
- drought_tolerance;
- root_depth;
- root_width;
- growth_rate;
- maximum_height;
- light_requirement;
- shade_tolerance;
- seed_mass;
- seed_count;
- seed_dispersal_distance;
- lifespan;
- nutrient_requirement;
- flood_tolerance;
- salinity_tolerance;
- fire_tolerance;
- defense_level;
- toxicity.

Позже добавляются traits морфологии, размножения, сезонности, симбиоза и химии.

---

## 4. Fitness не должен быть одной функцией похожести

Нежелательный вариант:

`fitness = 1 - distance(environment, preferred_environment)`.

Он полезен как smoke test, но не как конечная модель.

Целевая plant energy/resource model:

`energy_income = light_capture * photosynthesis_efficiency * temperature_response * water_response * nutrient_response`

`energy_cost = maintenance + roots + stem + leaves + defense + reproduction + repair`

Выживание/размножение следуют из положительного resource balance.

Trade-offs должны быть реальными:

- глубокие корни помогают при засухе, но дороги;
- высокий ствол получает свет, но требует structural biomass;
- много мелких семян дают дальнее распространение, но низкую survival probability;
- крупные семена дороже, зато устойчивее;
- токсичность/защита уменьшают herbivory, но требуют ресурсов;
- быстрый рост выигрывает после disturbance, но может проигрывать долговечным конкурентам.

---

## 5. Конкуренция и сукцессия

Даже plant-only модель должна создавать emergent succession.

Пример возможного результата:

`bare substrate -> pioneer plants -> shrubs -> young canopy -> mature canopy`

Эта последовательность не кодируется как state machine. Она должна возникать из:

- скорости роста;
- захвата света;
- доступности воды/питательных веществ;
- стоимости высоты;
- размножения;
- lifespan;
- disturbance.

---

## 6. Эволюция

Evolution loop может работать поколениями или непрерывно через reproduction events.

Минимальные операции:

- reproduction;
- mutation;
- selection;
- migration;
- local extinction;
- lineage tracking.

Позже:

- recombination;
- reproductive isolation;
- explicit speciation;
- coevolution;
- gene flow between neighboring populations.

Не обязательно хранить каждый организм. Для bake-scale предпочтителен hybrid population/cohort solver с distribution по traits.

---

## 7. Population truth вместо миллиардов особей

Планетарный масштаб требует representation hierarchy.

### ECO L0 — Planet Ecology

Хранится:

- species_id;
- region_id;
- population density / biomass;
- niche occupancy;
- migration flux;
- broad ecosystem state.

Никаких отдельных деревьев.

### ECO L1 — Regional Ecology

Материализуются:

- colonies;
- population patches;
- territories;
- migration corridors;
- disturbance state;
- water-hole/resource hotspots.

### ECO L2 — Local Ecology

Возле наблюдателя появляются конкретные:

- tree instances;
- bushes;
- grass clusters;
- nests;
- herds/packs.

### ECO L3 — Interactive Ecology

В ближнем радиусе работают:

- AI;
- damage;
- harvesting;
- eating;
- growth;
- reproduction;
- physics/interactions.

Главный принцип:

> **population is truth; individual is a representation unless interaction promotes it to durable world state.**

---

## 8. История важнее текущей пригодности

Одного `habitat_suitability` недостаточно.

Даже если вид идеально подходит месту, он может отсутствовать из-за:

- географической изоляции;
- отсутствия migration path;
- недавнего пожара;
- конкурента;
- болезни;
- локального вымирания;
- деятельности игроков;
- того, что линия эволюционно возникла в другой части планеты.

Поэтому runtime resolver должен учитывать минимум:

`environment + species niche + dispersal history + population history + disturbance history`.

Это создаёт эндемиков, разные островные сообщества и настоящую биогеографию.

---

## 9. SpeciesCatalog как результат bake/evolution

Evolution incubator выдаёт не готовые placements, а каталог видов.

Для каждого вида желательно сохранять:

- stable species_id;
- genome/traits;
- lineage parent(s);
- niche response curves;
- phenotype recipe;
- reproduction/dispersal model;
- interaction traits;
- known range priors;
- provenance/evolution run metadata.

Пример runtime query:

`species_candidates = catalog.query(environment, geography, history)`

после чего population solver определяет реальное присутствие/плотность.

---

## 10. Филогения и эндемизм

Полезно хранить дерево происхождения:

`ancestor -> lineage A -> species A1/A2`

`ancestor -> lineage B -> species B1`

Это позволяет:

- формировать похожие, но разные виды на изолированных островах;
- давать игроку научное исследование происхождения;
- оценивать genetic similarity;
- сохранять историю альтернативной эволюции планеты.

---

## 11. Phenotype отдельно от ecological genome

Не нужно в первой версии эволюционировать полноценный mesh.

Разделение:

### Ecological genome

Определяет survival strategy и interaction traits.

### Phenotype recipe

Определяет представление:

- height;
- trunk thickness;
- branching density;
- branching angle;
- leaf size;
- leaf shape family;
- leaf density;
- root visibility;
- color ranges;
- flower/fruit parameters.

На раннем этапе phenotype может выбирать ближайший готовый asset archetype и параметризовать его.

Позже возможны L-system, graph grammar или procedural plant generators.

Важная цель — чтобы форма была объяснима экологией: ветер -> ниже и крепче; конкуренция за свет -> выше; засуха -> меньше leaf area и глубже корни.

---

## 12. Disturbance как обязательный фактор

Без disturbance система рискует быстро прийти к однообразному доминирующему состоянию.

Будущие disturbance types:

- fire;
- flood;
- drought;
- storm;
- landslide;
- volcanic event;
- disease;
- unusual freeze/heat wave;
- impact event;
- player-created disturbance.

Одинаковый climate + разная disturbance history должен давать разные landscapes.

---

## 13. Не искать статический «баланс»

Цель evolution bake — не обязательно неподвижное equilibrium.

Лучше искать устойчивый **dynamic attractor**:

- bounded population oscillations;
- stable coexistence bands;
- recurring succession;
- устойчивые extinction/recolonization patterns.

Acceptance должна измерять стабильность диапазонов и отсутствие runaway collapse/explosion, а не требовать абсолютно постоянных чисел.

---

## 14. Животные — после доказательства plant-only модели

Будущие fauna traits:

- body_mass;
- metabolism;
- locomotion cost;
- movement speed;
- sensory ranges;
- diet profile;
- digestive efficiency;
- toxin tolerance;
- reproduction rate;
- offspring strategy;
- sociality;
- territory size;
- camouflage;
- armor;
- activity cycle.

Food web должен опираться на свойства пищи, а не на hardcoded `Rabbit eats Grass01`.

Plant nutrition/defense properties:

- protein;
- carbohydrates;
- fiber;
- water;
- toxins;
- minerals;
- digestibility.

Это позволяет coevolution: plant toxin <-> herbivore tolerance, predator performance <-> prey escape/armor/social behavior.

---

## 15. Player impact и terraforming

Ecology должна реагировать на world changes:

- вырубка;
- пожар;
- строительство дамб;
- изменение hydrology;
- pollution;
- mining/excavation;
- agriculture;
- introduction of alien species;
- atmosphere/climate changes.

Пример:

`dam -> groundwater rises -> soil moisture changes -> old community loses suitability -> wetland species spread -> herbivore distribution changes -> predator distribution changes`.

Terraforming не должен делать `replace tundra with forest`. Он меняет environmental conditions, после чего ecology реагирует сама.

---

## 16. Invasive species

Вид с другой планеты/континента может попасть в новую среду.

Если:

- climate подходит;
- natural predators отсутствуют;
- конкуренты слабее;

он может стать invasive и изменить population truth.

Это создаёт emergent gameplay без ручного сценария.

---

## 17. Player discovery gameplay

ECO может стать основой научного gameplay.

Игрок обнаруживает неизвестный species_id, сканирует:

- morphology;
- environmental tolerance;
- chemistry;
- lineage;
- ecological role;
- possible uses.

Каталоги могут быть:

- personal;
- settlement;
- faction/science network;
- planetary.

Практическая ценность видов:

- food;
- medicine;
- construction material;
- fibers;
- biofuel;
- industrial chemistry;
- terraforming;
- farming/breeding.

---

## 18. Artificial selection

Позже игрок может выращивать поколения и выбирать traits:

- yield;
- fruit size;
- cold tolerance;
- drought tolerance;
- growth speed;
- useful chemistry.

Результат должен становиться новым stable cultivar/genome, пригодным для торговли и распространения.

---

## 19. Alien life extensibility

Первая реализация может быть Earth-like carbon/water/photosynthesis.

Но contracts не должны намертво предполагать только Earth biology.

Будущий `LifeChemistryProfile` может задавать:

- solvent;
- primary chemistry basis;
- energy sources;
- atmospheric requirements;
- radiation interaction.

Это оставляет путь к chemosynthesis, methane environments и фантастической биологии без переписывания всей архитектуры.

---

## 20. Offline evolution vs runtime ecology

Разделяем две задачи.

### Evolution Incubator / Bake

Дорогая ускоренная симуляция:

- тысячи/миллионы поколений;
- mutation/selection/speciation;
- поиск устойчивых стратегий;
- формирование SpeciesCatalog.

Может выполняться заранее, асинхронно или как development/content pipeline.

### Runtime Ecology

Не переигрывает миллионы лет при подлёте игрока.

Она использует:

- baked catalog;
- environmental truth;
- persistent population/history state;
- deterministic procedural materialization.

---

## 21. Network / server zoning

Клиент не должен быть authoritative ecology solver.

Authoritative крупномасштабное состояние в будущем:

- PopulationPatchState;
- EcologyEpoch/Revision;
- DisturbanceHistory;
- promoted durable individuals when necessary.

Клиенту можно передавать компактное representation data:

- region_id;
- ecology_revision;
- species population summary;
- deterministic materialization seed/recipe.

На границе серверных зон передаются агрегаты:

- migration flux;
- disturbance propagation;
- water/resource boundary effects;
- population boundary conditions.

Не требуется сетевой entity на каждое растение.

---

## 22. Интеграция с world generation

Целевая зависимость:

`Planet Parameters -> Geology -> Terrain -> Hydrology -> Climate/Environment Fields -> ECO -> Flora/Fauna Presentation`.

ECO не решает, где проходит canonical river и не владеет material truth.

Она потребляет G/Matter/Environment queries и производит ecological state/derived representations.

---

## 23. Программа ECO0–ECO10

### ECO0 — Contracts

Определить research contracts:

- EnvironmentSample;
- PlantGenome/SpeciesTraits;
- SpeciesCatalog;
- PopulationPatch;
- NicheResponse;
- DisturbanceEvent;
- PhenotypeRecipe;
- provenance/replay metadata.

### ECO1 — Environmental Field Lab

Небольшой deterministic landscape и визуализация непрерывных environmental fields.

### ECO2 — Plant Competition Baseline

Plant-only ресурсная модель без сложной speciation. Проверить coexistence и specialization.

### ECO3 — Evolution + Lineages

Mutation, selection, migration, lineage tracking, extinction и initial speciation experiments.

### ECO4 — Herbivore Research

Добавить plant consumption и простейшие herbivore populations.

### ECO5 — Predator / Food-Web Research

Проверить устойчивость нескольких trophic levels.

### ECO6 — Ecosystem Bake

Сформировать portable deterministic SpeciesCatalog и ecological priors.

### ECO7 — Runtime Population Resolver

Environment + history + catalog -> population distribution без повторной длинной evolution simulation.

### ECO8 — Visual Materialization

Population truth -> vegetation/animal representations с LOD/promotion rules.

### ECO9 — Persistent Living Ecology

Disturbance, harvesting, construction effects, invasive species, long-term population state.

### ECO10 — Discovery / Breeding Gameplay

Научный каталог, species discovery, artificial selection, trade/use of biological resources.

---

## 24. Главный research proof

Первый proof считается успешным, если на одном deterministic landscape без жёстких biome classes и hardcoded species roles из общих ancestral plant genomes стабильно возникают несколько экологически специализированных линий, а сохранённый SpeciesCatalog затем воспроизводимо заселяет другой участок со сходными условиями.

Это доказывает самую важную идею программы:

> разнообразие мира можно получать не из случайной таблицы ассетов, а из причинно связанной модели среды, эволюции, распространения и истории.