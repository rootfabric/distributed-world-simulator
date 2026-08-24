# ECO.EVO7 FFF6 — Closed Community Evolution / Succession Lab R1 — CANDIDATE

**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1` (базовый HEAD `504b9e28`, FFF0–FFF5 в составе)
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§14 визуализация, §15 полигон+управление+HUD, §16 G5/G11/G15, §17 Experiment A, §18 запрет архетипов, §19 FFF6)
**Дизайн:** `docs/plans/ECO_EVO7_FFF6_SUCCESSION_LAB_DESIGN_RU.md` (все «открытые вопросы» §12 разрешены, см. ниже)
**Статус:** CANDIDATE (реализаторская роль; самопринятия нет)

## Design brief (реализация)

- **Проблема:** после FFF3/FFF4/FFF5 петли (свет, вода, органика) доказаны по отдельности на микрокосмах; ТЗ §19 FFF6 требует собрать их в один контролируемый ландшафт с ≥100 generation-equivalents, наблюдаемыми canopy/understory/gap-переходами, anti-runaway, deterministic replay и geometry-only visual proof.
- **Выбрано:**
  - `scripts/research/ecology/evo7_succession_simulation_v1.gd` — чистый non-node модуль (без SceneTree/RNG): шесть зон (`FLOODED` clay/wet/flood 0.80 · `RIPARIAN` loam 0.65 · `MESIC_LOAM` loam 0.45 · `DRY_SAND` sand 0.18 · `UNDER_CANOPY` loam+статичная крона · `CANOPY_GAP` = UNDER_CANOPY минус крона с детерминированным удалением после поколения 8). Каждая зона — контур FFF3-образца (сетка 5×5, шаг 0.35 м, OFFSPRING_PER_PARENT=2, один ancestor `lineage_seed=20260823`, поток `EVO7-FFF6|seed|gen|parent|off`, воспроизводство только через `LineageExtension`, best-child наследует позицию родителя). За цикл: свет (`understory_light_field_v1`, геометрия популяции + кроны) → вода (`soil_water_field_v1` с текстурой зоны) → органика (`soil_organic_field_v1`, переносимая карта legacy) → скоринг `net_resource_proxy + ESTABLISHMENT_BONUS·establishment_capacity·cell_organic` (ON) под СВОЙ understory-light и влагу своей ячейки (OFF — база; различие только в назначении среды). Fitness-компоненты и семантика бонуса унаследованы от FFF5 без изменения констант.
  - **Experiment A:** CANOPY_GAP входно идентичен UNDER_CANOPY; удаление кроны — операция над research-списком geometry-records на границе поколений 8→9. Наблюдаемо: свет восстанавливается (траектория 0.065→0.63), net-баланс сообщества возвращается из отрицательного в положительный, потомки GAP ≠ потомки UNDER_CANOPY.
  - **Лаба** `scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn` + `scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd`: 3×2 сетка зон (PLOT_SPACING 17; UNDER_CANOPY|CANOPY_GAP — соседняя пара), мир строится процедурно в `_ready()`; эволюция — отложенными шагами (по зоне на кадр, без потоков) с прогрессом в HUD; растения материализуются реальным конвейером PH5 `CoupledDevelopment.realize → growth_graph → PlantRenderDescription.build → MultiScaleRepresentation.build(tier) → MultiscaleMaterializer.build` через общий хелпер `Simulation.realize_entry` (визуал растёт из ТЕХ же growth graph'ов, что кормили поля — G15); лабовые кодировщики (EVO6-паттерн): корневой стержень ∝ `realized_root_depth_m`, диск тени ∝ crown_radius/shade_ppm, маркер транспирации, Label3D fitness-компонент; статичная крона рендерится из тех же замороженных констант, что и её light-records.
  - **HUD:** StatsLabel (фаза, средние §15 по зонам, bound-pinning индикатор G11), GeometryReadout (средние 7 полей FEATURE_FIELDS по зонам + парные `geometry-distinct` флаги по `GEOMETRY_THRESHOLDS`), HashLabel (seed/policy/ancestor, `lab_result_hash`, по зонам pool1/pop/field/light/effects + индикатор REPLAY MATCH), HelpLabel. Оверлеи 1–5 и C-режим не входят ни в один ecological hash.
  - **Autocap:** `EVO7_FFF6_LAB_AUTOCAP=1` — сцена прогоняет симуляцию + stability (2 зоны × 108 циклов) + replay headless-style, печатает машинный вердикт и `quit(0/1)`.
- **Отвергнуто:** расширение `environment_sample_v1` полем texture (см. вопрос 1); потоки для эволюции (риск недетерминизма); k-means кластеризация; гейтинг «pioneer-направления» по `leaf_economics_proxy` (нестабилен, см. калибровку п.4); рендер кроны процедурной геометрией вне конвейера PH5 (нарушение G15-дисциплины для эволюционирующих растений).
- **Риски:** слабая различимость пар зон по морфологии при 16 поколениях (минимум 4 пары на seed 20260823 — порог ≥3 держится с запасом всего в одну пару, зафиксировано честно); второй порядок оси economics не даёт надёжного «pioneer» знака за 8 пост-удаление поколений.

## Разрешение открытых вопросов дизайна (§12)

1. **texture-канал:** НЕ заводить versioned successor `environment_sample`; texture остаётся versioned параметром water/organic-field fixture (канон FFF4: «texture enters ONLY as field parameters»). Идентичность зон — через суффикс `environment_revision` `<fixture_revision>|fff6|<zone>|<identity>`: чексамы базовых сред шести зон попарно различны (assert в acceptance), схема v1 не расширена.
2. **Ручное удаление canopy:** сделаны ОБА варианта. Исследовательская истина — детерминированное scheduled-удаление (поколение > 8, только в CANOPY_GAP, только над списком records). Плюс debug-клавиша `X` (вне минимума §15.1, допущена дизайном): интерактивный контрфактический toggle видимости кроны и пересчёта светового оверлея; презентационный слой, хэш-панель не меняет (G15 наблюдаемо вживую).
3. **Длительность прогона:** замер — полный `run_all` ≈ 19–20 c синхронно (6 зон × 16 поколений × 2 режима), что существенно выше порога 2–3 c из дизайна. Решение: инкрементальный драйвер `create_context / context_step / context_finish` — лаба исполняет по одной зоне между кадрами с HUD-прогрессом («SIMULATING zone k/6»), без потоков; байт-идентичность агрегата `context_finish` == `run_all` доказана ассертом acceptance-теста.
4. **Видимость crown_density:** оставлены graph-driven foliage anchors (константа foliage_fraction профиля TIER_1 не меняется); плотность дополнительно читается численно (GeometryReadout, dens-колонка) и через диски тени (радиус/интенсивность от realized crown/shade). Презентационное масштабирование foliage-инстансов от `realized_crown_density` НЕ добавлено — задекларированное ограничение R1.
5. **≥100 generation-equivalents:** долгий stability-прогон живёт В МОДУЛЕ (`run_zone_stability`, `STABILITY_GENERATIONS=108`) и выполняется acceptance-скриптом и автокапом лабы; интерактивная лаба держит короткий 16-поколенческий просмотр. Так визуальная правда и stability-evidence разделены без дублирования математики.
6. **Кластеризация HUD:** детерминированная greedy-пороговая по каноническому порядку identity с бегущими центроидами (вектор присоединяется к первому кластеру, чей центроид НЕ geometry-distinct от него). Только диагностическая метка, в хэши не входит; порядок обхода фиксирован канонически, поэтому hash-независимость соблюдена по построению. Замечено: при текущих GEOMETRY_THRESHOLDS внутри зоны кластеры практически не сливаются (count ≈ 25) — метрика слабоинформативна, зафиксировано как ограничение.

## Управление (ТЗ §15.1 + дизайн §4)

| Клавиша | Действие | Канал |
|---|---|---|
| `SPACE` | initial (gen-1 ancestor pool) / final | перестройка `Plants`, HUD-фаза |
| `F` | feedback ON/OFF (готовые прогоны обоих режимов) | геометрия финальных популяций, mean_understory_light |
| `C` | нейтральный материал: один общий серый `StandardMaterial3D` на все MeshInstance/MultiMesh всех растений | исчезают цветовые кодировки; остаются геометрия + GeometryReadout |
| `1` | light overlay | квады по ячейкам CELL_SIZE_M=1.0 + Label3D значения (LightField.compute по отображаемым записям + кроне) |
| `2` | soil moisture overlay | квады по `final_cell_moisture` (база минус transpiration draw — водный мост подключён реально) |
| `3` | shade output overlay | диски под кронами, интенсивность ∝ shade_output_ppm |
| `4` | transpiration overlay | маркеры над кронами ∝ transpiration_demand_ppm |
| `5` | fitness components overlay | Label3D gain/cost/net у каждого растения |
| `R` | deterministic reset | полный перезапуск симуляции тем же seed/policy/потоком; панель обязана совпасть (индикатор REPLAY MATCH) |
| `X` | debug: manual canopy toggle (GAP) | презентационный контрфактический просмотр; хэши не трогает |
| WASD/QE/mouse/Esc | камера (EVO6-паттерн) | — |

## Bucket-pruning upgrade (обязательный этап A)

`understory_light_field_v1.compute`: источники индексируются по ячейкам `cell_identity_for(...)`; для каждой цели сканируются только ячейки в чебышёв-радиусе `ceil(max_crown_radius / CELL_SIZE_M) + 1` вокруг её ячейки; кандидаты сортируются по возрастанию индекса validated-массива = канонический порядок identity. Пропускаются только доказуемо нулевые пары (высота ≤ цели, radius ≤ 0, dist ≥ radius ⇒ вес 0), поэтому суммы аккумулируются в том же каноническом порядке и `field_hash`/`plant_light_hash`/per-plant light побайтово совпадают до/после. Регрессия: `RUN_ECO_EVO7_FFF3_TESTS.ps1` зелёный, bridge `result_hash=cd30fcbfeb294e19` — бит-идентичен базовому прогону ДО правки (зафиксирован этой же сессией до изменения). Сложность O(N²)→O(N+C+local); тот же паттерн для water-поля остаётся на FFF7 (как и заявлено в дизайне §8).

## История калибровки (честно; константы FFF1–FFF5 не менялись)

1. **Двойное воспроизводство поколения 1** (self-review до первого прогона): пул поколения 1 считался отдельным проходом reproduce, а затем settlement воспроизводил тех же детей повторно — избыточно и риск расхождения. Исправлено: один проход reproduce за поколение, pool-hash собирается из его result_hash'ей.
2. **Read-only const array → вечный цикл** (`context_step`): `"pending": Array(ZONE_ORDER)` сохранил ссылку на read-only константу — `pop_front()` падал, `run_all` зависал. Диагностировано калибровочным пробом (stderr «Array is in read-only state»). Фикс: `(ZONE_ORDER as Array).duplicate()`.
3. **Опечатка в материализаторе лабы**: `rod_mesh.mesh = rod_mesh` вместо `root_rod.mesh = ...` — SCRIPT ERROR на каждом растении, автокап честно печатал FAIL rendered=0. Найдено headless-прогоном сцены, исправлено, повторный прогон PASS rendered=150.
4. **Кросс-seed калибровка направлений** (20260823/24/25, полные прогоны): устойчивы — пары geometry-distinct 4/7/9 (≥3), ON/OFF дивергенция 6/6 на всех seed'ах, восстановление света GAP +0.566/+0.561/+0.569, net-recovery +0.053/+0.057/+0.064, pinning ≤0.04. НЕустойчивы (ассертом не стали, честно): направление `mean_leaf_economics_proxy` GAP-vs-UNDER (второй порядок на этом горизонте: 0.456 vs 0.464 — знак против наивного ожидания) и разница корней UNDER−GAP (−0.209/−0.032/−0.162 — знак плавает). Преемник-маркер сукцессии построен на структурно гарантированных фактах: свет, net-баланс, дивергенция популяций.
5. **Пороги acceptance** взяты с запасом ≥2× к минимумам cross-seed: pre-removal light <0.15 (набл. 0.065), gap delta >0.30 (набл. ≥0.561), net recovery >0.02 (набл. ≥0.053), pairs ≥3 (мин. набл. 4 — запас минимальный, задекларирован).

## Что реализовано

1. `scripts/research/ecology/understory_light_field_v1.gd` — bucket-pruned neighbor search (см. выше), заголовок дополнен доказательством бит-идентичности; формат хэшей и API не менялись.
2. `scripts/research/ecology/evo7_succession_simulation_v1.gd` — NEW: модуль сукцессии; зоны/параметры/фикстуры, крона-константы, контур FFF3-образца с тремя полями, Experiment A, `run_zone_stability` (108 циклов, NaN/bounds/pinning-вердикт), `bound_pinning_fractions` (8 осей LineageExtension, ≥99% к верхней границе), greedy-кластеризация, инкрементальный context-API, `realize_entry` (общая реализация для лабы), `result_hash`.
3. `scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn` + `scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd` — NEW: лаба по дизайн-дереву §2 (Sun/WorldEnvironment/Zones с Ground/WaterPlane/Title/OverlayGrid/CanopyRing/Plants, Camera3D, HUD×4), PH5-материализация, C-режим, оверлеи 1–5, X-toggle, R-reset, autocap.
4. `tests/research/ecology/eco_evo7_fff6_succession_lab_acceptance.gd` — NEW: 171 assertion (детерминированная инициализация шести зон, общий пул G4, G5-пары по GEOMETRY_THRESHOLDS, Experiment A, ON/OFF во всех зонах, stability 108×2, replay + context-equivalence + seed-sensitivity, fail-closed matrix, source boundaries включая отсутствие второй mutation authority в узле лабы).
5. `RUN_ECO_EVO7_FFF6_TESTS.ps1` — NEW: цепочка FFF6→FFF5→FFF4→FFF3→FFF2→FFF1→FFF0→P1B-S1→PH2→P1A-S1→P1A-S2→P1C-S4→PH0.

## Autocap / acceptance evidence

Headless-прогон сцены (`EVO7_FFF6_LAB_AUTOCAP=1`, Godot 4.7.1.stable.double.custom_build.a13da4feb):

```text
ECO.EVO7-FFF6-VIS: READY zones=6 plants=150 result_hash=52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436
ECO.EVO7-FFF6-VIS: PASS rendered=150 zones_ok=true onoff=true geom_pairs=4 gap_delta=0.5657 stability_pin_max=0.080 replay=true result_hash=52995cf4bcd03578
```

Acceptance: `ECO.EVO7 FFF6 Succession Lab: PASS (171 assertions)`, `result_hash=52995cf4bcd03578…`.

Наблюдаемые числа (seed 20260823, 16 поколений):

```text
зона           init.light  ON light  ON moist  ON organic  ON net     OFF net
FLOODED        0.6899      0.6781    0.8990    0.2009      +0.04838   +0.09392
RIPARIAN       0.6615      0.6418    0.6061    0.1825      +0.02945   +0.07656
MESIC_LOAM     0.6263      0.6075    0.4094    0.1946      +0.01577   +0.05155
DRY_SAND       0.7820      0.7610    0.1539    0.1380      +0.01277   +0.03992
UNDER_CANOPY   0.0666      0.0637    0.4098    0.1955      -0.03909   +0.06205
CANOPY_GAP     0.0666      0.6356    0.4116    0.1906      +0.01427   +0.06617

GAP-траектория света: 0.0666 … 0.0647 (поколение 8, крона ещё стоит)
                      → 0.6294 (поколение 9, крона удалена) → 0.6356 (финал)
```

Интерпретация: тень кроны делает net-баланс подлеска ОТРИЦАТЕЛЬНЫМ (−0.039) при положительном во всех открытых зонах; удаление кроны мгновенно возвращает свет (×10) и выводит сообщество GAP в положительный баланс (+0.014), популяции GAP и UNDER_CANOPY расходятся — succession-loop (Experiment A шаги 5–6) наблюдаем. Stability: 108 циклов MESIC_LOAM и DRY_SAND — средства конечны, в [0,1], ни одна из 8 осей не упирается в границу всей популяцией (pin-max 0.08).

## Focused evidence

Полная цепочка `RUN_ECO_EVO7_FFF6_TESTS.ps1` (Windows headless, двойная сборка a13da4feb):

```text
ECO.EVO7 FFF6 Succession Lab:        PASS (171 assertions)  # result_hash 52995cf4bcd03578
ECO.EVO7 FFF5 Soil Memory:           PASS (91)              # 304d6da59e52c8e5
ECO.EVO7 FFF4 Water Feedback:        PASS (101)             # 0b4c95442253b2df
ECO.EVO7 FFF3 Light Feedback:        PASS (51)              # cd30fcbfeb294e19 — БИТ-ИДЕНТИЧЕН после pruning
ECO.EVO7 FFF2 Morphology Evolution:  PASS (56)
ECO.EVO7 FFF1 Functional Phenotype:  PASS (110)
ECO.EVO7 FFF0 Contract Mapping:      PASS (112)
ECO.P1B-S1 Mutation/Lineage kernel:  PASS (5834)
ECO.PH2: PASS (107)   P1A-S1: PASS (109)   P1A-S2: PASS (235)
P1C-S4: PASS (15)    PH0: PASS (63)
RUN_ECO_EVO7_FFF6_TESTS.ps1: "ECO.EVO7 FFF6 Succession Lab candidate: PASS"
EVO6 WATER_SELECTION -SkipBaseline: PASS, result_hash 7010e307… (не изменён)
godot --import: без новых parse-ошибок для eco_evo7-файлов
```

(Счётчики FFF5–PH0 совпадают с требованиями этапа; FFF3/FFF4/FFF5 result_hash'и не изменились.)

## Осознанные ограничения R1

1. **Визуальный exact-Windows GUI-прогон отложен** (роль реализатора без desktop-capture): сцена проверена headless-autocap'ом (PASS, rendered=150) и следует EVO6-паттерну; команда графического запуска — `& "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe" --path <worktree> res://scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn` (BREAKPOINT_RUNTIME_DISABLED=1), ожидаемый маркер `ECO.EVO7-FFF6-VIS: READY …`. Скриншот-доказательство G5/C-режима — на line-level checkpoint.
2. **Forest-scale N≥1000** — FFF7; pruning сделан сейчас, потому что дёшев и нужен для честного G12-замера (дизайн §8).
3. **Крона не участвует в water/litter records** (только light geometry) — задекларированная граница R1: статичные деревья не имеют эволюционирующего phenotype для demand/litter.
4. **Effect records публикуются один раз (final generation)** на mode-прогон, а не каждый цикл: промежуточные публикации ничего не потребляют, экономия существенна на 108-цикловом stability; отклонение от паттерна мостов задекларировано в заголовке модуля.
5. **«Pioneer»-направление по leaf_economics не гейтится** — нестабильно на этом горизонте (калибровка п.4); направление отбора доказывается светом/net-балансом/дивергенцией.
6. **Запас порога G5 минимален** (мин. 4 пары при пороге ≥3): рост поколений/потомков может усилить сигнал, но это будущая перекалибровка.
7. **Кластерная диагностика слабая** (~25 кластеров на зону при любых порогах) — только label, на selection не влияет.
8. **DISPLAY_SCALE=3.0** — презентационное увеличение микрокосма для читаемости; экология считает 0.35 м; в хэши не входит.

## Следующий шаг

Line-level final checkpoint: сводка G1–G15 по всем этапам EVO7 (FFF0–FFF6), скриншот-доказательство C-режима лабы, решение о candidate→accepted переходе.
