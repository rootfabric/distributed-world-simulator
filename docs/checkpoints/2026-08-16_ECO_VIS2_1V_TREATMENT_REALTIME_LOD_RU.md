# ECO VIS2.1-V — Treatment Realtime LOD

Дата: 2026-08-16

Статус: **WINDOWS_RUNTIME_AND_GRAPHICAL_VALIDATED_CANDIDATE — REVIEW_BLOCKER_REPAIRED, FRESH_REVIEW_REQUIRED**

Не merge. Не self-accept. Этот checkpoint фиксирует exact Windows runtime evidence, graphical confirmation, первый независимый review FAIL и его harness-only repair. Fresh independent re-review остаётся обязательным следующим gate.

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

Previous clean automated candidate before independent review:

`4aa46bb784e4daaf846d0c33ee8d8155f7195e86` — `test(eco): retire VIS2.1-V verbose leak diagnostics`

Independent review correctly found that `4aa46bb...` weakened zero-exit shutdown-leak detection because Godot may emit an ObjectDB leak only as a `WARNING` without `--verbose`.

Exact current Windows-runtime-validated code-under-test after the review blocker repair:

`e26e4da3fdfacc42219d9a55a07d56c9bbff494a` — `test(eco): fail closed on VIS2.1-V shutdown leaks`

`e26e4da...` is harness-only relative to the reviewed runtime candidate: it changes only `RUN_ECO_VIS2_1V_TESTS.ps1`. No production, scene, renderer, CONTROL/TREATMENT, CRN, comparator or causal simulation code changes were made for this repair.

Later documentation commits are intentionally checkpoint-only and are not themselves code-under-test SHAs.

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

The topology repair was reproduced locally against the project-provided exact Godot `4.7.1.stable.double.custom_build.a13da4feb`: the bad inherited-script-state topology reproduced an orphan Node/RefCounted shutdown profile, while the direct VIS2.0 scene topology exited cleanly.

## 7. First independent review and blocking finding

The first fresh independent review returned `FAIL` with one blocker in the acceptance harness, not in production VIS2.1-V architecture.

Finding:

- `4aa46bb...` had removed `--verbose` from the final smoke;
- `Invoke-GodotProcess()` still rejected non-zero exit, `SCRIPT ERROR:`, `ERROR:` and `Parse Error`, but had no explicit shutdown-leak signatures;
- exact Godot can return exit code `0` and emit only `WARNING: 1 ObjectDB instance was leaked at exit ...` for an orphan Node when not using `--verbose`;
- therefore a new shutdown leak plus a valid PASS marker could have been accepted as green.

The reviewer independently reproduced this on exact engine `4.7.1.stable.double.custom_build.a13da4feb` and correctly treated it as a formal-acceptance blocker.

The review's production conclusions were otherwise positive: presentation-only LOD, single Treatment world, data-only Control, unchanged CRN/causality, bounded VIS2.1 caches/comparison, fork+1 Treatment semantics and the `d55c05d...` scene-topology repair were found architecturally sound.

The original `FAIL` remains valid historical evidence and is not retroactively converted to PASS.

## 8. Acceptance-harness repair

Repair commit:

`e26e4da3fdfacc42219d9a55a07d56c9bbff494a` — `test(eco): fail closed on VIS2.1-V shutdown leaks`

Scope:

- exactly one changed file relative to the prior reviewed HEAD: `RUN_ECO_VIS2_1V_TESTS.ps1`;
- no production/runtime code changed.

The repair adds explicit fail-closed patterns independent of verbosity for:

- `ObjectDB instance was leaked at exit`;
- `ObjectDB instances were leaked at exit`;
- `Leaked instance:`;
- `Resource still in use:`;
- `resource/resources still in use at exit`;
- `Orphan StringName:`;
- `StringName: N unclaimed string names at exit`.

The final VIS2.1-V smoke also runs with `--verbose` again.

Existing enforcement remains:

- exact Godot identity;
- timeout/kill;
- redirected stdout/stderr;
- non-zero exit rejection;
- zero-exit `SCRIPT ERROR:` rejection;
- zero-exit `ERROR:` rejection;
- `Parse Error` rejection;
- explicit PASS marker requirement;
- isolated temp project/dependency graph.

The blocker path was also reproduced locally with the project-provided exact Godot: a deliberate orphan Node with exit code `0` and a valid PASS marker emits the non-verbose ObjectDB leak warning, and the new explicit pattern matches it; with `--verbose`, `Leaked instance:`/`ERROR:` provides an additional independent rejection path.

## 9. Exact Windows automated validation after repair — 2026-08-17

Windows worktree executed exact repaired candidate:

`e26e4da3fdfacc42219d9a55a07d56c9bbff494a`

with exact engine:

`4.7.1.stable.double.custom_build.a13da4feb`

Observed gate results:

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
- shutdown leak gate: `STRICT (explicit leak signatures + verbose smoke)`;
- VIS2.1-V Treatment realtime LOD smoke: PASS — 25 assertions;
- VIS2.1-V automated gate: PASS.

The strict verbose smoke ended cleanly. No reported `ObjectDB ... leaked`, `Leaked instance:`, `Resource still in use`, `Orphan StringName`, `ERROR:`, `SCRIPT ERROR:` or parse failure occurred.

This is the current exact automated acceptance evidence.

## 10. Windows graphical validation — 2026-08-16

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

The screenshot visibly shows one rendered Treatment ecology field, active VIS2.1 CONTROL vs TREATMENT charts, non-zero post-fork deltas, data-only CONTROL declaration and realtime Treatment LOD ACTIVE.

The graphical evidence predates the harness-only `e26e4da...` repair. It does not need rerun because that repair changes only the PowerShell acceptance harness and no presentation/runtime files.

A single screenshot is not used as sole proof of every distance transition or causal invariant; those are additionally covered by the automated VIS2.1-V contract and inherited VIS2.1 regression gate.

## 11. Current conclusion

VIS2.1-V is a **Windows-runtime-and-graphical-validated candidate with the first-review harness blocker repaired**.

The production architecture remains unchanged since the first independent review. The exact repaired harness candidate `e26e4da...` has passed the complete Windows gate with strict explicit shutdown-leak detection plus verbose smoke.

This is not yet formal independent acceptance, not authorization to merge, and not permission to skip fresh review.

## 12. Next gate

Run a fresh READ-ONLY independent R1 review on the exact current branch and repaired code-under-test.

The reviewer must specifically verify:

- branch freshness and exact SHAs;
- the previous `FAIL` finding is understood and not erased;
- `e26e4da...` is harness-only and fixes the identified failure mode;
- explicit shutdown-leak signatures are sufficient and not accidentally overbroad/underbroad;
- `--verbose` is restored for the final smoke;
- existing error/PASS-marker/timeout/isolation checks remain intact;
- exact Windows evidence on `e26e4da...` is clean;
- no production/runtime files changed as part of this review repair;
- prior production conclusions (LOD presentation-only, one Treatment field, Control data-only, CRN/fork/boundedness/topology invariants) remain valid because runtime code is unchanged.

Do not modify production, tests or documentation during that review. Do not merge or self-accept.
