# ECO.EVO7 FFF0 — Contract Mapping Audit

**Статус:** `RESEARCH_CANDIDATE / NON_CANONICAL_UNTIL_ACCEPTED`
**Дата:** 2026-08-23
**Базовый HEAD спецификации:** `d4d5c309a2da772751cd53adf17554eea697dd19` (`docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md`, далее «ТЗ»)
**Ветка:** `feature/eco-evo7-fff-r1`
**Exit-критерий ТЗ §19 FFF0:** design checkpoint PASS — точная таблица `EVO7 semantic axis -> accepted PH field`, инвентарь mutation authority и environment channels, замороженные ownership boundaries, минимальный список действительно новых contract-полей.

Этот документ — результат аудита существующего кода на ветке `feature/eco-evo6-water-selection-r1` @ `d4d5c309`. Все ссылки `файл :: символ` проверены чтением исходников и зафиксированы машинно в `tests/research/ecology/eco_evo7_fff0_contract_mapping_acceptance.gd`.

---

## 1. Инвентарь mutation authority (единственное ядро наследственности)

`scripts/research/ecology/plant_mutation_lineage_kernel_v1.gd :: MutationKernel`

| Факт | Значение | Следствие для EVO7 |
|---|---|---|
| `MUTABLE_TRAITS` | ровно `["water_preference","root_depth_m","growth_rate","shade_tolerance","seed_dispersal_distance_m"]` | **Ни один морфологический признак сейчас не эволюционирует.** PH0-триты существуют, но вне отбора |
| policy | `default_policy()`: `mutation_probability` 0.42 + per-trait `_step`; `policy_hash()` | политика тритов живёт в schema/registry — расширение по ТЗ §12.2 |
| heredity | `reproduce()` + `plant_lineage_record_v1 :: LineageRecord` (`mutation_event_hash`, `parent_genome_checksum`) | lineage identity сохраняется при любом extension |
| consumers | `evo6_water_evolution_bridge_v1.gd` делегирует `MutationKernel.reproduce`, меняя только `mutation_probability=0.52` | паттерн «bridge без второго ядра» доказан — EVO7 повторяет его |

**Ключевой вывод FFF0-A:** семантический gap «морфология вне эволюционного контура» доказан. Это главный пробел, который закрывает FFF2 — через versioned additive extension политики/kernel (ТЗ §12.1), не через второй мутатор.

## 2. Наследуемые носители сегодня

Два разных наследуемых контракта уже существуют и **не должны быть слиты**:

1. `plant_genome_v1.gd :: PlantGenome` — ecological scalar-геном, 13 полей, `validate()` требует exact field count (`genome.keys().size() != FIELD_NAMES.size()` ⇒ reject). Schema v1 in-place не расширяется (ТЗ §2.4).
2. `plant_development_traits_v1.gd :: Traits` — морфологический потенциал PH0, 8 тритов + `BOUNDS` + checksum; ровно 12 полей контракта (зафиксировано `docs/plans/ECO_EVO4_B1/B2` derivation contracts).

Связка геном↔триты идёт через принятые derivation contracts EVO4-B1/B2; seed envelope (`plant_development_contract_v1 :: create_seed_envelope`) несёт оба checksum + детерминированный `individual_seed`.

## 3. Главная таблица: EVO7 semantic axis → accepted surface

| Ось ТЗ §3.1 | Существующий носитель | Вердикт | Обоснование / semantic gap |
|---|---|---|---|
| Stature / height potential | `PlantGenome.height_m` [0.05–50]; PH0 `max_height_m` [0.10–40]; GrowthGraph `metrics.height_m` | **REUSE** | Полная цепочка потенциал→реализация→метрика существует |
| Crown spread / apical dominance | PH0 `crown_spread_m`, `apical_dominance`, `branch_probability`, `branch_angle_deg`, `branch_length_ratio`, `branching_depth` | **REUSE** | Силуэт и ширина кроны полностью параметризованы |
| Crown density | косвенно: произведение branch-тритов; render-side `foliage_fraction` (визуальный knob); в PH track doc §3.2 заявлены, но не реализованы `leaf_density`/`leaf_area` | **NEW (additive)** | Явной наследуемой оси листовой плотности нет; shape-прокси не задаёт фотосинтетическую площадь и водный спрос |
| Leaf economics (SLA proxy) | отсутствует полностью (grep: нет sla/leaf thickness/turnover в .gd/.py) | **NEW (additive)** | Доказанный gap |
| Structural investment / wood density | только cost-сторона: `plant_resource_model_v1 :: structural_cost = 0.095*pow(height_m,1.20)`; PH3 `structural_cost_scale`. Наследуемой оси нет | **NEW (additive)** | Есть цена без оси: нужно наследуемое значение, которое эта цена масштабирует |
| Root depth | `PlantGenome.root_depth_m` (mutable! работает в `evo6_water_fitness_v1` dry-bonus и `with_root_depth`) | **REUSE** | Уже эволюционирующий функциональный признак |
| Root spread | отсутствует (`root_lateral_spread` — только bullet в PH track doc; RootGraph в коде не существует) | **NEW (additive)** | Доказанный gap |
| Root-shoot allocation | placeholder: `plant_development_contract_v1.create_initial_development_state()` кладёт `root_allocation`/`shoot_allocation` = 0.5, их никто не читает и не наследует | **NEW (additive) + wiring** | Поле состояния есть, наследуемого потенциала и потребителя нет |

Сводка: **reuse = 4 оси** (stature, crown spread/apical dominance, root depth + вся PH0 branch-механика), **new additive поля = 5** (`foliage_density`, `leaf_economics_proxy`, `structural_investment`, `root_spread_m`, `root_shoot_ratio`). Минимальность списка соответствует exit-критерию FFF0.

## 4. Реализация фенотипа (plasticity) — переиспользуется как есть

- `plant_environment_coupled_development_v1.gd :: realize(seed_envelope, inherited_traits, environment_sample, response_profile)` → `realized_development_traits` + `growth_graph` + `phenotype_hash`.
- Коэффициенты отклика: `plant_development_plasticity_profile_v1 :: shade_elongation_strength, drought_size_suppression, light_branching_strength, ...` (0–1).
- Это точное воплощение `realized_trait = genetic_potential * plastic_response(...)` из ТЗ §1.1/§6. Среда модифицирует реализацию и никогда — checksum генома (доказано тестом PH0: «development traits do not mutate accepted genome»).

EVO7 расширяет только **набор входов** (understory light, water stress уже частично есть) и добавляет derived functional phenotype поверх `realized_*`, не трогая механизм.

## 5. Детерминизм — поверхности переиспользуются

- individual seed: `plant_development_contract_v1 :: derive_individual_seed(parent_lineage, reproduction_event, seed_index, genome_revision)` (sha256 → s63).
- стохастика формы: `plant_growth_graph_skeleton_v1 :: _unit(seed, key)` — каждый выбор хэшируется `(individual_seed | key)`.
- seal: `compute_phenotype_hash()` над `individual_seed | genome_checksum | traits_checksum | environment_checksum | profile_checksum | realized_checksum | graph_hash` — это формальный носитель инварианта `Phenotype = Genome × Environment × Age × History × Seed`.
- `PlantFunctionalPhenotype` (FFF1) обязан войти в эту же дисциплину: собственное поле `phenotype_hash` поверх уже посчитанных checksum'ов, byte-identical при равных входах (gate G1).

## 6. Environment channel inventory

Есть сегодня:

| Канал | Носитель |
|---|---|
| point environment | `environment_sample_v1 :: temperature_c, soil_moisture, sunlight, nutrients, flood_frequency` (+ coords/seed/revision/checksum) |
| terrain water features | `evo5_terrain_demo_v1` artifact: `features.in_water`, `features.water_dist_m`; effective `soil_moisture_ppm` через `evo5_factor_registry_v1` |
| правила DSL читают | `evo5_rule_compiler_v1 :: WHEN_KEYS = {neighbours, water_dist_m, in_water, mineral, wind_exposure, sun_exposure, snow_cover_frac, soil_moisture_ppm}` |
| сезонные поля | `plant_seasonal_world_v1`: temperature/moisture/light/nutrients |
| fixture | `synthetic_environment_fixture_v1` (river valley, 128×128, stable hash) |

Нет сегодня (gap-доказательство кодом: `environment_sample_v1.FIELD_NAMES` не содержит соответствующих полей):

| Отсутствующий канал | Нужен для | Решение по ТЗ |
|---|---|---|
| `soil_texture` (sand/loam/clay) | FFF4 (§9.4 ТЗ) | versioned ecological input / fixture channel, НЕ новая геология |
| understory light field | FFF3 | агрегатор shade-записей растений (см. §8) |
| litter / organic matter | FFF5 | flux-записи + медленный legacy proxy |
| transpiration flux | FFF4 | derived от functional phenotype, bounded uptake |

Важно: вода и тень сегодня **только потребляются** растениями (pairwise contested-light; контекст `canopy_overlap`/`local_density` задаёт вызывающий код через `VerticalLight.create_context`) — ни одно растение не публикует эффект в среду. Это ровно поверхность, которую достраивает `plant_environment_effect.v1` ТЗ §7.

## 7. Feedback surfaces, которые нельзя дублировать или ломать

- CAL1-B `plant_relative_vertical_light_competition_v1` — zero-sum light pool по относительной высоте (высокое затеняет низкое асимметрично — совместимо с §8.2 ТЗ); контекст `create_context(canopy_overlap, local_density, label)` подаётся вызывающим кодом → **естественная точка инъекции** будущих агрегированных cell-полей вместо all-pairs скана.
- CAL1-C `plant_spatial_crown_root_competition_v1` — crown/root overlap давление между пространственными соседями (поверхность пространственной конкуренции; собственный контекст конкуренции).
- P3.6 `plant_disturbance_succession_v1` — уже есть succession-поверхность; EVO7 даёт ей причинную морфологическую основу.
- `plant_resource_model_v1` — net balance с costs/penalties; fitness decomposition ТЗ §11 расширяет её, а не заменяет.

## 8. Ownership boundaries freeze (обязательные правила)

```text
1. environment != genome writer: среда меняет только realized expression
   и fitness; наследственность меняется только через MutationKernel.
2. Единственная mutation authority: plant_mutation_lineage_kernel_v1
   (+ его versioned additive successor). Второй мутатор запрещён (G13).
3. Renderer не пишет назад: PlantRenderDescription/MultiScale остаются
   derived-only; presentation settings не входят в ecological hash (G15).
4. Растение не пишет Environment state напрямую: только effect records,
   применяемые агрегатором в canonical order по identity (ТЗ §7).
5. Feedback aggregation: spatial buckets/cells, O(N + C + local),
   order-invariance по G12; SceneTree-порядок запрещён как источник истины.
6. Запрет hardcoded archetypes TREE/BUSH/GRASS в selection (ТЗ §18);
   допустимы только постфактум cluster labels.
```

Source-boundaries этих правил фиксируются машинно в acceptance-тесте (по образцу source-gate теста PH0).

## 9. Минимальный список новых contract-полей (вход FFF1)

Аддитивный versioned successor к development traits (имена рабочие, freeze units — на FFF1 после design review):

```text
plant_development_traits_extension_evo7.v1 (additive):
  foliage_density        # crown density axis, [0..1] normalized
  leaf_economics_proxy   # fast-slow SLA-like axis, [0..1]
  structural_investment  # wood density proxy, [0..1]
  root_spread_m          # lateral root extent, метры, bounds как у crown_spread
  root_shoot_ratio       # наследуемая цель allocation, [0.15..0.85]

derived (FFF1): distributed_world_simulator.ecology.plant_functional_phenotype.v1
  состав полей — по ТЗ §5, компилируется ТОЛЬКО из accepted
  genome + traits(+extension) + environment + profile + age/history/seed.

effect record (FFF3/FFF4): distributed_world_simulator.ecology.plant_environment_effect.v1
env input (FFF4): soil_texture fixture channel
evolution (FFF2): extension MUTATION POLICY к kernel v1 — min/max/step/
  probability/canonical order на каждое новое поле, единый lineage path.
```

## 10. Машинная фиксация аудита

`tests/research/ecology/eco_evo7_fff0_contract_mapping_acceptance.gd` проверяет (итоговые assertion-числа — в выводе раннера `RUN_ECO_EVO7_FFF0_TESTS.ps1`):

- M1: genome v1 FIELD_NAMES == ожидаемые 13, exact-count валидация присутствует в исходнике (v1 не расширяется in-place);
- M2: `MUTABLE_TRAITS` == 5 известных тритов; морфология вне ядра (фиксация gap FFF0-A);
- M3: PH0 TRAIT_NAMES/BOUNDS == 8 тритов; checksum детерминирован;
- M4: plasticity/realize-поверхность существует (`static func realize`), профиль пластичности содержит заявленные коэффициенты;
- M5: environment_sample FIELD_NAMES не содержит texture/litter/transpiration каналов (кодовое доказательство gap);
- M6: мост EVO6-WATER содержит preload/delegation к kernel и не определяет собственный набор мутабельных тритов (G13 preview);
- M7: cost-сторона structural_cost существует при отсутствии наследуемой оси (фиксация gap);
- M8: root_allocation/shoot_allocation placeholder 0.5 не наследуется (фиксация gap);
- M9: renderer pipeline: PROFILE_ORDER из 6 профилей, multiscale tiers, отсутствие write-back маркеров в render-исходниках;
- M10: determinism smoke: traits checksum и individual seed воспроизводимы.

## 11. Открытые вопросы → FFF1 design brief (не блокируют FFF0 PASS)

1. Связь `genome.height_m` ↔ `traits.max_height_m` в functional fitness: какая величина входит в `photosynthetic_gain_proxy` (предварительно: PH0-потенциал через graph metrics, скаляр генома остаётся в ecological fitness — уточнить по EVO4-B1/B2 derivation contracts).
2. Юниты и bounds пяти новых полей (сейчас нормализованные 0–1, кроме root_spread_m) — freeze после sensitivity-проб FFF1.
3. Точка расширения kernel: additive policy schema vs successor kernel — решить на FFF2 design brief с migration-тестом.
