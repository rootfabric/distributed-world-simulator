# ECO VIS2.1-V — Independent Acceptance R2

Дата: 2026-08-17

Статус: **INDEPENDENT PASS / VIS2.1-V FORMALLY CLOSED**

Этот checkpoint фиксирует branch-local formal acceptance исследовательско-визуального этапа ECO VIS2.1-V. Он не является merge в `main`, не изменяет production authority/persistence/network ownership и не означает глобальное принятие всей ECO программы.

## 1. Exact identities

Repository:

`rootfabric/distributed-world-simulator`

Branch:

`feature/eco-vis2-1v-treatment-realtime-lod`

Validated VIS2.1 ancestry base:

`39336f31501f15166cd4eb9766b02c98f5bcaf12`

Latest production topology/lifecycle repair:

`d55c05d704b25d310ea0232e4af063bb1afeb767` — `fix(eco): avoid inherited VIS2.1 script-state leak`

Final exact Windows-runtime-validated code-under-test:

`3546520b744f3bf6e6dffc1a7fe7ef7d500e6f70` — `test(eco): reject VIS2.1-V RID shutdown leaks`

Pre-acceptance documentation HEAD reviewed for freshness:

`2caa86eec565a9f4a633935049d691a9c8cfa73b`

The acceptance commit containing this file is documentation-only and is intentionally newer than the tested code-under-test SHA.

## 2. Accepted capability

VIS2.1-V provides camera-distance realtime LOD for the single visible TREATMENT population while preserving the accepted VIS2.1 causal experiment model.

Accepted paired topology after fork:

- CONTROL = data-only;
- TREATMENT = exactly one visible ecology population;
- realtime LOD = NEAR / MID / FAR;
- progressive PH5 = OFF;
- whole-field PH5 rebuild = 0;
- camera motion is presentation-only and cannot mutate canonical experiment traces.

Accepted presentation thresholds:

- NEAR through approximately 110 m;
- MID approximately 75..240 m;
- FAR beginning approximately 190 m.

## 3. Preserved causal invariants

Independent review confirmed no blocker in production architecture and no causal redesign after the validated VIS2.1 base:

- ControlRunner remains data-only;
- Treatment begins at fork+1;
- common-random-number root remains shared and unchanged;
- Treatment divergence enters through environment/fitness rather than branch RNG salt;
- Comparator/TraceContract semantics remain unchanged;
- rolling branch caches/comparison windows remain bounded;
- exactly one Treatment ecology field is rendered;
- no whole-field PH5 rebuild returns after fork.

## 4. Lifecycle repair accepted

The derived-scene lifecycle defect was traced to a scripted inherited PackedScene creating an intermediate VIS2.1 script-state and orphan TreatmentRunner before the final VIS2.1-V root script replaced it.

Accepted repair `d55c05d...` instances the VIS2.0 scene directly while the final VIS2.1-V script extends VIS2.1 integration logic, preserving VIS2.1 semantics without creating the intermediate scripted PackedScene state.

VIS2.1-V also explicitly tears down its Treatment runner and realtime renderer-owned resources.

The bad and repaired topologies were reproduced against exact Godot `4.7.1.stable.double.custom_build.a13da4feb`; the repaired topology exited cleanly.

## 5. Independent review history

Two earlier independent FAIL verdicts remain valid historical evidence.

### FAIL #1 — ObjectDB zero-exit leak false-green

The old harness could accept:

`WARNING: 1 ObjectDB instance was leaked at exit ...`

with exit code 0 and a valid PASS marker.

Repair:

`e26e4da3fdfacc42219d9a55a07d56c9bbff494a`

restored `--verbose` and explicit ObjectDB/resource/StringName shutdown detection.

### FAIL #2 — RenderingServer RID zero-exit leak false-green

A second fresh review reproduced on the exact engine:

`WARNING: 1 RID of type "CanvasItem" was leaked.`

and plural RID variants with exit code 0.

Repair:

`3546520b744f3bf6e6dffc1a7fe7ef7d500e6f70`

centralized shutdown matching and added RID singular/plural/allocation plus renderer-cache `still in use` coverage and matcher self-tests.

Neither historical FAIL is retroactively erased.

## 6. Final acceptance harness

Final `RUN_ECO_VIS2_1V_TESTS.ps1` acceptance behavior includes:

- exact Godot identity;
- isolated temp project/dependency graph;
- parser preflight;
- timeout + Kill();
- async redirected stdout/stderr;
- non-zero exit rejection;
- zero-exit `SCRIPT ERROR:` rejection;
- zero-exit `ERROR:` rejection;
- `Parse Error` rejection;
- required PASS marker;
- explicit shutdown matching independent of verbosity for ObjectDB, RID, resources, StringName and leak/still-in-use warnings;
- `--verbose` final smoke as defense in depth;
- matcher self-coverage fixtures exercising the same predicate used by the real process path.

## 7. Exact Windows evidence

Exact engine:

`4.7.1.stable.double.custom_build.a13da4feb`

Exact code-under-test:

`3546520b744f3bf6e6dffc1a7fe7ef7d500e6f70`

Final observed results:

- shutdown leak matcher coverage: PASS;
- VIS2.1-V exact Godot identity: PASS;
- CONTROL runner: PASS — 82 assertions;
- TREATMENT R1 runner: PASS — 96 assertions;
- Comparator R1: PASS — 82 assertions;
- VIS1.8B: PASS — 51 assertions;
- VIS1.9: PASS — 29 assertions;
- VIS2.0: PASS — 33 assertions;
- VIS2.1 integration: PASS — 57 assertions;
- VIS2.1 rolling-cache long smoke G20..G220: PASS;
- VIS2.1 boundedness/performance: PASS;
- VIS2.1-V parser preflight: PASS;
- shutdown gate: `STRICT (ObjectDB + RID + resources + StringName + verbose smoke)`;
- VIS2.1-V Treatment realtime LOD: PASS — 25 assertions;
- final `ECO.VIS2.1-V automated gate: PASS`.

No ObjectDB/RID/resource/StringName leak diagnostics or Godot parser/runtime errors were emitted by the final strict smoke.

## 8. Graphical evidence

Windows graphical validation was completed before the harness-only review repairs and remains valid because those repairs changed only PowerShell acceptance tooling.

Captured paired state included:

- fork `G31`;
- paired generation `G73`;
- Treatment `DROUGHT 100%`;
- one visible Treatment ecology field;
- CONTROL data-only;
- realtime LOD `ACTIVE`;
- displayed thresholds `near<=110m`, `mid=75..240m`, `far>=190m`;
- non-zero Control/Treatment deltas.

The user confirmed the graphical lab launched and worked.

## 9. Final fresh independent R2 verdict

Freshness was confirmed against exact pre-acceptance branch HEAD:

`2caa86eec565a9f4a633935049d691a9c8cfa73b`

The independent reviewer confirmed:

- both prior FAIL verdicts were valid;
- `3546520...` is harness-only;
- ObjectDB zero-exit leaks are rejected;
- RID singular, plural and allocation leak forms are rejected;
- resource/cache/StringName shutdown leak forms are rejected;
- matching is independent of `--verbose`;
- `--verbose` remains defense in depth;
- matcher self-coverage exercises the same real predicate;
- false-positive and false-negative risks are acceptable for the pinned exact engine and current stage;
- all prior timeout/error/PASS-marker/isolation gates remain intact;
- no new blocker was introduced;
- prior production and graphical conclusions remain valid.

Final verdict:

`PASS`

## 10. Closure

**VIS2.1-V is formally accepted and closed.**

Development may proceed to the next ECO visual/evolution research stage.

Boundary preserved:

`research ecology state != visual observer state != production/network authority`

No merge to `main` is authorized by this checkpoint alone.
