# ECO.EVO7 FFF4 — Water + Soil Texture Feedback R1 — CANDIDATE

**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1`
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§9, §13, §19 FFF4; gates G8, G9 + G10/G12 как поддерживающие)
**Основание:** FFF0 (mapping), FFF1 (functional phenotype), FFF2 (morphology evolution, single authority), FFF3 (light feedback loop, контракт effect-записей).

## Design brief (pre-build, research MEDIUM)

- **Проблема:** EVO6-WATER сделал воду селективной поверхностью, но односторонней — среда влияет на растения, растения не влияют на воду (§9: «сделать двусторонней»). Нужно: transpiration demand, bounded uptake (вода не ниже нуля), встречный эффект кроны (испарение), root access, sand/loam/clay как versioned fixture-канал (НЕ новая геология, §9.4).
- **Выбрано:** `soil_water_field_v1` — cell-bucketed агрегатор по дисциплине `understory_light_field_v1` (канонический порядок по identity, snapped floats, fail-closed): uptake `min(demand, remaining·access·texture_eff)` с последовательным исчерпанием ячейки в каноническом порядке (структурный инвариант «суммарный uptake ≤ доступная вода» + fail-closed проверка), `root_access = clamp01(0.3 + 0.4·depth_norm + 0.3·spread_norm)`, texture-параметры `sand 0.85/1.0/1.35`, `loam 1.0/1.0/1.0`, `clay 0.9/1.0/0.8` (uptake eff / базовая линия / evap mult), shade_suppression = `clamp01(canopy_cover·0.6)` с soft-disc весом из светового поля; `evo7_water_feedback_bridge_v1` — микрокосм 5×5 (0.35 м, 16 поколений), две сценарные fixture-варианты «texture × moisture» на одних и тех же 25 позициях: `dry_sand` (sand + сухая точка dry_ridge) и `mesic_loam` (loam + мезическая точка wet_lowland); ON — каждое растение реализуется/оценивается под влагой СВОЕЙ ячейки (derived EnvironmentSample, как в FFF3 для света), OFF — все под базовой влагой; формула мутационного потока `EVO7-WATER|seed|gen|parent|off` идентична в обоих режимах и обоих сценариях.
- **Отвергнуто:** пропорциональное рационирование воды (сложнее, нет преимущества перед каноническим порядком); межпоколенческий перенос влаги (поле пересобирается из fixture каждый generation — memory-петля это FFF5); texture-условные правила морфологии — запрещены G9 source gate.
- **Риски:** слабый сигнал «растения сушат почву» при большой ёмкости ячейки (гасится калибровкой ёмкости); нейтрализация отбора при дедупликации «одно растение на позицию» по родительскому identity (см. историю калибровки, п.3 — главный риск реализовался); насыщение сухой ячейки в ноль (гасится выбором ёмкости: сухой сценарий остаётся demand-limited).

## История калибровки (честно, три итерации до рабочей; константы FFF1 не менялись)

1. **Итерация 1** (ёмкость ячейки 8·10⁶ ppm, 2 потомка, settle «дедупликация по позиции родителя» как в FFF3): контур работает, направление LAI верное (dry 0.257 < mesic 0.344), но корни стоят на месте (dry 0.881 < mesic 0.934 — направление неверно), ON/OFF влага различается на 0.0005 — сигнал петли утоплен. **Диагноз:** при дедупликации по позиции все потомки одной позиции имеют одинаковый parent_fitness, выживающий выбирается tie-break по checksum ⇒ наследование по позициям нейтрально (случайное блуждание), кросс-позиционного отбора нет; согласанный LAI-контраст держался в основном на пластичности реализации, а не на эволюции.
2. **Итерация 2** (ёмкость 4·10⁶ — усиление «растения сушат почву»; 4 потомка — дисциплина направленной эволюции FFF2): на фиксированном seed направления встали правильно, но на 3 seed'ах дельта корней −0.06/−0.11/−0.01 — по-прежнему дрейф: усечение глобальное, а settle сохранял родовые линии позиций.
3. **Рабочая калибровка:** глобальное усечение (все потомки соревнуются, лучшие 25 занимают позиции) с назначением позиций по фиксированному копростому шагу (7, coprime с 25) — ранг приспособленности не совпадает систематически ни с одной пространственной ячейкой, «одно растение на позицию» сохранено. Результат: все три направления G9 устойчивы на 3 seed'ах (LAI 0.131/0.140/0.150; корни 1.39/0.65/1.29; rsr 0.048/0.146/0.031), сухая влага 0.046→0.011 (видимое исчерпание без насыщения в ноль). **Константы `plant_functional_phenotype_v1.gd` не менялись** — FFF1 осталась зелёной без перекалибровки (110 assertions).

## Что реализовано

1. `scripts/research/ecology/plant_environment_effect_v1.gd` — каналы `water_uptake_ppm` и `evaporation_suppression_ppm` переведены из INACTIVE в ACTIVE (FFF4); `create(...)` принимает оба значения (дефолт 0 — обратимо к FFF3-вызовам); `litter_input_ppm`/`soil_binding_ppm` остаются зарезервированными нулями до FFF5 (ненулевое значение = нарушение контракта).
2. `tests/research/ecology/eco_evo7_fff3_light_feedback_acceptance.gd` — единственное разрешённое изменение: ассерт «inactive channels are zero in R1» проверяет теперь `litter_input_ppm`/`soil_binding_ppm` (водные каналы больше не нулевые). Остальные 50 ассертов FFF3 не тронуты.
3. `scripts/research/ecology/soil_water_field_v1.gd` — агрегатор §9+§13:
   - входы: записи растений (identity, координаты, `transpiration_demand_ppm`, геометрия кроны, `realized_root_depth_m/spread_m`, `root_shoot_ratio` — едет в записи для FFF5, в формулу доступа R1 не входит) + versioned fixture-входы (`fixture_id/fixture_version`, per-cell texture `sand|loam|clay`, per-cell `base_moisture` [0,1], `base_evaporation_rate`);
   - обновление в каноническом порядке: `uptake_i = min(demand_i, remaining·access_i·texture_eff)`, последовательное исчерпание ячейки; структурный инвариант `Σ uptake ≤ base_moisture·CELL_WATER_CAPACITY_PPM` проверяется и fail-closed;
   - `evaporation_cell = base_evap · texture_evap_mult · (1 − clamp01(canopy_cover·0.6))`, canopy cover — точечная проба в центре ячейки с soft-disc весом `clamp01(1 − d/r)` · crown_density (идея светового поля);
   - `moisture_after = clamp01(base − (uptake+evap)/ёмкость)`, ёмкость `CELL_WATER_CAPACITY_PPM = 4·10⁶` (калибровка);
   - выходы: per-cell moisture/uptake/evaporation/cover, per-plant `actual_uptake_ppm` + `root_access`, `field_hash` + `plant_uptake_hash` (identity-sorted токены), публикация effect-записей с водными каналами в каноническом порядке; fail-closed на все нарушения входов.
4. `scripts/research/ecology/evo7_water_feedback_bridge_v1.gd` — замкнутый водный контур: 25 позиций (5×5, 0.35 м), 16 поколений, 4 потомка, воспроизводство только через `LineageExtension` (единственная authority), сценарии `dry_sand`/`mesic_loam` на одних позициях; ON — оценка под влагой своей ячейки, OFF — под базовой; метрики на сценарий/режим: `final_population_hash`, `final_field_hash`, `mean_cell_moisture`, `mean_fitness`, mean features (включая `root_shoot_ratio`), quartiles «самая сухая/самая влажная четверть растений» по средней глубине корней, `feature_delta_on_minus_off`, кросс-сценарное сравнение G9.
5. Тест `eco_evo7_fff4_water_feedback_acceptance.gd` (95 assertions) + раннер `RUN_ECO_EVO7_FFF4_TESTS.ps1` (цепочка 11 наборов, включая P1B-S1 kernel 5834).

## Наблюдаемая динамика (lineage_seed 20260823, 16 поколений, 25 растений, feedback ON)

```text
dry_sand  (sand,  dry_ridge):  base moisture 0.0464 -> initial field 0.0263 -> final 0.0107
                               (сообщество исчерпало ~77% базовой влаги; demand-limited, без клампа в ноль)
mesic_loam (loam, wet_lowland): base moisture 0.4974 -> initial field 0.4532 -> final 0.4303

                        dry_sand ON   dry_sand OFF   mesic ON   mesic OFF
mean fitness (net)        +0.0315       +0.0428       +0.0101     +0.0163
mean LAI proxy             0.273         0.348         0.404       0.514
mean height, м             2.53          3.27          3.85        4.29
mean root_depth, м         2.29          1.94          0.90        1.07
mean root_shoot_ratio      0.397         0.428         0.349       0.364
final population hash      7d8c3688…     b0ab2b14…     c97a24df…   3ee04314…
```

G9-дельты (ON, dry_sand против mesic_loam): LAI **−0.131** (компактная крона), root depth **+1.391** (root-heavy), rsr **+0.048**; на seed'ах 20260824/25: LAI −0.140/−0.150, корни +0.652/+1.293, rsr +0.146/+0.031 — направления устойчивы. Пороги ассертов (0.05 / 0.30 / 0.015) взяты с запасом ≥2× к минимальным наблюдаемым дельтам.

Интерпретация: в сухом песке высокая лиственная масса «сжигает» общую воду ячейки (transpiration demand ∝ LAI) и сама же страдает от падения activity — отбор идёт в компактную крону и глубокие корни (root-reach компенсация в функциональном фенотипе + доступ к воде); в мезическом лёме вода не лимитирует, и высокие high-LAI стратегии остаются конкурентными (рост 3.85 м, положительный net). Замкнутый контур: растения → сухая почва → отбор (ON против OFF при том же потоке мутаций даёт разные популяции; начальное поле ≠ финальному). Дополнительно: петля УСИЛИВАЕТ root-heavy отбор в dry_sand (ON 2.29 м против OFF 1.94 м).

## Gates

- **G8 Water engineering** — после обновления поля влага каждой ячейки в [0,1] и не выше базы; суммарный uptake ячейки ≤ доступной воды (структурно + stress-проба с 10× превышением demand — кламп, не овердро); high-LAI сообщество сушит почву сильнее low-LAI контроля (−0.05 по средней влаге при 7.5× demand); затенённая ячейка теряет меньше воды на испарение, чем незатенённая (suppression = clamp01(cover·0.6), точные значения 20000·0.52); texture-канал: sand быстрее испаряет (1.35×) и даёт меньше uptake на доступную воду (0.85 против 0.9 clay); effect-записи несут nonzero `water_uptake_ppm`/`evaporation_suppression_ppm` и валидируются; fail-closed на 8 классов некорректных входов. PASS.
- **G9 Sand vs loam** — dry_sand эволюционирует компактную крону (LAI ниже на >0.05 при наблюдаемых 0.131) и root-heavy форму (глубина корней выше на >0.30 при наблюдаемых 1.39; rsr выше на >0.015 при наблюдаемых 0.048); mesic_loam не запрещает высокие стратегии (положительный net, рост > 2 м — фактически 3.85 м); source gate: в fitness-пути (`plant_functional_phenotype_v1`) нет ни одного вхождения texture/sand/loam/clay; в мосте токены текстур встречаются только в fixture-конструкции (построчная проверка); «archetype»/«if texture» отсутствуют в поле и мосте; texture входит только как параметры водного поля. PASS.
- **G10 Closed-loop causality** (поддерживающий) — initial field hash ≠ final в обоих сценариях; ON ≠ OFF по финальным популяциям в обоих сценариях при формуле потока `EVO7-WATER|seed|gen|parent|off`. PASS.
- **G12 Order invariance** (поддерживающий) — перестановки и реверс входных записей дают идентичные `field_hash`, `plant_uptake_hash` и per-plant uptake; combined hash effect-записей порядко-инвариантен. PASS.
- **G13/G14** — наследственность только через `LineageExtension`→v1 kernel (нет RNG в слое, source gate); полная регрессия зелёная (ниже). PASS.

## Focused evidence

`Godot 4.7.1.stable.double.custom_build.a13da4feb`, Windows headless:

```text
ECO.EVO7 FFF4 Water Feedback:           PASS (95 assertions)   # bridge ~9-10 s
ECO.EVO7 FFF3 Light Feedback:           PASS (51)
ECO.EVO7 FFF2 Morphology Evolution:     PASS (56)
ECO.EVO7 FFF1 PlantFunctionalPhenotype: PASS (110)
ECO.EVO7 FFF0 Contract Mapping:         PASS (112)
ECO.P1B-S1 Mutation/Lineage kernel:     PASS (5834)
ECO.PH2: PASS (107)  P1A-S1: PASS (109, b862c4fc…)  P1A-S2: PASS (235)
P1C-S4: PASS (15)    PH0: PASS (63, 9d812950…)
EVO6-WATER -SkipBaseline: PASS, result_hash 7010e307… (не изменён)
RUN_ECO_EVO7_FFF4_TESTS.ps1: "ECO.EVO7 FFF4 Water Feedback candidate: PASS"
```

## Осознанные ограничения R1

1. **Нет groundwater simulator и цикла дождей**: влага — статический per-cell fixture; поле пересобирается из `base_moisture` каждый generation, межпоколенческая память пересыхания (и восстановление) — FFF5 (soil legacy) или отдельный water authority (§9.2).
2. **Texture — versioned fixture-канал** (`fixture_id/fixture_version` в хэше поля), не геология: однородная текстура на сценарий; пространственно-неоднородные карты текстур входом уже поддержаны, но в сценариях R1 не используются.
3. **Рационирование по каноническому identity**: ячейка исчерпывается в порядке identity — детерминировано и порядко-инвариантно, но приоритет арбитражен (задекларированное упрощение R1).
4. **`root_shoot_ratio` едет в записи, но не входит в формулу доступа R1** (зарезервировано под water-use coupling FFF5); выгода корней в R1 — root-reach компенсация в функциональном фенотипе + доступ к воде при дефиците.
5. **Canopy cover — точечная проба в центре ячейки** с soft-disc весом; послойное/площадное покрытие и максимум suppression 0.6 — упрощение R1.
6. **Квартильная метрика** «сухая/влажная четверть по глубине корней» — наблюдаемость, не гейт (шумит между seed).
7. **Пороги G9** откалиброваны на фиксированном seed с запасом ≥2× и подтверждены на 2 дополнительных seed'ах; полная cross-seed батарея — FFF6/FFF7.
8. **ON/OFF-сравнение**: общий поток мутаций, среда назначает его линиям (назначение среды — тестируемая причинность, как в FFF3).

## Следующий шаг

FFF5 — Soil/Litter Memory R1: активация `litter_input_ppm`/`soil_binding_ppm` (каналы уже в контракте и защищены), межпоколенческая память влаги/грунта (пересыхание и восстановление), water-use coupling на `root_shoot_ratio`; вопрос канонического groundwater authority (§9.2, §10).
