# ECO.EVO7 FFF5 — Soil/Litter Memory R1 — CANDIDATE

**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1` (база `3c3c6a6e`, FFF0–FFF4 в составе)
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§10 litter/soil legacy, §17 Experiment D, §19 FFF5; поддерживающие G10/G12/G13/G14)
**Основание:** FFF0–FFF4; `litter_flux_ppm` уже считался в функциональном фенотипе (FFF1), канал `litter_input_ppm` был зарезервирован нулём в effect-контракте.

## Design brief (pre-build, research MEDIUM)

- **Проблема:** после FFF3/FFF4 среда влияет на растения и растения влияют на среду *внутри поколения*, но между поколениями участок «забывает». Спецификация §10 требует медленной петли: leaf turnover → litter_input → organic matter proxy → замедленное влияние на удержание влаги и приживаемость («растение меняет участок → на изменённом участке иначе растёт следующее поколение»).
- **Выбрано:**
  - `soil_organic_field_v1` — cell-bucketed агрегатор органики по дисциплине водного поля (канонический порядок по identity, snapped floats, fail-closed): `cell += litter_share`, затем затухание `organic *= (1 − decay_rate·texture_mult)` с мультипликаторами **sand 1.3 / loam 1.0 / clay 0.75** (органика копится быстрее всего в глине), кламп `[0, ORGANIC_CAPACITY=1.0]`; опциональная карта `initial_organic` переносит состояние между обновлениями (накопление legacy мостом); конверсия `LITTER_PPM_PER_ORGANIC = 2.5·10⁶` (одиночное растение ~20k ppm даёт ~0.008/обновление).
  - **Retention coupling для водного поля:** статический аксессор `retention_multiplier(o) = 1 + RETENTION_PER_ORGANIC·clamp01(o)`, `RETENTION_PER_ORGANIC = 0.35`. Водное поле принимает карту органики как ОПЦИОНАЛЬНЫЙ вход `organic_map`: испарение ячейки дополнительно масштабируется на `1/multiplier` с клампом `[0, unscaled]` (органика = мульча, вода не уходит ниже нуля и не выше базового испарения). Отсутствие карты = pristine-путь, бит-идентичный прежнему поведению (доказано ниже).
  - `evo7_litter_feedback_bridge_v1` — сообщественный мост по образцу FFF3/FFF4: сетка 5×5, 0.35 м, одно растение на позицию, воспроизводство только через `LineageExtension`, глобальное усечение + копростый шаг `(rank·7) mod 25`; сценарий `loam_legacy` (loam над контрольной точкой wet_lowland; plateau отсеян калибровкой — слишком сухо, медленный сигнал органики тонет в водном стрессе); формула мутационного потока `EVO7-LITTER|seed|gen|parent|off` едина во всех прогонах.
  - **Experiment D (гейт этапа):** фаза 1 — сообщество растёт 10 циклов, накапливая органический legacy; фаза 2 — растения удаляются; фаза 3 — два ИДЕНТИЧНЫХ свежих seed-пула (копии одного ancestor-bundle, одна формула потока) на 8 равных поколений: пул A на изменённой (organic) карте, пул B на pristine (нули). Fitness ON-режима: `net_resource_proxy + ESTABLISHMENT_BONUS·establishment_capacity·cell_organic`, `ESTABLISHMENT_BONUS = 0.05` (при mesic net O(0.01–0.03) и органике O(0.1–0.5) бонус O(0.002–0.012) — того же порядка, что разброс net между морфологиями, т.е. заметно рулит усечением, но не маскирует физиологию). Бонус считается по ПОСЛЕ-обновлению состоянию ячейки — участку, который потомство наследует (декларированная семантика «переданного участка»).
- **Отвергнуто:** гейтинг по знаку same-genomes net-дельты (см. калибровку, п.1 — пластичность PH2 делает знак нестабильным); гейтинг по направлению средней влаги между пулами (п.2 — смешивается с эволюцией спроса); nutrient-ветку §10 — осознанно отложена (нет поля питательности).
- **Риски:** слабый влаговый сигнал retention на фоне uptake в мезической точке (принято: сильная сторона петли — establishment-компонента и накопление органики); вырождение бонуса в «магическую формулу» без аудит-следа (константа задокументирована, компонента публикуется отдельно в метриках пулов); нейтрализация Experiment D при неидентичных пулах (предусловие `seed_pools_identical` проверяется ассертом).

## История калибровки (честно; константы FFF1 не менялись)

1. **Итерация 1 (проектное допущение о монотонности net):** планировалось гейтить «same-genomes net balance под modified-vs-pristine влагой» как структурно неотрицательный (net, казалось, монотонен по влажности: activity растёт, maintenance не зависит). Диагностический прогон на seed 20260824 дал **отрицательную** дельту (−1.35·10⁻⁴; по геномам 28 «+»/22 «−» при глубочайшем корне всего 1.41 м — дело не в root-reach компенсации). **Диагноз:** PH2-пластичность пере-реализует морфологию под изменившейся влагой (`realize` зависит от среды, compile проверяет `environment_checksum`), поэтому «тот же геном» даёт *другое* растение, и знак дельты — эмпирический шум ±2·10⁻⁴. **Решение:** same-genomes кросс-оценка оставлена как observability; гейт перенесён на establishment-компоненту и на полевую проверку retention «те же растения → меньше испарение».
2. **Итерация 2 (смешанная метрика средней влаги):** направление `mean_cell_moisture(modified) − mean_cell_moisture(pristine)` между пулами тоже нестабильно по seed (+0.00112 / −0.00209 / −0.00174): независимо эволюционировавшие пулы имеют разный transpiration demand, и их uptake пересушивает клетки сильнее, чем retention бережёт. **Решение:** сравнение средних влаги между пулами — только наблюдаемость; каузальность retention доказывается на уровне поля при фиксированных записях.
3. **Рабочая калибровка:** базовые константы (`BONUS 0.05`, `LITTER_PPM_PER_ORGANIC 2.5M`, `DECAY 0.08`, legacy 10 / pool 8 поколений, 4 потомка) дали устойчивые направления на трёх seed'ах с первого прогона моста: расхождение популяций A/B и ON/OFF есть на всех трёх; organic-дельта 0.0825–0.0835; establishment-дельта 0.00219–0.00246. Пороги ассертов взяты ≥2× к минимальным наблюдениям (0.04 / 0.001 / 0.08 / 0.11 — см. константы acceptance-теста). **Константы `plant_functional_phenotype_v1.gd` не менялись** — FFF1 осталась зелёной (110) без перекалибровки.

Примечание об объёме правок предыдущих тестов (аналог прецедента FFF4→FFF3 из чекпоинта FFF4): активация канала сделала недействительными **тамозер-гарды нуля** в двух предыдущих тестах. Минимально исправлены: FFF4 — строка членства каналов (`litter` теперь ACTIVE, `soil_binding` остался INACTIVE) и тамозер `soil_binding_ppm = 7`; FFF3 — тамозер `soil_binding_ppm = 5`. Счётчики сохранены (101 и 51), остальные ассерты не тронуты.

## Что реализовано

1. `scripts/research/ecology/plant_environment_effect_v1.gd` — `litter_input_ppm` переведён INACTIVE→ACTIVE (FFF5); `create(...)` получил trailing-аргумент `litter_input_ppm = 0` (дефолт — все вызовы FFF3/FFF4 бит-идентичны); header обновлён; guard `INACTIVE_CHANNEL_NONZERO` продолжает защищать `soil_binding_ppm`.
2. `scripts/research/ecology/soil_organic_field_v1.gd` — см. design brief; выходы: per-cell `organic_after/deposited_litter_ppm/litter_share/decay_factor/retention_multiplier`, per-plant депозиты, `organic_field_hash` + `plant_litter_hash` (identity-sorted токены), каноническая карта `organic_map` для переноса, публикация effect-записей с `litter_input_ppm` (одно-канальная дисциплина: shade/water в этих записях нули, потребители merge'ат по identity); fail-closed на 8 классов некорректных входов.
3. `scripts/research/ecology/soil_water_field_v1.gd` — опциональный вход `organic_map` (cell→[0,1]); при наличии: обязательное покрытие занятых ячеек, диапазон значений, `evaporation = clamp(unscaled / retention_multiplier(organic), 0, unscaled)`; uptake не трогается; пер-ячеечные `organic_input/evaporation_retention` и дополнительные hash-токены появляются ТОЛЬКО при активной связи (pristine hash-формат не менялся).
4. `scripts/research/ecology/evo7_litter_feedback_bridge_v1.gd` — фазы 1–3 Experiment D, ON/OFF-контрфактический прогон, метрики: хэши начальной/финальной organic-карт и поля, траектория средней органики, population hashes трёх прогонов, средние organic/moisture/net/establishment-component/features по пулам, дивергентные дельты, same-genomes кросс-оценка (observability), `result_hash`.
5. Тест `tests/research/ecology/eco_evo7_fff5_soil_memory_acceptance.gd` (91 assertion) + раннер `RUN_ECO_EVO7_FFF5_TESTS.ps1` (цепочка из 12 наборов: FFF5→FFF4→…→PH0).

## Experiment D — наблюдаемые числа

Прогон `lineage_seed 20260823` (legacy 10 поколений, пулы 8 поколений, 25 растений):

```text
Legacy-фаза:  средняя органика 0.0223 -> 0.1610 за 10 циклов (монотонный рост)
              средняя влага финального поля 0.4451 (база fixture 0.4974)

                        пул A (MODIFIED)   пул B (PRISTINE)   OFF (modified map)
final population hash     cf80770b57…        8dd10322b3…        28f25118ac…
mean cell organic           0.2194             0.1369             0.2207
mean cell moisture          0.4471             0.4459             0.4487
mean net_balance           +0.00166           +0.00222           +0.00427
mean establishment comp    +0.00588           +0.00369            0.00000 (по построению)
mean height, м              3.44               4.05               3.30
```

Дивергенция (seed 23 / 24 / 25): популяции A≠B — **да/да/да**; ON≠OFF — да/да/да;
organic delta **+0.0825 / +0.0835 / +0.0826**; establishment-дельта **+0.00219 / +0.00246 / +0.00235**;
same-genomes net-дельта (observability): +2.28·10⁻⁴ / −1.35·10⁻⁴ / +4.29·10⁻⁵ (шум пластичности, см. калибровку п.1).
Полевой уровень retention (фиксированные записи): organic 0.4 → испарение ×(1/1.14)=0.877, влага ячейки строго выше pristine.

Интерпретация: идентичные семена на участке, «удобренном» прошлым сообществом, дают другую популяцию с более высокой establishment-успешностью — ecological memory в направлении «изменённая почва помогает следующему поколению» (spec §17-D пункт 5: establishment/divergence различаются). Направление устойчиво на трёх seed'ах, пороги — с запасом ≥2×.

## Gates

- **Experiment D causality (exit-гейт этапа)** — предусловие идентичности пулов (хэши чексамов совпадают); популяции modified/pristine различаются; establishment-компонента выше на modified почве (порог 0.001 при наблюдаемых ≥0.00219); organic-наследие реально (initial ≠ final хэш карты, траектория растёт, порог 0.08 при наблюдаемых ~0.16–0.17). PASS.
- **G10 Closed-loop causality** (поддерживающий) — legacy строится (initial/final organic hash разные), ON≠OFF при общей формуле потока. PASS.
- **G12 Order invariance** (поддерживающий) — перестановка и реверс входных записей дают идентичные `organic_field_hash`/`plant_litter_hash` и per-plant депозиты; combined hash effect-записей порядко-инвариантен. PASS.
- **Retention coupling** — те же растения на organic-карте теряют меньше воды на испарение (точная математика `base/(1+0.35·organic)`), влага ячейки выше, uptake не тронут; absent-map поведение бит-идентично (stash-проверка ниже); fail-closed на 3 класса плохих карт. PASS.
- **Effect contract** — `litter_input_ppm` активен и ненулевой в записях органического поля, валидируется; `soil_binding_ppm` по-прежнему zero-enforced; комбинированный хэш порядко-инвариантен. PASS.
- **G13/G14** — наследование только через `LineageExtension`→v1 kernel (source gate: нет randf/randi/randomize/RNG/archetype; формула `EVO7-LITTER|seed|gen|parent|off`; texture-токены только в fixture-конструкции); регрессия зелёная (ниже). PASS.

## Бит-идентичность pristine-пути водного поля

Stash round-trip на этой же рабочей копии: FFF4 acceptance на исходных (HEAD) версиях `plant_environment_effect_v1.gd` + `soil_water_field_v1.gd` печатает `result_hash=0b4c95442253b2df`; с изменениями FFF5 — тот же `0b4c95442253b2df`. Изменение контракта нейтрально для FFF3/FFF4 (hash `cd30fcbf…` из ревью FFF4 относится к более ранней head до repair R1 — текущий HEAD-хэш и есть 0b4c9544…).

## Focused evidence

`Godot 4.7.1.stable.double.custom_build.a13da4feb`, Windows headless:

```text
ECO.EVO7 FFF5 Soil Memory:               PASS (91 assertions)   # bridge result_hash 304d6da59e52c8e5, ~21 s (3 прогона моста)
ECO.EVO7 FFF4 Water Feedback:            PASS (101)             # result_hash 0b4c95442253b2df — бит-идентичен HEAD до изменений
ECO.EVO7 FFF3 Light Feedback:            PASS (51)
ECO.EVO7 FFF2 Morphology Evolution:      PASS (56)
ECO.EVO7 FFF1 PlantFunctionalPhenotype:  PASS (110)
ECO.EVO7 FFF0 Contract Mapping:          PASS (112)
ECO.P1B-S1 Mutation/Lineage kernel:      PASS (5834)
ECO.PH2: PASS (107)   P1A-S1: PASS (109)   P1A-S2: PASS (235)
P1C-S4: PASS (15)    PH0: PASS (63)
EVO6-WATER -SkipBaseline: PASS, result_hash 7010e307… (не изменён)
RUN_ECO_EVO7_FFF5_TESTS.ps1: "ECO.EVO7 FFF5 Soil Memory candidate: PASS"
```

(Фактические счётчики полного прогона цепочки зафиксированы в логе валидации этой сессии; все наборы зелёные.)

## Осознанные ограничения R1

1. **Нет микробов/сущностей**: органика — скалярный прокси на ячейку без профиля по глубине и фракций разложения; `soil_biotic_legacy` (§10) — отдельный будущий этап.
2. **Нет поля питательности**: nutrient availability из §10 отложена; органика в R1 влияет ТОЛЬКО на удержание влаги (retention) и приживаемость (establishment bonus).
3. **Retention слабее uptake в мезической точке**: влаговый эффект органики O(+0.001) средней влаги на уровне поля; на уровне независимо эволюционировавших пулов направление средней влаги даже меняет знак (спрос эволюционирует). Сильная каузальность этапа — establishment-компонента и дивергенция популяций.
4. **Один сценарий** (`loam_legacy`/wet_lowland); plateau отсеян калибровкой; пространственно-неоднородные карты текстур/органики входами поддержаны, но в сценарии R1 не используются.
5. **Бонус считается по пост-обновлению органике** («участок, наследуемый потомством») — декларированная семантика; альтернатива (до-обновление) сдвинула бы сигнал на одно поколение.
6. **Каноническое приоритетное усечение и копростый шаг наследованы от FFF4** — арбитрарность приоритета identity и фиксированного шага 7 остаётся задекларированным упрощением.
7. **Cross-seed батарея — 3 seed'а** (ручная диагностика + пороги с запасом ≥2×); полная автоматизированная cross-seed батарея — FFF6/FFF7 (как и в FFF4).
8. **Same-genomes кросс-оценка — observability**, не гейт: пластичность PH2 делает знак нестабильным (см. калибровку п.1); это честно задокументировано в коде моста.
9. **(Repair-дополнение по line-audit):** FFF4 декларировала связку `root_shoot_ratio → water access` для будущих этапов; в R1 водного поля `root_access` считается только из норм глубины/распространения корней — rsr-член НЕ введён и это ограничение здесь явно пере-декларируется как отложенное (кандидат на FFF7 вместе с nutrients-полем).

## Следующий шаг

FFF6 — Closed Community Evolution / Succession Lab: собрать light + water + soil feedback в один controlled landscape (≥100 generation-equivalents, canopy/understory/gap transitions, anti-runaway gate, deterministic replay, geometry-only visual proof) — дизайн: `docs/plans/ECO_EVO7_FFF6_SUCCESSION_LAB_DESIGN_RU.md`.
