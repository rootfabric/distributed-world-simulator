# ECO.EVO7 FFF0 — Contract Mapping Checkpoint — Независимое финальное ревью

**Дата:** 2026-08-23
**Роль:** независимый REVIEWER (свежая изолированная роль, implementer не участвовал)
**Ветка:** `feature/eco-evo7-fff-r1`
**Ревьюируемый коммит:** `6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f` (diff `d4d5c309a2da772751cd53adf17554eea697dd19..6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f`)

---

## Вердикт

**PASS**

Все пункты чеклиста R1–R8 подтверждены чтением исходников и собственным прогоном раннера на exact head. Блокирующих и мажорных находок нет; зафиксированы 2 MINOR и 5 NOTE (см. «Находки»). Вердикт относится к статусу CANDIDATE этапа FFF0 и не является canonical acceptance.

## Проверенный HEAD (exact sha)

```text
git rev-parse HEAD -> 6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f   (совпадает с требованием)
git rev-parse d4d5c309 -> d4d5c309a2da772751cd53adf17554eea697dd19 (база, совпадает с аудит-доком)
git branch --show-current -> feature/eco-evo7-fff-r1
git status --porcelain -> staged изменений НЕТ; только untracked .uid sidecar-файлы и __pycache__ (к коммиту не относятся, см. NOTE-6)
```

Diff `d4d5c309..6b56c82a` добавляет ровно 4 файла, 435 вставок, 0 удалений:

```text
A  RUN_ECO_EVO7_FFF0_TESTS.ps1
A  docs/checkpoints/2026-08-23_ECO_EVO7_FFF0_R1_RU.md
A  docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md
A  tests/research/ecology/eco_evo7_fff0_contract_mapping_acceptance.gd
```

## Протестированные головы и фактические числа прогонов

Команда: `powershell -Command ".\RUN_ECO_EVO7_FFF0_TESTS.ps1"` из корня worktree, Windows, headless.
Фактический вывод (ревьюер запускал лично; exit code 0):

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
=== ECO FFF0 contract mapping acceptance ===
ECO.EVO7 FFF0 Contract Mapping: PASS (168 assertions)
=== ECO P1A-S1 parent environment regression ===
ECO.P1A-S1 environment_hash=b862c4fc529b5fd8229355c4c38b96a429e4ef1d902d6dd86b27860d8ce51af7
ECO.P1A-S1 Environment Baseline: PASS (109 assertions)
=== ECO P1A-S2 parent resource regression ===
ECO.P1A-S2 simulation_hash=618ec5c188fcb8b7c27a1e95147fcb9c9646eb6448c68a57a90cd525d5a9492c
ECO.P1A-S2 Single-Plant Resource Model: PASS (235 assertions)
=== ECO P1C-S4 parent aggregate regression ===
ECO.P1C-S4 aggregate=0ca70eab1e5db569a45e244a6cd2f378469197472de2a7d35f8a4a15db870112 failure_matrix={GLOBAL_TAKEOVER: PASS, DIVERSITY_COLLAPSE: PASS, CLUSTER_COLLAPSE: PASS, FALSE_NICHE_UNIFORM: PASS, RUNAWAY_TRAIT: PASS_NO_MUTATION_STATIC_BOUNDED_FOUNDERS, REPLAY_DIVERGENCE: PASS_EXACT_HASH_CONTRACT}
ECO.P1C-S4 Aggregate Contract: PASS (15 assertions)
=== ECO PH0 development trait contract regression ===
ECO.PH0 development_traits_hash=9d812950f421c2618ce0c62aa30e417e953dd9a61abdc14a03f9d129df876dea individual_seed=959597643576420676
ECO.PH0 Development Trait Contract: PASS (63 assertions)
ECO.EVO7 FFF0 Contract Mapping candidate: PASS
```

Сверка с заявлениями чекпойнт-дока `docs/checkpoints/2026-08-23_ECO_EVO7_FFF0_R1_RU.md::33-41`:

| Заявлено | Фактически | Совпадение |
|---|---|---|
| `FFF0 Contract Mapping: PASS (168 assertions)` | то же | ✅ |
| P1A-S1 hash `b862c4fc529b5fd8…` | идентичен | ✅ |
| PH0 development_traits_hash `9d812950f421c261…` | идентичен | ✅ |
| P1A-S2 235 / P1C-S4 15 / PH0 63 assertions | то же | ✅ |
| Godot `4.7.1.stable.double.custom_build.a13da4feb` | то же | ✅ |
| Финальная строка `candidate: PASS` | есть | ✅ |

Дополнительно: независимый статический подсчёт `_check`-вызовов в acceptance-скрипте даёт те же **168** (M1=16, M2=15, M3=81, M4=9, M5=11, M6=4, M7=8, M8=6, M9=11, M10=7) — число не взято «с потолка».

Не пере-проверялось ревьюером: EVO6-WATER регрессия (`RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline`, result_hash `7010e307…`) — вне обязательного re-run скоупа данного ревью; дифф не затрагивает ни одного файла EVO6-поверхностей, поэтому этим коммитом результат изменён быть не мог (см. NOTE-5).

## Чеклист R1–R8

| Пункт | Результат | Основание (файл::строка) |
|---|---|---|
| R1. Дифф только research/docs/runner | **PASS** | `git diff --stat d4d5c309..6b56c82a` = ровно 4 файла выше; путей `scripts/ecology/production`, `scripts/runtime`, `config/control`, `scenes` нет |
| R2. REUSE-строки цитируют реальное | **PASS** | `plant_genome_v1.gd::6-18` FIELD_NAMES вкл. `height_m`::10, `root_depth_m`::12, exact-count `::84`; `plant_development_traits_v1.gd::18-19` TRAIT_NAMES ровно 8 + BOUNDS::22-31; `evo6_water_fitness_v1.gd::29` читает `root_depth_m`; дополнительно: `plant_growth_graph_skeleton_v1.gd::123` metrics.height_m, `::144` `_unit(seed,key)`; `plant_environment_coupled_development_v1.gd::12` realize, `::126-129` композиция phenotype-hash; `plant_renderer_profile_v1.gd::5` PROFILE_ORDER; `plant_resource_model_v1.gd::86` `structural_cost = 0.095*pow(height_m,1.20)`. Оговорка по языку одной цитаты — NOTE-3 |
| R3. NEW/gap-заявления держатся сегодня | **PASS** | grep `scripts/research/ecology/*.gd`: `leaf_economics`, `wood_density`, `root_spread`, `soil_texture`, `transpiration`, `litter` — 0 вхождений в код; `foliage_density` — только presentation-параметр `evo4_bridge_presentation_v1.gd::168,288,307` (не heritable); `foliage_fraction` — render-side `plant_renderer_profile_v1.gd::26,46,59`, `plant_render_description_v1.gd::88-90`; `environment_sample_v1.gd::5-18` FIELD_NAMES без texture/litter/transpiration/understory_light; `plant_development_traits_v1.gd` — ни одной новой оси |
| R4. MUTABLE_TRAITS = ровно 5, мост делегирует | **PASS** | `plant_mutation_lineage_kernel_v1.gd::9-15` точный список 5 экологических тритов, морфологии нет (`height_m` лишь сохраняется в snapshot `::317-328`); `reproduce()`::120, `policy_hash()`::105, `validate_policy()`::76; `evo6_water_evolution_bridge_v1.gd::7` preload kernel, `::153` `MutationKernel.reproduce(...)`, `::4` «No second mutation path», собственного `MUTABLE_TRAITS` нет (grep: 0) |
| R5. Качество acceptance-теста M1–M10 | **PASS** (с MINOR-1/NOTE-7) | тесты соответствуют §10 аудит-дока; тавтологий/always-true нет; поломка любого заявленного факта ловится (смена списка/порядка полей — `::38-40,48-50,65-67`, удаление exact-count валидации — `::42`, появление morphology в ядре — `::48-52`, heritable allocation — `::126-127`, исчезновение gap-каналов — `::93-94`, render write-back — `::137-138`); M8 — поведенческая проверка через `create_seed_envelope`/`create_initial_development_state` `::114-127` |
| R6. Раннер повторяет домовый паттерн | **PASS** | `RUN_ECO_EVO7_FFF0_TESTS.ps1` зеркалит `RUN_ECO_PH0_TESTS.ps1`: param/GODOT_BIN `::1`, `BREAKPOINT_RUNTIME_DISABLED` save/set/restore `::7-9,27-29`, uid-cache preflight `--import` c проверкой exit code `::10-13`, throw при ненулевом exit теста `::24`, финальная строка печатается только после успешного цикла `::31` (throw её минует). Отличие от PH0-раннера: нет хардкод-сводок per-test — допустимо, сводки дают сами тесты |
| R7. Запрещённые паттерны в новых файлах | **PASS** | scan 4 файлов: второго mutation kernel нет; environment→genome записи нет; renderer write-back нет; hardcoded веток TREE/BUSH/GRASS нет (упоминания — только как запрет в доке `ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md::108`); O(N²)-feedback логики нет; acceptance-скрипт только читает (`FileAccess.get_file_as_string`) и preload'ит research-константы, записей в файловую систему нет; `extends SceneTree` — домовый стандарт |
| R8. Честность чекпойнт-дока | **PASS** | заголовок и статус — CANDIDATE (`2026-08-23_ECO_EVO7_FFF0_R1_RU.md::1`), прямое «не претендует на canonical acceptance до независимого review/verification» `::69-74`; все приводимые числа/хэши совпали с фактическим прогоном дословно; раздел «Что этот checkpoint НЕ делает» корректно ограничивает объём доказанного |

## Находки

### BLOCKER

Нет.

### MAJOR

Нет.

### MINOR

1. **MINOR-1 — дублирование проверок в M3 завышает счётчик assertions.**
   `tests/research/ecology/eco_evo7_fff0_contract_mapping_acceptance.gd::68` — `check_bounds_keys(expected)` вызывается **внутри** цикла по 8 тритам, поэтому одни и те же 8 проверок `BOUNDS.has(...)` выполняются 8 раз (`::73-75`): 64 из 168 assertions (~38%) — повторы. Гарантию это не ослабляет (каждый уникальный факт проверен), но метрика «168 assertions» частично раздута, а перенос проверки одной строкой вне цикла убрал бы шум. Также имя `check_bounds_keys` без префикса `_` выбивается из стиля остальных хелперов файла.
2. **MINOR-2 — неточная атрибуция параметров инъекции в аудит-доке.**
   `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md::91`: параметры `canopy_overlap`/`local_density` приписаны CAL1-C (`plant_spatial_crown_root_competition_v1`), хотя в коде это сигнатура `create_context(canopy_overlap, local_density)` CAL1-B — `plant_relative_vertical_light_competition_v1.gd::11-20`; CAL1-C же получает от вызывающего кода traits/profile (`plant_spatial_crown_root_competition_v1.gd::12,41-44`). Суть тезиса («caller-supplied давление — естественная точка инъекции cell-полей») верна, но ссылка ведёт не к тому носителю; для FFF3 это риск дезориентации. Рекомендуется поправить формулировку отдельной doc-правкой.

### NOTE

3. **NOTE-3 — язык цитируемого символа не указан.** `ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md::73`: `evo5_rule_compiler_v1 :: WHEN_KEYS` — это Python-модуль `scripts/research/ecology/evo5_rule_compiler_v1.py::5-8` (множество ключей совпадает с цитатой дословно), тогда как остальная таблица §6 описывает GDScript-носители. Стоило бы пометить `.py`.
4. **NOTE-4 — второй presentation-knob не назван.** Помимо `foliage_fraction` (упомянут в доке `::41`), в коде есть визуальный параметр `foliage_density` (`evo4_bridge_presentation_v1.gd::168`, влияет на количество мутовок/листьев в презентации). Он тоже presentation-side и не heritable, поэтому главный gap-вывод FFF0-A не меняется; но раз док фиксирует «визуальные knobs», стоило назвать оба во избежание путаницы с будущим heritable-полем `foliage_density` (§9).
5. **NOTE-5 — EVO6-WATER цифры не воспроизведены ревьюером.** Блок «Регрессия EVO6-WATER (G14)» (`2026-08-23_ECO_EVO7_FFF0_R1_RU.md::43-60`) принят по доверию к неизменности кода: дифф не трогает ни один EVO6-файл, а сам раннер в мой обязательный re-run скоуп не входит. Противоречий не обнаружено, но формально эти числа мной не воспроизведены.
6. **NOTE-6 — рабочее дерево замусорено untracked-артефактами.** `git status --porcelain` показывает ~200 untracked `.uid` sidecar-файлов и `scripts/research/ecology/__pycache__/`. Staged-изменений нет, к коммиту `6b56c82a` они не относятся; но их стоит либо закоммитить по политике репозитория, либо покрыть `.gitignore`.
7. **NOTE-7 — часть проверок M1/M4/M6/M9 — строковые source-gate.** Проверки вида «исходник содержит подстроку» (`acceptance::42-43,80-86,99-102,136-140`) фиксируют существование поверхности/маркера, а не поведение; например, проверка комментария «No second mutation path» (`::101`) сама по себе не поймала бы второй путь под другим именем. Для audit-fixation FFF0 (по образцу source-gate PH0) это приемлемо; поведенческое ядро (M2-списки, M5-FIELD_NAMES, M8-runtime) независимо и надёжно.

## Заявление о независимости

Ревью выполнено свежей изолированной ролью REVIEWER: implementer данной работы в роли ревьюера не участвовал, переписка с ним отсутствовала. Все проверки выполнены лично ревьюером на exact head `6b56c82ab8a2d672e3c48b8bf5a8becb5f8a841f` в worktree `C:\distributed-world-simulator\worktrees\eco-water-r1` (ветка `feature/eco-evo7-fff-r1`): факты сверены чтением исходников (kernel, genome, traits, environment sample, bridge, fitness, resource model, competition surfaces, rule compiler, growth graph, coupled development, render pipeline), раннер `RUN_ECO_EVO7_FFF0_TESTS.ps1` запущен самостоятельно, его вывод приведён выше без сокращений. Единственный созданный файл — настоящий отчёт; существующие файлы не изменялись, commit/push не выполнялись.
