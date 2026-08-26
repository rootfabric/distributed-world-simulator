# ECO.EVO7 FFF6 — Лаборатория сукцессии: дизайн сцены, управления и наблюдаемости

**Статус:** `RESEARCH_DESIGN / NON_CANONICAL_UNTIL_ACCEPTED`
**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1`, базовый HEAD `fd6855e3` (проверен)
**Родительская спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` §14 (визуальная материализация), §15 (полигон + управление + HUD), §16 (gates, особенно G5/G15), §17 (эксперименты), §18 (запрет archetypes), §19 (FFF6).
**Переиспользуемые поверхности:** `evo7_light_feedback_bridge_v1.gd`, `evo7_morphology_evolution_bridge_v1.gd`, `understory_light_field_v1.gd`, `plant_functional_phenotype_v1.gd`, `plant_environment_effect_v1.gd`, `plant_mutation_lineage_extension_evo7_v1.gd`, `synthetic_environment_fixture_v1.gd`, render-конвейер `plant_render_description_v1 → plant_multiscale_representation_v1 → plant_multiscale_materializer_v1`, дом-паттерн лабы `eco_evo6_water_evolution_lab.gd/.tscn`, правила запуска `docs/GODOT_LOCAL_TESTING_RU.md`.

---

## 1. Цель и границы

FFF6 собирает light + water + soil feedback в один контролируемый ландшафт (ТЗ §19): ≥100 generation-equivalents для stability evidence, наблюдаемые canopy/understory/gap-переходы, anti-runaway, deterministic replay, geometry-only visual proof. Лаба — **read-only наблюдатель** над research-мостами: она не добавляет ни второй mutation authority, ни write-back в среду.

## 2. Структура сцены

Дом-правило 1:1 basename (как EVO6):

- `res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn` — минимальная сцена: корень `Node3D` + `ext_resource` на скрипт (образец: `eco_evo6_water_evolution_lab.tscn`, 6 строк).
- `res://scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd` — весь мир строится процедурно в `_ready()`.

Дерево узлов (эскиз):

```text
EcoEvo7FormFunctionFeedbackLab (Node3D, script)
├─ Sun (DirectionalLight3D, -48°/32°, energy 1.25)      # как EVO6
├─ WorldEnvironment (BG_COLOR + ambient)                # как EVO6
├─ Zones (Node3D)
│  ├─ Zone_FLOODED (Node3D)
│  │  ├─ Ground (MeshInstance3D, BoxMesh 14×0.35×8)
│  │  ├─ WaterPlane (MeshInstance3D)                    # только FLOODED/RIPARIAN
│  │  ├─ Title (Label3D, billboard)
│  │  ├─ OverlayGrid (Node3D)                           # квады-оверлеи 1..5, скрыты
│  │  ├─ CanopyRing (Node3D)                            # только UNDER_CANOPY/CANOPY_GAP
│  │  └─ Plants (Node3D)                                # materialized population
│  ├─ Zone_RIPARIAN / Zone_MESIC_LOAM / Zone_DRY_SAND   # тот же шаблон без CanopyRing
│  ├─ Zone_UNDER_CANOPY (шаблон + CanopyRing)
│  └─ Zone_CANOPY_GAP  (шаблон + CanopyRing)
├─ Camera3D (WASD/QE + mouse capture, как EVO6)
└─ HUD (CanvasLayer)
   ├─ StatsLabel (Label)          # средние показатели §15
   ├─ GeometryReadout (Label)     # feature-вектор по зонам (доказ G5)
   ├─ HashLabel (Label)           # hash-панель replay
   └─ HelpLabel (Label)           # раскладка клавиш
```

Расстановка зон: 3×2 сетка, `PLOT_SPACING := 17.0`; UNDER_CANOPY и CANOPY_GAP — соседняя пара для прямого визуального сравнения. Растения материализуются реальным конвейером PH5: `CoupledDevelopment.realize(...) → ph2["growth_graph"] → PlantRenderDescription.build(...) → MultiScaleRepresentation.build(description, tier) → MultiscaleMaterializer.build(...)`; узлы `branch_mesh`/`foliage_multimesh`/`far_mesh` кладутся в `Plants`. Лабовые геометрические кодировщики (презентационные, read-only от `PlantFunctionalPhenotype`): корневой стержень вниз `length ∝ realized_root_depth_m` (паттерн EVO6), диск тени под кроной `radius ∝ realized_crown_radius_m` для overlay 3.

## 3. Шесть зон: связываемые контракты входов

Каждая зона — один прогон эволюционного контура FFF3-образца (`evo7_light_feedback_bridge_v1._run_mode`): сетка 5×5 = 25 растений, шаг 0.35 м, 16 поколений, OFFSPRING_PER_PARENT=2, один ancestor `LineageExtension.create_ancestor_bundle(...)` (`default_ancestor_bundle`, lineage_seed=20260823), один mutation stream `"EVO7-FFF6|seed|gen|parent|offspring"`. Различаются только входы среды. Базовые точки — `Fixture.control_point(...)`, финальные числа freeze на реализации:

| Зона | texture | base soil_moisture | base sunlight | nutrients | flood_frequency | canopy на старте |
|---|---|---|---|---|---|---|
| FLOODED | clay | ~0.95 (saturated) | 0.85 | 0.70 | ~0.80 | нет |
| RIPARIAN | loam | ~0.65 | 0.85 | 0.60 | ~0.35 | нет |
| MESIC_LOAM | loam | ~0.45 | 0.80 | 0.45 | ~0.02 | нет |
| DRY_SAND | sand | ~0.18 | 0.95 | 0.25 | ~0.00 | нет |
| UNDER_CANOPY | loam | ~0.45 | 0.85 (base) | 0.45 | ~0.02 | **да** (статичный CanopyRing) |
| CANOPY_GAP | loam | ~0.45 | 0.85 (base) | 0.45 | ~0.02 | да → **удаляется в runtime** |

Механика привязки:

- `derived_env = EnvSample.create(x, z, temperature_c, soil_moisture, sunlight, nutrients, flood_frequency, seed, "<fixture_revision>|fff6|<zone>|<identity>")` — zone/identity в `environment_revision` даёт различные checksum'ы зон без изменения schema v1.
- **texture** — versioned lab-fixture параметр зоны (FFF0 §6: `environment_sample_v1.FIELD_NAMES` не содержит texture; канал sand/loam/clay по ТЗ §9.4 входит через FFF4 water-bridge как versioned input). В лабе texture читается water-каналом (water persistence / drought onset) и HUD/overlay 2; в ecological hash попадает только через производные channel-значения, не как отдельное поле v1.
- **CanopyRing** — 8–12 статичных высоких растений с фиксированным phenotype (tall/dense, не размножаются, не эволюционируют); их geometry-records участвуют в `LightField.compute(...)` наравне с популяцией (G6).
- **CANOPY_GAP vs UNDER_CANOPY**: идентичные входы; в CANOPY_GAP лаба на детерминированной границе поколений (mid-run, например после поколения 8) исключает CanopyRing из geometry-records и пересчитывает light field → свет восстанавливается, light-demanding/pioneer стратегия получает преимущество (ТЗ §17 Experiment A, шаги 5–6; G6-removal). Удаление — только операция над research-списком records, не над узлами сцены: сцена всегда отображает текущий список. Дополнительно допускается debug-клавиша `X` (вне минимума §15.1) для ручного удаления/возврата canopy — см. §12.

## 4. Управление (ТЗ §15.1): клавиша → API → визуальный канал

| Клавиша | Действие / API | Визуальный канал |
|---|---|---|
| `SPACE` | переключение initial/final: initial = feature-набор поколения 1 (ancestor-пул), final = итоговые population каждого моста | перестройка `Plants` из сохранённых feature-наборов; HUD-фаза |
| `F` | feedback ON/OFF counterfactual: переключение между результатами `_run_mode(use_feedback=true/false)` (паттерн `evo7_light_feedback_bridge_v1`) | геометрия final-популяций, `mean_understory_light` в HUD |
| `C` | neutral colors ON/OFF: все растения всех зон получают **один и тот же** `StandardMaterial3D` (единый серый albedo, без per-plant/per-zone вариаций) | исчезают все цветовые кодировки; остаются только геометрия + `GeometryReadout` (§5) |
| `1` | light overlay: `LightField.compute(records)` зоны → `plant_light[identity]["understory_light"]` | полупрозрачные квады `OverlayGrid` по ячейкам `CELL_SIZE_M=1.0` + Label3D значения |
| `2` | soil moisture overlay: base moisture зоны минус transpiration draw (когда подключён FFF4 water-bridge), clamp [0,1] | тон Ground/квады + значения по ячейкам |
| `3` | shade output overlay: `shade_output_ppm` из `PlantFunctionalPhenotype` каждого растения | диски под кронами `radius ∝ crown_radius`, интенсивность ∝ ppm |
| `4` | transpiration overlay: `transpiration_demand_ppm` из phenotype | цвет/высота маркера над кроной + HUD-среднее |
| `5` | fitness components overlay: `photosynthetic_gain_proxy`, `maintenance_cost_proxy`, `net_resource_proxy` | Label3D у растений + zone-среднее в HUD |
| `R` | deterministic reset: полный перезапуск мостов с теми же `lineage_seed`/policy/ancestor и тем же mutation stream (§7) | перестройка мира; hash-панель обязана совпасть |

Оверлеи — чистый presentation-слой: их цвета и выключатели не входят ни в один ecological hash (G15). Для G5-скриншота оверлеи выключены.

## 5. C-режим: geometry-only proof (G5)

При `C` все растения всех шести зон переводятся на один идентичный нейтральный материал. Различия обязаны читаться геометрией:

- высота ствола/сегменты — `realized_height_m` (уже отражена growth graph'ом);
- ширина/силуэт кроны — `realized_crown_radius_m`, apical dominance (vertical vs spreading);
- плотность листвы — количество foliage-инстансов профиля (`foliage_fraction` профиля остаётся константой лабы; плотность видима через graph-driven anchors);
- толщина ствола — `structural_investment` (конусность из `PlantRenderDescription`);
- корневой стержень — длина ∝ `realized_root_depth_m`, ширина лапы ∝ `realized_root_spread_m`;
- LAI proxy — суммарная листвая масса кроны.

Экранный read-out `GeometryReadout`: таблица по зонам со средними 7 полей `FEATURE_FIELDS` (`realized_height_m, realized_crown_radius_m, realized_crown_density, leaf_area_index_proxy, realized_root_depth_m, realized_root_spread_m, structural_investment`) и парными флагами `geometry-distinct` по `GEOMETRY_THRESHOLDS` из `evo7_morphology_evolution_bridge_v1.gd`. G5-критерий лабы: в C-режиме ≥3 зон попарно различимы этим вектором при одном материале.

## 6. HUD (ТЗ §15)

Источник данных — **read-only агрегация** по `PlantFunctionalPhenotype` отображаемых растений каждой зоны (никаких параллельных пересчётов):

```text
mean height / crown radius / LAI proxy / root depth+spread  ← средние FEATURE_FIELDS
mean water preference                                        ← genome.water_preference (read-only)
mean shade output / transpiration                            ← shade_output_ppm / transpiration_demand_ppm
mean fitness                                                 ← net_resource_proxy
unique genomes                                               ← мощность множества bundle_checksum
morphology cluster count                                     ← постфактум-кластеризация FEATURE_FIELDS-векторов
```

Кластеризация — детерминированная greedy-пороговая по `GEOMETRY_THRESHOLDS`, только diagnostic label (ТЗ §18: TREE/BUSH/GRASS-подобные ярлыки запрещены в selection; здесь их нет и в labels). Anti-runaway индикатор: доля популяции, у которой evolvable-оси упёрлись в ≥99% bound (`Traits.BOUNDS` / `Extension.BOUNDS`) — для G11-наблюдаемости.

## 7. Детерминированный replay (R)

`R` пересоздаёт состояние: тот же `lineage_seed=20260823`, тот же ancestor bundle, та же policy (`LineageExtension.default_policy()`, hash в HUD), те же формулы `mutation_seed` на (generation, parent_index, offspring_index) — идентично FFF2/FFF3-мостам. Никакой RNG, никакой зависимости от порядка обхода SceneTree.

Hash-панель `HashLabel` (доказательство replay):

```text
lineage_seed, evo7_policy_hash, ancestor_bundle_checksum
по зонам: first_generation_score_hash (общий пул), final_population_hash,
          final_field_hash, final_plant_light_hash, last_effects_combined_hash
lab_result_hash (агрегат по образцу _result_hash FFF3-моста)
```

PASS: два подряд `R` дают побайтово одинаковую панель; `first_generation_score_hash` совпадает между всеми зонами и между F ON/OFF (общий candidate pool, G4-наблюдаемость).

## 8. План производительности

- **Cell-bucket pruning** в `understory_light_field_v1.compute`: R1-реализация делает all-pairs scan по records (buckets c `CELL_SIZE_M=1.0` считаются, но не prune). Апгрейд: источники раскладываются по `cell_identity_for(...)`, для каждой цели сканируются только ячейки в радиусе `ceil(max_crown_radius/CELL_SIZE_M)`; аккумуляция строго в canonical identity order. Требование: `field_hash`/`plant_light_hash` побайтово совпадают до/после (регрессия `RUN_ECO_EVO7_FFF3_TESTS.ps1`). Тот же паттерн — для water-поля, когда войдёт FFF4. Итоговая сложность O(N + C + local) (ТЗ §13).
- **Ожидаемый объём сцены:** 6 зон × 25 растений = 150 эволюционирующих + 2 CanopyRing × ~10 = ~170 materialized plants на view; 16 поколений × 2 режима (F) на зону. Прогон мостов в `_ready()` синхронно (паттерн EVO6), при необходимости — loading-строка в HUD.
- **LOD:** существующие MultiScale tiers по `select_tier_hysteretic(projected_height_px, previous_tier)`: ближние зоны TIER_0_FULL/TIER_1_REDUCED, средние TIER_2_CANOPY, дальние TIER_3_IMPOSTOR; TIER_4_POPULATION_ONLY не используется при 170 растениях. Переключение tier — presentation-only, hash-панель не меняет (G15).
- Forest-scale N (≥1000 растений на terrain-сетке) — осознанно FFF7; pruning-апгрейд делается в FFF6, потому что он дёшев и нужен для честного G12-замера на 6 зонах.

## 9. Граница визуальной истинности (G15; FFF0 §8 правило 3)

- Рендер читает только derived-описания: `PlantRenderDescription`/`MultiScale` несут `ecological_truth_hash = source_graph_hash`; лаба не конструирует геометрию из чего-либо, кроме realized phenotype.
- Presentation settings (C-материал, оверлеи 1–5, tier/LOD, цвета зон) **не входят** в ecological hashes: `phenotype_hash`, `field_hash`, `population_hash` не зависят ни от одного из них; переключение C/оверлеев не меняет `HashLabel`.
- Лаба не пишет назад: genome/phenotype/environment authority для неё read-only; effect records публикует только `LightField.effect_records(...)` в canonical identity order; ни один узел сцены не является источником ecological истины (запрет SceneTree-order dependence, G12).

## 10. Acceptance checklist → gates

| Проверка лабы | Gate | Критерий |
|---|---|---|
| C-режим: ≥3 зоны различимы по geometry feature vector (`GeometryReadout` + визуально) | **G5** | ≥3 пар zone-средних превышают `GEOMETRY_THRESHOLDS` при одном материале |
| Сукцессионный цикл наблюдаем: CanopyRing удалён → `mean_understory_light` CANOPY_GAP восстанавливается → доля light-demanding (высокий `leaf_economics_proxy`, низкий `shade_tolerance`) потомков растёт | G6/G7, §17-A | light(CANOPY_GAP, после removal) > light(UNDER_CANOPY); направление отбора меняется после удаления |
| Anti-runaway дисплей: ни одна зона не завершает со всеми evolvable-осями у max bound | G11 | bound-pinning индикатор HUD < 1.0 по осям в умеренных зонах (MESIC_LOAM) |
| Deterministic replay: `R` дважды → идентичная hash-панель; общий первый пул между зонами | G4/G12 | hash-панель побайтово равна; `first_generation_score_hash` общий |
| Presentation-инвариантность: C/оверлеи/LOD не меняют `HashLabel` | **G15** | hashes равны до/после переключений |
| Автопроверка: `EVO7_FFF6_LAB_AUTOCAP=1` → headless-совместимый прогон печатает `PASS/FAIL` и `quit(0/1)` (паттерн `_autocap` EVO6) | — | rendered==expected, G5-флаги, succession-маркеры, replay-равенство |

Запуск — по `docs/GODOT_LOCAL_TESTING_RU.md`: свежий worktree → `--import`; затем GUI-binary:
`& "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe" --path C:\distributed-world-simulator\worktrees\eco-water-r1 res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn` (с `BREAKPOINT_RUNTIME_DISABLED=1`); ожидаемый маркер `ECO.EVO7-FFF6-VIS: READY ... result_hash=...`.

## 11. Вне scope (FFF7 и далее)

Scale/profiling на forest-N, aggregation LOD популяции, persistence boundary, production environment write authority, network/read-only projection — ТЗ §19 FFF7. Также вне первой волны: litter/soil-legacy визуализация (FFF5-канал отображается только когда мост подключён), пожары, травоядные, сексуальная генетика (ТЗ §20).

## 12. Открытые вопросы для имплементатора

1. **texture-канал:** заводить ли versioned successor `environment_sample` с `soil_texture` в FFF6 или передавать texture только параметром water-bridge (v1 не расширяется in-place)? Влияет на environment checksums зон.
2. **Ручное удаление canopy:** достаточно ли детерминированного scheduled removal в CANOPY_GAP, или добавлять debug-клавишу `X` (вне минимума §15.1) для интерактивного counterfactual?
3. **Длительность прогона:** 6 зон × 16 поколений × 2 режима в `_ready()` — замерить; если >2–3 c, вынести эволюцию в отложенный шаг с прогрессом в HUD (без потоков, чтобы не рисковать детерминизмом).
4. **Видимость crown_density:** достаточно ли graph-driven foliage anchors, или добавить презентационный масштаб foliage-инстансов от `realized_crown_density` (остаётся presentation-only)?
5. **≥100 generation-equivalents (ТЗ §19):** запускать ли полный stability-прогон в лабе или оставить его acceptance-скрипту (`tests/research/ecology/eco_evo7_fff6_*_acceptance.gd`), а лабе — короткий интерактивный прогон?
6. **Кластеризация HUD:** пороговая greedy против k-means — фиксировать детерминированный вариант и его hash-независимость от порядка обхода.
