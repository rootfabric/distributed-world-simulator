# ECO CONV0-A — Design-Contract требования выравнивания ECO как consumer'а канонических контрактов мира

Статус: `DESIGN_CONTRACT_ONLY / RESEARCH_FRONTIER / NO RUNTIME OWNERSHIP / NO IMPLEMENTATION`.

База: ветка `feature/eco-evolutionary-ecology`, head на момент подготовки: `b7b4db75` (после ff-синхронизации с `origin/feature/eco-evolutionary-ecology` на `84f217e8`), дата: `2026-08-24`. Главный источник состояния — main-owned registry `config/control/project-program-registry.v1.json`; при конфликте этого текста с registry/PC0 приоритет у registry.

## 1. Назначение документа

Этот документ фиксирует **design-contract-only требования** этапа `ECO.CONV0-A Global Alignment / World Integration Consumer Requirements`: что именно ECO, как research/design frontier, требует от будущих канонических foundation-контрактов мира, чтобы будущая production-конвергенция ecology не создала второй World Query, Spatial Fabric, Population Manager, Material Registry, Lifecycle Manager или Scheduler.

Документ консолидирует и привязывает к актуальному списку блокеров registry три существующих артефакта (не заменяет их):

- план этапа: `docs/future_features/evolutionary_ecology/ECO_CONV0_GLOBAL_ALIGNMENT_RU.md`;
- gap-отчёт по R3 candidate: `docs/future_features/evolutionary_ecology/ECO_CONV0_A_R3_GAP_REPORT_RU.md`;
- machine-readable requirements: `config/ecology/eco-conv0-a-global-consumer-requirements.v1.json` (`ECO-CONV0-A-2026-08-12-R1`, decision `CONV0_A_REQUIREMENTS_COMPLETE_GLOBAL_GAPS_IDENTIFIED`).

Позиция registry: `current_stage = ECO.CONV0-A`, `next_stage = "Execute CONV0-A design requirements only, then CAL1. Do not implement production adapters before canonical foundation contracts and a fresh Harness-controlled production frontier."` ECO — experimental/research frontier и не блокирует V0/P (`docs/control/CURRENT_PROJECT_FRONTIERS_RU.md`, раздел ECO: `research status alone != product blocker`).

## 2. Registry-блокеры как источник требований

Актуальные блокеры программы ECO в registry и какое design-требование из каждого следует:

| Блокер registry | Design-требование CONV0-A |
|---|---|
| `CONV0_B_REQUIRES_CANONICAL_R3_WQ_MAT_LIFE_WB_CONTRACTS` | Все ECO-side consumer-контракты (environment query shape, population projection shape, promotion boundary, work proposal shape) формулируются как **требования к форме**, а финальная привязка (`CONV0-B freeze`) выполняется только после появления canonical R3 + WQ/MAT/LIFE/WB contract shapes. До этого private substitutes запрещены. |
| `PRODUCTION_ENVIRONMENT_ADAPTER_REQUIRES_CANONICAL_WORLD_QUERY_CONTRACTS` | Production environment adapter не создаётся. Требуется лишь зафиксированный набор обязательных полей/provenance для будущего запроса environmental projection (раздел 4) и явный выбор пути потребления WQ (gap `R3_WQ_SYSTEM_DOMAIN_SCOPE_UNSPECIFIED`). |
| `RICH_SUBSTRATE_MODEL_REQUIRES_CANONICAL_MATERIAL_ONTOLOGY_PROJECTION` | Богатая substrate-модель ECO (nutrients/rooting/chemistry) проектируется исключительно как потребитель `MaterialDefinitionId` + domain property projection от MAT; никакой ECO-private material ontology / soil identity (gap `R3_ENV_ECO_PROJECTION_PATH_UNSPECIFIED`). |
| `PRODUCTION_ECO_REQUIRES_CANONICAL_WORLD_WORK_BUDGET` | Ecology work проектируется в форме bounded work proposal к WB (`run/full/coarse/defer/batch/S1_dispatch` решает WB); ECO не владеет scheduler/budget (gap `R3_WB_ECO_CONSUMER_UNSPECIFIED`). |
| `FULL_POOL_COMPACT_DOMINANCE_CAL1_REQUIRED_BEFORE_UNCONSTRAINED_MORPHOLOGY_EVOLUTION`, `ECO_P2_REQUIRES_CAL1_ACCEPTANCE` | Основной research effort после CONV0-A переходит в `ECO.CAL1 Morphology Economics Calibration`; CONV0-A не реализует ничего, что подменяло бы или опережало CAL1/P2. |
| `PRODUCTION_RUNTIME_PROMOTION_REQUIRES_FRESH_PC0_HARNESS_CONTROLLED_FRONTIER` | Любая production-runtime промоция ECO — только через свежий PC0/Harness-controlled frontier; данный документ таких полномочий не создаёт. |

## 3. Ownership matrix (consumer/producer семантика)

Канонический владелец → использование ECO → запрещённая локальная замена:

| Foundation | Owner | Использование ECO (consumer semantics) | Запрещено создавать в ECO |
|---|---|---|---|
| Time Fabric | TF | simulation time, domain tick, history windows, dormant/catch-up timing | `EcoGlobalClock`/`EcoSchedulerClock` |
| Spatial Domain Fabric | SD | WorldAddress/domain scope, отображение на ecology patch identities | `EcoWorldAddress`/`EcoChunkId` |
| Environment Simulation | ENV | temperature/moisture/sunlight/flood/disturbance truth projection | собственный environment store |
| Material Ontology | MAT | substrate `MaterialDefinitionId` + property projection | `EcoMaterialRegistry`/`EcoSoilMaterialId` |
| World Query Fabric | WQ | non-authoritative retrieval/merge projections | `EcoWorldQueryDatabase` |
| Population Field | POP | production aggregate container/promotion substrate | planet-wide runtime population manager |
| World Lifecycle Fabric | LIFE | `ABSTRACT/DORMANT/SIMULATED/ACTIVE/PRESENTED`, promoted-individual boundary | `EcoPromotionManager` |
| World Work Budget | WB | work proposals (cost/quality/priority) | `EcoGlobalWorkScheduler` |
| Network Replication Policy | NX | population/domain interest, promoted-individual replication | `EcoReplicationManager` |
| World Transaction Model | WT/M0 | future cross-domain effects (harvesting/planting/damage) | `EcoTransactionCoordinator` |
| Schema Compatibility | COMPAT | versioning envelope для долгоживущего ecology state | unversioned persistence schema |

Инвариант матрицы: ECO владеет **экологической модельной семантикой** (lineage/heredity/recruitment/density/biomass/competition/selection/dispersal/biogeography, derived representation requirements) и не владеет ни одной runtime-fabric обязанностью.

## 4. Environment projection — требуемая форма запроса

Требуется от будущих canonical contracts (не реализация WQ API):

```text
request context:
  WorldAddress / canonical domain scope
  simulation time / interval (+ history window при необходимости)
  requested field set, caller scope, input revision constraints
        ↓ required fields:
  temperature; moisture; sunlight;
  nutrient availability; flood/water stress;
  disturbance history/summary;
  substrate/material projection (MAT)
        ↓ required provenance:
  spatial/domain reference; time interval;
  source revisions; query/projection revision;
  quality/completeness flags
```

Обязательный инвариант: `ENVIRONMENT_QUERY_RESULT_REVISION_NE_ECOLOGY_STATE_REVISION` — revision результата запроса никогда не совпадает с revision экологического состояния.

## 5. Population projection — требуемая форма вывода

Derived output ECO для presentation/network/diagnostics обязан выражать aggregate state без planet-wide individual objects:

```text
population/lineage identity reference; canonical spatial/domain reference;
count/density; biomass summary; seed-bank/recruitment summary;
phenotype/development distribution; health/stress distribution;
representation hints; promotion/interaction relevance hints;
source revision/provenance
```

Правила: `visual sample != canonical organism`; `Node3D existence != organism existence`; `LOD != identity`; planet-wide individual GrowthGraph array запрещён. Это requirements shape, а не новый canonical population store; semantic owner — ECOLOGY_MODEL, runtime container — POP.

## 6. Promotion boundary — требуемый transition contract

```text
aggregate population truth
    ↓ observation / interaction / damage / ownership relevance
promoted individual detail
    ↓ dormancy/demotion
aggregate-compatible retained delta / population truth
```

Demotion может убрать representation/detail без удаления canonical ecological identity/state. Состояния и триггеры потребляются от LIFE (см. `promotion_requirements` machine-readable JSON).

## 7. Work budget — требуемая форма предложения работы

```text
domain scope; simulation interval; input revisions;
estimated cost; quality options; priority/relevance;
result revision/provenance
```

Допустимые исходы решает WB: `full / coarse / defer / batch / S1_dispatch`. Инвариант: `WORLD_WORK_BUDGET_NE_AUTHORITY`. Измеренные бюджеты EVO4 B7 scale probe (~1000 инстансов, узкое место draw calls) передаются как вход в обсуждения CONV0-A/WQ-WB, но не являются реализацией бюджета.

## 8. Network interest — требуемый принцип

Default: `server population/domain truth → client deterministic/derived representation`. Репликация отдельных организмов — только после explicit promotion/interaction relevance. Владелец shared interest/replication budget policy — NX8/NX. Инвариант: `REPLICATION_LOD_NE_ECOLOGY_IDENTITY`.

## 9. Открытые gap'и для владельцев foundations

Зафиксированные в `ECO_CONV0_A_R3_GAP_REPORT_RU.md` / machine-readable JSON гэпы, требующие решения владельцев (не ECO):

1. `R3_ECO_PROGRAM_ID_COLLISION` (HIGH) — закрепить `ECO = Evolutionary Ecology`, economy program = `ECON`; до GLOBAL-P0 R3 promotion.
2. `R3_ECO_POP_OWNERSHIP_INTERSECTION_UNSPECIFIED` (HIGH) — ECO: model semantics, POP: generic production fabric; adapter boundary, не две population fabrics.
3. `R3_WQ_SYSTEM_DOMAIN_SCOPE_UNSPECIFIED` (MEDIUM) — выбрать: system/domain-scoped WQ principal либо отдельный canonical ENV/domain-projection path; ECO-private WQ запрещён в обоих вариантах.
4. `R3_ENV_ECO_PROJECTION_PATH_UNSPECIFIED` (MEDIUM) — объявить explicit `ENV+MAT(+WQ) → evolutionary ECO` consumer intersection.
5. `R3_WB_ECO_CONSUMER_UNSPECIFIED` (MEDIUM) — выбрать путь budgeting ecology work (напрямую или через POP/ENV adapter) с сохранением ownership WB.

## 10. Что НЕ заявляется

Этот документ и этап CONV0-A **не заявляют и не авторизуют**:

- никаких production adapters (в т.ч. production `EcoEnvironmentQuery` adapter, environment/material/population adapters);
- никакой реализации до принятия CAL1 **и** до появления канонических контрактов (canonical R3 + WQ/MAT/LIFE/WB/POP/ENV contract shapes);
- ECO-private WorldAddress/spatial fabric, material ontology, generic population runtime fabric, lifecycle/authority/persistence/transport foundation, global work scheduler;
- фиксацию production network replication protocol;
- начало P3/PH6 runtime работ или любой production-runtime frontier (требуется fresh PC0/Harness-controlled frontier);
- изменение архитектурных конфигураций, ownership или статуса принятых чекпоинтов ECO.PH/EVO3/EVO4;
- новые полномочия ECO как product blocker для V0/P.

## 11. Stop rule и следующий шаг

Stop rule CONV0-A: требования сформулированы, гэпы переданы владельцам foundations, реализация не начата — этап завершён (текущий decision: `CONV0_A_REQUIREMENTS_COMPLETE_GLOBAL_GAPS_IDENTIFIED`; повторная проверка против актуального R3 candidate — при каждом refresh). Следующий primary research шаг ветки: `ECO.CAL1 — Morphology Economics Calibration`. `CONV0-B compatibility/freeze` остаётся frozen-waiting до появления canonical R3 + WQ/MAT/LIFE/WB контрактов.
