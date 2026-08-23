# ECO.EVO7 FFF6 — Closed Community Evolution / Succession Lab R1 — Финальное независимое ревью (RU)

**Роль:** изолированный независимый REVIEWER (свежая роль, не участвовал в реализации)
**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1`, worktree `C:\distributed-world-simulator\worktrees\eco-water-r1`
**Цель ревью:** коммит `d129b0ba3fff1ae303216a47628d2a4a7f49a904` (диф `504b9e28..d129b0ba`)
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` §14–§19; дизайн `docs/plans/ECO_EVO7_FFF6_SUCCESSION_LAB_DESIGN_RU.md`

---

## Вердикт

# **PASS**

Все проверки чеклиста R1–R8 подтверждены по первоисточникам; все три прогона доказательной базы воспроизведены рецензентом самостоятельно на точном HEAD с числами, совпавшими с заявленными. Блокирующих и мажорных находок нет; зафиксированы 1 MINOR-замечание и 7 NOTE.

## Проверенный HEAD

```
git rev-parse HEAD → d129b0ba3fff1ae303216a47628d2a4a7f49a904   — СОВПАДАЕТ с целевым
родитель d129b0ba  → 221713672edca6647e3ba4a86a54ab01b00b9bf1   (docs-only «passport R3 refresh»)
git status --porcelain: изменённых отслеживаемых файлов НЕТ, в индексе пусто;
незакоммиченное — только untracked *.uid (ожидаемо, артефакты Godot-импорта).
```

Замечание по базе диффа: `git diff 504b9e28..d129b0ba` содержит **8-й файл** `docs/checkpoints/2026-08-23_ECO_PASSPORT_R3_REFRESH_RU.md` (+30 строк) — он попал в диапазон через промежуточный docs-only коммит `22171367`, сам целевой коммит `d129b0ba` содержит ровно 7 заявленных файлов. К ревью кода это не относится (см. NOTE-1).

Содержимое коммита проверено чтением файлов рабочего дерева на этом HEAD (дерево чистое, содержимое == коммит) и дифом:

| Файл | Статус | Объём |
|---|---|---|
| `scripts/research/ecology/understory_light_field_v1.gd` | MODIFIED | +40/-1 |
| `scripts/research/ecology/evo7_succession_simulation_v1.gd` | NEW | 1082 строки |
| `scenes/labs/ecology/eco_evo7_form_function_feedback_lab.tscn` | NEW | 6 строк |
| `scripts/labs/ecology/eco_evo7_form_function_feedback_lab.gd` | NEW | 952 строки |
| `tests/research/ecology/eco_evo7_fff6_succession_lab_acceptance.gd` | NEW | 325 строк |
| `RUN_ECO_EVO7_FFF6_TESTS.ps1` | NEW | 39 строк |
| `docs/checkpoints/2026-08-23_ECO_EVO7_FFF6_R1_RU.md` | NEW | 129 строк |

## Фактические числа прогонов

Все прогоны выполнены рецензентом лично, на Windows, на точном HEAD, последовательно.

### 1. Полная цепочка: `powershell -Command ".\RUN_ECO_EVO7_FFF6_TESTS.ps1"` — exit code 0, терминальная строка `ECO.EVO7 FFF6 Succession Lab candidate: PASS`

```
FFF6 succession lab acceptance        PASS (171 assertions)   result_hash=52995cf4bcd03578
FFF5 soil/litter memory acceptance    PASS (91 assertions)    bridge result_hash=304d6da59e52c8e5
FFF4 water feedback acceptance        PASS (101 assertions)   bridge result_hash=0b4c95442253b2df
FFF3 light feedback chain             PASS (51 assertions)    bridge result_hash=cd30fcbfeb294e19  ← БИТ-ИДЕНТИЧЕН после bucket-pruning
FFF2 morphology evolution chain       PASS (56 assertions)
FFF1 functional phenotype chain       PASS (110 assertions)
FFF0 contract mapping chain           PASS (112 assertions)
P1B-S1 mutation lineage kernel        PASS (5834 assertions)
PH2 coupled development               PASS (107 assertions)
P1A-S1 parent environment regression  PASS (109 assertions)   environment_hash=b862c4fc529b5fd8…51af7 ✓
P1A-S2 parent resource regression     PASS (235 assertions)   simulation_hash=618ec5c188fcb8b7…
P1C-S4 aggregate contract             PASS (15 assertions)
PH0 development trait contract        PASS (63 assertions)    development_traits_hash=9d812950f421c261…76dea ✓
```

Все счётчики и хэши совпали с ожидаемыми из задания и с чекпоинт-документом (171/91/101/51/56/110/112/5834/107/109/235/15/63; P1A-S1 hash `b862c4fc…`; PH0 traits hash `9d812950…`). FFF3 `result_hash=cd30fcbfeb294e19` — эмпирическое подтверждение бит-идентичности light-поля после pruning-апгрейда (совпадает с зафиксированным до правки базовым прогоном).

### 2. Headless-гейт сцены (`EVO7_FFF6_LAB_AUTOCAP=1`) — exit code 0

```
ECO.EVO7-FFF6-VIS: READY zones=6 plants=150 result_hash=52995cf4bcd03578f6c0df98c0091d2cea0985bc5eb2a6706ea5a78ffedbe436
ECO.EVO7-FFF6-VIS: PASS rendered=150 zones_ok=true onoff=true geom_pairs=4 gap_delta=0.5657 stability_pin_max=0.080 replay=true result_hash=52995cf4bcd03578
EXITCODE=0
```

Совпадение `result_hash` в ТРЁХ независимых каналах — acceptance-скрипт (`run_all`), лаба (инкрементальный context-путь) и headless-сцена — плюс `replay=true` внутри гейта: детерминированность и эквивалентность путей исполнения доказаны фактически. Числа совпадают с чекпоинт-документом (geom_pairs=4 ≥ 3, gap_delta 0.5657 > 0.30, pin_max 0.080).

### 3. `powershell -Command ".\RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline"` — exit code 0, PASS

```
Python rule pack + numeric predicates: ALL OK / PASS
water fitness math:                    PASS (5 assertions)
water-driven evolution causality:      PASS (24 assertions)  result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e
visual observatory adapter:            READY plants=72 result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e
                                       PASS plants=72 pref_span=0.657 root_span=0.700
```

`result_hash=7010e307…aa6e` **идентичен** в evolution-канале и visual observatory — EVO6-WATER регрессия не задета новым кодом.

## Чеклист R1–R8

### R1. Корректность bucket-pruning в `understory_light_field_v1.gd` — ✅ ПОДТВЕРЖДЕНО

- **Пропускаются только доказуемо нулевые пары.** Внутри диапазона сканирования фильтры пар идентичны старому all-pairs циклу: self (строка 117), `height_source <= height_target` (119), `radius <= 0` (122), `distance >= radius` (127). Вес `w = clamp01(1 - dist/r)` строго положителен только при `dist < radius_source <= max_crown_radius`; пропускаемая ячейкой пара имеет `dist >= radius` ⇒ слагаемое было бы **ровно 0.0**.
- **Диапазон ячеек покрывает максимальный радиус короны.** `prune_range = ceili(max_crown_radius / CELL_SIZE_M) + 1` (строка 92); максимум считается по ВСЕМ validated-записям, включая статичную крону (89–91). Математически: если `|dx_coord| < r <= max_r`, то `|floor(xs/cell) - floor(xt/cell)| <= ceil(max_r/cell)` — запас +1 делает покрытие консервативным. Индексация источников и цель используют один и тот же `cell_identity_for`/`floori(x/CELL_SIZE_M)` (64, 96, 105–106).
- **Канонический порядок сумм сохранён.** Каждый источник лежит ровно в одном бакете; ключи ячеек `(dx,dz)` попарно различны ⇒ дубликатов нет; `candidate_indices.sort()` (113) даёт возрастание индекса validated-массива, который отсортирован по identity (80–81) — это в точности порядок старого `for source in validated`. Пропущенные слагаемые — точные нули: для неотрицательных аккумуляторов `x + 0.0 == x` побайтно в IEEE754, поэтому `snappedf(overlap,1e-9)` (130), transmittance (131), understory (132), `field_hash`/`plant_light_hash` (180–202) неизменны. Эмпирика: FFF3 `cd30fcbfeb294e19`, FFF4 `0b4c95442253b2df`, FFF5 `304d6da59e52c8e5` — без изменений.
- **RNG не введён:** grep по файлу — `randf|randi|randomize|RandomNumberGenerator|shuffle` — пусто.
- Референс: `scripts/research/ecology/understory_light_field_v1.gd::83-113` (новый блок), `::114-132` (неизменная арифметика).

### R2. Граница визуальной истинности (G15) — ✅ ПОДТВЕРЖДЕНО

- Лабовый узел — read-only наблюдатель: эволюция исполняется ТОЛЬКО модулем `Simulation.create_context/context_step/context_finish` (`eco_evo7_form_function_feedback_lab.gd::87, 95-113`); узел не содержит ни `LineageExtension`, ни `EnvSample`, ни второй mutation/environment authority (grep чист; source-gate теста `eco_evo7_fff6_succession_lab_acceptance.gd::291-298`).
- Визуал материализуется тем же путем, что кормил поля: `Simulation.realize_entry → RenderDescription.build → Representation.build → MultiscaleMaterializer.build` (`lab::322-365`; хелпер `evo7_succession_simulation_v1.gd::921-936`).
- Записи в genome/phenotype/environment authority отсутствуют: `_result` только читается; `zone_parameters()` возвращает копию (`simulation::316-319`); кэш растений — новые словари (`lab::443-461`).
- Экологическая математика живёт в non-node модуле (свет/вода/органика/скоринг/воспроизводство: `simulation::606-758`); в узле нет переизобретений. Единственный вызов `LightField.compute` в узле — оверлей-1 пересчитывает свет по каноническому модулю поверх отображаемых записей (`lab::556-582`) — см. NOTE-4.
- Презентационные настройки не входят ни в один хэш: hash-панель строится исключительно из полей `_result` (`lab::753-778`); C/оверлеи/X/tier/DISPLAY_SCALE их не касаются; автокап дополнительно доказывает replay (`lab::935-936`).

### R3. Каузальность сукцессии (Experiment A) — ✅ ПОДТВЕРЖДЕНО

- CANOPY_GAP входно идентичен UNDER_CANOPY кроме `canopy_removed_at_generation`: -1 vs 8 при одинаковых texture/moisture/sunlight/nutrients/flood/control_point (`simulation::123-132`); ассерты предусловий `acceptance::158-165`.
- Детерминированное удаление в середине прогона: `canopy_active := has_canopy and not (removed_at > 0 and generation > removed_at)` (`simulation::607`); pre/post-свет фиксируется на поколениях 8/9 (`simulation::625-628`); удаление — операция над research-списком geometry-records (`_with_canopy`, `simulation::879-884`).
- Наблюдаемость с полями: восстановление света ассертится с запасами `pre>0 ∧ pre<0.15`, `post>under+0.30`, `post>pre*3` (`acceptance::171-175`); согласованность траектории с границей удаления ±1e-9 (181-182); восстановление net-баланса `>0.02` под собственный свет ячейки (185-186); расхождение потомков GAP vs UNDER (189-190); восстановление света и в OFF-контрфактуальном режиме (193-196). Фактические числа прогона: свет GAP 0.0647→0.6294, net −0.039→+0.014, delta vs UNDER +0.5657 — каузальная цепочка наблюдаема.

### R4. Нет захардкоженных архетипов (§18) — ✅ ПОДТВЕРЖДЕНО

- Кластеризация — постфактум-диагностика: жадная пороговая по `GEOMETRY_THRESHOLDS` в каноническом порядке identity (`simulation::426-451`); результат — только число в отчёте и в result_hash, на скоринг/воспроизводство не влияет (единственные использования: `simulation::808`, `1071`; сравнение зон `823-841`).
- Ветвей вида `if species_class == TREE` нет нигде в новом коде (grep `species_class|archetype|"TREE"|"BUSH"|"GRASS"` по лабе и модулю — пусто; слово "archetype" в модуле отсутствует — ассерт `acceptance::286`).
- Имена зон гейтят только замороженные параметры среды (fixture-каналы), не морфологию — разрешённый дизайн-приём (§17 Experiment B: среда удорожает стратегию, а не запрещает её).

### R5. Стабильность + anti-runaway (G11 preview) — ✅ ПОДТВЕРЖДЕНО

- `STABILITY_GENERATIONS = 108 >= 100` (`simulation::78`); `run_zone_stability` считает один zone-режим ON полный горизонт и возвращает вердикты finite/bounds/pinning/trajectory (`simulation::261-313`).
- Bound-pinning измерен по всем 8 evolvable-осям LineageExtension против `Traits.BOUNDS`/`ExtensionTraits.BOUNDS` с порогом «pinned» = ≥99% диапазона вверх от нижней границы (`BOUND_PINNING_FRACTION=0.99`, `simulation::93, 393-410`).
- Ассерты теста: `completed==108 ∧ >=100`, конечность средств, средства в [0,1], конечность траектории, «ни одна ось не упёрта всей популяцией» (<1.0), размер карты пиннинга == 8, доли sane (`acceptance::228-249`). Факт: pin_max = 0.080 (обе зоны stability). Автокап повторяет те же проверки (`lab::926-933`). Замечание о мягкости порога <1.0 — NOTE-2.

### R6. Управление (§15.1) — ✅ ПОДТВЕРЖДЕНО

- Все клавиши реализованы: SPACE initial/final, F feedback ON/OFF, C нейтральный материал, 1 свет / 2 влага / 3 тень / 4 транспирация / 5 fitness, R deterministic reset (+X debug-удаление кроны, документировано как презентационный контрфактикум вне минимума §15.1): `lab::794-827`, таблица управления в чекпоинт-доке (строки 32-44).
- C-режим: ОДИН общий экземпляр `StandardMaterial3D` применяется ко всем MeshInstance3D/MultiMeshInstance3D всех растений (`_neutral_material`, `lab::465-472, 838-845`) — цветовые кодировки исчезают, остаётся геометрия; на экран выводится GeometryReadout со средними 7 полей FEATURE_FIELDS по зонам и попарными geometry-distinct флагами с критерием «>=3 satisfies G5» (`lab::723-750`).
- Хэш-панель доказывает replay: R запоминает полную панель до сброса и сравнивает после перезапуска, индикатор REPLAY MATCH/MISMATCH (`lab::659-660, 817-821`).
- HUD показывает весь перечень §15.1 (mean height/crown/LAI/root depth+spread/water preference/shade/transpiration/fitness, unique genomes, cluster count, bound-pinning): `lab::664-720`.

### R7. Качество теста — ✅ ПОДТВЕРЖДЕНО (171 ассерт, воспроизведено)

- Шесть зон: детерминированная инициализация — параметры frozen, [0,1]-диапазоны, попарно различные checksums базовых сред, один ancestor-популяционный хэш, один generation-one candidate pool между зонами И режимами G4 (`acceptance::42-128`).
- ON/OFF дивергенция: агрегат `on_off_divergent_zones == 6` И явное попарное неравенство `final_population_hash` в каждой зоне (`acceptance::138-143`) — двойное, не тавтология.
- CANOPY_GAP restoration: три независимых световых ассерта с полями + согласованность границы траектории + net-recovery + расхождение GAP/UNDER + OFF-режим (`acceptance::168-196`) — при поломке удаления (например, крона не снимается или снимается не там) хотя бы один ассерт падает: pre<0.15 исключает «канопа не затенялась», post>pre*3 и post>under+0.30 исключают «не восстановилась».
- Geometry-distinct zone pairs >= 3 на фиксированном seed 20260823: факт geom_pairs=4; дополнительно baseline-отделение >=1 (`acceptance::131-135`); семантика компаратора покрыта юнит-ассертами threshold-boundary (`270-278`).
- Stability: 2 зоны × 108 (`acceptance::227-249`).
- Replay: run_all дважды бит-идентичен; инкрементальный context-путь бит-идентичен run_all; seed-sensitivity SEED+1 меняет исход (`acceptance::204-223`).
- Fail-closed матрица: минимальные поколения, пустой/частичный context, неизвестная зона, невалидная среда realize_entry, пустые кластеризация/пиннинг, boundary компаратора (`acceptance::253-278`).
- Source boundaries: текстовые grep-гейты единственной lineage authority/RNG/archetype-лексики (`acceptance::282-301`) — сами по себе грубые (NOTE-3), но здесь независимо подтверждены ручным анализом источников.
- Тавтологий, маскирующих поломку сукцессионной каузальности, не найдено: каузальные ассерты опираются на значения из разных вычислительных веток (траектория света, net-баланс под собственную среду, популяционные хэши).

### R8. Честность документации — ✅ ПОДТВЕРЖДЕНО

- Чекпоинт помечен **CANDIDATE** с явным «самопринятия нет» (`docs/checkpoints/2026-08-23_ECO_EVO7_FFF6_R1_RU.md::7`).
- Все шесть открытых вопросов дизайна §12 разрешены явно (чекпоинт-док §«Разрешение открытых вопросов дизайна», пункты 1–6 ↔ `design::159-166`): texture-канал без расширения v1; scheduled removal + debug-X; инкрементальный драйвер вместо потоков с байт-идентичностью; crown_density без презентационного масштабирования (ограничение); stability в модуле/acceptance, не в интерактивной лабе; greedy-кластеризация как label.
- История калибровки честна, включая два снятых нестабильных ассерт-кандидата (направление leaf_economics_proxy GAP-vs-UNDER — знак против наивного ожидания; разница корней UNDER−GAP — знак плавает) с фактическими числами (чекпоинт-док §«История калибровки», п.1–5).
- Ограничения декларированы: визуальный exact-Windows GUI-прогон отложен (headless-autocap вместо скриншота), forest-scale N≥1000 — FFF7, крона вне water/litter records, effect-records только на final generation, минимальный запас порога G5 (4 при >=3), слабая информативность кластерной метрики, DISPLAY_SCALE вне хэшей (чекпоинт-док §«Осознанные ограничения R1», п.1–8).
- Overclaiming не обнаружен: формулировки уровня «succession-loop … наблюдаем», а не «сукцессия доказана»; направление отбора опирается на структурно гарантированные факты (свет/net/дивергенция).

## Находки

**BLOCKER:** нет.

**MAJOR:** нет.

**MINOR:**

- **MINOR-1** — `RUN_ECO_EVO7_FFF6_TESTS.ps1::14-28`: цепочка не включает FFF6-зависимость EVO6-WATER (`RUN_ECO_EVO6_WATER_SELECTION.ps1`), хотя чекпоинт-док приводит её как focused evidence (строка 110). Регрессия зелёная (проверено настоящим ревью отдельно), но автоматическим стражем она не является — следующий этап может забыть её запустить вручную. Не блокирует: результат воспроизведён и идентичен.

**NOTE:**

- **NOTE-1 (environment)** — база диффа задания `504b9e28..d129b0ba` содержит 8-й файл `docs/checkpoints/2026-08-23_ECO_PASSPORT_R3_REFRESH_RU.md` из промежуточного docs-only коммита `22171367`; сам целевой коммит — ровно 7 файлов. Расхождение задания, не кода.
- **NOTE-2** — `tests/.../eco_evo7_fff6_succession_lab_acceptance.gd::239-241`: порог anti-runaway ассерте «ни одна ось не упёрта всей популяцией» (<1.0) существенно мягче наблюдаемых 0.08; заголовок честно называет это G11-preview, но к G11 стоит заранее перекалибровать потолок (например, <=0.25) на cross-seed статистике.
- **NOTE-3** — `acceptance::283-301`: source-boundary гейты — текстовые grep по нижнему регистру исходников («randf», «archetype», «envsample»…). Поодиночке слабые (проходят при нерелевантных вхождениях), однако в данном коммите продублированы ручной проверкой ревьюера — риска не несут, повышать строгость желательно постепенно.
- **NOTE-4** — `lab::556-563`: оверлей-1 вызывает `LightField.compute` внутри узла сцены. Это НЕ вторая реализация математики (вызывается канонический модуль поверх read-only отображаемых записей), но формально узел выполняет экологический пересчёт для показа; допустимо, граница G15 не нарушена (хэши панели из `_result`).
- **NOTE-5** — `understory_light_field_v1.gd::92`: при будущем росте радиусов корон относительно CELL_SIZE_M=1.0 площадь сканирования растёт квадратично от prune_range (сложность деградирует к O(N·k²)); корректность не страдает, forest-scale профилирование — заявленный FFF7.
- **NOTE-6 (environment)** — при headless-прогоне сцены в stderr наблюдается шум аддона `breakpoint_mcp` («could not listen on 127.0.0.1:9081»); на гейт и exit code 0 не влияет, к коммиту отношения не имеет.
- **NOTE-7 (environment)** — в рабочем дереве множество untracked `*.uid`-файлов Godot (включая `evo7_succession_simulation_v1.gd.uid`); изменённых отслеживаемых файлов нет — совпадает с ожиданиями задания, вопрос трекинга .uid остаётся политикой репозитория вне этого ревью.

## Заявление о независимости

Рецензент — изолированная свежая роль, не участвовавшая в реализации FFF6 и не связанная с реализатором. Все проверки выполнены самостоятельно на точном HEAD `d129b0ba3fff1ae303216a47628d2a4a7f49a904`: собственное чтение полного диффа и всех семи файлов, собственных сверок со спецификацией (§14.1, §15.1, §16 G4/G5/G6/G7/G11/G12/G15, §17-A, §18, §19 FFF6) и дизайном (§12 открытые вопросы), собственные запуски всех трёх доказательных прогонов (цепочка FFF6, headless-автокап сцены, EVO6-WATER -SkipBaseline) с записью фактически полученных чисел. Журналы реализатора не использовались как доказательство — только как объект сверки claims↔facts (все заявленные числа подтвердились). Изменения существующих файлов, коммиты и push не производились; создан единственный новый файл — настоящий отчёт. Контрольные скрипты миссии (`CONTROL_DEVELOPMENT.ps1 -Drive/-CloseRole`) не запускались, так как контракт роли запрещает любые записи помимо файла отчёта; закрытие роли остаётся за родительской миссией.

---
*Ревьюер: независимая REVIEWER-роль, ECO research stage FFF6. Отчёт подготовлен 2026-08-23.*
