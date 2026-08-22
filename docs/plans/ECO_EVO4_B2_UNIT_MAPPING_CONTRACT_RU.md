# ECO.EVO4/E4.B2 — Контракт единиц и пластичности моста (plasticity-v0)

Статус: `RESEARCH_ONLY / BRIDGE_CONTRACT / NO_ACCEPTANCE_AUTHORITY`.
Правило: `evo4-b2-plasticity-v0` (заморожено настоящим документом ДО кода).

## 1. Входные поверхности

| Вход | Источник | Ключи |
|---|---|---|
| Запись расширенного каталога | `validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json` | `development_traits` (ровно PH0), `evo4_bridge.individual_seed_demo`, `genome` |
| Условия точки | B5 `evo4_point_sampling_v1.sample()` по принятому снапшоту | `light_availability_ppm`, `soil_moisture_ppm`, `nutrient_availability_ppm`, `disturbance_pressure_ppm`, `temperature_milli_c` |
| Возраст когорты | явный `cohort_age_years` ИЛИ синтез (§4) | — |

## 2. Нормализация единиц

- Доступность: `a_x = ppm / 1_000_000 ∈ [0, 1]` (ppm — частей на миллион).
- Температура: `temperature_milli_c` — милли-градусы Цельсия (−4000 = −4 °C).
- Нейтральная точка масштабирования: `a = 0.5` → фактор 1.0.

## 3. Формулы пластичности v0 (монотонные, объявленные)

Семантика — presentation-сторона моста, НЕ ecological truth; ретюнинг принятых ядер E3.x запрещён.

| Масштаб | Формула | Диапазон | Действие |
|---|---|---|---|
| `height_scale` | `clamp(0.70 + 0.60·a_light, 0.70, 1.30)` | свет → высота | × на `max_height_m` |
| `crown_scale` | `clamp(0.70 + 0.60·a_soil, 0.70, 1.30)` | влага → крона | × на `crown_spread_m` |
| `branch_prob_scale` | `clamp(0.80 + 0.40·a_nutrient, 0.80, 1.20)` | питательность → ветвление | × на `branch_probability` |
| `stress_index` | `clamp(a_disturbance, 0, 1)` | нарушения → угнетение | `max_height_m ×= (1 − 0.35·stress)`; `internode_length_m ×= (1 − 0.25·stress)` |

Порядок применения: базовый trait → масштаб → угнетение → **clamp в PH0 bounds**. Результат `effective_development_traits` сохраняет ровно 12-полевую PH0-форму (с пересчитанным checksum по алгоритму §3 контракта B1) и пригоден для прямой подачи в принятый `plant_growth_graph_skeleton_v1.build()`.

`dormancy_state = "DORMANT_COLD"` при `temperature_milli_c < 0`, иначе `"ACTIVE"`.

## 4. Возраст когорты (демографический синтез v0)

Предпочтителен явный `cohort_age_years`. Fallback-синтез (объявленные константы):

`cohort_age_years = min(lifespan_years, BASE_AGE_YEARS + cohort_index · COHORT_STEP_YEARS)`, `BASE_AGE_YEARS = 2.0`, `COHORT_STEP_YEARS = 1.5`.

Честная граница: артефакты программ EVO3 несут **наборы установления** (`established_patch_ids`), но не время установления; истинная временная ось ожидает решения E3.6-R (multi-snapshot temporal evidence). Синтез — презентационный прокси без population-truth притязаний.

## 5. Артефакт компиляции

`scripts/research/ecology/evo4_bridge_compiler_v1.py` → `validation/ecology/evo4_b2_development_state.v1.json`:

- схема `distributed_world_simulator.ecology.evo4_b2_development_state.v1`;
- записи: `{lineage_id, genome_id, stable_spatial_key, individual_seed_demo, cohort_age_years, development_state: {age_years, dormancy_state, stress_index, plasticity_scales}, effective_development_traits}`;
- матрица компиляции: каждая запись артефакта B1 × каждый сэмпл снапшота `e3_final_unseen_planet_field_snapshot.arid-basin-02.v1.json` × `cohort_index = 0`;
- `provenance`: `{rule_id: evo4-b2-plasticity-v0, generator, generator_version, input sha256: b1_artifact, snapshot, sampling_module}`.

Детерминизм: чистые функции, без часов/случайности; fresh-process ребилд байт-идентичен.
