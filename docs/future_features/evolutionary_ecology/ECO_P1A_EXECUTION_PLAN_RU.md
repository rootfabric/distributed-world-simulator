# ECO.P1A — Environmental Causality Baseline

## Назначение чекпоинта

ECO.P1A должен доказать две вещи до начала настоящей эволюции:

1. непрерывная экологическая среда получается детерминированной, объяснимой и независимой от presentation/LOD;
2. один фиксированный plant genome причинно реагирует на эту среду, поэтому в разных местах возникает различная жизнеспособность и biomass без biome-specific правил.

ECO.P1A **не включает mutation, natural selection, speciation или межвидовую конкуренцию**. Они начинаются только после принятия базовой причинной модели.

Главный вопрос acceptance:

> Можно ли в любой контрольной точке объяснить, почему одно и то же растение здесь растёт хорошо, плохо или погибает, через конкретные environmental resources и costs?

---

# STEP 1 — Environment Contracts + Deterministic Fixture

## Цель

Создать минимальную ecological truth, на которую будут опираться все следующие опыты, не связывая её с текущей графикой, camera, LOD или конкретной production G-реализацией.

## Сделать

Определить research-контракты минимум для:

- `EnvironmentSample`;
- `EnvironmentFieldProvider`;
- stable sample coordinates / fixture coordinates;
- deterministic environment revision/seed;
- field hashing / replay metadata.

Создать synthetic fixture порядка `4 km × 4 km`, например `128 × 128` logical patches, содержащую:

- river corridor;
- wet lowland;
- dry plateau;
- sunny slope;
- shaded slope;
- flood-prone zone.

Первая версия environment содержит пять непрерывных fields:

- `temperature`;
- `soil_moisture`;
- `sunlight`;
- `nutrients`;
- `flood_frequency`.

Fixture должна быть аналитической/research-only. Она не становится новой terrain/hydrology foundation и позже заменяется адаптером к canonical G/world queries.

## Что проверить

- повторный query одной координаты при одном seed/revision идентичен;
- независимый повторный run даёт тот же environment hash;
- совпадающие координаты дают одинаковые samples при разных diagnostic sampling resolutions;
- нет искусственных швов на logical patch boundaries;
- river/lowland действительно статистически влажнее plateau;
- sunny/shaded slope различаются по sunlight;
- presentation не участвует в вычислении truth.

## Результат шага

Headless `EXP-V0 Environmental Field Determinism` и сериализуемый набор контрольных samples/hashes.

## Gate

`STEP1_PASS` только если deterministic + seam-safe environment доказан численно.

---

# STEP 2 — Single-Plant Resource Model

## Цель

Проверить, что экологическая пригодность возникает из resource balance, а не из одной скрытой magic fitness-функции.

## Сделать

Ввести один фиксированный plant genome с небольшим набором traits:

- `height`;
- `growth_rate`;
- `root_depth`;
- `water_preference`;
- `water_tolerance_width`;
- `shade_tolerance`;
- `seed_count`;
- `seed_dispersal_distance`;
- `lifespan`.

Первая resource-модель должна явно разделять минимум:

### Income

- light/photosynthetic income;
- water availability response;
- nutrient response.

### Costs / penalties

- maintenance;
- root cost;
- structural/height cost;
- growth allocation;
- reproduction allocation;
- flood/water-stress penalty.

Важно: на этом шаге один и тот же genome используется во всём fixture. Никаких `river plant`, `dry plant`, `forest tree`.

## Что проверить

На карте должны естественно появиться:

- favourable zone;
- marginal zone;
- lethal/unsustainable zone.

Экстремальная влажность не обязана быть лучше оптимальной: flood-prone area должна иметь возможность ухудшать результат.

Изменение traits должно иметь trade-off. Например, увеличение `root_depth` может помочь на сухом участке, но обязано иметь дополнительную metabolic/biomass cost.

## Обязательные diagnostics

Для выбранного patch показывать breakdown:

- light income;
- water response/limitation;
- nutrient response/limitation;
- maintenance cost;
- root cost;
- structural cost;
- reproduction allocation;
- flood/stress penalty;
- resulting net energy/resource surplus.

## Метрики

- biomass per patch;
- total biomass over time;
- births/deaths либо эквивалентный cohort turnover;
- net resource balance;
- survival/reproduction success;
- dominant limiting factor.

## Результат шага

Headless `EXP-V1 Single Species Resource Response`.

## Gate

`STEP2_PASS` если spatial niche возникает причинно из resources/costs и модель не имеет очевидного бесплатного монотонного trait (`more is always better`).

---

# STEP 3 — Diagnostic Visual Lab + Controlled Trait Probes

## Цель

Сделать эксперимент наблюдаемым человеком и одновременно проверить чувствительность базовой модели без настоящей эволюции.

## Сделать

Создать presentation-only ECO.P1A lab, которая использует те же contracts, что headless tests.

Минимальные режимы heatmap:

1. temperature;
2. soil moisture;
3. sunlight;
4. nutrients;
5. flood frequency;
6. biomass;
7. net resource balance;
8. dominant limiting factor.

При выборе точки показывать полный `EnvironmentSample`, plant traits и resource/cost breakdown.

Добавить несколько **controlled probes**, которые не являются видами и не входят в canonical catalog:

- BASE;
- SHALLOW_ROOT;
- DEEP_ROOT;
- WATER_LOVING;
- DROUGHT_TOLERANT;
- SHADE_TOLERANT;
- SUN_FAVORED.

Они нужны только для sensitivity experiment: понять, действительно ли изменение одного/нескольких traits ожидаемо перемещает ecological niche.

## Что смотреть глазами

- biomass visually коррелирует с environmental causes, но не является простой копией одного field;
- dry/wet/light/shade zones дают разные причины ограничения;
- deep roots реально расширяют часть dry range, но не бесплатно;
- water-loving probe смещается к влажным зонам;
- shade-tolerant probe лучше переносит low-light area;
- flood extreme способен быть неблагоприятным даже при высокой moisture.

## Результат шага

Запускаемая ECO.P1A visual lab и сохранённые diagnostic screenshots/observations при acceptance.

## Gate

`STEP3_PASS` если поведение можно объяснить визуально и оно совпадает с headless numerical evidence.

---

# STEP 4 — Determinism, Sensitivity and Failure Classification

## Цель

Не принять красивый, но математически хрупкий prototype.

## Сделать

Провести фиксированный набор прогонов:

### Replay

- same seed + same revision + same config -> identical result hash;
- повторный запуск после полного restart -> identical result hash.

### Sensitivity

Небольшие контролируемые изменения:

- moisture field amplitude;
- sunlight field amplitude;
- root cost;
- maintenance cost;
- flood penalty;
- selected plant traits.

Результат должен изменяться непрерывно/объяснимо, а не хаотически перескакивать при микроскопическом изменении параметров, если для этого нет явной нелинейной причины.

### Failure classification

Специально искать:

- global extinction;
- unbounded biomass growth;
- one-field domination (`only moisture matters`);
- free trait escalation;
- boundary seams;
- hidden biome/region conditionals;
- result dependence on presentation resolution;
- unstable floating-point/replay divergence.

## Обязательные outputs

- environment hash;
- simulation hash;
- config/revision/seed;
- total biomass time series;
- per-zone summary;
- resource limitation summary;
- controlled-probe comparison.

## Результат шага

Повторяемый acceptance runner и failure matrix.

## Gate

`STEP4_PASS` если baseline replay deterministic, sensitivity объяснима, а известные runaway/failure modes либо отсутствуют, либо честно классифицированы и ограничены.

---

# STEP 5 — ECO.P1A Acceptance + Decision for Evolution

## Цель

Закрыть базовый причинный чекпоинт и решить, достаточно ли модель хороша, чтобы запускать mutation/selection.

## Acceptance criteria

ECO.P1A считается ACCEPTED только если одновременно выполнено:

1. environment query deterministic и seam-safe;
2. environment truth не зависит от camera/LOD/presentation;
3. один fixed genome создаёт пространственно различную viability/biomass;
4. favourable, marginal и unsustainable zones объяснимы resource breakdown;
5. нет biome-specific placement logic;
6. minimum один structural trade-off доказан экспериментально, предпочтительно `root_depth benefit vs cost`;
7. same-seed replay даёт identical environment/simulation hashes;
8. controlled trait probes ожидаемо сдвигают niche;
9. baseline population/biomass bounded и не уходит в runaway или total extinction;
10. visual lab и headless evidence описывают одну и ту же truth-модель.

## Решение после acceptance

Если PASS:

`ECO.P1A ACCEPTED -> ECO.P1B Local Adaptation Proof`

В P1B controlled probes убираются как источник вариантов. Остаётся один ancestor, а нужные стратегии должна найти mutation + selection.

Если FAIL:

не добавлять evolution. Классифицировать причину в одну из групп:

- ENVIRONMENT_MODEL;
- RESOURCE_MODEL;
- TRADEOFF_MODEL;
- NUMERICAL_STABILITY;
- DIAGNOSTIC_GAP;
- PERFORMANCE_MODEL.

После фикса повторять только затронутые gates и общий deterministic acceptance.

---

# Рекомендуемая последовательность разработки

Работать последовательно:

`STEP 1 -> STEP 2 -> STEP 3 -> STEP 4 -> STEP 5`

Допускается начать заготовку визуального lab параллельно STEP 2 только после того, как contracts STEP 1 стабилизированы. Presentation не должна диктовать структуру environment/resource model.

---

# С чего начать прямо сейчас

Начать с **STEP 1 — Environment Contracts + Deterministic Fixture**.

Это наиболее дешёвый и наиболее важный фундамент ближайшего эксперимента. Если сразу начать с растений или красивой сцены, придётся одновременно отлаживать environmental truth, биологическую модель и presentation, и невозможно будет уверенно определить источник ошибки.

Первый рабочий deliverable должен быть маленьким, но полноценным:

> один headless command/test строит synthetic 4×4 km fixture, запрашивает набор фиксированных координат, проверяет deterministic/seam invariants и печатает stable environment hash плюс значения пяти fields для контрольных точек.

После этого STEP 2 сможет опираться уже на доказанную среду.