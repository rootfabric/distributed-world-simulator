# ECO ARCH2 A10.5 / ECO-POLYGON-1 — Architecture (P0)

Статус: ARCHITECTURE. Дата: 2026-09-20.
Owner map: `ECO_ARCH2_A10_5_OWNER_MAP_RU.md`. Work order: `ECO_ARCH2_A10_5_WORK_ORDER_RU.md`.

## 1. Четыре слоя

```text
┌───────────────────────────────────────────────────────────────┐
│ 4. PRESENTATION / UI                                          │
│    EcologyWorkbench scene, editors, timeline, realizer view   │
│    читает ТОЛЬКО completed immutable snapshots                │
├───────────────────────────────────────────────────────────────┤
│ 3. READ-ONLY PROJECTION                                       │
│    phenotype_snapshot.compile, observatory observe(),         │
│    diversity_metrics, MorphologyDescriptor,                   │
│    plant_multiscale_representation (A9 tiers), metrics        │
├───────────────────────────────────────────────────────────────┤
│ 2. SIMULATION / ORCHESTRATION                                 │
│    ExperimentController, ExperimentBranch,                    │
│    resource_lifecycle_runtime.step_population,                │
│    persistent_environmental_feedback.advance,                 │
│    snapshot_seam (A8), observatory_session                    │
├───────────────────────────────────────────────────────────────┤
│ 1. CANONICAL MODEL (A1–A10, без изменений полигоном)          │
│    organism_genome_v2, development_program_v1, body_graph_v1, │
│    genome_mutation_v1, local_environment_field_v1,            │
│    resource_lifecycle_runtime_v1, persistent_environmental_   │
│    feedback_v1, snapshot_seam_v1, A10 world bindings          │
└───────────────────────────────────────────────────────────────┘
```

Правила зависимостей: стрелки только вниз (UI → projection → orchestration → canonical). Canonical слой не знает о полигоне. Presentation не вызывает canonical mutation API напрямую и не пишет в Genome/BodyGraph/environment.

## 2. Scene composition — reusable EcologyWorkbench

`EcologyWorkbench` — переиспользуемый компонент полигона (переносимый в основной симулятор), который **ничем не владеет**: ни world, ни player/camera, ни Region, ни Matter, ни persistence. Все внешние зависимости приходят через явный `setup(...)`:

```gdscript
# Контракт (P12; полный skeleton — scripts/ecology/workbench/)
var deps := {
    "world_adapter": <PolygonWorldAdapter or null>,   # WORLD-COMPAT; null => LAB mode
    "environment_source": <A4 field factory / fixture>,
    "snapshot_sink": <A8 seam / observatory session>,
    "clock": <run controls>,
    "presentation": <realizer + projection bindings>,
}
workbench.setup(deps)
```

**LAB host scene — composition root**: она создаёт LAB-фикстуры (`environment_fixture_v1`, `local_environment_field_v1.create`), A8 session (`observatory_session_v1` + `snapshot_seam_v1`) и передаёт их в workbench. В WORLD-COMPAT host подставляет `PolygonWorldAdapterV1` над A10 bindings. Сами сцены полигона не содержат biological logic.

## 3. Threading правила

1. **Один canonical mutation step на session**: `resource_lifecycle_runtime.step_population` + `persistent_environmental_feedback.advance` выполняются последовательно в едином симуляционном контексте; никакого параллельного второго шага над тем же state.
2. **Публикация только completed immutable snapshots**: UI/projection/metrics читают состояние только после завершения tick (через `observatory_session.observe()` / phenotype compile); промежуточные partial state не публикуются.
3. **Abort = join**: ускорение/остановка background-прогона останавливаетсяjoin'ом (дождаться завершения текущего bounded step), а не отменой посреди canonical перехода.
4. **Race fail-closed**: если publication/cursor race обнаружен (hash mismatch, stale snapshot), операция fail-closed — ошибка, никакого «догаданного» продолжения; `snapshot_seam_v1.apply` уже требует `expected_snapshot_hash`.

## 4. Команда UI

Каждое действие пользователя — command, не прямой вызов:

```text
Button → Command (versioned, validated)
       → ExperimentController (orchestration, слой 2)
       → canonical API (слой 1: step_population / feedback.advance /
         genome_mutation.mutate / snapshot_seam.apply / ...)
       → completed snapshot (публикация)
       → Projection → UI update
```

Command-объекты детерминированы, логируются в experiment history (A8/seam commands, MAX_COMMANDS=96 per batch) и составляют replay-журнал ветки. UI никогда не мутирует canonical state в обход контроллера.

## 5. Skeleton-контракты

Каталог `scripts/ecology/workbench/` (P0, skeleton без реализации биологии):

| Файл | Слой | Роль |
|---|---|---|
| `experiment_manifest_v1.gd` | 2 | versioned manifest эксперимента (seed, zones, founders, operators, profile, metrics) |
| `experiment_controller_v1.gd` | 2 | orchestration: run/pause/step/checkpoint/restore/fork; единственный вызывающий canonical mutation step |
| `experiment_branch_v1.gd` | 2 | ветка эксперимента от checkpoint (A8-linked история) |
| `experiment_metrics_v1.gd` | 3 | сбор метрик из completed snapshots |
| `experiment_comparison_v1.gd` | 3 | сравнение веток/seed'ов без скрытого выбора winner |
| `placement_plan_v1.gd` | 2 | рассадка founders по зонам через canonical spatial addressing (A4) |
| `morphology_descriptor_v1.gd` | 3 | derived view над canonical BodyGraph (не второй truth) |
| `generic_morphology_realizer_v1.gd` | 4 | universal procedural realizer (обязательный fallback для неизвестных топологий) |
| `organization_profile_v1.gd` | 2 | FREE/SOFT/EARTH_LIKE/NMS_LIKE/CUSTOM soft bias, versioned, в manifest/provenance |
| `polygon_world_adapter_v1.gd` | 2 | WORLD-COMPAT adapter над A10 bindings (read Region/Matter/Damage; ACTIVE-only; explicit-only Matter mapping) |
