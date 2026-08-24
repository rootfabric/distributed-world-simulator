# ECO.EVO7 FFF2 — Morphology Evolution R1 — Независимое ревью (FINAL REVIEW)

**Дата:** 2026-08-23
**Роль:** изолированная свежая роль reviewer (FFF2 research stage)
**Коммит:** `f63f3d928bbdc8b745b49b42b113bc37ea73220c` (diff `7d171d35..f63f3d92`, 7 файлов: 5 новых + 2 изменённых)
**Ветка:** `feature/eco-evo7-fff-r1`
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§12.1, §12.2, §19 FFF2; гейты G4, G5, G13)

---

## Вердикт

# **PASS**

Блокеров и мажоров нет. Все три гейта стадии (G4, G5, G13) подтверждены по исходникам и независимо воспроизведены прогонами; все числа checkpoint-документа воспроизводятся бит-в-бит; единственная mutation authority не нарушена. Найдены 2 MINOR-неточности в нарративе калибровки checkpoint-документа (не влияют на гейты, хэши и корректность самой калибровки) и 3 NOTE.

---

## Проверенный HEAD

- `git rev-parse HEAD` = `f63f3d928bbdc8b745b49b42b113bc37ea73220c` — **совпадает** с требуемым.
- `git status --porcelain` — **индексированных (staged) изменений нет**; присутствуют только untracked-артефакты среды (`*.gd.uid`, `__pycache__`), не входящие в diff коммита.
- Ветка: `feature/eco-evo7-fff-r1`.
- `git diff --name-only 7d171d35..f63f3d92` — ровно 7 файлов, состав соответствует заданию; `plant_mutation_lineage_kernel_v1.gd` в diff **отсутствует**.

---

## Фактические числа прогонов

### 1. `.\RUN_ECO_EVO7_FFF2_TESTS.ps1` — exit code 0, терминальная строка `ECO.EVO7 FFF2 Morphology Evolution candidate: PASS`

| Тест | Результат | Примечание |
|---|---|---|
| FFF2 morphology evolution acceptance | **PASS (56 assertions)** | бридж выполнен 3 раза (replay + другой seed) |
| FFF1 functional phenotype chain | **PASS (110)** | после перекалибровки |
| FFF0 contract mapping chain | **PASS (112)** | |
| P1B-S1 mutation lineage kernel | **PASS (5834)** | population_hash `83a114cd…`, chain_hash `3792cf99…` — регрессия самого kernel |
| PH2 environment-coupled development | **PASS (107)** | |
| P1A-S1 environment baseline | **PASS (109)** | environment_hash `b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` |
| P1A-S2 single-plant resource | **PASS (235)** | simulation_hash `618ec5c1…` |
| P1C-S4 aggregate contract | **PASS (15)** | failure matrix — все PASS |
| PH0 development trait contract | **PASS (63)** | traits hash `9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` |

Все числа совпадают с «Focused evidence» checkpoint FFF2 (docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md:63-73).

### 2. `.\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline` — exit code 0, **PASS**

- `result_hash = 7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` — **побайтно идентичен** в evolution (`ECO.EVO6-WATER evolution: PASS (24)`) и visual observatory (`ECO.EVO6-WATER-VIS: PASS plants=72`). Совпадает с принятым значением; FFF1/FFF2 регрессию не сломали (G14).

### 3. Независимый probe (внешний скрипт в `%TEMP%\fff2_probe_review.gd`, вне репозитория; Godot headless, 2 отдельных процесса)

- `Bridge.run_all(20260823, 24, 18, 4)`: `result_hash = dac30340e0790aed40a5e45e003520d30c3e61dc4f588d10133aa4025ece7c4b` — **идентичен в двух независимых процессах** (кросс-процессный детерминизм).
- `common_first_candidate_pool_hash = 10703123e2ac…` — **один и тот же во всех 5 сценариях** (G4 подтверждён независимо от теста).
- `distinct_final_population_pairs = 10` (10/10), `geometry_distinct_pairs = 10` (10/10), `scenarios_distinct_from_baseline = 4` (4/4) — совпадает с заявленным в checkpoint (там, где тест требует ≥8/≥8/≥3, фактически достигнут максимум).
- Таблица «Наблюдаемая экология» checkpoint (строки 43-47) — **все 30 чисел (5 сценариев × 6 метрик) совпали** с probe до заявленной точности (wet +0.0353/4.72/0.676/0.535/1.204/0.188; sunny +0.0813/4.16/0.757/0.522/1.134/0.913; shaded −0.0005/0.11/0.126/0.000/0.051/0.050; dry +0.0893/3.96/0.673/0.382/2.933/0.194; plateau +0.0614/3.56/0.702/0.414/1.788/0.160).
- Запасы порогов G5 (span/порог по 7 полям): height 4.608/0.25 (18.4×), crown_radius 0.710/0.20 (3.5×), density 0.631/0.04 (15.8×), LAI 0.535/0.05 (10.7×), root_depth 2.882/0.25 (11.5×), root_spread 0.863/0.25 (3.5×), structural 0.139/0.04 (3.5×) — заявленный в checkpoint «запас ≥2×» подтверждён с запасом (фактически ≥3.5×).
- Направления G5: dry/wet root_depth = 2.933/1.204 = **2.44×** (>1.5×); sunny−shaded density = 0.631 (>0.2); shade height 0.110 (<1.0); wet height 4.718 (>2.0); net в sunny/dry положителен.
- Предок (новая калибровка, age=1.0): sunny **+0.0057**, wet −0.0062, dry −0.0023, plateau −0.0036, shade −0.0163.
- Реконструкция СТАРОЙ калибровки (LAI/20, root 0.06, structural 0.095/8) на предке: net = **−0.041…−0.046** во всех 5 средах; LAI_old(wet) = 0.0256 — совпадает с заявленными «≈ 0.026» в истории калибровки (п.2). Верификация моей репликации: с новыми константами формула воспроизводит fitness предка −0.006175 бит-в-бит.

---

## Чеклист R1–R8

### R1. Kernel не тронут; делегация наследственности — **ПОДТВЕРЖДЕНО**

- `git diff --name-only 7d171d35..f63f3d92`: `plant_mutation_lineage_kernel_v1.gd` отсутствует; v1 semantics не менялись (MUTABLE_TRAITS — 5 геномных полей, plant_mutation_lineage_kernel_v1.gd:9-15).
- Extension делегирует геном+lineage 1:1: `Kernel.reproduce(...)` — scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd:119-121; дочерний lineage берётся из результата kernel — :124-125 (`genome_result["lineage"]`). Собственной реализации геномной мутации нет: extension не прелоадит `plant_lineage_record_v1` и не пишет lineage-поля.
- Второй lineage-книги нет: extension добавляет только morphology events (:137-169) и bundle-чекмсумы (`bundle_checksum`/`_bundle` :197-214, включают lineage checksum из kernel).
- Тест: цепочка остаётся на v1-записи — tests/research/ecology/eco_evo7_fff2_morphology_evolution_acceptance.gd:71-73 (parent_individual_id, generation+1, genome_checksum == lineage.genome_checksum); source-gate делегации :134-135; P1B-S1 (5834) зелёный.

### R2. Нет RNG; keyed rolls; frozen order; шаги в policy — **ПОДТВЕРЖДЕНО**

- grep `randf|randi|randomize|RandomNumberGenerator|Time.|rand_range|shuffle` по обоим новым скриптам — **0 совпадений**; source-gate теста дублирует проверку (acceptance:127-133).
- Все роллы через sha256 `_unit01` — extension:272-274 (идентично kernel:372-374); ключи `(event_context|layer|axis|gate|delta)` — extension:143-144.
- Канонический порядок — frozen const `AXES`/`AXIS_NAMES` — extension:27-41; тест фиксирует порядок (acceptance:36-40).
- Шаги берутся из policy, не из цикла: extension:145 (`effective_policy[step_key]`); в коде мутации нет числовых литералов шагов.
- NOTE-1 (не блокер): bridge формирует mutation seed через `String.hash()` — evo7_morphology_evolution_bridge_v1.gd:153; это детерминированный (не RNG) 32-битный хэш, паттерн идентичен принятому EVO6-WATER (evo6_water_evolution_bridge_v1.gd:152). Кросс-версионная стабильность `String.hash()` не гарантирована документацией Godot — приемлемо для research R1 с зафиксированной сборкой (4.7.1 custom).

### R3. Policy schema §12.2 — **ПОДТВЕРЖДЕНО**

- Каждая ось имеет min/max из layer-контрактов: `_bounds` — extension:237-239; `Traits.BOUNDS` (max_height_m [0.10,40], crown_spread_m [0.05,30], apical_dominance [0,1]) — plant_development_traits_v1.gd:22-31; `Extension.BOUNDS` (5 осей) — plant_development_traits_extension_evo7_v1.gd:32-38; тест проверяет наличие bound каждой оси (acceptance:41-43).
- Шаг — в policy per-axis; общий probability gate `morphology_probability` — extension:146; канонический порядок — const.
- `validate_policy` отвергает: отсутствие genome_policy — :59-60; невалидную kernel-политику — :61-62; отсутствие шага — :66-67; лишние поля (точный count) — :68-69; плохую вероятность — :70-72; отрицательный шаг — :75-76; шаг больше диапазона оси — :77-79. Тесты на все 4 класса отказа — acceptance:45-56.
- `policy_hash` покрывает kernel policy hash + probability + все шаги — extension:82-89; детерминизм и длина 64 проверены (acceptance:33-35).

### R4. Fail-closed reproduce_bundle — **ПОДТВЕРЖДЕНО**

- `offspring_index < 0` → `{}` — extension:111-112; невалидный/tampered bundle (checksum gate) — :113-114 и :216-231 (сравнение `bundle_checksum` :228-230); невалидная policy — :116-117; отказ kernel — :122-123; повторная валидация мутированных трейтов — :171-174.
- Тест tampered `ext_traits` (изменение foliage_density → отказ) — acceptance:77-80.

### R5. G4 механика бриджа — **ПОДТВЕРЖДЕНО**

- Формула seed одинакова во всех сценариях (сценарий в формулу не входит): `"EVO7-MORPHO|lineage_seed|generation|parent_index|offspring_index"` — bridge:153.
- Pool hash первого поколения записывается per-scenario — bridge:146, 161-162, 188; равенство всех пяти enforced в `run_all` с возвратом `{}` при расхождении — bridge:84-87.
- Детерминированный отбор: fitness desc, tiebreak bundle_checksum asc — bridge:215-218 (применяется :163-164).
- Независимое подтверждение: probe — pool hash `10703123e2ac…` одинаков во всех 5 сценариях; replay в тесте даёт идентичный result_hash (acceptance:89-90); смена seed меняет результат (acceptance:91-92); кросс-процессный result_hash идентичен (см. выше).

### R6. Калибровочный аудит — **ПОДТВЕРЖДЕНО, с 2 MINOR в нарративе**

- Три константы в diff совпадают с описанием: `LEAF_AREA_REF_M2` 20.0→2.0 — plant_functional_phenotype_v1.gd:43; `STRUCTURAL_COST_SCALE` 0.095/8→0.095/40 — :47; `ROOT_MAINTENANCE_PER_METER` 0.06→0.025 — :49.
- FFF1 acceptance после перекалибровки: **PASS (110)** — воспроизведено моим прогоном.
- FFF1 checkpoint честно дополнен: аддендум «Recalibration (FFF2)» со старыми значениями — docs/checkpoints/2026-08-23_ECO_EVO7_FFF1_R1_RU.md:36 (формула LAI с пометкой «was /20») и :46-54; направление couplings не менялось, это заявлено.
- История калибровки в FFF2 (две неудачные попытки) — docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md:18-22. П.2 подтверждён независимо: LAI предка при /20 = 0.0256 ≈ «0.026» (probe). П.1: направление (отрицательный net предка при старых константах) подтверждено реконструкцией, но заявленная величина «≈ −0.001» не воспроизводится — фактически −0.041…−0.046 (MINOR-1). Утверждение «предок в продуктивных средах положителен» верно только для sunny_slope (MINOR-2).

### R7. Качество тестов — **ПОДТВЕРЖДЕНО**

- G4 (acceptance:85-92): pool hash присутствует (64 hex), ≥8 из 10 пар различны, deterministic replay — идентичный result_hash, другой seed меняет результат. Не тавтологии: пороги реальны (10 пар максимум, фактические 10).
- G5 (acceptance:94-110): ≥8 geometry-пар, ≥3 сценария от baseline, направления dry>1.5×wet, dry>plateau, sunny>shaded+0.2, shade<1.0, wet>2.0, положительный net в sunny/dry. Запасы реальны (probe: 2.44×; 0.631; 0.110; 4.718).
- G13 source gates (acceptance:127-137): нет RNG в обоих скриптах, `Kernel.reproduce` делегация, preload kernel, блок MUTABLE_TRAITS kernel нетронут (строковая проверка блока).
- Наследуемый сдвиг и guards (acceptance:112-125): предок не мутирует при evaluate, сухие корни удвоились vs предка, средние внутри declared bounds.
- Пороги с документированным запасом: checkpoint:58 перечисляет пороги и наблюдаемые span — совпадают с кодом (bridge:33-41) и probe; заявление «запас ≥2×» подтверждено (факт ≥3.5×).
- Ручной пересчёт assertions: 16+11+5+9+4+11 = 56 — совпадает с напечатанным числом.

### R8. Честность документации — **ПОДТВЕРЖДЕНО, с MINOR-1/2 и NOTE-3**

- Статус **CANDIDATE** — docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md:1.
- Раздел ограничений (5 пунктов) — :75-81: fitness-preview (:77), structural neutral drift (:78), shade collapse (:79), пороги на одном детерминированном seed (:80), fixture-only среды (:81). Все заявленные ограничения соответствуют коду.
- Таблица наблюдаемой экологии (:43-47) — 30/30 чисел совпали с probe; заявления гейтов (10/10, 4/4, идентичный pool, replay) — совпали; пороги и span в тексте — совпали с кодом и измерениями; EVO6 hash — совпал.
- MINOR-1/MINOR-2/NOTE-3 — см. «Находки».

---

## Находки

### BLOCKER

Нет.

### MAJOR

Нет.

### MINOR

1. **MINOR-1 (документация, нарратив калибровки).** `docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md:20` — «net-баланс предка был отрицателен (≈ −0.001)». Направление подтверждено, но величина не воспроизводится: точная реконструкция компилятора с исходными константами (LAI/20, root 0.06, structural 0.095/8) на текущем head даёт net = −0.041…−0.046 во всех 5 средах (верификация репликации: с новыми константами формула даёт −0.006175 — совпадение с probe до 1e-6). Вероятна опечатка (−0.04 → −0.001) либо иной контекст измерения. На гейты, хэши и корректность принятой калибровки не влияет. Рекомендация: исправить величину при следующей ревизии checkpoint.
2. **MINOR-2 (документация, нарратив калибровки).** `docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md:22` — «предок в продуктивных средах положителен, в shade отрицателен». Фактически (probe, age=1.0): положителен только sunny_slope (+0.0057); wet_lowland −0.0062, dry_ridge −0.0023, plateau −0.0036 — отрицательны. Давление отбора от этого сильнее, а не слабее (эволюционировавшие популяции положительны в 4/5 сред — таблица это честно показывает), но формулировка неточна. Рекомендация: уточнить формулировку («предок около нуля/отрицателен всюду, кроме sunny; эволюция выводит net в плюс»).

### NOTE

1. **NOTE-1 (стиль/переносимость).** `evo7_morphology_evolution_bridge_v1.gd:153` — mutation seed через `String.hash()` (32-бит). Детерминирован в рамках сборки (подтверждено кросс-процессно), паттерн идентичен принятому EVO6-WATER (`evo6_water_evolution_bridge_v1.gd:152`), но документация Godot не гарантирует стабильность `String.hash()` между версиями движка. Для research R1 с зафиксированным Godot 4.7.1 — приемлемо; при переносе evidence на другую сборку — пересчитать.
2. **NOTE-2 (робастность, недостижимый на практике путь).** `evo7_morphology_evolution_bridge_v1.gd:209` — при отказе `FunctionalPhenotype.compile` кандидат получает `features = {}` и fitness −999; если бы такой кандидат попал в финальную популяцию, цикл mean-features (:174-175) упал бы runtime-ошибкой вместо отказо-безопасного `{}`. Для валидных бандлов недостижимо (все входы chain-валидированы, −998-й fitness не проходит отбор при N≥2). Ужесточить до `return {}` на уровне сценария — дешёвое улучшение на будущее.
3. **NOTE-3 (точность формулировки ограничения).** `docs/checkpoints/2026-08-23_ECO_EVO7_FFF2_R1_RU.md:53,78` — «structural_investment дрейфует нейтрально-вниз / к минимуму». Наблюдение (probe): смешанный слабый дрейф — plateau 0.283 (↓ с 0.40), wet 0.330 (↓), sunny 0.421 (↑), shaded 0.414 (↑), dry 0.422 (↑); среднее 0.374 (слегка вниз). Характеристика «нейтральный дрейф без benefit-стороны» корректна, «к минимуму» — с оговоркой: в 3/5 сред значение предка не уменьшилось. Суть ограничения (нет benefit-стороны до FFF3+) задокументирована верно.

---

## Заявление о независимости

Ревью выполнено изолированной свежей ролью, не участвовавшей в реализации FFF2. Все проверки проведены лично по первоисточникам на проверенном HEAD `f63f3d92`: git-состояние, полный diff, исходники обоих новых скриптов, kernel, контрактов bounds, теста, раннера, обоих checkpoint-документов и спецификации; оба обязательных прогона (`RUN_ECO_EVO7_FFF2_TESTS.ps1`, `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline`) выполнены мной на этой машине с записью фактических чисел; дополнительно числа ecology-таблицы и гейт-метрики воспроизведены собственным probe-скриптом, размещённым вне репозитория (`%TEMP%\fff2_probe_review.gd`), включая кросс-процессную проверку детерминизма и независимую реконструкцию старой калибровки. Данные предыдущих ревью/верификаций не использовались как доказательства. В репозитории создан ровно один новый файл — настоящий отчёт; существующие файлы не изменялись; commit/push не выполнялись.

**Итог: PASS** (2 MINOR по нарративу калибровки, 3 NOTE; блокеров и мажоров нет).
