# ECO EVO7 / ECO-VIS2 — Procedural Plant Renderer R2.1

## Причина

R2 candidate `025048067c20942f501412438d6395cb69bf8630` исправил явный scene launch и визуальную читаемость, но Windows focused acceptance выявил platform-specific lifecycle ordering defect:

- VIS1: PASS 41/41;
- VIS2: FAIL 69 assertions, 1 failure;
- failure: `VIS2 replaces inherited VIS1 top title`.

Probe доказал, что при `--script` тест завершается из `SceneTree._init()` до первой итерации main loop. Поэтому node `_ready()`, где R2 применял VIS2 identity, срабатывает слишком поздно. Ручной вызов `_apply_vis2_identity()` немедленно делает assertion зелёным.

## R2.1 repair

Тест не ослабляется и arbitrary frame wait не добавляется.

`initialize_runtime()` теперь синхронно выполняет:

1. `ensure_ui_built()`;
2. `_apply_vis2_identity()`;
3. `_ensure_vis2_ui()`;
4. затем base Workbench initialization.

`_ready()` остаётся обычным graphical runtime path.

Таким образом runtime identity и UI composition больше не зависят от наличия первого frame в `--script` acceptance.

Runtime revision: `ECO.EVO7-VIS2.R2.1`.

## Authority

Repair не затрагивает biology, phenotype evidence, genome, fitness, population authority, persistence или network authority. Это только initialization ordering presentation/test-harness hardening.

## Expected Windows focused result

```text
ECO.EVO7 VIS1 Spatial World Viewer: PASS (41 assertions)
ECO.EVO7 VIS2 Procedural Plant Renderer: PASS (69 assertions)
```

После focused PASS требуется один graphical window run на exact R2.1 head с:

```text
ECO.EVO7 VIS2 READY scene=EcoEvo7VIS2ProceduralPlantViewer revision=ECO.EVO7-VIS2.R2.1
```
