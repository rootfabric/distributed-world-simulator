# ECO.EVO7 FFF5 — Soil/Litter Memory R1 — независимое финальное ревью (FFF5 FINAL REVIEW)

**Роль:** изолированный свежий REVIEWER (не участвовал в реализации).
**Дата ревью:** 2026-08-23.
**Объём:** commit `5b2ae706` (диф `3c3c6a6e..5b2ae706`, 9 файлов), спецификация `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§10, §17 Experiment D, §19 FFF5).

---

## Вердикт

# PASS

Стадия FFF5 Soil/Litter Memory R1 реализована по контракту, гейт этапа (Experiment D causality: «растение меняет участок → на изменённом участке иначе растёт следующее поколение») выполнен и подтверждён собственным независимым прогоном ревьюера. Все пункты чеклиста R1–R8 подтверждены по исходникам; документация честна, включая раскрытие двух отброшенных при калибровке гейтов. Блокирующих и крупных находок нет.

---

## Проверенный HEAD

- `git rev-parse HEAD` = `5b2ae7065357263890d90c8c4970903d3e18ef35` — **совпадает с требуемым точно**.
- Индекс чистый (`git diff --cached` пуст). В рабочей копии присутствуют только нетрекаемые артефакты (`*.gd.uid`, `__pycache__/`) — в коммит не входят, на ревью не влияют (см. Находки, NOTE-5).
- Диф `3c3c6a6e..5b2ae706` содержит ровно 9 заявленных файлов (1613 вставок / 18 удалений), посторонних правок нет:
  - MODIFIED: `scripts/research/ecology/plant_environment_effect_v1.gd`, `scripts/research/ecology/soil_water_field_v1.gd`, `tests/research/ecology/eco_evo7_fff4_water_feedback_acceptance.gd`, `tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd`;
  - NEW: `scripts/research/ecology/soil_organic_field_v1.gd`, `scripts/research/ecology/evo7_litter_feedback_bridge_v1.gd`, `tests/research/ecology/eco_evo7_fff5_soil_memory_acceptance.gd`, `RUN_ECO_EVO7_FFF5_TESTS.ps1`, `docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md`.

---

## Фактические числа прогонов (прогоно́вано самим ревьюером на проверенном HEAD)

### RUN_ECO_EVO7_FFF5_TESTS.ps1 — терминальная строка: `ECO.EVO7 FFF5 Soil Memory candidate: PASS`

| Набор | Факт | Ожидалось | Совпадение |
|---|---|---|---|
| FFF5 soil/litter memory | **PASS (91)** | 91 | да |
| FFF4 water feedback | **PASS (101)**, `result_hash=0b4c95442253b2df` | 101, 0b4c9544… | да |
| FFF3 light feedback | **PASS (51)**, `result_hash=cd30fcbfeb294e19` | 51 | да |
| FFF2 morphology evolution | **PASS (56)** | 56 | да |
| FFF1 functional phenotype | **PASS (110)** | 110 | да |
| FFF0 contract mapping | **PASS (112)** | 112 | да |
| P1B-S1 mutation lineage | **PASS (5834)** | 5834 | да |
| PH2 coupled development | **PASS (107)** | 107 | да |
| P1A-S1 environment baseline | **PASS (109)**, `environment_hash=b862c4fc529b5fd8…` | 109, b862c4fc… | да |
| P1A-S2 single-plant resource | **PASS (235)** | 235 | да |
| P1C-S4 aggregate contract | **PASS (15)** | 15 | да |
| PH0 development trait contract | **PASS (63)**, `development_traits_hash=9d812950f421c261…` | 63, 9d812950… | да |

Дополнительно: FFF5-мост напечатал `bridge result_hash=304d6da59e52c8e5` — бит-идентично чекпоинту (`docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md::77`). Exit code раннера — 0.

### RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline — **PASS**

- Эволюция: `ECO.EVO6-WATER result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e`.
- Визуальный обсерваторий: `ECO.EVO6-WATER-VIS … result_hash=7010e30707613e2837c45c26e7b516547fc5e35ad88997f93bc62660efecaa6e` — **хэши идентичны** в обоих прогонах, ожидаемое значение совпадает посимвольно. Регрессия EVO6-WATER зелёная: водная выборка не задета изменениями FFF5.

---

## Чеклист R1–R8

### R1. Контракт эффектов: активация litter_input_ppm — **ПОДТВЕРЖДЕНО**

- `litter_input_ppm: int = 0` добавлен **дефолтным замыкающим аргументом**: `scripts/research/ecology/plant_environment_effect_v1.gd::34`; кламп `maxi(int(litter_input_ppm),0)`: `::45`; запись поля: `::55`. Для вызовов без litter-аргумента запись и `effect_hash` бит-идентичны прежним (значение канала 0 == прежний хардкод).
- Каналы: litter переведён INACTIVE→ACTIVE: `plant_environment_effect_v1.gd::18-19`.
- **Все прежние продакшн-вызовы передают litter не передают** (проверен каждый call-site `Effect.create`): `understory_light_field_v1.gd::133-135` (5 позиционных), `soil_water_field_v1.gd::304-308` (7 позиционных); FFF3-тест: `eco_evo7_fff3_light_feedback_acceptance.gd::40,51-52`; FFF4-тест: `eco_evo7_fff4_water_feedback_acceptance.gd::91,96,104-105` — ни один не передаёт 8-й аргумент.
- `soil_binding_ppm` остаётся зарезервированным нулём и **энфорсится**: хардкод 0 в записи `plant_environment_effect_v1.gd::56`; `validate()` отвергает ненулевое значение кодом `ECO_EFFECT_INACTIVE_CHANNEL_NONZERO`: `::82-84` (INACTIVE = только `soil_binding_ppm`).
- Эмпирическое доказательство нейтральности: FFF4 воспроизвёл `result_hash=0b4c95442253b2df` на новом HEAD (см. прогоны) — контрактное изменение прозрачно для FFF3/FFF4.
- Тестовое покрытие: `tests/research/ecology/eco_evo7_fff5_soil_memory_acceptance.gd::102-118` (активный канал, зарезервированный soil_binding, ненулевой litter+валидация, отказ negative litter, отказ nonzero soil_binding, дефолт сохраняет ноль для старых вызовов `::113-114`, порядко-инвариантный combined hash `::117-118`).

### R2. Связка водного поля: opt-in и pristine-нейтральность — **ПОДТВЕРЖДЕНО**

- Опциональный вход `organic_map` (cell→[0, ORGANIC_CAPACITY]): документация контракта `soil_water_field_v1.gd::92-95`; fail-closed валидация типа и диапазона с отдельными кодами ошибок: `::124-129` (`ECO_WATER_FIELD_INPUTS_ORGANIC_MAP_TYPE`, `ECO_WATER_FIELD_INPUTS_ORGANIC_RANGE`).
- Отсутствие карты → путь бит-идентичен прежнему: `organic_map = field_inputs.get("organic_map", {})`, флаг связи: `soil_water_field_v1.gd::166-168`; при отсутствии флага `evaporation := unscaled_evaporation`, где `unscaled_evaporation` считается тем же выражением, что прежняя единственная строка (`::212-213`). Uptake-ветка не тронута (тест: «uptake is untouched» `eco_evo7_fff5_soil_memory_acceptance.gd::261`).
- При наличии карты: обязательное покрытие занятых ячеек и повторная проверка диапазона per-cell внутри `compute()` (fail-closed, defense in depth): `soil_water_field_v1.gd::216-221`; масштабирование `evaporation = clampf(unscaled / retention_multiplier(organic), 0, unscaled)` — никогда не ниже нуля и не выше несмасштабированного: `::222-226`. Пер-ячеечные `organic_input/evaporation_retention` появляются только при активной связи: `::266-268` области вывода ячейки (см. диф, блок после `"plant_count"`).
- Хэш: дополнительные токены — ТОЛЬКО при `organic_coupling` (`soil_water_field_v1.gd::320-329`); заголовок хэша (`::330-334`) и `_plant_uptake_hash` (`::336-347`) не изменились → pristine-формат хэша бит-идентичен. Тесты: явная нулевая карта == pristine по испарению (`eco_evo7_fff5_soil_memory_acceptance.gd::244-245`), отсутствие карты = `organic_coupling=false` и нет пер-ячеечного состояния (`::246`).
- Механизм stash round-trip понятен из кода и корректен; FFF4-acceptance по-прежнему ассертит собственную детерминированность result-hash: `eco_evo7_fff4_water_feedback_acceptance.gd::280` (replay) и `::282` (чувствительность к seed). Значение `0b4c95442253b2df` воспроизведено ревьюером на HEAD (см. таблицу прогонов); вторая половина round-trip (старые версии файлов) опирается на запись имплементатора — см. NOTE-3.
- FFF4-мост не передаёт `organic_map` ни в одном вызове (`evo7_water_feedback_bridge_v1.gd::93,169-189,217,236-239,331`) — регрессионный путь чисто pristine.

### R3. Почвенное органическое поле — **ПОДТВЕРЖДЕНО**

- Каноническая identity-sorted обработка: сортировка записей `soil_organic_field_v1.gd::139-140`; депозиты накапливаются целыми числами в отсортированном порядке (`::149-166`) — суммы точны, порядок входа не влияет.
- Deposit → texture decay → clamp: `after_deposit = before + litter_share` (`::193-194`); `decay_factor = 1 − decay_rate·texture_mult` с мультипликаторами **sand 1.3 / loam 1.0 / clay 0.75**: `::62`, `::195`; кламп `[0, ORGANIC_CAPACITY]`: `::196`. Точные значения факторов проверены тестом (0.94 clay / 0.896 sand): `eco_evo7_fff5_soil_memory_acceptance.gd::190-192`; направление «clay > sand» — `::190`.
- Порядко-инвариантные хэши: `_organic_field_hash` по sorted cell ids: `soil_organic_field_v1.gd::292-308`; `_plant_litter_hash` по sorted identities: `::310-319`. G12-перестановки и реверс в тесте: `eco_evo7_fff5_soil_memory_acceptance.gd::148-166`.
- Carryover-карта: `initial_organic` поддержан; tracked cells = занятые + carry-over-only; текстуры обязаны покрывать все; отсутствие покрытия занятой ячейки — fail-closed: `soil_organic_field_v1.gd::144-145,162-164,170-182,189-190`. Накопление через carryover в тесте: `eco_evo7_fff5_soil_memory_acceptance.gd::168-177`.
- Fail-closed матрица (пустой набор, дубликаты identity `::133-134`, отрицательный litter, ячейка без текстуры, неизвестная текстура, пустой fixture id, decay_rate вне [0,1], carryover с дыркой, значение выше capacity): код `soil_organic_field_v1.gd::77-112,124-136,154-157`; тесты `eco_evo7_fff5_soil_memory_acceptance.gd::203-213`.
- `retention_multiplier(o) = 1 + 0.35·clamp01(o)` (`RETENTION_PER_ORGANIC = 0.35`): `soil_organic_field_v1.gd::52,120-121`; точная математика в тесте `::200`.
- Нет RNG, нет SceneTree: модуль `extends RefCounted`, только static-функции; source-gate тест запрещает randf/randi(/randomize/get_tree/node/camera: `eco_evo7_fff5_soil_memory_acceptance.gd::324-330`.

### R4. Experiment D — **ПОДТВЕРЖДЕНО**

- Фаза 1 (legacy build, органика от реального `litter_flux_ppm` растений): `_run_legacy_phase` 10 поколений с feedback ON: `evo7_litter_feedback_bridge_v1.gd::238-260`; litter-записи строятся из фенотипа (`::640-650`, поле `litter_flux_ppm` берётся из FunctionalPhenotype `::611`), органическое поле обновляется каждый цикл (`::347-356`).
- Фаза 2 («растения удаляются») + фаза 3: legacy-популяция отбрасывается; два свежих пула стартуют заново: пул A с `legacy["final_organic_map"]`, пул B с `{}` (pristine): `evo7_litter_feedback_bridge_v1.gd::111-120`. Соответствует §17-D п.3 («исходные растения удаляются»).
- Идентичность пулов by construction: один и тот же объект `ancestor` передаётся в оба прогона; каждая позиция получает глубокую копию бандла (`::311-318`); одна формула мутационного потока `"EVO7-LITTER|seed|gen|parent|off"` с индексными seed'ами (`::429`), одинаковые позиции/fixture/число поколений. Предусловие ассертом: `seed_pools_identical` по хэшу чексамов поколения 1 (`::124-126,405-406`), тест: `eco_evo7_fff5_soil_memory_acceptance.gd::298`. Единственное различие между прогонами A/B — начальная органическая карта (fair comparison).
- Дивергенция: `populations_differ_modified_vs_pristine` по final population hashes — жёсткий ассерт: `eco_evo7_fff5_soil_memory_acceptance.gd::302`; направление измеряется и гейтится по establishment-компоненте (порог 0.001 при наблюдаемых ≥0.00219): `::306-307`; organic-дельта и modified-pool наследование: `::304-305`; ON/OFF-контрфактикуал: `::303`. Направление влаги публикуется в метриках divergence (`evo7_litter_feedback_bridge_v1.gd::139`), но сознательно не гейтится (см. R5).
- Соответствие спецификации §17 Experiment D (пункты 1–5, `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md::862-870`): рост нескольких cycles ✓ (10), litter/soil legacy ✓, удаление исходных ✓, одинаковый pool на modified/pristine ✓, establishment/divergence различаются ✓. Exit-гейт §19 FFF5 («Experiment D causality PASS», `::958-967`) выполнен.

### R5. Честность fitness-связки и раскрытие отброшенных гейтов — **ПОДТВЕРЖДЕНО**

- Fitness = `net_resource_proxy + ESTABLISHMENT_BONUS·establishment_capacity·cell_organic`: `evo7_litter_feedback_bridge_v1.gd::394-401`; константа `ESTABLISHMENT_BONUS := 0.05` с расчётным обоснованием порядка величин: `::81-83,45-49`; бонус по пост-обновлению органике ячейки («наследуемый потомством участок») — семантика декларирована: `::20-22`, чекпоинт `docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md::15,98`.
- Раскрытие ДВУХ отброшенных гейтов присутствует и соответствует реальности:
  - same-genomes net delta нестабилен по знаку из-за PH2-пластичности (пере-реализация морфологии под изменившейся влагой): калибровка п.1 `docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md::21`; в коде кросс-оценка явно помечена OBSERVABILITY, not a gate, с тем же диагнозом и числами (+2.3e−4 / −1.4e−4 / +4.3e−5): `evo7_litter_feedback_bridge_v1.gd::484-492`;
  - направление средней влаги между пулами смешивается с эволюцией transpiration demand: калибровка п.2 `docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md::22`; ограничение №3: `::96`.
- Проверено, что этих гейтов НЕТ как жёстких ассертов: в `eco_evo7_fff5_soil_memory_acceptance.gd` отсутствуют любые проверки знака `net_balance_same_genomes_modified_minus_pristine` (кросс-оценка гейтится только по `genome_count==50`, `::299`) и знака `moisture_modified_minus_pristine` (метрика вычисляется мостом `::139`, но в тесте не ассертится). Структурно гарантированный факт retention вместо этого ассертится на уровне поля при фиксированных записях: `::257,260` — ровно как задекларировано в коде моста (`::489-492`).
- Пороги с запасом ≥2× к наблюдаемым: константы `eco_evo7_fff5_soil_memory_acceptance.gd::27-34`; сверка с наблюдаемыми (0.161 vs 0.08; 0.0825–0.0835 vs 0.04; 0.00219–0.00246 vs 0.001; 0.2194 vs 0.11) — согласованы; числа в чекпоинте `::40-55` согласуются с константами теста и с моим прогоном.

### R6. Правки межстадийных гардов — **ПОДТВЕРЖДЕНО (объём ровно заявленный)**

- FFF3: ровно одна пара строк — тамозер перенесён `litter_input_ppm=5` → `soil_binding_ppm=5` (+актуализация текста label): диф `tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd::46-47`. Обоснованно: активация litter сделала старый guard недействительным (ненулевой litter теперь легален); прецедент установлен именно так в FFF4 (тогда правился FFF3-тест при активации water-каналов — см. `docs/evidence/2026-08-23_ECO_EVO7_FFF4_FINAL_REVIEW_RU.md::28`).
- FFF4: ровно две пары строк — членство каналов (litter теперь ACTIVE, soil_binding INACTIVE: `eco_evo7_fff4_water_feedback_acceptance.gd::90`) и тамозер `litter=7` → `soil_binding=7` (`::99-100`). Счётчик сохранён: **101 подтверждён моим прогоном**; FFF3 — **51 подтверждён**.
- Оба файла проходят в составе цепочки (см. прогоны); FFF4 продолжает ассертить собственную детерминированность result-hash (`::280`).

### R7. Цепочка раннера — **ПОДТВЕРЖДЕНО**

- `RUN_ECO_EVO7_FFF5_TESTS.ps1::14-27` содержит ровно 12 наборов в порядке: FFF5, FFF4, FFF3, FFF2, FFF1, FFF0, P1B-S1, PH2, P1A-S1, P1A-S2, P1C-S4, PH0 — полный требуемый список.
- Проброс exit-кода: `if ($LASTEXITCODE -ne 0) { throw ... }`: `RUN_ECO_EVO7_FFF5_TESTS.ps1::31`; UID-preflight (import при отсутствии uid-cache): `::10-13`; терминальная строка кандидата: `::38`.

### R8. Честность документации — **ПОДТВЕРЖДЕНО**

- Статус CANDIDATE: `docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md::1`.
- Ограничения присутствуют и полны: нет микробов/сущностей (`::94`), nutrients field отложен — органика влияет ТОЛЬКО на retention+establishment (`::95`, а также design brief «Отвергнуто» `::16`), слабость retention против uptake (`::96`), один сценарий (`::97`), пост-обновление бонуса (`::98`), наследие усечения/шага от FFF4 (`::99`), cross-seed = 3 сидa (`::100`), кросс-оценка observability (`::101`).
- История калибровки раскрывает неудачи (обе итерации с отрицательными/нестабильными дельтами и диагнозами): `::19-23`; правки предыдущих тестов задокументированы со счётчиками: `::25`.
- Наблюдаемые числа согласованы с порогами теста и с независимым прогоном ревьюера (все счётчики и хэши совпали, включая `304d6da59e52c8e5`, `0b4c95442253b2df`, `cd30fcbfeb294e19`, `b862c4fc…`, `9d812950…`, `7010e307…`): `::72-88`.

---

## Находки

Блокирующих (BLOCKER) и крупных (MAJOR) находок нет. Минимальных (MINOR), влияющих на поведение принятых путей, не обнаружено.

- **NOTE-1.** Поле воды теперь всегда добавляет ключ `"organic_coupling"` в возвращаемый словарь даже в pristine-режиме: `scripts/research/ecology/soil_water_field_v1.gd` (строка в блоке сборки `field`, см. диф, строка ~279 новой версии). На хэш не влияет (не входит в токены `::330-334`), потребителей с проверкой точного состава ключей водного поля нет (FFF4 зелёный, 101). Расширение поверхности контракта — принять к сведению.
- **NOTE-2.** Nutrient-ветка §10 (спец.: `moisture retention / nutrient availability / establishment`, `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md::527`; §19 FFF5 `::964`) в R1 отложена. Это осознанное сокращение объёма, честно раскрытое в чекпоинте (`::16,::95`) и в шапке органического поля (`soil_organic_field_v1.gd::33-35`); §10 `::530` прямо разрешает упрощённую первую версию. Отклонение от буквы §19 частичное, задокументированное — на вердикт не влияет.
- **NOTE-3.** Stash round-trip: вторая половина доказательства (прогон FFF4 на ДОизменённых версиях двух файлов, печатавший `0b4c95442253b2df`) опирается на запись имплементатора (`docs/checkpoints/2026-08-23_ECO_EVO7_FFF5_R1_RU.md::70`) — ревьюер не мог её воспроизвести, не модифицируя рабочую копию (запрет роли). Компенсирующая триангуляция: (а) механизм pristine-нейтральности полностью подтверждён чтением диффа (R2); (б) оба исторических хэша — FFF3 `cd30fcbfeb294e19` и FFF4 `0b4c95442253b2df` — воспроизведены ревьюером бит-идентично на новом HEAD. Риск ошибки имплементатора минимален, на вердикт не влияет.
- **NOTE-4.** Косметика: комментарий к `_run_pool` размещён после return предыдущей функции между функциями (`evo7_litter_feedback_bridge_v1.gd::262-264`), смешанный отступ. На исполнение не влияет.
- **NOTE-5.** В рабочей копии присутствуют нетрекаемые артефакты Godot-импорта (`*.gd.uid`, `scripts/research/ecology/__pycache__/`). В коммит не входят, staged-изменений нет; рекомендуется держать их вне индекса (уже так).

---

## Заявление о независимости

Ревью выполнено изолированной свежей ролью REVIEWER, не участвовавшей в проектировании, реализации, калибровке или валидации стадии FFF5. Все выводы чеклиста R1–R8 получены непосредственным чтением исходников, диффа `3c3c6a6e..5b2ae706` и спецификации; доверия документации имплементатора не оказывалось — документы использовались только как объект проверки. Оба прогона доказательств (`RUN_ECO_EVO7_FFF5_TESTS.ps1`, `RUN_ECO_EVO6_WATER_SELECTION.ps1 -SkipBaseline`) выполнены лично ревьюером на проверенном HEAD `5b2ae7065357263890d90c8c4970903d3e18ef35` с чистым индексом; приведённые числа взяты из фактического вывода прогонов. Ролью запрещено коммитить, пушить и менять существующие файлы; создан только настоящий отчёт. Конфликтов интересов не имеется.
