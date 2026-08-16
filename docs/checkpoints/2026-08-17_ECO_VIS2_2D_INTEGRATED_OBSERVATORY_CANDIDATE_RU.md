# ECO VIS2.2-D — Integrated Replicated Causal Observatory

Дата: 2026-08-17

Статус: **IMPLEMENTED / ATTACHED_EXACT_ENGINE_FOCUSED_PASS / FULL_WINDOWS_GATE_REQUIRED**

Не merge. Не self-accept. VIS2.2-D пока не Windows-runtime-validated.

## 1. Входная проверенная база

Branch:

`feature/eco-vis2-2-replicated-causal-observatory`

VIS2.2-C Windows-validation checkpoint:

`699c5c30de15c3f5dda487687dfcfc0531c70944`

C code-under-test:

`0532c5334cd0a083b4e2dc1a2711f4ba6fd4e380`

Windows evidence на exact Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- VIS2.2-A: PASS 131 assertions;
- VIS2.2-B R2 canonical aggregate: PASS 218 assertions;
- VIS2.2-C observatory panel: PASS 42 assertions;
- полный `RUN_ECO_VIS2_2C_TESTS.ps1`: PASS;
- strict ObjectDB/RID/resource/StringName/error shutdown gate: clean.

## 2. VIS2.2-D implementation lineage

Initial D orchestration prototype был добавлен как отдельный commit и при локальном exact-engine parser preflight обнаружил два GDScript type-inference defects на dynamic AggregateModel expressions.

Этот prototype superseded и удалён из текущего tree; его история сохранена в git.

Hardened final D class:

`scripts/labs/ecology/eco_vis2_2_integrated_observatory_lab_r1.gd`

commit:

`5b34a926a7dab3ad1bcd040f033ea567f6116d32`

Leak-safe scene pointer/topology commit:

`708e293c34d31ba67760e2316058c46f24aa38ea`

Current scene:

`scenes/labs/ecology/eco_vis2_2_integrated_observatory_lab.tscn`

The scene directly instances validated VIS2.0 PackedScene and applies the final VIS2.2-D script. It does NOT inherit a scripted VIS2.1/VIS2.1-V PackedScene, avoiding the intermediate script-state lifecycle leak class previously discovered in VIS2.1-V.

Current-tree cleanup removing the superseded parser-defective prototype:

`1ec293521d76518c5bb202777ddaac6f3684da3b`

Graphical launcher:

`RUN_ECO_VIS2_2D_LAB.ps1`

## 3. Integrated runtime contract

At replicated fork VIS2.2-D creates one `VIS2.2-A PairSet` from the immutable VIS2.0 fork and one `VIS2.2-B AggregateModel`.

Default replicate count is 8, configurable before fork in the bounded range 2..16.

For each replicate:

- Control and Treatment share one replicate-specific CRN root;
- roots differ between replicates;
- all Control branches remain data-only;
- all nonselected Treatment branches remain data-only.

Exactly one selected Treatment generation map is materialized through the inherited VIS2.1-V realtime near/mid/far LOD renderer.

The VIS2.2-C panel receives only the bounded aggregate summary and presentation selection.

## 4. Selection invariant

Changing selected replicate, including `R0 -> R3 -> R1`, must not change:

- aggregate `series_hash`;
- replicate roots;
- causal generation cursor.

It only changes the selected visible Treatment generation map and panel selection.

State reports:

- `visible_population_fields = 1`;
- `control_data_only = true`;
- `nonselected_treatments_data_only = true`;
- selected field hash;
- aggregate hash/window;
- replicate roots;
- realtime LOD state.

## 5. Canonical aggregate boundary

D never aggregates raw Treatment fork history. It uses:

`PairSet generation maps -> VIS2.2 PairTraceAdapter -> VIS2.1 TraceAdapter -> AggregateModel`.

Thus the canonical boundary repaired in VIS2.2-B R2 is retained in the integrated lab.

## 6. PH5 and source presentation

After replicated fork:

- source VIS2.0 experiment panel is hidden;
- progressive VIS1.9 PH5 is actively cleared by the D guard;
- whole-field PH5 rebuild remains disabled;
- only realtime selected-Treatment proxies are visible.

## 7. Lifecycle ownership

D explicitly owns and releases:

- PairSet, which itself owns Treatment runner Nodes;
- AggregateModel reference;
- VIS2.2-C panel CanvasLayer.

Inherited VIS2.1-V `_exit_tree()` then releases the realtime renderer resources. The inherited single-pair VIS2.1 Treatment runner is explicitly retired during D `_ready()` because D uses the replicated PairSet instead.

## 8. Automated D gate

Current runner:

`RUN_ECO_VIS2_2D_TESTS.ps1`

It first runs the complete Windows-validated C ancestry gate and then executes an isolated D parser/smoke with exact engine identity and strict shutdown leak/error rejection.

Repository D test:

`tests/research/ecology/test_eco_vis2_2_integrated_observatory_lab.gd`

covers:

- G20 replicated fork;
- one visible Treatment field;
- Controls/nonselected Treatments data-only;
- LOD tier accounting;
- G20 -> G34 advance;
- immutable source fork/snapshot;
- R0 -> R3 -> R1 selection invariance;
- observatory panel selection/hash agreement;
- FLOOD switch and further generations;
- replicate-root stability;
- deterministic restart to fork;
- PairSet and panel teardown.

## 9. Attached exact-Godot local evidence

Project-provided binary:

`4.7.1.stable.double.custom_build.a13da4feb`

The hardened R1 script first passed an exact-engine parser and focused integrated runtime probe.

Then the exact repository D test and exact D scene topology were executed locally against a mock dependency graph on the same engine build.

Result:

`ECO.VIS2.2-D integrated observatory lab: PASS (63 assertions)`

Strict post-shutdown scan:

`STRICT_SCAN_PASS`

No `SCRIPT ERROR`, `ERROR`, `Parse Error`, ObjectDB/RID/resource/StringName leak diagnostics were present.

This proves D orchestration/test/scene syntax and integration contracts against the exact engine. It does NOT replace the full real ecology dependency run on the Windows worktree.

## 10. Required next gate

Run the current branch with:

`RUN_ECO_VIS2_2D_TESTS.ps1`

on the exact Windows Godot build. Only after that full gate passes may VIS2.2-D be marked Windows-runtime-validated and graphical D validation proceed.