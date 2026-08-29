# V0 SM1 / B6 R9 — Fresh Exact-Head Machine Re-Verifier Instruction

Repository: rootfabric/distributed-world-simulator

Role: FRESH INDEPENDENT READ-ONLY VERIFIER
Risk: CRITICAL
Work Order: V0-SM1-R1-WO-001
Checkpoint: V0_SM1_SEAMLESS_PRODUCT_INTEGRATION

Historical verifier records:
- V0-SM1-R1-WO-001-VERIFICATION-001.v1.json = FAILED on the old composite subject;
- V0-SM1-R1-WO-001-VERIFICATION-002.v1.json = FAILED on R8 after the first canonical regression stopped at M7.

Required new verifier record:
V0-SM1-R1-WO-001-VERIFICATION-003.v1.json

## 0. Role boundary

You are not the Implementer, previous Verifier, Reviewer, Director, R9 Windows validation agent, or Human approver.

The R9 Windows V2 PASS is prior evidence only. It is not a substitute for your own execution.

Do not modify runtime, tests, fixtures, contracts, harness implementation, production docs, PR metadata, or branch metadata.
Do not repair failures.
Do not merge any PR.
Do not accept SM1.
Do not start B7.
Do not activate P7.
Do not silently rerun a failed governed M7 series, M5 decisive series, or canonical regression and report only a later pass.

Your machine verdict is exactly one of:

VERIFIED | FAILED | INSUFFICIENT_EVIDENCE

## 1. Exact repaired composite subject

The B6 subject is exact R9. R9 contains the original SM1 composite subject, the validated R8 M5 continuity repair, and the bounded two-file M7 camera-basis repair.

~~~text
SUBJECT_HEAD = b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
SUBJECT_TREE = 7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68
SUBJECT_BRANCH = repair/m7-camera-basis-sync-r9

R8_HEAD = b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
R8_TREE = 7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68

OLD_SUBJECT_HEAD = 6fdfc047f54e727e6b398370e576c746c7949441
OLD_SUBJECT_TREE = b9b1202d959b3da4a0c73840091c7bf56070429e

SOURCE_SM1_HEAD = b270fb806038333c97fa1ed49655961adddd6a21

R7_HEAD = baa0e192209e72aba5ae9d04663eea85b1099e82
R7_TREE = 08f01fd955c2d31c1ad49aa917e542c93e278241
~~~

Expected ancestry/composition:

- OLD_SUBJECT_HEAD is an ancestor of SUBJECT_HEAD;
- SOURCE_SM1_HEAD is an ancestor of SUBJECT_HEAD;
- R8_HEAD is the direct repair base ancestor of SUBJECT_HEAD;
- SUBJECT_HEAD is exactly 48 commits ahead of OLD_SUBJECT_HEAD;
- SUBJECT_HEAD is exactly 9 commits ahead of R7_HEAD;
- R8 -> R9 delta is exactly 2 commits / 2 files.

R9 changed paths exactly:

~~~text
tools/runtime/m7_playable_network_client.gd
tests/runtime/test_m7_playable_networked_processes.gd
~~~

R9 must not change M5 convergence, network protocol, server authority, pickup range, visibility thresholds, SM1 runtime, or P6/P7 surfaces.

## 2. Fresh materialization

Use a brand-new checkout not used by the Implementer, R9 Windows validator, previous B6 Verifier, or any prior validation attempt.

~~~powershell
git clone https://github.com/rootfabric/distributed-world-simulator.git C:\dws-sm1-b6-r9-verifier
cd C:\dws-sm1-b6-r9-verifier
git fetch origin --prune
git checkout --detach b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
~~~

Before execution:

~~~powershell
$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()
$Status = @(git status --porcelain)

Write-Host "HEAD=$Head"
Write-Host "TREE=$Tree"

if ($Head -ne "b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f") { throw "SUBJECT_HEAD_MISMATCH" }
if ($Tree -ne "7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68") { throw "SUBJECT_TREE_MISMATCH" }
if ($Status.Count -ne 0) { throw "SUBJECT_NOT_CLEAN_BEFORE_EXECUTION" }
~~~

Prove ancestry/composition:

~~~powershell
git merge-base --is-ancestor 6fdfc047f54e727e6b398370e576c746c7949441 b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
if ($LASTEXITCODE -ne 0) { throw "OLD_SUBJECT_ANCESTRY_FAILED" }

git merge-base --is-ancestor b270fb806038333c97fa1ed49655961adddd6a21 b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
if ($LASTEXITCODE -ne 0) { throw "SOURCE_SM1_ANCESTRY_FAILED" }

git merge-base --is-ancestor b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
if ($LASTEXITCODE -ne 0) { throw "R8_BASE_ANCESTRY_FAILED" }

git rev-list --count 6fdfc047f54e727e6b398370e576c746c7949441..b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
git rev-list --count baa0e192209e72aba5ae9d04663eea85b1099e82..b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
git rev-list --count b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f..b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
git diff --name-only b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f..b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
~~~

Expected counts: 48, 9, 2, and exactly the two R9 paths above.


## 3. Exact Godot identity

Required identity:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

Windows:

~~~powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$VersionOutput = & $env:GODOT_BIN --version 2>&1
$Version = ($VersionOutput | Select-Object -First 1).ToString().Trim()
Write-Host "Godot=$Version"
if ($Version -ne "4.7.1.stable.double.custom_build.a13da4feb") { throw "GODOT_IDENTITY_MISMATCH: $Version" }
$global:LASTEXITCODE = 0
~~~

Important: this Windows Godot build can print the correct version while leaving a non-zero native LASTEXITCODE. Compare the version string explicitly. Do not classify that version-only behavior as a candidate failure.

If exact Godot is unavailable: INSUFFICIENT_EVIDENCE.


## 4. Fresh governed R9 M7 stability

This is the direct R9 repair gate. It must use the repository-equivalent isolated validation environment.

First create an isolated editor-import profile and perform a clean editor import. Then each M7 attempt gets a fresh isolated parent profile with HOME, USERPROFILE, APPDATA, LOCALAPPDATA, XDG_DATA_HOME, XDG_CONFIG_HOME, XDG_CACHE_HOME, BREAKPOINT_RUNTIME_DISABLED=1, GODOT_SILENCE_ROOT_WARNING=1, and PLANET_SIMULATOR_INVENTORY_PROFILE=planet_default.

The historical direct-shell R9 attempt that failed on Seven Days UI/profile assertions is classified as INVALID_VALIDATION_ENVIRONMENT and must not be inherited as a candidate verdict.

Required editor import:

~~~powershell
$VerifierProfiles = Join-Path $PWD ("artifacts\test-results\b6-r9-verifier-profiles-" + $PID)
$ImportProfile = Join-Path $VerifierProfiles "editor-import"
$env:HOME = $ImportProfile
$env:USERPROFILE = $ImportProfile
$env:APPDATA = Join-Path $ImportProfile "data"
$env:LOCALAPPDATA = Join-Path $ImportProfile "data"
$env:XDG_DATA_HOME = Join-Path $ImportProfile "data"
$env:XDG_CONFIG_HOME = Join-Path $ImportProfile "config"
$env:XDG_CACHE_HOME = Join-Path $ImportProfile "cache"
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
$env:GODOT_SILENCE_ROOT_WARNING = "1"
$env:PLANET_SIMULATOR_INVENTORY_PROFILE = "planet_default"
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:XDG_CONFIG_HOME,$env:XDG_CACHE_HOME | Out-Null

& $env:GODOT_BIN --headless --editor --path $PWD --quit
if ($LASTEXITCODE -ne 0) { throw "EDITOR_IMPORT_FAILED" }
~~~

Then run one consecutive M7 series of exactly 10 attempts. Before each attempt, assign a fresh isolated parent profile using the same environment variables above.

Each run must produce:

~~~text
M7 playable network processes: 54 assertions, 0 failures
~~~

Required final result: 10/10, one governed series, zero replacement runs.

If any governed run fails: STOP; preserve the first failure; do not restart the 10x series; do not run M5 decisive or canonical.

Semantic R9 checks that must be true in exact subject bytes:
- _set_automated_camera_yaw exists;
- it computes a wrapped yaw delta from current scalar yaw;
- it calls playground.player.adjust_view(yaw_delta, 0.0);
- direct automated `playground.player.camera_yaw =` assignment is absent;
- the existing M7 process test contains the source guards for the helper/public API/direct-assignment ban;
- no network/server-authority/range/timeout semantics are changed by the R9 delta.


## 5. Inherited Inherited R8 M5 pre-gates

Run before any decisive series.

### 4.1 Contracts

~~~powershell
& $env:GODOT_BIN --headless --path . --script res://tests/runtime/test_m5_graphical_acceptance_contracts.gd
~~~

Required: 126 assertions, 0 failures, exit 0.

### 4.2 R7 convergence guard

~~~powershell
& $env:GODOT_BIN --headless --path . --script res://tests/runtime/support/m5_convergence_release_guard_regression.gd
~~~

Required: 31 assertions, 0 failures.

### 4.3 R8 control-read regression

~~~powershell
& $env:GODOT_BIN --headless --path . --script res://tests/runtime/support/m5_control_read_consistency_regression.gd
~~~

Required:

~~~text
M5 control read consistency regression: 25 assertions, 0 failures
~~~

### 4.4 Pipe smoke

~~~powershell
& $env:GODOT_BIN --headless --path . --script res://tests/runtime/test_m5_graphical_multiplayer_acceptance.gd -- --m5-pipe-smoke-only
~~~

Required:

~~~text
M5_CHILD_PIPE_OBSERVABILITY_PASS
exit=0
stdout_bytes>0
stderr_bytes>0
~~~

Any pre-gate failure is preserved. Do not start the decisive series.


## 6. Fresh decisive M5 stability

Only after all pre-gates PASS.

Run exactly once:

~~~powershell
.\RUN_M5_GRAPHICAL_STABILITY_TESTS.ps1 -GodotPath "$env:GODOT_BIN" -Runs 10
~~~

Required:

~~~text
run 1 PASS
...
run 10 PASS
M5_GRAPHICAL_STABILITY_PASS 10/10
~~~

If any run 1..10 fails:

- STOP;
- preserve the first failure;
- do not restart the 10x series;
- do not substitute a later pass;
- do not run canonical full regression.

Record exact occurrences of:

~~~text
M5_CONTROL_READ_UNAVAILABLE
M5_CONVERGENCE_RELEASE_INTEGRITY_FAILED
~~~

If PASS, inspect client reports for control_read.transient_recoveries / last_attempts / last_elapsed_ms. A recovery observation is useful but not required.


## 7. Fresh focused SM1 belt

Use an isolated Godot profile.

~~~powershell
$Profile = Join-Path $PWD ("artifacts\test-results\b6-r9-focused-profile-" + $PID)
$env:HOME = $Profile
$env:USERPROFILE = $Profile
$env:APPDATA = Join-Path $Profile "data"
$env:LOCALAPPDATA = Join-Path $Profile "data"
$env:XDG_DATA_HOME = Join-Path $Profile "data"
$env:XDG_CONFIG_HOME = Join-Path $Profile "config"
$env:XDG_CACHE_HOME = Join-Path $Profile "cache"
$env:PLANET_SIMULATOR_INVENTORY_PROFILE = "planet_default"
New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:XDG_CONFIG_HOME,$env:XDG_CACHE_HOME | Out-Null

& $env:GODOT_BIN --headless --editor --path $PWD --quit
if ($LASTEXITCODE -ne 0) { throw "EDITOR_IMPORT_FAILED" }
~~~

Run all 13:

~~~powershell
$Tests = @(
  "tests/network/test_v0_sm1_player_carry_and_gateway_pivot.gd",
  "tests/runtime/test_v0_sm1_owner_map_and_transfer.gd",
  "tests/runtime/test_v0_sm1_graphical_handoff_processes.gd",
  "tests/runtime/test_v0_sm1_fault_matrix_1_6.gd",
  "tests/runtime/test_v0_sm1_concurrent_crossings.gd",
  "tests/runtime/test_v0_sm1_reconnect_after_handoff.gd",
  "tests/runtime/test_v0_sm1_gateway_failure_restart.gd",
  "tests/runtime/test_v0_sm1_authority_recovery.gd",
  "tests/runtime/test_v0_sm1_world_state_continuity.gd",
  "tests/runtime/test_v0_sm1_world_mutations_around_handoff.gd",
  "tests/runtime/test_v0_sm1_combined_carry_world_chain.gd",
  "tests/runtime/test_v0_sm1_historical_activation_replay.gd",
  "tests/runtime/test_v0_sm1_repeated_crossings_impaired_network.gd"
)

foreach ($Test in $Tests) {
  Write-Host "=== $Test ==="
  & $env:GODOT_BIN --headless --path $PWD --script ("res://" + $Test)
  if ($LASTEXITCODE -ne 0) { throw "FOCUSED_SM1_FAILED: $Test" }
}
~~~

Required: 13/13 PASS.


## 8. Repeated impaired-network stability

Run tests/runtime/test_v0_sm1_repeated_crossings_impaired_network.gd five consecutive times.

All 5 must pass without replacing a failed iteration. Record assertion count and PASS marker for every run.


## 9. Canonical full world/core regression

Only after:

- Inherited R8 M5 pre-gates PASS;
- fresh M5 10/10 PASS;
- focused SM1 13/13 PASS;
- impaired network 5/5 PASS.

Run exactly once, with no warm-up full run:

~~~powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
~~~

Read artifacts/test-results/world-regression-summary.json.

Required:

~~~text
passed = true
declared_test_count = 304
discovered_test_count = 304
steps = 307
bad exits = 0
~~~

Audit:

~~~powershell
$S = Get-Content .\artifacts\test-results\world-regression-summary.json -Raw | ConvertFrom-Json
$Bad = @($S.steps | Where-Object { [int]$_.exit_code -ne 0 })
Write-Host "passed=$($S.passed)"
Write-Host "declared=$($S.declared_test_count)"
Write-Host "discovered=$($S.discovered_test_count)"
Write-Host "steps=$(@($S.steps).Count)"
Write-Host "bad_exits=$($Bad.Count)"
~~~

The first canonical failure is authoritative. Do not replace it with a rerun.


## 10. Inherited R8 semantic audit

Independently inspect exact subject bytes and prove:

- m5_convergence_barrier.gd is unchanged from R7;
- Support.read(_control_file) is absent from the M5 graphical client driver;
- all four control-dependent client stages use bounded typed reads;
- retryable errors are only NOT_FOUND / OPEN_FAILED / EMPTY / INCOMPLETE;
- valid JSON {} is successful and is not retried;
- empty path is non-transient;
- retry horizon is bounded;
- no stale .bak control is accepted as current truth;
- exhaustion becomes explicit M5_CONTROL_READ_UNAVAILABLE;
- CONTROL_GENERATION_REGRESSED_AFTER_RELEASE is not weakened;
- no convergence generation retry is introduced;
- convergence timeout is not increased.

Do not infer this from PR prose.


## 11. Historical evidence cross-check

Read but do not inherit as your own verdict:

~~~text
config/control/harness/executions/E2026-08-24-V0-SM1-R1/verifications/V0-SM1-R1-WO-001-VERIFICATION-001.v1.json
config/control/harness/executions/E2026-08-24-V0-SM1-R1/verifications/V0-SM1-R1-WO-001-VERIFICATION-002.v1.json
config/control/harness/executions/E2026-08-24-V0-SM1-R1/evidence/V0-SM1-R1-B6-M7-R9-WINDOWS-VALIDATION-002.v1.json
config/control/harness/executions/E2026-08-24-V0-SM1-R1/evidence/V0-SM1-R1-R9-WINDOWS-VALIDATION-PROTOCOL-CORRECTION-001.v1.json
config/control/harness/executions/E2026-08-24-V0-SM1-R1/evidence/V0-SM1-R1-B6-M7-R9-ROOT-CAUSE-001.v1.json
~~~

Important Windows V2 nuance: one PowerShell Gate-E wrapper invocation raised NativeCommandError before a governed Godot exit code was captured. It is wrapper-only evidence, not a governed M5 pipe-smoke result. Do not count it as a candidate test failure or as a replacement run. Independently execute your own pipe smoke once and judge that execution only.


## 12. Project Control

After runtime validation:

~~~powershell
git fetch origin --prune
.\CONTROL_PROJECT.ps1 -NoFailOnRed
~~~

Read the machine JSON reports and record standard overall, V0 health, directional overall, candidate-specific critical hits, cross-branch overlaps, and human-attention items.

Known prior exact-R9 CI evidence:

~~~text
Project Control run 33250316990 = SUCCESS
exact HEAD = b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f
artifact = project-control-report
artifact id = 9714151584
artifact digest = sha256:38485eb077c00cae90931a39e9d0bc30056cd99af63a8fb9bf94c98de33a8a9a
~~~

Do not infer GREEN from workflow SUCCESS. Capture current report status exactly.


## 13. Freshness after execution

~~~powershell
$FinalHead = (git rev-parse HEAD).Trim()
$FinalTree = (git rev-parse 'HEAD^{tree}').Trim()

git diff --exit-code
$TrackedExit = $LASTEXITCODE

git diff --cached --exit-code
$StagedExit = $LASTEXITCODE

git status --short

if ($FinalHead -ne "b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f") { throw "FINAL_HEAD_CHANGED" }
if ($FinalTree -ne "7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68") { throw "FINAL_TREE_CHANGED" }
if ($TrackedExit -ne 0 -or $StagedExit -ne 0) { throw "TRACKED_TREE_MUTATED" }
~~~

Generated .gd.uid files and ignored artifacts may exist. List them exactly. Do not commit them.


## 14. Exact-head review freshness warning

Historical Reviewer PASS is not bound to exact R9 bytes.

Therefore:
- B6 machine verdict may be VERIFIED if all B6 machine predicates pass;
- do not claim a fresh exact-head Reviewer PASS for R9;
- B7/checkpoint proposal remains blocked until exact-head review freshness and remaining control predicates are reconciled.


## 15. Required new verifier record

After verification, create exactly one new control-only record:

~~~text
config/control/harness/executions/E2026-08-24-V0-SM1-R1/verifications/V0-SM1-R1-WO-001-VERIFICATION-003.v1.json
~~~

Do not overwrite VERIFICATION-001 or VERIFICATION-002.

Minimum fields:

~~~json
{
  "schema": "distributed_world_simulator.harness_verification.v1",
  "work_order_id": "V0-SM1-R1-WO-001",
  "verified_head_sha": "b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f",
  "verified_tree_sha": "7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68",
  "verifier": "INDEPENDENT_VERIFIER_B6_FRESH_SESSION_R3",
  "verdict": "VERIFIED | FAILED | INSUFFICIENT_EVIDENCE",
  "verified_at_utc": "<UTC>",
  "environment": "<exact Windows + Godot path/version>",
  "checks": {
    "subject_identity": {},
    "r9_m7_decisive_10x": {},
    "r8_m5_pre_gates": {},
    "m5_decisive_10x": {},
    "focused_sm1": {},
    "repeated_impaired_network_5x": {},
    "full_world_core_regression": {},
    "r8_semantic_audit": {},
    "r9_semantic_audit": {},
    "pc0": {},
    "freshness": {}
  },
  "notes": "<evidence-grounded summary>"
}
~~~

Commit the record only on a dedicated control-only verification-record branch descended from control/v0-sm1-b6-r9-verifier-dispatch-r3. Never commit it to the runtime R9 branch.


## 16. VERIFIED requirements

VERIFIED requires all:
- exact R9 HEAD b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f and TREE 7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68;
- ancestry/composition proven (48 / 9 / 2 and exact two-file R9 delta);
- exact double Godot;
- isolated editor import PASS;
- fresh governed R9 M7 10/10 at 54/0 each, one series, no replacement run;
- R9 semantic audit PASS;
- M5 contracts 126/0;
- R7 guard 31/0;
- R8 control-read regression 25/0;
- pipe smoke with non-empty stdout/stderr;
- fresh M5 decisive 10/10 single series;
- focused SM1 13/13;
- impaired network 5/5 at 69/0 each;
- first and only canonical full regression PASS;
- 304 declared / 304 discovered / 307 steps / zero bad exits;
- inherited R8 semantic audit proves no convergence weakening;
- subject byte identity preserved;
- no critical candidate-specific control defect invalidates the machine subject.

## 17. Failure rules

Editor-import or R9 M7 failure: B6 BLOCKED; preserve first exact failure; no replacement M7 series; M5 decisive/canonical not run.

M5 pre-gate failure: B6 BLOCKED; decisive/canonical not run.

M5 decisive failure: B6 BLOCKED; NO RERUN; canonical not run.

Focused SM1 or impaired-network failure: B6 BLOCKED; preserve first exact failure.

Canonical failure: B6 BLOCKED; preserve first and only canonical attempt; do not replace with rerun.

Do not repair anything.

## 18. Forbidden conclusions

Even after VERIFIED, do not declare:
- SM1 accepted;
- checkpoint proposed/accepted;
- B7 complete;
- merge authorized;
- human gate satisfied;
- P7 activated;
- fresh Reviewer PASS on R9;
- PC0 GREEN unless the machine report itself says GREEN.

## 19. Expected next state after VERIFIED

~~~text
B6 MACHINE VERIFICATION = CLOSED
R9 = VERIFIED / NOT MERGED
B7 = BLOCKED pending exact-head Reviewer freshness + remaining control reconciliation
human RUNTIME_FEATURE_MERGE = untouched
P7 = BLOCKED
~~~