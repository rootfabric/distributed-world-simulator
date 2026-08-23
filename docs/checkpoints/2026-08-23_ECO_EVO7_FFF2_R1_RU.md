# ECO.EVO7 FFF2 — Morphology Evolution R1 — CANDIDATE

**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1`
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§12, §19 FFF2; gates G4, G5, G13)
**Основание:** `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md` (FFF0-A: морфология вне эволюции), checkpoint FFF1.

## Design brief (pre-build, research MEDIUM)

- **Проблема (FFF0-A):** ни один морфологический признак не наследуется — `MUTABLE_TRAITS` v1-kernel содержит только 5 экологических полей генома. Функциональные оси FFF1 не могут эволюционировать.
- **Рассмотренные альтернативы:**
  1. расширить `MUTABLE_TRAITS` v1 in-place — запрещено ТЗ §12.1 (ломка v1 semantics);
  2. второй «быстрый EVO7 mutator» с собственной lineage-книгой — запрещено ТЗ (G13);
  3. **выбрано:** versioned additive extension единственной authority — `plant_mutation_lineage_extension_evo7_v1`, который делегирует наследственность генома 1:1 в `Kernel.reproduce(...)` и добавляет морфологические оси в ТО ЖЕ lineage-событие (один вход воспроизводства, один mutation seed, одна v1 lineage-цепь, keyed rolls `(seed|layer|axis)` в canonical порядке).
- **Fitness R1:** `net_resource_proxy` из PlantFunctionalPhenotype (preview декомпозиции §11). Без feedback в среду.
- **Риски:** расползание масштабов gain/cost (гасится калибровкой, см. историю ниже); дрейф structural к минимуму (declared: benefit придёт в FFF3+); схлопывание shade-популяций (наблюдается, биологически осмысленно для R1).

## История калибровки (честно, две неудачные попытки до рабочей)

1. Первая попытка: при исходных константах FFF1 net-баланс предка был глубоко отрицателен (≈ −0.041…−0.046 по всем средам) — отбор минимизировал издержки, вся морфология схлопывалась (h→0.1 м, radius→0). Причина: structural cost `0.095/8·h^1.2` перевешивал слабый benefit высоты.
2. Вторая попытка: `STRUCTURAL_COST_SCALE → 0.095/40` — высота перестала обваливаться, но LAI предка был ≈ 0.026 (радиус скелета ограничен геометрией ветвей ~0.7 м, а `LEAF_AREA_REF_M2 = 20` делал LAI микроскопическим) — gain никогда не покрывал корневой maintenance, снова коллапс.
3. Рабочая калибровка: `LEAF_AREA_REF_M2 20 → 2.0`, `ROOT_MAINTENANCE_PER_METER 0.06 → 0.025` (плюс /40 из п.2). Предок при этом остаётся около нуля или отрицателен (положителен только в sunny_slope) — давление отбора действует во всех средах; эволюционные популяции достигают положительного net в 4 из 5 сред, а в shade отбор схлопывает морфологию в карликовую. Все константы задокументированы в `plant_functional_phenotype_v1.gd`, FFF1-гейты после перекалибровки зелёные (110 assertions — направления не зависят от масштабов).

## Что реализовано

1. `scripts/research/ecology/plant_mutation_lineage_extension_evo7_v1.gd` — versioned additive extension единственной mutation authority:
   - canonical 8 осей: `ph0:max_height_m`, `ph0:crown_spread_m`, `ph0:apical_dominance`, `ext:foliage_density`, `ext:leaf_economics_proxy`, `ext:structural_investment`, `ext:root_spread_m`, `ext:root_shoot_ratio`;
   - policy: `genome_policy` (политика v1-kernel, без изменений) + `morphology_probability` + per-axis step с проверкой диапазона оси; `policy_hash` поверх kernel policy hash;
   - `reproduce_bundle`: делегация `Kernel.reproduce` (геном + v1 lineage record) + keyed rolls морфологии в том же событии; stable id (один `/e7` маркер); fail-closed на tampered bundle (checksum gate);
   - `create_ancestor_bundle`: геном + PH0-триты + extension под одной lineage записью.
2. `scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd` — мост по образцу EVO6-WATER:
   - 5 сценариев-контрольных точек фикстуры: `wet_lowland`, `sunny_slope`, `shaded_slope`, `dry_ridge`, `plateau` (baseline = plateau);
   - общий formula-seed `"EVO7-MORPHO|lineage_seed|generation|parent|offspring"` во всех средах ⇒ общий generation-one candidate pool (G4);
   - отбор: fitness desc, tiebreak по bundle checksum; 24 поколения, популяция 18, 4 потомка;
   - метрики: mean feature vector (7 осей G5), unique bundles, pairwise distinctness с порогами, `distinct_final_population_pairs`, `geometry_distinct_pairs`, `scenarios_distinct_from_baseline`.
3. Тест `eco_evo7_fff2_morphology_evolution_acceptance.gd` (56 assertions) + раннер `RUN_ECO_EVO7_FFF2_TESTS.ps1` с цепочкой, включающей регрессию самого kernel (P1B-S1, 5834 assertions).
4. Перекалибровка трёх констант `plant_functional_phenotype_v1.gd` (см. историю); аддендум в checkpoint FFF1.

## Наблюдаемая экология (lineage_seed 20260823, 24 поколения)

| Сценарий | mean fitness | height | crown_density | LAI | root_depth | root_spread |
|---|---|---|---|---|---|---|
| wet_lowland | +0.0353 | 4.72 | 0.676 | 0.535 | 1.204 | 0.188 |
| sunny_slope | +0.0813 | 4.16 | **0.757** | 0.522 | 1.134 | 0.913 |
| shaded_slope | −0.0005 | **0.11** | 0.126 | 0.000 | 0.051 | 0.050 |
| dry_ridge | +0.0893 | 3.96 | 0.673 | 0.382 | **2.933** | 0.194 |
| plateau (baseline) | +0.0614 | 3.56 | 0.702 | 0.414 | 1.788 | 0.160 |

Направления, возникшие из trade-offs (не из правил):
- **градиент влаги ⇒ глубина корней**: dry 2.93 > plateau 1.79 > sunny/wet ≈ 1.2 (глубокие корни окупаются только там, где вода лимитирует);
- **градиент света ⇒ плотность кроны**: sunny 0.757 > shaded 0.126 (в shade листва не окупает maintenance);
- **shade ⇒ карликовость**: высота 0.11 м против ~4 м в продуктивных средах (структурная цена высоты не окупается при низком gain);
- structural_investment дрейфует нейтрально-вниз (declared: benefit появится в fitness-декомпозиции FFF3+).

## Gates

- **G4 Common mutation pool causality** — `common_first_candidate_pool_hash` идентичен во всех 5 средах (мост структурно падает при расхождении); final populations: 10/10 пар различны; deterministic replay: повторный прогон даёт идентичный `result_hash`; смена lineage_seed меняет результат. PASS.
- **G5 Geometry divergence (numeric)** — 10/10 пар геометрически различимы (пороги с запасом: height 0.25, crown_radius 0.20, density 0.04, LAI 0.05, root_depth 0.25, root_spread 0.25, structural 0.04 при наблюдаемых span до 4.6 м / 0.63 density / 2.9 м корней); ≥3 сценария отличны от baseline (наблюдено 4/4); направления: dry roots > 1.5×wet roots, sunny density > shaded + 0.2, shade height < 1.0 м. PASS. (Полный C-neutral визуальный gate — FFF6.)
- **G13 No second mutation path** — геном наследуется только через `Kernel.reproduce` (делегация в исходнике, v1 MUTABLE_TRAITS нетронуты, P1B-S1 регрессия 5834 assertions зелёная); в evolution-слое нет RNG-примитивов (source gate); tampered bundle отклоняется checksum-гейтом; lineage-цепь ведётся единственной v1 записью. PASS.

## Focused evidence

`Godot 4.7.1.stable.double.custom_build.a13da4feb`, Windows headless:

```text
ECO.EVO7 FFF2 Morphology Evolution:      PASS (56 assertions)
ECO.EVO7 FFF1 PlantFunctionalPhenotype:  PASS (110 assertions)  # после перекалибровки
ECO.EVO7 FFF0 Contract Mapping:          PASS (112 assertions)
ECO.P1B-S1 Mutation/Inheritance/Lineage: PASS (5834 assertions) # kernel dependency
ECO.PH2: PASS (107)   P1A-S1: PASS (109, b862c4fc…)   P1A-S2: PASS (235)
ECO.P1C-S4: PASS (15) PH0: PASS (63, 9d812950…)
EVO6-WATER -SkipBaseline: PASS, result_hash 7010e307… (не изменён FFF1/FFF2)
```

## Осознанные ограничения R1

1. Fitness = net_resource_proxy (preview); полная декомпозиция §11 (survival/establishment/reproduction) — FFF3+.
2. Structural investment дрейфует к минимуму (нет benefit-стороны) — ожидаемое поведение R1, задокументировано.
3. Shade-популяция схлопывается в карликовую форму около нулевого net — для R1 допустимо; establishment/survival компоненты дадут understory-стратегии положительную нишу в FFF3+.
4. Пороги G5 откалиброваны на детерминированном seed с запасом ≥2× к наблюдаемым span; sensitivity-проба на других seed — в FFF3.
5. Пороги среды = 5 контрольных точек фикстуры; soil texture и пространственная агрегация — FFF4/FFF3.

## Следующий шаг

FFF3 — Light Feedback R1: canopy spatial projection, shade-агрегация в cell-buckets, understory light field, light-компонента fitness, canopy removal counterfactual (G6, G7, G10, G12). Именно там появляется подлесок как ниша.
