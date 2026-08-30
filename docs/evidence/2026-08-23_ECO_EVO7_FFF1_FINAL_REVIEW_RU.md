# ECO.EVO7 FFF1 — Независимое финальное ревью R1 (PlantFunctionalPhenotype)

**Роль:** изолированный независимый REVIEWER (свежий контекст, без доступа к разговору имплементатора).
**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1`
**Ревьюируемый коммит:** `a8958d7dcfa6e96b52923f53395b966d382a3eec` (diff `d0d57f7e..a8958d7d`)
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§5, §6, §11, §19 FFF1, gates G1–G3)
**Аудит-основание:** `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md`

---

## Вердикт

# PASS

Блокирующих и мажорных находок нет. Все чеклист-пункты R1–R8 подтверждены по исходникам (не по документации), оба прогон-раннера перевыполнены самостоятельно на точном HEAD, все заявленные числа и хеши воспроизведены байт-в-байт. Обнаружены 2 MINOR- и 7 NOTE-находок (см. «Находки»), ни одна не подрывает контракты G1–G3, единственность морфологической истины или чистоту границ слоя.

---

## Проверенный HEAD

- `git rev-parse HEAD` = `a8958d7dcfa6e96b52923f53395b966d382a3eec` — **совпадает с требуемым**.
- `git status --porcelain`: staged/modified tracked-файлов **0** (только предварительно существовавшие untracked `.uid`-сайдкары Godot и `__pycache__`, в коммит не входят, см. NOTE-7).
- Родитель коммита: `d0d57f7e` (`git log --format="%h %p"`: `a8958d7d d0d57f7e`), т.е. diff `d0d57f7e..a8958d7d` — ровно один коммит `feat(eco): EVO7 FFF1 PlantFunctionalPhenotype derived contract (G1-G3)`.
- Повторная проверка после всех прогонов: HEAD не изменился, modified/staged по-прежнему 0 — ревью ничего не модифицировало.

---

## Фактические числа прогонов

Оба раннера выполнены мной лично на HEAD `a8958d7d` (Godot `4.7.1.stable.double.custom_build.a13da4feb`, Windows, headless).

### `.\RUN_ECO_EVO7_FFF1_TESTS.ps1` — exit code 0

| Тест | Результат | Факт | Ожидалось | Совпадение |
|---|---|---|---|---|
| FFF1 functional phenotype acceptance | PASS | **107 assertions** | 107 | ✅ |
| FFF0 contract mapping chain | PASS | **112 assertions** | 112 | ✅ |
| PH2 environment-coupled development dependency | PASS | **107 assertions** | 107 | ✅ |
| P1A-S1 parent environment regression | PASS | **109 assertions**, `environment_hash=b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7` | 109, hash `b862c4fc…` | ✅ |
| P1A-S2 parent resource regression | PASS | **235 assertions**, `simulation_hash=618ec5c188fc…` | 235 | ✅ |
| P1C-S4 parent aggregate regression | PASS | **15 assertions**, failure matrix — все PASS | 15 | ✅ |
| PH0 development trait contract regression | PASS | **63 assertions**, `development_traits_hash=9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea` | 63, hash `9d812950…` | ✅ |
| Терминальная строка | — | `ECO.EVO7 FFF1 PlantFunctionalPhenotype candidate: PASS` | та же | ✅ |

### `.\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline` — exit code 0

- Python acceptance: PASS; fitness math: PASS (5); evolution: PASS (24); visual adapter: PASS (plants=72).
- **`result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e`** — идентичен в evolution-прогоне и в visual observatory, совпадает с ожидаемым.
- Терминальная строка: `ECO.EVO6-WATER strong water rules + evolutionary divergence + visual adapter: PASS`.

Расхождений между заявленными в checkpoint-документе числами и моими фактическими прогонами **нет**.

---

## Чеклист R1–R8

Формат: пункт → результат → файл::строка.

### R1. Область диффа — ✅ PASS
- `git diff --name-status d0d57f7e..a8958d7d`: ровно 5 добавленных файлов (`A`), удалений/модификаций нет:
  `RUN_ECO_EVO7_FFF1_TESTS.ps1`, `docs/checkpoints/2026-08-23_ECO_EVO7_FFF1_R1_RU.md`, `scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd`, `scripts/research/ecology/plant_functional_phenotype_v1.gd`, `tests/research/ecology/eco_evo7_fff1_functional_phenotype_acceptance.gd`.
- `scripts/ecology/production`, `scripts/runtime`, `config`, `scenes`, тесты вне `tests/research/ecology` — не затронуты. Runner лежит в корне (runner-путь, разрешён).

### R2. Единственная морфологическая истина — ✅ PASS
- Геометрия не строится: нет `Skeleton`, build-вызовов, конструирования сегментов; единственные «segment»-упоминания — чтение счётчиков графа `plant_functional_phenotype_v1.gd::186-192`.
- Потребляется `ph2_realized` как вход: `plant_functional_phenotype_v1.gd::67`; валидация: схема PH2 `::76`, realized-триты через `Traits.validate` `::80`, граф через `graph_hash`+`metrics` `::82`, привязка `genome_checksum` `::84`, `environment_checksum` `::86`.
- `CoupledDevelopment` используется только как константа `SCHEMA` (`::76`); `realize(...)` компилятором не вызывается — второго генератора нет. Морфология приходит исключительно из `plant_environment_coupled_development_v1.gd::realize` (проверено: `result` содержит `realized_development_traits`/`growth_graph`, `plant_environment_coupled_development_v1.gd::49-50`).

### R3. Нет связности с heredity/render/persistence — ✅ PASS
- Preload'ы компилятора (plant_functional_phenotype_v1.gd::32-36): только Traits, Extension, Genome, EnvironmentSample, CoupledDevelopment. Нет `plant_mutation_lineage_kernel_v1`, lineage-записей, render description/profile/multiscale, persistence-writers (подтверждено чтением всего файла + grep).
- Extension-контракт: ни одного preload/references (весь файл `plant_development_traits_extension_evo7_v1.gd`, grep по lineage/render/persist/FileAccess — 0 совпадений).
- Тестовые source-gate'ы дублируют границу: `eco_evo7_fff1_functional_phenotype_acceptance.gd::107-109` (heredity-токены) и `::215-223` (camera/mesh/persistence/authority и др.).

### R4. Контракт расширения — ✅ PASS
- Ровно 5 осей с заявленными границами: `plant_development_traits_extension_evo7_v1.gd::32-38` — `foliage_density [0.05,1]`, `leaf_economics_proxy [0,1]`, `structural_investment [0,1]`, `root_spread_m [0.05,30]`, `root_shoot_ratio [0.15,0.85]`. Состав осей совпадает с доказанными FFF0 gap'ами (`ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md::41-48`).
- Exact-field-count validate: `::76` (+ проверка отсутствующих `::78-80` и неожиданных полей `::81-83`).
- Checksum в house-стиле: `"|".join(PackedStringArray).sha256_text()` с `%.9f` (`::100-104`) — тот же стиль, что PH0 (`plant_development_traits_v1.gd::100-112`).
- `with_trait` отклоняет неизвестное имя трита `::65-66` и невалидный источник `::67-68`.

### R5. Аудит математики компилятора — ✅ PASS (с 1 MINOR + 2 NOTE)
Все заявленные в шапке couplings сверены с кодом `plant_functional_phenotype_v1.gd`:
- age-кривые: `pow(age,0.8)` `::96,102`; `pow(age,0.5)` `::97,103` — совпадают с шапкой `::14-15`.
- foliage-bearing floor: `0.35 + 0.65*lateral_fraction` — `CROWN_BASE_FOLIAGE=0.35` `::42`, формула `::105`.
- LAI = density * PI * r² / 20, cap 6 — `::107-108` (`LEAF_AREA_REF_M2=20.0` `::43`, `LEAF_AREA_CAP=6.0` `::44`).
- allocation factors `2*rsr` / `2*(1-rsr)`: `::99-100`; применяются только к функциональным компонентам (`::114-115,124-126`), геометрия не трогается.
- root reach 0.22: `::46,118`; константа реально существует в `plant_resource_model_v1.gd::68` (см. NOTE-3 о форме функции).
- structural cost scale `0.095/8`: `::47,127`; источник `0.095 * pow(height,1.20)` подтверждён в `plant_resource_model_v1.gd::86`.
- ppm: floor+nonneg `::197-198`; snap 1e-9: `::194-195`.
- Порядок токенов хеша фиксирован: литеральный `PackedStringArray` + фиксированный `_NUMERIC_FIELDS` + фиксированный порядок ppm (`::170-184`), итерации по словарю нет. В хеш входят: schema, version, individual_seed, 5 provenance-хешей, 14 числовых полей, 3 ppm int.
- **MINOR-1:** `age_fraction` — числовое поле §5, попадает в payload (`::144`), но **отсутствует в токенах хеша** (нет в `_NUMERIC_FIELDS` `::51-57`). Детерминизм G1 не страдает; чувствительность хеша к возрасту обеспечивается транзитивно через хешируемые height/radius/roots; коллизия возможна только в вырожденных нулевых случаях. Подробнее в «Находках».
- **NOTE-2:** в шапке `::21` для `leaf_size_proxy` заявлено `internode/1.0 (declared)` без упоминания clampf [0,1] (`::109`); границы PH0 `internode_length_m [0.02,4.0]` допускают насыщение значения на 1.0.

### R6. Fail-closed — ✅ PASS (все 6 случаев в коде; 1 NOTE по покрытию)
- Подделанный genome checksum → `{}`: `::70-71`; тест `…acceptance.gd::188-190`.
- Out-of-range extension → `{}`: `::72-73`; тест `::192-194`.
- Чужая схема ph2 → `{}`: `::76-77`; тест `::196-198`.
- Несовпадение ph2/environment checksum → `{}`: `::84-87`; тест `::200-202`.
- `age_fraction` вне [0,1] (включая non-finite) → `{}`: `::88-90`; тест `::204-206`.
- Отрицательный `individual_seed` → `{}`: `::91-93`; **в тесте не проверяется** (NOTE-4).
- **MINOR-2:** fail-closed не тотален для сфабрикованного ph2 с корректной строкой схемы, но неполным составом полей — прямые обращения `metrics["height_m"]`/`metrics["horizontal_radius_m"]` (`::95,102,103`) и `ph2["inherited_traits_checksum"]`/`ph2["phenotype_hash"]` (`::145,147`) дают runtime-ошибку вместо `{}` (проверен только `graph.has("metrics")` `::82`). Из реального вывода `realize()` недостижимо — робастностный зазор, не дыра детерминизма.

### R7. Качество тестов — ✅ PASS
- **G1**: byte-identical payload (сравнение всех ключей) `::72-78`, идентичный hash `::72-73`, независимость от порядка ключей входного словаря `::80-88`, воспроизводимость hash из payload `::70`, длина 64 `::69`, наличие всех полей §5 `::54-63`, диапазоны `::64-67`, монотонность age-кривой `::90-92`.
- **G2**: wet vs dry через настоящий PH2-путь (realize → realized traits → graph) `::95-104`; genome checksum неизменен `::105`; kernel-снимок `::97,106`; source-scan на heredity-токены `::107-109`.
- **G3**: ветвящаяся референс-морфология с guard-assertions (`lateral_segment_count>0`, `horizontal_radius_m>0`, `LAI>0`) `::116-122`; одноосные пробы с bit-identical несвязанными осями: stature→root depth/spread `==` `::130-131`; foliage_density→height `==`, root `==` `::140-141`; economics→height `==` `::149`; structural→height `==` `::157`; root_spread→height `==` `::164`; rsr→height `==` `::173`; наследуемость корней через genome-контракт `::176-181`; немутация входов `::184`.
- **Тавтологии:** эхо-проверки (`::147,156,172`) переформулируют формулы, но каждая идёт в паре с реальной coupling-проверкой (gain/litter/cost/net); «mutation authority untouched» `::106` внутри процесса почти тавтологична, однако подпирается source-scan'ами `::107-109`. Утверждения `==` (bit-identical) — несущие: любое скрытое перекрёстное coupling их ломает. Утверждения, которое прошло бы при сломанном заявленном coupling, **не найдено**.
- **NOTE-5:** проверка немутации входов `::184` покрывает только PH0 traits (не genome/ext/env).
- **NOTE-4:** негативный случай `individual_seed < 0` тестом не покрыт.

### R8. Честность документации — ✅ PASS
`docs/checkpoints/2026-08-23_ECO_EVO7_FFF1_R1_RU.md`:
- Статус **CANDIDATE** заявлен в заголовке (`::1`).
- Все требуемые declared limitations присутствуют: extension-оси без собственной plasticity `::76`; structural investment — только cost-сторона `::77`; allocation масштабирует компоненты, не геометрию `::78`; foliage floor 0.35 `::79`; отсутствие обратной связи в среду `::24,83`.
- Overclaiming не найден: flux-поля честно описаны как «публикация значений» без эффектов (`::24`); reuse констант помечен как «задекларировано» (`::25`); все числа evidence `::63-72` совпали с моими прогонами байт-в-байт.
- **NOTE-6:** FFF0-документ (`ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md::154`) планировал freeze units/bounds «после sensitivity-проб FFF1»; фактически границы заморожены в R1 без sensitivity-проб, калибровка отложена в FFF3+ (честно объявлено в limitation `::79`). Мягкое отклонение от плана, задокументированное.

---

## Находки

### BLOCKER
Нет.

### MAJOR
Нет.

### MINOR

1. **`age_fraction` не входит в токены `phenotype_hash`.** `plant_functional_phenotype_v1.gd::51-57` (`_NUMERIC_FIELDS`) и `::169-184` (`compute_phenotype_hash`) против payload-поля `::144`. При этом эхо `individual_seed` в хеш входит (`::172`), а эхо `age_fraction` — нет: непоследовательно. Детерминизм (G1) не нарушен; инъективность хеша по возрасту держится транзитивно (age меняет height/radius/roots, которые хешируются), но в вырожденных нулевых payload'ах (например, age 0 vs ~0, либо сфабрикованный ph2 с нулевой геометрией) два разных `age_fraction` дают одинаковый хеш при разных payload-полях. Рекомендация для FFF2+: добавить `age_fraction` в токены хеша (это изменит значение `phenotype_hash` — делать в рамках отдельного коммита с обновлением evidence).
2. **Fail-closed не тотален для schema-valid, но неполного сфабрикованного ph2.** `plant_functional_phenotype_v1.gd::95,102,103,145,147` — прямая индексация `metrics["height_m"]`, `metrics["horizontal_radius_m"]`, `ph2["inherited_traits_checksum"]`, `ph2["phenotype_hash"]` при проверенном лишь `graph.has("metrics")` (`::82`) и строке схемы (`::76`). Такой payload недостижим из `realize()` (поля всегда проставляются, `plant_environment_coupled_development_v1.gd::43-52`), но контрактный метод compile обязан падать в `{}`, а не runtime-ошибкой. Рекомендация: заменить прямые обращения на `.get` с fail-closed-проверками.

### NOTE

1. **`with_trait` не валидирует новое значение по границам** (`plant_development_traits_extension_evo7_v1.gd::64-73`): out-of-range значение даёт словарь, который честно проваливает `validate()`/compile (fail-closed сохранён на границе потребления, тест `::192-194`). Для probe-хелпера допустимо, но сигнатура молча возвращает невалидный словарь.
2. **Шапка не декларирует clamp `leaf_size_proxy`**: заявлено `internode/1.0 (declared)` (`plant_functional_phenotype_v1.gd::21`), в коде `clampf(..., 0.0, 1.0)` (`::109`); при границах PH0 internode до 4.0 м прокси насыщается на 1.0. Документировать в freeze-списке.
3. **Root-reach 0.22 — reuse константы, не формулы**: в `plant_resource_model_v1.gd::67-68` бонус капируется `clamp(depth/2,0,1)` (максимум 0.22), в компиляторе — `minf(depth,20)*0.22` (`plant_functional_phenotype_v1.gd::118`, насыщение через clampf при depth ≳ 4.6 м). Заявление в шапке (`::46`) и checkpoint-доке (`::25`) сформулировано как reuse константы — честно, но формы функций различаются; учесть при калибровке FFF3+.
4. **Покрытие: `individual_seed < 0`** кодом обработан (`plant_functional_phenotype_v1.gd::91-93`), но в `eco_evo7_fff1_functional_phenotype_acceptance.gd` негативного кейса нет (в отличие от остальных пяти кейсов R6).
5. **Покрытие: немутация входов** проверена только для PH0 traits (`…acceptance.gd::184`); genome/ext/env формально не проверены (по коду compile мутирует только локальные копии — риск отсутствует, но ассерт односторонний).
6. **Границы осей заморожены в R1 без sensitivity-проб**, которые FFF0-план предполагал перед freeze (`ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md::154`); калибровка явно отложена (`2026-08-23_ECO_EVO7_FFF1_R1_RU.md::79`). Осознанное отклонение, но его стоит зафиксировать в FFF2-брифе, чтобы bounds не «съехали» молча.
7. **Untracked-артефакты в worktree**: множество `.uid`-сайдкаров Godot и `scripts/research/ecology/__pycache__/` (untracked, не staged, в коммит `a8958d7d` не входят). К ревьюируемому коммиту отношения не имеют; рекомендация — отдельная уборка/`.gitignore` вне рамок FFF1.

---

## Заявление о независимости

Данное ревью выполнено изолированным свежим контекстом роли REVIEWER, не участвовавшим в реализации FFF1 и не имевшим доступа к рабочему разговору имплементатора. Все проверки чеклиста выполнены мной непосредственно по исходникам и git-данным на точном HEAD `a8958d7dcfa6e96b52923f53395b966d382a3eec`; оба тестовых раннера (`RUN_ECO_EVO7_FFF1_TESTS.ps1`, `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline`) перевыполнены мной лично, зафиксированы фактические (а не заявленные) числа. В рамках ревью создан ровно один новый файл — настоящий отчёт; существующие файлы не модифицировались, commit/push не выполнялись. Ни одна документация не принималась на веру без сверки с кодом; утверждения checkpoint-документа о числах прогонов подтверждены независимым воспроизведением.
