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
3. `tests/research/ecology/eco_evo7_fff1_functional_phenotype_acceptance.gd` — gates G1–G3 (110 assertions после repair R1) + fail-closed + source-boundaries.
4. `RUN_ECO_EVO7_FFF1_TESTS.ps1` — цепочка: FFF1 → FFF0 chain → PH2 (зависимость) → P1A-S1/S2 → P1C-S4 → PH0.

## Замороженные couplings R1 (проверяются тестом)

```text
realized_height_m       = graph.metrics.height_m * age^0.8
realized_crown_radius_m = graph.metrics.horizontal_radius_m * age^0.5
realized_crown_density  = foliage_density * (0.35 + 0.65 * lateral_fraction)
leaf_area_index_proxy   = crown_density * PI * r^2 / 2.0  (cap 6)  # recalibrated by FFF2, was /20
leaf_size_proxy         = realized internode / 1.0        (declared)
leaf_conservative       = 1 - leaf_economics_proxy
realized_root_depth_m   = genome.root_depth_m * (2*rsr) * age^0.5
realized_root_spread_m  = root_spread_m       * (2*rsr) * age^0.5
allocation factors      = 2*rsr (root), 2*(1-rsr) (shoot); 1.0 при rsr=0.5;
                          масштабируют ТОЛЬКО функциональные компоненты, не геометрию
structural_investment   = potential echo; в R1 влияет только на cost
```

## Recalibration (FFF2, 2026-08-23)

Калибровочный эксперимент FFF2 показал, что исходные масштабы компонент делают net-баланс предка отрицательным во всех средах (отбор вырождается в минимизацию издержек). Изменены три константы `plant_functional_phenotype_v1.gd`:

- `LEAF_AREA_REF_M2`: 20 → **2.0** (радиус скелетной кроны ~0.5–1.5 м ⇒ LAI должен быть порядка 0.1–1);
- `ROOT_MAINTENANCE_PER_METER`: 0.06 → **0.025** (корневой upkeep сравним с маржинальным gain, а не доминирует над ним);
- `STRUCTURAL_COST_SCALE`: 0.095/8 → **0.095/40** (структурная цена высоты не должна подавлять её слабый R1-benefit).

Направления всех couplings G1–G3 не изменились; FFF1 acceptance после перекалибровки: **PASS (110 assertions)**. Подробности и история калибровки — в checkpoint FFF2.

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
ECO.EVO7 FFF1 PlantFunctionalPhenotype: PASS (110 assertions)  # после repair R1
ECO.EVO7 FFF0 Contract Mapping:         PASS (112 assertions)   # chain
ECO.PH2 Environment-Coupled Development: PASS (107 assertions)  # dependency
ECO.P1A-S1: PASS (109)   hash b862c4fc… = accepted
ECO.P1A-S2: PASS (235)   hash 618ec5c1… = accepted
ECO.P1C-S4: PASS (15)    failure matrix all PASS
ECO.PH0:    PASS (63)    traits_hash 9d812950… = accepted
EVO6-WATER -SkipBaseline: PASS, result_hash 7010e307… (evolution == visual observatory)
```

## Review & Verification

### Independent review — PASS

Свежая изолированная роль reviewer'а на exact head `a8958d7dcfa6e96b52923f53395b966d382a3eec`.

- Отчёт: `docs/evidence/2026-08-23_ECO_EVO7_FFF1_FINAL_REVIEW_RU.md`.
- R1–R8 подтверждены по коду, включая single-morphological-truth (компилятор не строит геометрию), отсутствие heredity/render/persistence-связностей, сверку констант 0.22 и 0.095 с `plant_resource_model_v1`, фиксированный порядок hash-токенов.
- BLOCKER/MAJOR: нет. MINOR-1: `age_fraction` не входил в токены `phenotype_hash` (детерминизм цел, инъективность ослаблена в вырожденных случаях). MINOR-2: fail-closed был не тотален для сфабрикованного schema-valid ph2 без provenance-полей (прямой dict-индекс мог дать runtime error вместо `{}`).
- **Repair R1 (этот коммит):** `age_fraction` добавлен в hash-токены; provenance-поля ph2 (`phenotype_hash`, `inherited_traits_checksum`) проверяются на непустоту до использования; добавлены регрессионные assertions (+3). Гейты и принятые хэши поверхностей не менялись; полный раннер после repair: FFF1 PASS (110), цепочка зелёная.

### Clean-checkout verification — VERIFIED

Независимая роль верификатора на чистом detached worktree той же exact head (без `.godot`, fresh-worktree import правило отработано).

- Отчёт: `docs/evidence/2026-08-23_ECO_EVO7_FFF1_VERIFICATION_RU.md`.
- Все хэши/assertion counts совпали с checkpoint-документом, ноль расхождений; EVO6-WATER `result_hash 7010e307…` побайтно идентичен в evolution и visual observatory; dry root_depth 0.85 → 2.16355.
- NOTE (не блокер): parse-ошибки трёх legacy `eco_evo5_*.tscn` при импорт-скане существуют на голове независимо от FFF1.

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
