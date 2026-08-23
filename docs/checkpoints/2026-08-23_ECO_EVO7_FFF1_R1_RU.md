# ECO.EVO7 FFF1 — PlantFunctionalPhenotype R1 — CANDIDATE

**Дата:** 2026-08-23
**Ветка:** `feature/eco-evo7-fff-r1`
**Спецификация:** `docs/plans/ECO_EVO7_FORM_FUNCTION_FEEDBACK_TECHNICAL_SPEC_RU.md` (§5, §6, §11; этап FFF1 §19; gates G1–G3)
**Аудит-основание:** `docs/plans/ECO_EVO7_FFF0_CONTRACT_MAPPING_RU.md`

## Design brief (pre-build, research MEDIUM)

- **Проблема:** функциональные оси EVO7 (плотность кроны, экономика листа, структурная инвестиция, корневое распространение, allocation) не имеют ни наследуемых носителей, ни derived read-out; selection bridge пока видит только 5 скаляров генома.
- **Рассмотренные альтернативы:**
  1. компилировать функциональный фенотип напрямую из genome v1 — отвергнуто: дублирует PH2-пластичность и создаёт второй генератор морфологии;
  2. расширять genome v1 новыми полями — отвергнуто: exact-count schema v1 заморожена (FFF0 M1), ТЗ §2.4 требует versioned additive extension;
  3. **выбрано:** аддитивное расширение development traits (`extension_evo7.v1`) + derived компилятор `PlantFunctionalPhenotype.v1`, который потребляет ТОЛЬКО принятые поверхности (PH2 realize → realized traits + growth graph metrics) и не регенерирует морфологию.
- **Риски:** дублирование истины (гасится компиляционной дисциплиной + source-gate «компилятор не трогает heredity/render»); вырожденная плотность кроны у безветвых графов (гасится foliage-bearing floor, см. ограничения); расползание units (freeze в этом документе, sensitivity — FFF3+).

## Что реализовано

1. `scripts/research/ecology/plant_development_traits_extension_evo7_v1.gd` — versioned additive successor-контракт (никогда не заменяет PH0):
   `foliage_density [0.05..1]`, `leaf_economics_proxy [0..1]` (0=conservative, 1=fast), `structural_investment [0..1]`, `root_spread_m [0.05..30]`, `root_shoot_ratio [0.15..0.85]`; checksum в house-стиле; `with_trait` для controlled probes.
2. `scripts/research/ecology/plant_functional_phenotype_v1.gd` — derived read-only контракт `distributed_world_simulator.ecology.plant_functional_phenotype.v1`:
   - состав полей = §5 ТЗ + provenance (`inherited_traits_hash`, `growth_graph_hash`, `plasticity_phenotype_hash`, `derived_representation: true`) + `net_resource_proxy`;
   - **компиляционная дисциплина:** морфология берётся исключительно из PH2 `realize(...)` (realized traits + graph metrics); компилятор ничего не генерирует, не пишет, не касается mutation/render/persistence;
   - компоненты §11 (preview): `photosynthetic_gain_proxy`, `maintenance_cost_proxy` (shoot+root+structural), `net_resource_proxy`; flux-записи `transpiration_demand_ppm`, `shade_output_ppm`, `litter_flux_ppm` (только публикация значений — **обратной связи в среду нет**, эффект-рекорды придут в FFF3/FFF4);
   - reuse констант: root-reach `0.22` и structural-cost `0.095` из `plant_resource_model_v1` (задекларировано);
   - fail-closed: любой невалидный/несогласованный вход (checksum mismatch ph2↔genome↔environment) ⇒ пустой результат.
3. `tests/research/ecology/eco_evo7_fff1_functional_phenotype_acceptance.gd` — gates G1–G3 (107 assertions) + fail-closed + source-boundaries.
4. `RUN_ECO_EVO7_FFF1_TESTS.ps1` — цепочка: FFF1 → FFF0 chain → PH2 (зависимость) → P1A-S1/S2 → P1C-S4 → PH0.

## Замороженные couplings R1 (проверяются тестом)

```text
realized_height_m       = graph.metrics.height_m * age^0.8
realized_crown_radius_m = graph.metrics.horizontal_radius_m * age^0.5
realized_crown_density  = foliage_density * (0.35 + 0.65 * lateral_fraction)
leaf_area_index_proxy   = crown_density * PI * r^2 / 20  (cap 6)
leaf_size_proxy         = realized internode / 1.0        (declared)
leaf_conservative       = 1 - leaf_economics_proxy
realized_root_depth_m   = genome.root_depth_m * (2*rsr) * age^0.5
realized_root_spread_m  = root_spread_m       * (2*rsr) * age^0.5
allocation factors      = 2*rsr (root), 2*(1-rsr) (shoot); 1.0 при rsr=0.5;
                          масштабируют ТОЛЬКО функциональные компоненты, не геометрию
structural_investment   = potential echo; в R1 влияет только на cost
```

## Gates

- **G1 Deterministic phenotype** — идентичные входы ⇒ byte-identical payload + hash; порядок ключей входного словаря не влияет; age-кривая монотонна. PASS.
- **G2 Plasticity without Lamarckian write** — один genome в wet_lowland vs dry_ridge: realized height ниже в сухой среде, phenotype_hash различен, genome checksum неизменен, mutation authority не тронута, source компилятора не содержит heredity-путей. PASS.
- **G3 Heritable morphology** — контролируемые одноосные пробы на ветвящейся референс-морфологии (branch_probability 0.9, branching_depth 4 — house pattern controlled probes; дефолтный seed растёт голый ствол, что и породило foliage-bearing floor):
  stature ↑ ⇒ height/maintenance/shade ↑, root-сторона bit-identical;
  foliage_density ↑ ⇒ density/LAI/transpiration/shade ↑, height bit-identical;
  leaf_economics ↑ ⇒ gain/litter ↑, conservative = точный комплемент;
  structural ↑ ⇒ cost ↑, net ↓ (survival-coupling отложен, declared);
  root_spread ↑ ⇒ spread/cost ↑;
  rsr 0.5→0.8 ⇒ root-факторы ↑, gain ↓, геометрия независима (declared);
  genome root_depth ↑ ⇒ realized depth ↑ и gain в dry ↑ (наследственность только через accepted genome контракт). PASS.

## Focused evidence

`Godot 4.7.1.stable.double.custom_build.a13da4feb`, Windows headless:

```text
ECO.EVO7 FFF1 PlantFunctionalPhenotype: PASS (107 assertions)
ECO.EVO7 FFF0 Contract Mapping:         PASS (112 assertions)   # chain
ECO.PH2 Environment-Coupled Development: PASS (107 assertions)  # dependency
ECO.P1A-S1: PASS (109)   hash b862c4fc… = accepted
ECO.P1A-S2: PASS (235)   hash 618ec5c1… = accepted
ECO.P1C-S4: PASS (15)    failure matrix all PASS
ECO.PH0:    PASS (63)    traits_hash 9d812950… = accepted
EVO6-WATER -SkipBaseline: PASS, result_hash 7010e307… (см. checkpoint FFF0; повторён для FFF1)
```

## Осознанные ограничения R1 (не блокируют G1–G3)

1. Extension-оси пока без собственной plasticity (realized = potential; environment-coupling новых осей приходит вместе с их feedback-каналами в FFF3/FFF4).
2. Structural investment в R1 — только cost-сторона; survival/longevity-выгода войдёт в fitness-декомпозицию FFF3+.
3. Allocation масштабирует компоненты, не геометрию (declared); геометрическое перераспределение — после FFF3.
4. `CROWN_BASE_FOLIAGE = 0.35` — floor для безветвых стволов; калибровка константы — вопрос sensitivity-гейтов, не R1.

## Что этот checkpoint НЕ делает

- не вводит feedback в среду (никаких effect records / агрегаторов);
- не делает новые оси эволюционируемыми (это FFF2 через единственный mutation authority);
- не строит визуал (FFF6) и не трогает production.

## Следующий шаг

FFF2 — Morphology Evolution R1: evolvable subset (5 extension полей + stature/crown через extension) через единственную `plant_mutation_lineage_kernel_v1` (versioned additive policy), common mutation pool ⇒ ≥3 geometry-различных популяций; G4, G5, G13.
