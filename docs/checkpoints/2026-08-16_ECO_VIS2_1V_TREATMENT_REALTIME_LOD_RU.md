# ECO VIS2.1-V — Treatment Realtime LOD

Дата: 2026-08-17

Статус: **WINDOWS_RUNTIME_AND_GRAPHICAL_VALIDATED_CANDIDATE — TWO REVIEW BLOCKERS REPAIRED, FRESH REVIEW REQUIRED**

Не merge. Не self-accept. Этот checkpoint фиксирует exact Windows runtime evidence, graphical confirmation, два корректных independent-review FAIL и их harness-only repairs. Fresh independent re-review остаётся обязательным следующим gate.

## 1. Exact topology

Repository:

`rootfabric/distributed-world-simulator`

Branch:

`feature/eco-vis2-1v-treatment-realtime-lod`

Validated VIS2.1 ancestry base:

`39336f31501f15166cd4eb9766b02c98f5bcaf12`

VIS2.1 Windows-validation checkpoint inherited by this branch:

`7ed945b037f9360fe0ba05dedd641e5bfa62c14c`

VIS2.1-V implementation lineage begins with:

`de7983ff207c1780649e7fab255554299a78b9d0` — `feat(eco): add VIS2.1-V treatment realtime LOD`

Latest production topology/lifecycle repair:

`d55c05d704b25d310ea0232e4af063bb1afeb767` — `fix(eco): avoid inherited VIS2.1 script-state leak`

First clean automated candidate before review:

`4aa46bb784e4daaf846d0c33ee8d8155f7195e86`

First harness repair after review #1:

`e26e4da3fdfacc42219d9a55a07d56c9bbff494a` — `test(eco): fail closed on VIS2.1-V shutdown leaks`

Exact current Windows-runtime-validated code-under-test after review #2 repair:

`3546520b744f3bf6e6dffc1a7fe7ef7d500e6f70` — `test(eco): reject VIS2.1-V RID shutdown leaks`

`3546520...` is harness-only relative to the previously reviewed branch state. It changes only `RUN_ECO_VIS2_1V_TESTS.ps1`; no production/runtime/scene/renderer/CONTROL/TREATMENT/CRN/comparator/cache/test code changed in this repair.

Later documentation commits are checkpoint-only and are not code-under-test SHAs.

## 2. Goal and presentation contract

VIS2.1-V restores camera-distance realtime LOD for the single visible TREATMENT population without changing causal simulation and without reintroducing whole-field PH5 rebuild.

Expected paired topology after fork:

- CONTROL = data-only;
- TREATMENT = exactly one visible ecology population;
- progressive PH5 = OFF;
- whole-field PH5 rebuild = 0;
- realtime Treatment LOD = NEAR / MID / FAR.

LOD ranges:

- NEAR: through approximately 110 m;
- MID: approximately 75..240 m;
- FAR: beginning around 190 m.

The renderer remains presentation-only; camera movement is not an input to canonical causal simulation or trace state.

## 3. Production architecture remains unchanged by review repairs

The two review repairs modify only the PowerShell acceptance harness.

The following validated production conclusions remain unchanged:

- ControlRunner and TreatmentRunner causal contracts are unchanged;
- common-random-number derivation is unchanged;
- Treatment begins at fork+1, not at fork;
- comparator/trace semantics are unchanged;
- rolling branch caches and comparison windows remain bounded;
- CONTROL remains data-only;
- only TREATMENT is rendered after fork;
- no second ecology world is introduced;
- whole-field PH5 does not return after fork;
- `d55c05d...` direct-VIS2.0 scene topology removes the intermediate scripted PackedScene state that previously created an orphan TreatmentRunner;
- VIS2.1-V explicitly tears down the dynamic Treatment runner and replacement realtime renderer resources.

## 4. Lifecycle/topology repair provenance

Relevant lifecycle repair chain before independent review:

- `72a53503f7085db0be79c1f8d5e031ad56c5b447` — test teardown ordering;
- `491d3990edd8efeb18c95f6e02971a4c4a9334d6` — finish smoke after teardown returns;
- `ad0895ab65a23a76fd13a2531c4c8da1240e3624` — release renderer resources on scene exit;
- `2fbf3aa0385740e1f5b9eb5e55b804de45f3bcc9` — explicitly free Treatment data runner on scene exit;
- `82978088e0b42cc6b606a74894a0579abab2520a` — assert Treatment runner teardown;
- `d55c05d704b25d310ea0232e4af063bb1afeb767` — avoid inherited VIS2.1 script-state leak by instancing VIS2.0 directly while the final VIS2.1-V script extends VIS2.1 integration logic.

The bad and repaired scene topologies were reproduced locally against the project-provided exact Godot `4.7.1.stable.double.custom_build.a13da4feb`. The old inherited-script-state topology reproduced orphan Node/RefCounted shutdown behavior; the repaired direct-VIS2.0 topology exited cleanly.

## 5. Independent review #1 — valid FAIL

The first fresh independent review returned `FAIL` with one acceptance-harness blocker.

Finding:

- `4aa46bb...` removed `--verbose` from the final smoke;
- `Invoke-GodotProcess()` rejected non-zero exit, `SCRIPT ERROR:`, `ERROR:` and `Parse Error`, but did not explicitly reject shutdown-leak warnings;
- exact Godot can return exit code `0` and emit only `WARNING: 1 ObjectDB instance was leaked at exit ...` for an orphan Node;
- therefore the harness could falsely accept a leaking run with a valid PASS marker.

The finding was independently reproduced on exact engine `4.7.1.stable.double.custom_build.a13da4feb`.

The first repair:

`e26e4da3fdfacc42219d9a55a07d56c9bbff494a`

restored `--verbose` and added explicit shutdown-leak detection for ObjectDB, leaked instances, resources and StringName diagnostics while preserving timeout/error/PASS-marker enforcement.

The original `FAIL` remains valid historical evidence and is not retroactively changed.

## 6. Independent review #2 — valid FAIL

The second fresh independent review confirmed that `e26e4da...` closed the original ObjectDB failure mode, but found a second real false-negative in the declared STRICT shutdown-leak gate.

Exact-engine negative control:

```gdscript
extends SceneTree

var leaked_rid: RID

func _initialize() -> void:
    leaked_rid = RenderingServer.canvas_item_create()
    print("ECO_TEST_PASS")
    quit(0)
```

On exact Godot `4.7.1.stable.double.custom_build.a13da4feb`, this can exit with code `0` and emit:

`WARNING: 1 RID of type "CanvasItem" was leaked.`

The same RID warning remains a warning even with `--verbose`; the prior leak patterns did not reject it. For a realtime LOD renderer this is a directly relevant resource-lifecycle failure class.

Therefore review #2 correctly returned `FAIL`.

This `FAIL` also remains valid historical evidence.

## 7. RID/shutdown-leak gate repair

Repair commit:

`3546520b744f3bf6e6dffc1a7fe7ef7d500e6f70` — `test(eco): reject VIS2.1-V RID shutdown leaks`

Scope:

- one changed file: `RUN_ECO_VIS2_1V_TESTS.ps1`;
- no production/runtime/test changes.

The repair centralizes shutdown-leak detection in `Test-GodotShutdownLeakOutput` and covers:

- ObjectDB leak warnings;
- `Leaked ...` diagnostics;
- `Resource still in use` / resources still in use at exit;
- StringName orphan/unclaimed diagnostics;
- singular RID leak: `1 RID of type ... was leaked`;
- plural RID leak: `N RIDs of type ... were leaked`;
- RID allocation leak form: `RID allocations of type ... were leaked at exit`;
- renderer cache `still in use` warnings such as framebuffer/uniform-set cache instances;
- a general warning fallback containing `leak/leaked/leaking` or `still in use`.

The runner retains `--verbose` for the final smoke as defense in depth.

It also runs `Assert-GodotShutdownLeakMatcherCoverage` before the engine gate. The self-check includes positive leak fixtures for ObjectDB, RID singular/plural, RID allocations, framebuffer/uniform-set cache, leaked instance, resource and StringName forms, plus benign fixtures that must not false-positive.

Exact attached-engine probing additionally reproduced both:

- `WARNING: 1 RID of type "CanvasItem" was leaked.`
- `WARNING: 2 RIDs of type "CanvasItem" were leaked.`

and the repair matcher rejects them.

## 8. Acceptance harness contract after `3546520...`

`RUN_ECO_VIS2_1V_TESTS.ps1` now preserves all previous strictness:

- exact Godot identity;
- isolated temp project/dependency graph;
- parser preflight;
- timeout + Kill();
- asynchronously redirected stdout/stderr;
- non-zero exit rejection;
- zero-exit `SCRIPT ERROR:` rejection;
- zero-exit `ERROR:` rejection;
- `Parse Error` rejection;
- explicit PASS marker requirement;
- explicit shutdown leak matcher independent of verbosity;
- `--verbose` final smoke as additional diagnostics;
- matcher self-coverage gate before real execution.

## 9. Exact Windows automated validation after RID repair — 2026-08-17

Windows worktree executed exact candidate:

`3546520b744f3bf6e6dffc1a7fe7ef7d500e6f70`

with exact engine:

`4.7.1.stable.double.custom_build.a13da4feb`

Observed results:

- `ECO.VIS2.1-V shutdown leak matcher coverage: PASS`;
- ECO.VIS2.1-V exact Godot identity: PASS;
- ECO.VIS2.1 exact Godot identity: PASS;
- ECO.VIS2.1 isolated dependency graph: PASS;
- ECO.VIS2.1 parser preflight: PASS;
- CONTROL runner: PASS — 82 assertions;
- TREATMENT R1 runner: PASS — 96 assertions;
- Comparator R1: PASS — 82 assertions;
- VIS1.8B regression: PASS — 51 assertions;
- VIS1.9 regression: PASS — 29 assertions;
- VIS2.0 regression: PASS — 33 assertions;
- VIS2.1 integration: PASS — 57 assertions;
- VIS2.1 long smoke G20..G220 with rolling eviction: PASS;
- VIS2.1 integrated boundedness/performance gate: PASS;
- VIS2.1 isolated gate: PASS — 7 scripts + parser preflight;
- VIS2.1-V isolated ecology dependency graph: PASS;
- VIS2.1-V parser preflight: PASS;
- shutdown leak gate: `STRICT (ObjectDB + RID + resources + StringName + verbose smoke)`;
- VIS2.1-V Treatment realtime LOD smoke: PASS — 25 assertions;
- VIS2.1-V automated gate: PASS.

The verbose smoke ended cleanly with no reported ObjectDB/RID/resource/StringName leak, `ERROR:`, `SCRIPT ERROR:` or parse failure.

This is the current exact automated acceptance evidence.

## 10. Windows graphical validation

The isolated graphical launcher was previously executed successfully and the user confirmed the lab works.

Captured state included:

- `fork=G31`;
- `paired=G73`;
- `DROUGHT 100%`;
- CONTROL `reps=56 fitness=0.915 genomes=56`;
- TREATMENT `reps=55 fitness=0.892 genomes=55`;
- non-zero post-fork deltas;
- `visible_fields=1`;
- LOD `ACTIVE`;
- thresholds `near<=110m mid=75..240m far>=190m`;
- CONTROL data-only.

The later repairs are PowerShell harness-only, so this graphical evidence remains applicable and does not need repetition.

## 11. Current conclusion

VIS2.1-V is a **Windows-runtime-and-graphical-validated candidate with both independently found acceptance-harness blockers repaired**.

The production architecture has not changed since the original production review. The exact current code-under-test `3546520...` has passed the full Windows gate with matcher self-coverage and strict ObjectDB/RID/resource/StringName shutdown detection plus verbose smoke.

This is not yet formal independent acceptance and not authorization to merge.

## 12. Next gate

Run a fresh READ-ONLY independent review on exact code-under-test `3546520...` and the documentation-only current branch HEAD.

The reviewer must specifically verify:

- both previous FAIL findings remain understood and preserved;
- repair scope is harness-only;
- the RID singular/plural/RID-allocation forms are rejected at exit code 0;
- matcher fallback does not create material false positives;
- matcher self-coverage itself cannot trivially pass while `Invoke-GodotProcess()` uses a different predicate;
- `--verbose` remains defense in depth rather than the sole RID detector;
- existing timeout/error/PASS-marker/isolation checks remain intact;
- exact Windows evidence on `3546520...` is clean;
- no reason exists to invalidate prior production or graphical conclusions.

Do not modify production, tests or documentation during review. Do not merge or self-accept.
