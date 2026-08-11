# ECO — Evolutionary Ecology Research

Статус: **research/design frontier**. Эта ветка не является новым runtime-владельцем и не меняет canonical world truth.

Цель программы — исследовать способ заселения процедурных планет правдоподобными экосистемами, где виды, сообщества и формы растений выбираются не жёсткими biome labels, не классами `TREE/BUSH/GRASS` и не случайной расстановкой ассетов, а возникают из условий среды, конкуренции, миграции, наследования, developmental programs и эволюционной истории.

Ключевая формула программы:

> **Environment + History + Evolution → Species Catalog + Population Truth → Runtime Representations**

Для формы растения добавляется второй контур:

> **Genome + Environment + Age + History + IndividualSeed → DevelopmentState → GrowthGraph → Phenotype → Representation**

## Главные принципы

1. **Biomes are observations, not rules.** Лес, тундра, болото и степь могут быть диагностическими ярлыками результата, но не должны быть первичной истиной генерации.
2. **Species are discovered, not placed.** Вид должен иметь экологические traits, нишу, происхождение и ограничения распространения.
3. **Population is canonical, individuals are representations.** Планетарная истина хранит популяции/колонии/ареалы; отдельные растения и животные материализуются только на нужном representation level.
4. **Ecology depends on history.** Одинаковые по текущему климату участки могут иметь разный состав видов из-за миграции, изоляции, пожаров, наводнений, вымираний и деятельности игроков.
5. **Fitness emerges from resources and costs.** Не использовать единственную магическую fitness-функцию вида `distance(environment, optimum)`. Организмы должны получать энергию/ресурсы и платить за рост, защиту, размножение, корни, ствол, листья и прочие traits.
6. **Plant form is developmental, not a hardcoded class.** Tree-like, shrub-like, grass-like и другие формы должны быть областями одного пространства developmental traits.
7. **Phenotype is not genome.** Один genome может давать разные формы в разных environment/history conditions; renderer не должен менять ecology truth.
8. **Ecology consumes world truth; it does not own geology, hydrology, matter, authority, persistence or networking.**

## Документы ветки

- `ECOLOGY_EVOLUTION_PROGRAM_RU.md` — полная концепция программы ECO, модели данных, runtime/bake архитектура и долгосрочные этапы ECO0–ECO10.
- `VEGETATION_EXPERIMENT_PLAN_RU.md` — конкретная последовательность экспериментов с растительностью от простого environmental field до эволюции, сукцессии, биогеографии и воспроизводимого bake.
- `PLANT_DEVELOPMENT_PHENOTYPE_TRACK_RU.md` — сквозной ECO.PH track: genome → DevelopmentState → ShootGraph/RootGraph → phenotype → seed lifecycle → visual materialization без hardcoded Tree/Bush generators.
- `P0_TECHNICAL_ALIGNMENT_RU.md` — границы владения и интеграция с G, Matter, Network, Construction, World Query/Work Budget и центральным PC0.
- `config/ecology/eco-evolutionary-ecology-roadmap.v1.json` — machine-readable research roadmap, ECO.PH convergence gates и основной порядок экспериментов.
- `config/control/branches/feature__eco-evolutionary-ecology.v1.json` — паспорт ветки.

## Первый практический vertical slice

Первый эксперимент не пытается делать животных, полноценную генетику или планетарный runtime.

Берётся участок порядка **4 × 4 км** с рекой, влажной низиной, сухим плато и склоном. Для него задаются непрерывные поля:

- temperature;
- soil moisture;
- sunlight;
- nutrients;
- flooding.

Стартуют около **20 ancestral plant genomes** с небольшим набором traits:

- height;
- growth_rate;
- root_depth;
- water_preference;
- shade_tolerance;
- seed_count;
- seed_dispersal_distance;
- lifespan.

Главная проверка: без hardcoded `river_plant`, `hill_plant`, `forest_tree` система должна сама получить устойчиво различающиеся линии, специализирующиеся на влажном берегу, сухом склоне, открытых местах и затенении.

Если это удаётся, результат сохраняется как `SpeciesCatalog + niche distributions`, после чего другой аналогичный участок должен воспроизводимо заселяться этими видами без повторного многотысячепоколенного evolution run.

После принятия базовой P1A causal/resource модели открывается ECO.PH0/PH1: сначала genome должен детерминированно строить **skeleton/GrowthGraph**, затем environment должен менять phenotype, затем morphology получает настоящие resource costs. Полноценный mesh остаётся поздним representation-этапом.

## Текущий scope ветки

Разрешено:

- архитектура;
- формализация контрактов;
- математические и headless research prototypes;
- deterministic experiment fixtures;
- offline/bake experiments;
- визуальные лаборатории, не претендующие на canonical world truth;
- deterministic GrowthGraph/skeleton research;
- developmental trait и seed lifecycle research contracts;
- метрики, acceptance criteria и результаты исследований.

Пока не разрешено считать готовым production runtime:

- planet-wide ecology authority;
- authoritative persistent populations;
- сетевую репликацию экологии;
- изменение canonical G/Matter state;
- новый scheduler/work-budget;
- новый spatial identity;
- новую persistence/transaction foundation;
- хранение GrowthGraph каждого растения как planet-wide truth.

Переход к runtime должен проходить отдельный PC0/harness gate после того, как исследовательская модель докажет полезность и появятся необходимые canonical contracts мира.