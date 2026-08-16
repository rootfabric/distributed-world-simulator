# ECO VIS2.1-V — Treatment Realtime LOD

Дата: 2026-08-16

Статус: **WINDOWS_RUNTIME_AND_GRAPHICAL_VALIDATED_CANDIDATE**

Не merge. Не self-accept. Этот checkpoint фиксирует exact Windows runtime evidence и пользовательскую graphical confirmation; fresh independent review остаётся следующим gate.

## 1. Exact topology

Repository:

`rootfabric/distributed-world-simulator`

Branch:

`feature/eco-vis2-1v-treatment-realtime-lod`

Validated VIS2.1 Windows candidate / VIS2.1-V ancestry base:

`39336f31501f15166cd4eb9766b02c98f5bcaf12`

VIS2.1 Windows validation checkpoint inherited by this branch:

`7ed945b037f9360fe0ba05dedd641e5bfa62c14c`

VIS2.1-V implementation lineage begins with:

`de7983ff207c1780649e7fab255554299a78b9d0` — `feat(eco): add VIS2.1-V treatment realtime LOD`

Latest topology/lifecycle production repair:

`d55c05d704b25d310ea0232e4af063bb1afeb767` — `fix(eco): avoid inherited VIS2.1 script-state leak`

Exact Windows-runtime-validated code-under-test:

`4aa46bb784e4daaf846d0c33ee8d8155f7195e86` — `test(eco): retire VIS2.1-V verbose leak diagnostics`

`4aa46bb...` is one harness-only commit after `d55c05d...`; it removes temporary `--verbose` leak diagnostics from `RUN_ECO_VIS2_1V_TESTS.ps1` and does not change runtime semantics.

The later documentation commits are intentionally checkpoint-only and are not themselves code-under-test SHAs.

## 2. Goal

VIS2.1-V restores camera-distance realtime LOD for the single visible TREATMENT population without changing causal simulation and without reintroducing whole-field PH5 rebuild.

CONTROL remains data-only.

## 3. Presentation tiers

VIS2.1-V uses camera-distance bands inherited from the earlier visual-field design:

- NEAR: current realtime trunk + canopy, through 110 m;
- MID: simplified canopy proxy, 75..240 m;
- FAR: cheaper canopy proxy, beginning at 190 m.

Ranges intentionally overlap and use visibility margins so transitions are not a single hard threshold.

Birth/death animation applies to the common plant root and therefore remains compatible with all realtime LOD tiers.

## 4. Architecture boundaries

VIS2.1-V does not redesign:

- CONTROL runner;
- TREATMENT causal runner contract;
- common CRN derivation;
- TraceContract;
- Comparator;
- bounded rolling caches;
- canonical comparison;
- Treatment environment forcing.

The new renderer is presentation-only and subclasses the existing VIS1.8A realtime proxy renderer.

After fork the intended topology remains:

- CONTROL = data-only;
- TREATMENT = the only visible ecology population;
- progressive PH5 = OFF;
- whole-field PH5 rebuild = 0;
- realtime LOD = near/mid/far.

## 5. UI cleanup

After creation of the paired fork, the inherited left VIS2.0 source panel is hidden because it describes the BASELINE source provider and can otherwise be mistaken for the active Treatment profile.

The authoritative post-fork presentation remains the VIS2.1 CONTROL vs TREATMENT comparison UI plus the visible Treatment field.

## 6. Lifecycle / topology repair provenance

The Windows shutdown investigation exposed a real derived-scene ownership issue rather than a simulation failure.

Relevant repair chain:

- `72a53503f7085db0be79c1f8d5e031ad56c5b447` — test teardown ordering for the replacement renderer;
- `491d3990edd8efeb18c95f6e02971a4c4a9334d6` — wait for teardown completion before smoke exit;
- `ad0895ab65a23a76fd13a2531c4c8da1240e3624` — release renderer resources on scene exit;
- `2fbf3aa0385740e1f5b9eb5e55b804de45f3bcc9` — explicitly free the inherited VIS2.1 Treatment data runner on scene exit;
- `82978088e0b42cc6b606a74894a0579abab2520a` — assert Treatment runner teardown;
- `d55c05d704b25d310ea0232e4af063bb1afeb767` — remove the derived-scene script-state collision by instancing the VIS2.0 scene directly while the VIS2.1-V script itself extends the VIS2.1 integration script, and add a small paired-mode progressive-PH5 guard node.

The final VIS2.1-V script owns cleanup of the dynamically attached Treatment runner and replacement realtime renderer in `_exit_tree()`.

The temporary verbose leak diagnostics were then retired in:

`4aa46bb784e4daaf846d0c33ee8d8155f7195e86`

without weakening parser/error/PASS-marker enforcement.

The final topology repair was also reproduced and checked locally against the project-provided exact Godot `4.7.1.stable.double.custom_build.a13da4feb`; the bad inherited-script-state topology reproduced an orphan Node/RefCounted shutdown profile, while the direct VIS2.0 scene topology exited cleanly.

## 7. Test contract

`RUN_ECO_VIS2_1V_TESTS.ps1` first executes the full validated VIS2.1 causal/boundedness gate and then creates an isolated ecology project for VIS2.1-V.

It verifies, among other things:

- exact custom Godot identity;
- isolated ecology dependency graph;
- parser preflight;
- custom LOD renderer installed;
- paired fork operation;
- VIS2.0 source panel hidden after fork;
- near/mid/far thresholds;
- all three tiers on live Treatment proxies;
- camera movement does not alter canonical simulation traces;
- paired progression continues;
- CONTROL remains data-only;
- visible population field count remains one;
- progressive/whole-field PH5 remains absent after fork;
- LOD tiers follow turnover population;
- common CRN root is preserved;
- Treatment runner and VIS2.1-V-owned presentation resources tear down cleanly.

The runner keeps timeout/kill behavior, redirected stdout/stderr, zero-exit Godot error scanning and explicit PASS-marker checking.

## 8. Exact Windows automated validation — 2026-08-16

Windows worktree executed exact candidate:

`4aa46bb784e4daaf846d0c33ee8d8155f7195e86`

with exact engine:

`4.7.1.stable.double.custom_build.a13da4feb`

Observed gate results:

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
- VIS2.1-V Treatment realtime LOD smoke: PASS — 25 assertions;
- VIS2.1-V automated gate: PASS.

The final clean run emitted no reported Godot `ERROR`, `SCRIPT ERROR`, parser failure, leaked-instance diagnostic, `ObjectDB` leak, or `Resource still in use` diagnostic.

The same topology repair had already passed once at `d55c05d...` with verbose diagnostics enabled; `4aa46bb...` repeated the complete gate after removing the temporary diagnostic verbosity.

## 9. Windows graphical validation — 2026-08-16

The isolated graphical launcher `RUN_ECO_VIS2_1V_LAB.ps1` was launched successfully on Windows and the user confirmed the client/lab is working.

Captured paired runtime state from the graphical session:

- stage: `ECO.VIS2.1-V`;
- playback: `PLAY`;
- fork generation: `G31`;
- paired generation: `G73`;
- Treatment profile: `DROUGHT 100%`;
- visible Treatment reps: `55`;
- CONTROL: `reps=56 fitness=0.915 genomes=56`;
- TREATMENT: `reps=55 fitness=0.892 genomes=55`;
- DELTA: `population=-1 fitness=-0.0231 genomes=-1 deaths=+1 alpha_share=+0.0094`;
- visible fields: `1`;
- Treatment LOD status: `ACTIVE`;
- thresholds displayed: `near<=110m mid=75..240m far>=190m`;
- tier accounting displayed: `55/55/55` for near/mid/far tier nodes.

The screenshot visibly shows:

- one rendered Treatment ecology field;
- active VIS2.1 CONTROL vs TREATMENT comparison charts;
- non-zero post-fork causal deltas;
- data-only CONTROL declaration in the HUD;
- realtime Treatment LOD declared ACTIVE;
- paired evolution continuing at G73 after fork G31;
- no second rendered CONTROL plant field.

The user explicitly reported that the client started and everything works. This graphical evidence is treated as confirmation of the intended VIS2.1-V presentation path. A single screenshot is not used as sole proof of every distance transition or causal invariant; those are additionally covered by the automated 25-assertion VIS2.1-V contract and inherited VIS2.1 regression gate.

## 10. Current conclusion

VIS2.1-V is now a **Windows-runtime-and-graphical-validated candidate**.

The prior lifecycle/topology leak is not reproduced on the exact final code-under-test, all inherited VIS2.1 causal/deterministic/boundedness regressions remain green, and the graphical lab operates in paired Treatment realtime-LOD mode with one visible ecology field.

This is not an independent acceptance and not authorization to merge.

## 11. Next gate

Hand the exact candidate and this checkpoint to a fresh READ-ONLY independent reviewer.

The reviewer must specifically re-check:

- scope/topology from validated VIS2.1 base through VIS2.1-V;
- presentation-only nature of LOD;
- CONTROL remains data-only;
- exactly one visible ecology population;
- no whole-field PH5 rebuild after fork;
- camera movement cannot mutate canonical traces;
- common CRN and Treatment causal semantics remain unchanged;
- bounded VIS2.1 caches/comparison remain inherited and green;
- shutdown/resource lifecycle repair and the derived-scene topology fix;
- strict runner behavior and exact-engine evidence;
- graphical evidence without overclaiming what one screenshot proves.

Do not modify production, tests or documentation during that review. Do not merge or self-accept.
