# ECO ARCH2 A10.5 / ECO-POLYGON-1 — Work Order (P0)

Статус: ACTIVE WORK ORDER. Дата: 2026-09-20.
Base: `origin/main` = `e200a61cb55930378d11c39dcc5950cf49db603c`.
Roadmap-источник: `docs/research/ecology/EVO_ARCH2_ROADMAP_R2_RU.md` (из `docs/eco-arch2-a10-5-polygon-roadmap-r1`, HEAD `a795e240`).

## 1. Scope

A10.5 / ECO-POLYGON-1 — **simulator-compatible experimental workbench**: срез реального симулятора (canonical model A1–A10 + инструменты), а НЕ отдельный симулятор и НЕ parallel ecology runtime.

Полигон позволяет: создать experiment, выбрать/изменить genomes, рассадить организмы по зонам среды, запустить симуляцию, наблюдать развитие, сохранять/восстанавливать/форкать/переигрывать/сравнивать ветки экспериментов — используя ТОЛЬКО реальные canonical данные и переходы A1–A10.

Формула (из roadmap R2):

```text
real Genome / DevelopmentProgram → real BodyGraph / DevelopmentState
  → real PhenotypeSnapshot → real A4 environment + A5/A6 lifecycle
  → A8 persistence / replay → A9 fidelity controls
  → A10 world-compatible bindings where applicable
  → ECO-POLYGON-1 UI / experiment orchestration only
```

## 2. Forbidden ownership (жёсткие границы)

Полигон (каталог `scripts/ecology/workbench/` и его сцены) НЕ создаёт и не владеет:

- `PolygonGenome` / второй genome truth;
- `PolygonBodyGraph` / второй body/morphology truth;
- `PolygonLifecycle` / отдельные lifecycle-правила (выживание, рост, размножение);
- `PolygonReproduction` / отдельную формулу reproduction;
- `PolygonResources` / бесплатные или альтернативные polygon resources;
- `PolygonPersistence` / второй save format, не связанный с A8;
- `PolygonMutationEngine` / UI-owned mutation semantics;
- `PolygonWorldState`, `PolygonRegion`, `PolygonMatter` / обход Region/owner/Matter правил в WORLD-COMPAT mode;
- `PolygonHandoff` / собственные handoff-правила.

Canonical truth остаётся в A1–A10 (см. `ECO_ARCH2_A10_5_OWNER_MAP_RU.md`). UI полигона не становится biological owner, resource owner, Region owner или persistence owner. Renderer/presentation не пишет обратно в Genome/DevelopmentProgram/BodyGraph.

## 3. Фазы P0–P13 и acceptance gates

| Фаза | Содержание | Acceptance gate |
|---|---|---|
| **P0** | Work order, owner map, architecture doc, contracts skeleton, evidence | Документы отражают реальные файлы/API на диске; skeleton компилируется без альтернативной биологии; tracked clean |
| **P1** | ExperimentManifest v1 + ExperimentController v1 (LAB mode): deterministic seed, treatment, zones, founders | Одинаковый manifest+seed → одинаковый стартовый state; validation ошибок до запуска |
| **P2** | PlacementPlan v1 + environment editor inputs: ручная/сеточная/seed-рассадка, WET/DRY/DARK-зоны | Placement использует canonical spatial/environment addressing (A4), не UI-only координаты |
| **P3** | Run controls: RUN/PAUSE/single tick/bounded step/run-to-horizon/RESET/checkpoint/restore | Ускорение не меняет ecological tick semantics; один canonical mutation step на session |
| **P4** | Genome/organism editor UI: просмотр/редактирование разрешённых значений, variants, compare | Редактор проходит canonical A1/A3 validation; никакого executable code в genotype; curated archetype не требуется |
| **P5** | Save/restore/fork/replay поверх A8 snapshot seam | save→restore продолжает историю; save→fork создаёт связанную отдельную историю; replay совпадает |
| **P6** | Observability: organism inspector `genome→development→body→function→resources→lineage`, events timeline | Visualization не меняет simulation state; только completed immutable snapshots |
| **P7** | MorphologyDescriptor + GenericMorphologyRealizer v1 | Валидная неизвестная BodyGraph topology отображается generic-примитивами; Specialized Realizer не условие validity |
| **P8** | OrganizationProfile v1: FREE/SOFT/EARTH_LIKE/NMS_LIKE/CUSTOM (soft bias, versioned) | Bias явно в manifest/provenance; детерминирован при seed; FREE отключает bias'ы, но не законы среды |
| **P9** | Emergent morphotypes: derived features, clustering, similarity labels | Labels — аналитика; по умолчанию не пишутся в genotype и не влияют на reproduction |
| **P10** | ExperimentMetrics + ExperimentComparison + batch runner | Все seeds сохраняются; нет скрытого выбора winner; сравнение по заранее выбранным метрикам |
| **P11** | WorldAdapter v1 (WORLD-COMPAT): A10 bindings (world/Matter/Region/Construction/damage/handoff) | Не обходятся owner/epoch/Region/Matter правила; explicit-only Matter mapping |
| **P12** | Presentation-слой: EcologyWorkbench scene, LAB host как composition root | Workbench не владеет world/player/camera/Region/Matter/persistence; setup через dependencies |
| **P13** | End-to-end acceptance сценарий (раздел 7 roadmap R2) + independent review | 16 шагов user scenario проходят; fresh review подтверждает отсутствие polygon-only biological truth |

Общие acceptance gates этапа — раздел 8 `EVO_ARCH2_ROADMAP_R2_RU.md`.

## 4. Deliverables P0

- `docs/research/ecology/ECO_ARCH2_A10_5_WORK_ORDER_RU.md` (этот файл)
- `docs/research/ecology/ECO_ARCH2_A10_5_OWNER_MAP_RU.md`
- `docs/research/ecology/ECO_ARCH2_A10_5_ARCHITECTURE_RU.md`
- `scripts/ecology/workbench/*.gd` (10 skeleton-файлов контрактов)
- `docs/research/ecology/ECO_ARCH2_A10_5_P0_EVIDENCE_RU.md`
