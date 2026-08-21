# ECO.PH — Plant Development & Phenotype Track

Статус: **research/design track внутри ECO**. Это не отдельный runtime-frontier и не новый владелец world truth.

## 1. Зачем нужен этот track

Текущий ECO уже умеет описывать растение числовым genome/traits и проверять, где оно может жить. Следующий шаг — сделать так, чтобы genome определял не только экологическую нишу, но и **программу развития формы**.

Целевая цепочка:

`Genome + Environment + Age + History + IndividualSeed -> DevelopmentState -> GrowthGraph -> Phenotype -> Representation`

После размножения:

`Parent Genome -> inheritance/mutation -> SeedGenomeEnvelope -> germination -> new DevelopmentState`.

Главная цель — не иметь жёстких классов `TREE`, `BUSH`, `GRASS`. Дерево, куст, трава, стелющееся растение или необычная инопланетная форма должны быть областями одного пространства developmental traits.

---

## 2. Главные инварианты

1. **Tree/bush/grass are observations, not canonical organism classes.**
2. **Genome defines a development program, not a mesh asset.**
3. **Phenotype = Genome × Environment × Age × History × IndividualSeed.**
4. **Morphology must pay ecological costs before evolution is allowed to select it.**
5. **GrowthGraph is derived representation state for ordinary individuals; population remains canonical truth.**
6. **An interacted/promoted individual may persist GrowthGraph deltas, damage and development state.**
7. **Changing renderer, mesh tessellation, leaf asset or LOD must not change ecology/genome hashes.**
8. **Seed carries heredity and deterministic individual identity, not a prebuilt plant model.**

---

## 3. Разделение genome

Целевой `PlantGenome` логически делится на несколько групп.

### 3.1 Ecological / metabolic traits

Уже существующие и будущие параметры:

- growth_rate;
- water_preference;
- water_tolerance_width;
- shade_tolerance;
- root_depth;
- lifespan;
- nutrient demand;
- flood tolerance;
- temperature response;
- defense/toxicity.

### 3.2 Developmental traits

Минимальный первый набор:

- max_height;
- internode_length;
- main_axis_strength;
- apical_dominance;
- branch_probability;
- branch_angle;
- branch_length_ratio;
- branch_thickness_ratio;
- branching_depth;
- crown_spread;
- leaf_density;
- leaf_area;
- leaf_orientation;
- root_lateral_spread;
- root_branch_probability;
- root_gravitropism;
- shoot_gravitropism;
- phototropism.

Позже:

- wood_density;
- branch_flexibility;
- leaf_thickness;
- leaf_lifespan;
- flower_density;
- fruit_size;
- seed_mass;
- dormancy strategy;
- seasonal growth rules.

Никакого обязательного `plant_type = TREE`.

---

## 4. DevelopmentState

Genome — это наследуемая программа, но конкретное растение должно иметь состояние развития:

- age;
- biomass/reserves;
- active growth tips;
- damaged/pruned segments;
- accumulated stress;
- current leaf/flower/fruit state;
- dormancy;
- root/shoot allocation;
- disturbance history relevant to this individual.

`DevelopmentState` не должен менять genome сам по себе.

---

## 5. GrowthGraph

Между genome и mesh вводится абстракция `GrowthGraph`.

Два домена:

- `ShootGraph`;
- `RootGraph`.

Условный segment/node хранит:

- stable local segment id;
- parent segment;
- start/end or direction/length;
- radius start/end;
- age;
- health;
- growth-tip state;
- leaf attachment sites;
- flower/fruit attachment sites;
- local resource/stress annotations при необходимости диагностики.

GrowthGraph нужен для:

- детерминированной формы;
- разных LOD;
- повреждения/обрезки;
- дальнейшего mesh generation;
- сохранения только тех individuals, которые реально promoted interaction-ом.

Он **не становится planet-wide canonical truth для каждого дерева**.

---

## 6. Как genome превращается в форму

Первая реализация должна использовать параметрическую stochastic development grammar.

Каждый active growth tip принимает решение из:

`developmental traits + local resources + gravity + light direction + obstacles + IndividualSeed`.

Например новое направление побега может складываться из:

- inherited branch angle;
- apical dominance;
- phototropism;
- gravitropism;
- deterministic individual variation;
- позже wind/obstacle response.

### Почему не начинать сразу с mesh

Сначала строится только skeleton/GrowthGraph. Это позволяет быстро проверять:

- плавный переход tree -> shrub;
- влияние одного trait;
- детерминизм;
- отсутствие скрытой asset-классификации;
- экологическую цену формы.

---

## 7. Алгоритмические варианты

### P0 — stochastic parametric grammar

Первый выбор для прототипа.

Genome управляет branch probability, internode length, angle, depth и dominance. Environment меняет вероятность/направление роста.

Плюсы: просто, быстро, хорошо мутируется, детерминируется IndividualSeed.

### P1 — environment tropisms

Добавляются:

- phototropism;
- shoot/root gravitropism;
- root attraction to moisture/nutrients;
- local suppression при нехватке ресурсов.

Один genome начинает давать разные phenotype в разных местах.

### P2 — space colonization для кроны

Опционально после доказательства grammar. Genome задаёт crown envelope, а ветви заполняют доступное пространство attraction points.

Не должен быть prerequisite для первых evolution experiments.

### P3 — procedural mesh

GrowthGraph превращается в:

- tube/spline branches;
- parameterized leaf archetypes;
- flowers/fruits;
- root geometry при необходимости.

Renderer — только representation.

---

## 8. Phenotypic plasticity

Один genome должен давать разные формы без mutation.

Примеры:

- открытое место -> более широкая крона;
- плотный canopy -> длиннее основной axis и меньше нижних ветвей;
- сухое место -> меньшая leaf area / иное root allocation;
- сильный wind в будущем -> ниже, толще, асимметричнее;
- иная gravity -> другая цена высоты и толщины.

Это позволяет отличить:

- **genetic adaptation**;
- **phenotypic response одного genome на среду**.

---

## 9. Morphology должна влиять на ecology

Если developmental traits только меняют картинку, evolution никогда не сможет осмысленно выбирать форму.

Нужны реальные trade-offs.

### Height

`+ light access / canopy competition`

`- structural biomass - maintenance - gravity/wind cost`

### Leaf area / density

`+ light capture`

`- construction - maintenance - transpiration/water loss`

### Branching

`+ crown coverage / light capture`

`- woody biomass - transport/maintenance cost`

### Root depth / spread

`+ water/nutrient access`

`- construction/maintenance cost`

S2 уже доказал первый такой trade-off для root depth. ECO.PH расширяет тот же принцип на видимую morphology.

Правило gate:

> trait нельзя считать evolutionary-selectable morphology, пока его benefit/cost не связан с resource model.

---

## 10. SeedGenomeEnvelope

Минимальный seed contract:

- genome / stable genome reference;
- lineage parent;
- mutation delta/provenance;
- stored energy;
- dormancy state;
- age;
- deterministic `individual_seed`.

Рекомендуемый individual seed:

`hash(parent_lineage, reproduction_event, seed_index, genome_revision)`.

Он определяет конкретную реализацию stochastic development без изменения inherited genome.

Жизненный цикл:

`Seed -> germination -> juvenile DevelopmentState -> GrowthGraph growth -> reproductive adult -> Seed`.

---

## 11. Population truth и materialization

Далеко от игроков:

`PopulationPatch(species/genome distributions, density, biomass, age distribution)`.

При materialization:

`PopulationPatch + genome + individual_seed + local environment -> derived individual phenotype`.

Обычный individual может быть dematerialized и воспроизведён детерминированно.

Если игрок:

- срубил ветвь;
- повредил растение;
- пересадил его;
- собрал плоды;
- сделал растение объектом долговременного gameplay,

individual может быть promoted в durable state с сохранённым DevelopmentState/GrowthGraph delta.

Это сохраняет принцип:

> **population is truth; individual is representation until interaction promotes it.**

---

## 12. ECO.PH roadmap

ECO.PH — сквозная исследовательская дорожка. Она не заменяет P1/P2/P3, а сходится с ними в определённых gates.

### PH0 — Development Trait Contract

**Когда:** после принятия ECO.P1A.

**Результат:**

- `DevelopmentTraits` schema;
- разделение inherited genome / DevelopmentState / GrowthGraph / renderer;
- deterministic IndividualSeed contract;
- запрет `TREE/BUSH/GRASS` как canonical type.

**Gate:** изменение developmental traits не меняет EnvironmentSample; renderer не влияет на genome/resource truth.

### PH1 — Deterministic GrowthGraph Skeleton Lab

**Можно вести параллельно с:** ECO.P1B Local Adaptation Proof.

**Результат:** один genome строит line/skeleton plant без mesh.

Контролируемые morph tests:

- apical dominance 1 -> 0;
- branch angle narrow -> wide;
- internode long -> short;
- branch probability low -> high.

**Gate:** плавные morphology transitions, deterministic graph hash, отсутствие hardcoded tree/bush classes.

### PH2 — Environment-Coupled Development / Plasticity

**Depends on:** PH1 + accepted P1A environment/resource contracts.

**Результат:** один genome получает разные GrowthGraph/phenotype в разных environment samples.

**Gate:** genetic genome одинаков, phenotype отличается объяснимо; environment truth не зависит от development representation.

### PH3 — Morphology-to-Resource Coupling

**Depends on:** PH2 + resource model.

**Должен сойтись до:** финального Strategy Competition Proof.

Добавляются реальные costs/benefits height, leaf area/density, branching, crown spread и root architecture.

**Gate:** нет `bigger is always better`; минимум три morphology traits имеют измеримый trade-off.

### PH4 — Seed Development Lifecycle

**Depends on:** mutation/inheritance contracts из ECO.P1B + PH3.

**Должен сойтись до:** `EXP-V6 Dispersal and Biogeography`.

**Результат:** parent -> seed genome envelope -> mutation -> germination -> juvenile -> adult -> new seeds.

**Gate:** одинаковый seed envelope детерминированно воспроизводит lineage/genome/development initial state; dispersal переносит heredity, а не готовый mesh.

### PH5 — Procedural Visual Materialization

**Сходится с:** `EXP-V9` в ECO.P3.

**Результат:**

- GrowthGraph -> branch mesh;
- parameterized leaf/flower/fruit archetypes;
- LOD projection;
- визуально различимые evolved developmental traits.

**Gate:** смена renderer/asset pack/tessellation не меняет ecology/genome hashes.

### PH6 — Promoted Individual Persistence

**Сходится с:** ECO.P3 representation/persistence research и будущим runtime promotion gate.

**Результат:** сохранение damage/pruning/growth delta только для promoted individuals.

Не разрешает ECO самостоятельно владеть production persistence.

---

## 13. Convergence с основной ECO roadmap

### P1A

Остаётся как есть. До его принятия не добавлять developmental complexity в resource truth.

### P1B Local Adaptation

Добавить mutation-ready developmental traits, но не требовать полноценный mesh. PH1 может идти параллельно.

### P1C Strategy Competition

Перед финальным acceptance конкуренции требуется convergence с PH3, иначе система докажет конкуренцию только абстрактных чисел, а не форм, которые действительно платят за свою morphology.

### P2 Ecological History

PH4 seed lifecycle становится естественным носителем наследования и dispersal для EXP-V6. Биогеография распространяет genome/lineage через seeds/population flux, а не placements готовых растений.

### P3 Portable Ecology

`EXP-V9 Phenotype Projection` расширяется до **Developmental Phenotype Materialization**:

`SpeciesCatalog genome + IndividualSeed + Environment -> Development/GrowthGraph -> visual phenotype`.

PH5 реализует mesh/leaf presentation, PH6 связывает promoted individuals с будущей persistence architecture.

---

## 14. Что не делать сейчас

До принятия P1A и PH0/PH1 не нужно одновременно строить:

- full L-system editor;
- высокодетальный procedural mesh;
- физику каждой ветки;
- growth simulation каждого растения на планете;
- сексуальную генетику;
- GPU forest renderer;
- network replication каждого GrowthGraph;
- собственную ECO persistence foundation.

Первое доказательство формы должно быть дешёвым: **genome -> deterministic skeleton**, затем **environment -> phenotype plasticity**, затем **morphology -> resource cost**.

---

## 15. Ближайший эксперимент после P1A

После принятия `ECO.P1A-S5` рекомендуемый старт ECO.PH:

1. реализовать 6–8 developmental traits;
2. построить один deterministic shoot skeleton линиями;
3. добавить sliders/controlled probes;
4. получить плавный переход высокого single-axis растения к широко ветвящемуся shrub-like phenotype;
5. доказать, что это один generator и одно trait-space, без `TreeGenerator`/`BushGenerator`;
6. только после этого подключать environment tropisms и resource costs.

Это даст ранний ответ на главный вопрос track:

> **может ли один общий developmental model порождать качественно разные формы растений из genome, не кодируя классы растений вручную?**
