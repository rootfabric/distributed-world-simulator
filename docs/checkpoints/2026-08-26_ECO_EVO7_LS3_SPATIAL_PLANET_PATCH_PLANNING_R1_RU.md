# ECO.EVO7 LS3 — Spatial Planet Patch Planning R1

**Статус:** `PLANNING_CHECKPOINT / RESEARCH_ONLY / NO_PRODUCTION_AUTHORITY`  
**Дата:** 2026-08-26  
**База:** LS2.1 `e08dcda410bd71961f956078bb9cfa117f8856bb`  
**Предшественник:** LS2 `f5c38bde45ae78a8242f8e423d04711ac615499e`  
**Цель:** перейти от трёх независимых live-зон к единой пространственной экологической системе на цельном участке поверхности планеты.

Этот checkpoint фиксирует архитектуру LS3 до начала implementation. Он не меняет текущую биологическую fitness-формулу, не активирует production ecology writes и не является FFF7/XFER acceptance.

---

## 1. Главный принцип LS3

LS3 не должен создавать готовый биом как причину.

Запрещённая причинная схема:

```text
biome = desert
  -> выбрать desert plant preset
  -> увеличить drought genes
  -> показать пустынную растительность
```

Нормативная схема LS3:

```text
planet patch
  -> relief + water + soil + temperature + light + moisture
  -> локальные различия establishment / resource balance / competition
  -> reproduction + dispersal + recruitment
  -> spatial selection
  -> community structure
  -> emergent biome classification только постфактум
```

То есть `desert / wetland / forest / alpine / ecotone` являются read-only выводом из физической среды и возникшей растительности, а не входом в fitness, mutation, dispersal или recruitment.

### 1.1. Legacy biome fields

Текущий `EarthRulePipeline` уже вычисляет физические поля, а затем отдельным downstream-правилом добавляет biome semantics. LS3 разрешает читать физические upstream-поля, но запрещает использовать legacy `biome_code`, `biome_name`, `tree_density` или аналогичный готовый vegetation preset как причинный ecological input.

Для acceptance вводится статический/семантический gate: LS3 evolution/recruitment/competition код не должен читать biome label/code.

---

## 2. Что именно меняется относительно LS1/LS2

LS1 доказал причинную дивергенцию одной founder population в трёх независимых live-зонах. LS2 материализовал эти три зоны визуально. LS2.1 добавил read-only observatory.

LS3 меняет research abstraction:

```text
LS1/LS2:
3 independent populations
DRY EDGE | MID PATCH | WET EDGE

LS3:
one contiguous patch
cell(0,0) ... cell(N-1,N-1)
        < dispersal >
        < competition >
        < local recruitment >
```

Никакой новой mutation authority не вводится. Все наследственные изменения по-прежнему обязаны проходить через canonical `LineageExtension.reproduce_bundle()` / accepted mutation kernel.

---

## 3. Размер первого полигона

R1 фиксирует основной acceptance размер:

- grid: `32 x 32`;
- 1024 spatial cells;
- nominal cell size: `16 m`;
- nominal patch width: `512 m`;
- coordinate origin: реальная surface direction из `ProceduralEarthWorld`;
- tangent basis: existing Earth east/north basis;
- world coordinates и surface sampling остаются double precision.

`64 x 64` поддерживается как interactive/stretch configuration после прохождения R1, но не является обязательным closure gate первого implementation slice.

Причина выбора 32x32: это уже полноценная пространственная система с границами, соседями, gradients и dispersal, но она позволяет сохранить короткие deterministic headless tests и не превращать первый LS3 slice в performance-проект.

---

## 4. Слои LS3

### LS3.0 — Real Planet Patch

Добавляется read-only `PlanetPatch` abstraction поверх `ProceduralEarthWorld`.

Для каждой cell фиксируются как минимум:

- patch coordinate `(x, y)`;
- tangent-space center position;
- planet surface direction;
- elevation;
- slope/aspect, если они derivable без новой authority;
- land/water state;
- river/lake/shore masks;
- base temperature;
- base moisture/aridity;
- stable physical sample hash.

`PlanetPatch` не хранит plants и не вызывает evolution. Это только геометрически связный physical substrate.

#### LS3.0 acceptance

1. `32x32 = 1024` deterministic cells.
2. Same world seed + same patch origin => identical patch hash.
3. Cell order не влияет на final patch hash.
4. Adjacent cells являются геометрически соседними на одной tangent patch, а не независимыми случайными Earth samples.
5. Patch не пишет в `ProceduralEarthWorld`, persistence, network или XFER.
6. Legacy biome labels не входят в canonical cell hash для ecology.

---

### LS3.1 — Environment Generator

Цель: получить сильную локальную физическую неоднородность на одном цельном patch, не кодируя названия будущих биомов.

Environment Generator является RAM-only research layer поверх real planet base sample.

Recipe описывает физические драйверы, например:

```text
rainfall / moisture forcing
local drainage
soil texture mixture
water retention
micro-relief amplitude
solar exposure
local temperature offset
surface-water influence radius
```

Recipe не имеет полей `desert`, `forest`, `wetland` и не содержит plant target/preset.

R1 должен иметь минимум три deterministic recipe-профиля для испытаний, но названия профилей физические:

- `WATER_GRADIENT_STRONG`;
- `RELIEF_DRAINAGE_STRONG`;
- `MIXED_PHYSICAL_HETEROGENEITY`.

Они используются как test fixtures, а не как ecological classes.

#### Нормативные environment fields R1

Минимальный spatial environment sample:

- `surface_water_fraction`;
- `soil_moisture`;
- `soil_texture_sand`;
- `soil_texture_clay`;
- `soil_water_retention`;
- `temperature_c`;
- `incident_light`;
- `elevation_m`;
- `local_relief_m`;
- `drainage_index`;
- `land_mask`.

Все значения bounded и детерминированы.

#### LS3.1 acceptance

1. Same patch + same recipe + same environment seed => identical field hash.
2. Different environment seed => different spatial field, сохраняя schema/bounds.
3. Generator создаёт измеримую пространственную variance по moisture/light/soil/relief.
4. Все physical bounds валидны; NaN/INF запрещены.
5. Recipe identity не входит в mutation/reproduction identity.
6. Ни biome label, ни desired plant strategy не являются input генератора.
7. Generator не имеет mutation/reproduction call site.

---

### LS3.2 — Spatial Cohort Lattice

Вместо трёх массивов populations создаётся единая spatial metapopulation.

Каждая cell хранит bounded набор reproductive slots/cohorts. Первый R1 не обязан моделировать миллионы растений.

Начальный бюджет:

- до 4 live individual/cohort slots на cell;
- максимум 4096 materialized ecological records на 32x32 patch;
- визуальный renderer может materialize меньшее число объектов, но ecological state остаётся отдельным от render state.

Founder initialization должна быть environment-neutral:

- один exact founder source;
- deterministic spatial placement;
- cell/environment identity не меняет genome или mutation seed;
- для counterfactual recipes начальный founder pool обязан быть идентичен.

#### LS3.2 acceptance

1. Initial population hash одинаков для counterfactual recipes при одинаковом founder seed.
2. Cell placement может различаться только по deterministic spatial placement seed, не по desired biome.
3. Evolution OFF сохраняет exact hereditary bundle identities.
4. Renderer не является ecological truth.
5. Пустая cell и occupied cell имеют однозначный deterministic state hash.

---

### LS3.3 — Dispersal / Recruitment

Здесь появляется первая настоящая spatial ecology динамика.

Причинная последовательность для offspring:

```text
parent bundle
  -> canonical reproduce_bundle()
  -> immutable child identity
  -> deterministic dispersal route/destination
  -> local environment evaluation
  -> establishment/recruitment
```

Критический инвариант: среда destination cell не имеет права участвовать в mutation identity ребёнка.

Dispersal может использовать уже существующие наследуемые traits, прежде всего `seed_dispersal_distance_m` и seed/reproductive budget, но не вводит альтернативный mutation kernel.

R1 dispersal kernel должен быть bounded и deterministic:

- child dispersal seed выводится из immutable child/lineage identity + generation + offspring ordinal;
- direction/distance фиксируются до чтения destination environment;
- out-of-patch candidates fail/clip по одному документированному правилу;
- recruitment зависит от physical local environment и resource availability.

#### LS3.3 acceptance

1. Same parents => same mutation candidate identities across different environment recipes.
2. Same child identity => same dispersal destination across counterfactual environments.
3. Environment может менять establishment success, но не child mutation/dispersal identity.
4. После нескольких поколений occupied map отличается между сильными physical recipes.
5. Deterministic replay даёт тот же population/spatial hash.
6. Нельзя создать offspring минуя canonical reproduction path.

---

### LS3.4 — Local Competition

Competition добавляется только после spatial recruitment, чтобы не смешивать причинные слои.

R1 использует уже принятые EVO7/FFF поверхности:

- canopy/light interception;
- bounded water demand/uptake;
- root depth/root spread;
- root-shoot allocation;
- structural/maintenance cost;
- water-limited realized resource balance.

Competition обязана быть локальной и order-independent.

Минимальные neighborhoods:

- same cell;
- Moore/Von Neumann neighbor ring, выбранный одной documented policy;
- larger interaction radius только если его требует phenotype trait.

#### LS3.4 acceptance

1. Sum water uptake не превышает available local water.
2. Resource state не становится отрицательным.
3. Evaluation order individuals/cells не меняет final deterministic hash.
4. Dense canopy снижает light downstream только через physical feedback field.
5. Root-heavy strategy имеет измеримую construction/maintenance цену.
6. Competition OFF/ON counterfactual сохраняет mutation identities и меняет selection/community outcome.

---

### LS3.5 — Emergent Biomes

Biome classifier вводится только после работающей spatial ecology.

Это read-only observatory layer.

Он читает:

- physical environment statistics;
- plant occupancy/cover;
- lineage richness;
- LAI/canopy height;
- root strategy;
- water state;
- spatial continuity/fragmentation.

Он может выдавать человекочитаемые labels:

- `desert-like`;
- `wetland-like`;
- `forest-like`;
- `grass/shrub-like`;
- `alpine-like`;
- `ecotone`.

Слово `-like` в research R1 подчёркивает, что это classification результата, а не production biome truth.

#### Нормативный one-way boundary

```text
physical environment + evolved community
                |
                v
        emergent classifier

NO EDGE BACK from classifier to ecology
```

#### LS3.5 acceptance

1. Classifier отключён => evolution/community hashes не меняются.
2. Поиск call sites подтверждает отсутствие biome read в fitness/recruitment/dispersal/competition.
3. Один patch может содержать несколько emergent classes и ecotones.
4. Class boundaries возникают из measured fields/community, а не из заранее заданной segmentation map.

---

### LS3.6 — Rule Workbench

Interactive workbench должен позволять пользователю менять физические условия и наблюдать причинный результат.

Controls R1:

- world seed;
- environment seed;
- environment recipe;
- Start/Pause;
- +1 / +10 / +100 generations;
- Reset same seeds;
- Evolution ON/OFF;
- Competition ON/OFF;
- environment overlay selector;
- population/lineage overlay selector;
- emergent biome overlay selector.

Разрешено менять physical rules/recipe. Запрещена кнопка типа `Make desert plants` или прямое редактирование genome под желаемый результат.

LS2.1 Observatory расширяется spatial metrics вместо создания второго competing observability stack.

---

### LS3.FINAL — Multi-environment Challenge

Финальный research gate должен доказать не красивую картинку, а причинную пространственную эволюцию.

Минимальный challenge:

- один exact founder population;
- один mutation policy;
- минимум 5 deterministic seeds;
- минимум 3 radically different physical environment recipes;
- >= 100 generations или документированный stabilization criterion;
- одинаковый generation-1 mutation identity floor для counterfactual pairs;
- spatial dispersal/recruitment включены;
- competition включена;
- emergent classifier read-only.

Обязательные результаты:

1. Разные physical environments дают статистически разные final community/population hashes.
2. Внутри одного heterogeneous patch возникает минимум два устойчиво различимых vegetation strategy clusters и переходная зона.
3. Water gradient вызывает сильный directional response в water preference/root depth/root-shoot/LAI без environment->genome shortcut.
4. Wet и dry участки имеют измеримо разные recruitment/occupancy trajectories.
5. Competition меняет spatial structure, но не mutation candidate identity.
6. Same-seed replay полностью deterministic.
7. Evolution OFF сохраняет hereditary state.
8. Classifier OFF не меняет ecological state.
9. Никаких production/world/persistence/network/XFER writes.

---

## 5. Observatory для LS3

LS2.1 metrics сохраняются и дополняются spatial metrics:

- global + per-region lineage richness;
- Shannon entropy;
- dominant fraction;
- fixation generation;
- trait mean/variance;
- fitness decomposition;
- occupied cell fraction;
- recruitment success rate;
- dispersal distance distribution;
- local extinction count;
- colonization count;
- mean neighborhood competition;
- spatial variance LAI/root depth/root-shoot/height;
- ecotone width;
- optional spatial autocorrelation metric после R1, если он не утяжелит closure.

Observatory остаётся read-only.

---

## 6. Authority boundary

На всех LS3 stages до отдельного production promotion решения:

```text
world_write                    = false
ecology_production_write       = false
persistence_write              = false
network_replication_write      = false
xfer_authority                 = false
alternate_mutation_authority   = false
biome_classifier_ecology_input = false
```

Все patch/environment/population state живёт в RAM research session.

Production `ProceduralEarthWorld` является read-only physical source и coordinate substrate.

---

## 7. Архитектурные запреты

LS3 считается неуспешным, если появляется хотя бы один из следующих shortcuts:

- `if biome == desert: mutate roots`;
- environment/zone/cell id входит в mutation seed;
- destination environment входит в dispersal identity;
- render geometry используется как ecological source of truth;
- отдельный LS3 mutation kernel;
- direct genome edit из Rule Workbench;
- plant preset выбирается по biome label;
- emergent classifier пишет обратно в environment/evolution;
- global unlimited competition scan каждого растения со всеми растениями;
- nondeterministic iteration order влияет на selection.

---

## 8. Implementation order

Строгий порядок:

```text
LS3.0 Real Planet Patch
  -> LS3.1 Environment Generator
  -> LS3.2 Spatial Cohort Lattice
  -> LS3.3 Dispersal / Recruitment
  -> LS3.4 Local Competition
  -> LS3.5 Emergent Biomes
  -> LS3.6 Rule Workbench
  -> LS3.FINAL Multi-environment Challenge
```

Каждый stage получает отдельный focused acceptance runner и не переписывает predecessor artifacts in-place без repair checkpoint.

---

## 9. Первый implementation slice после этого planning checkpoint

Следующая допустимая работа — **LS3.0 + LS3.1**, без dispersal и competition.

Первый slice должен создать:

1. `32x32` contiguous physical patch;
2. deterministic cell coordinate contract;
3. physical environment field generator поверх real Earth anchor;
4. debug overlay для elevation/water/moisture/soil/light;
5. exact patch/environment hashes;
6. tests на determinism, bounds, order invariance и biome-causality prohibition;
7. headless smoke на exact Godot double build.

После PASS этого слоя можно подключать spatial population state.

---

## 10. Definition of Done для planning checkpoint

Этот planning checkpoint завершён, когда:

- граница physical-first / emergent-biome зафиксирована;
- существующая canonical mutation authority сохранена;
- размер и coordinate model первого patch определены;
- последовательность LS3.0...LS3.FINAL определена;
- acceptance gates для каждого слоя определены;
- production authority остаётся fail-closed;
- следующий implementation slice однозначно ограничен LS3.0 + LS3.1.

**Planning verdict:** `READY_FOR_LS3.0_LS3.1_IMPLEMENTATION`, но только как research/shadow line поверх LS2.1 candidate.
