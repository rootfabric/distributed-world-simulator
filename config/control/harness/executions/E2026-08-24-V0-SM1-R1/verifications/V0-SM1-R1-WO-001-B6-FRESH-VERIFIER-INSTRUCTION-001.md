# V0 SM1 / B6 — Fresh Exact-Head Machine Verifier Instruction

Repository: `rootfabric/distributed-world-simulator`

Role: **FRESH INDEPENDENT READ-ONLY VERIFIER**

Risk: **CRITICAL**

Work Order: `V0-SM1-R1-WO-001`

Checkpoint: `V0_SM1_SEAMLESS_PRODUCT_INTEGRATION`

## 0. Role boundary

You are not the Implementer, Reviewer, Director or Human approver.

Do not modify runtime, tests, fixtures, contracts, docs, control policy, PR metadata or branch metadata.

Do not repair failures.

Do not merge any PR.

Do not accept SM1.

Do not activate P7.

Do not silently rerun a failure until it passes and then report only the pass.

Your job is to independently materialize the exact immutable candidate, execute machine evidence from scratch, inspect exact reports, and issue only:

`VERIFIED | FAILED | INSUFFICIENT_EVIDENCE`

## 1. Exact immutable subject

```text
SUBJECT_HEAD = 6fdfc047f54e727e6b398370e576c746c7949441
SUBJECT_TREE = b9b1202d959b3da4a0c73840091c7bf56070429e
```

Source implementation ancestor:

```text
SOURCE_HEAD = b270fb806038333c97fa1ed49655961adddd6a21
```

B4 evidence carrier:

```text
B4_CONTROL_HEAD = 1325812152944385c49af2ffe4f6afe6548d3b22
```

B5 Reviewer record carrier:

```text
B5_REVIEW_RECORD_HEAD = 8b4793d868eb81ff4786d51a4ba5ec90deb08a4e
B5_REVIEW_RECORD_TREE = 4df95dcd3c32e49539b074990095726ca5aa0b4f
```

B5 verdict:

```text
reviewed_head_sha = SUBJECT_HEAD
reviewed_tree_sha = SUBJECT_TREE
verdict = PASS
required_fixes = []
```

The Verifier must not inherit the Reviewer verdict as machine truth.

## 2. Fresh materialization

Use a new directory/worktree not used by Implementer or Reviewer.

Windows example:

```powershell
git clone https://github.com/rootfabric/distributed-world-simulator.git C:\dws-sm1-b6-runtime
cd C:\dws-sm1-b6-runtime
git fetch origin --prune
git checkout --detach 6fdfc047f54e727e6b398370e576c746c7949441
```

Before executing anything:

```powershell
git status --short
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
git cat-file -p 6fdfc047f54e727e6b398370e576c746c7949441
```

Expected:

```text
HEAD = 6fdfc047f54e727e6b398370e576c746c7949441
TREE = b9b1202d959b3da4a0c73840091c7bf56070429e
tracked working tree = clean
```

Also prove:

```powershell
git merge-base --is-ancestor b270fb806038333c97fa1ed49655961adddd6a21 6fdfc047f54e727e6b398370e576c746c7949441
if ($LASTEXITCODE -ne 0) { throw "source ancestry failed" }

git diff --name-only b270fb806038333c97fa1ed49655961adddd6a21..6fdfc047f54e727e6b398370e576c746c7949441
```

The repair layer must still be exactly 10 files / 4 commits.

## 3. Exact Godot identity

Required executable identity:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Windows:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
& $env:GODOT_BIN --version
```

If the exact custom double build is unavailable, verdict is `INSUFFICIENT_EVIDENCE`; do not substitute another Godot build.

Record full binary path and version.

## 4. Fresh focused SM1 machine belt

Run all exact SM1 standalone tests from the subject checkout with an isolated Godot user profile.

Minimum focused set:

```text
tests/network/test_v0_sm1_player_carry_and_gateway_pivot.gd
tests/runtime/test_v0_sm1_owner_map_and_transfer.gd
tests/runtime/test_v0_sm1_graphical_handoff_processes.gd
tests/runtime/test_v0_sm1_fault_matrix_1_6.gd
tests/runtime/test_v0_sm1_concurrent_crossings.gd
tests/runtime/test_v0_sm1_reconnect_after_handoff.gd
tests/runtime/test_v0_sm1_gateway_failure_restart.gd
tests/runtime/test_v0_sm1_authority_recovery.gd
tests/runtime/test_v0_sm1_world_state_continuity.gd
tests/runtime/test_v0_sm1_world_mutations_around_handoff.gd
tests/runtime/test_v0_sm1_combined_carry_world_chain.gd
tests/runtime/test_v0_sm1_historical_activation_replay.gd
tests/runtime/test_v0_sm1_repeated_crossings_impaired_network.gd
```

Recommended Windows helper:

```powershell
$Profile = Join-Path $PWD ("artifacts\test-results\b6-focused-profile-" + $PID)
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
if ($LASTEXITCODE -ne 0) { throw "editor import failed" }

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
  if ($LASTEXITCODE -ne 0) { throw "FAILED: $Test" }
}
```

Capture logs. Any first-run failure is evidence and must be preserved.

## 5. Repeated impaired-network stability

Independently rerun:

`tests/runtime/test_v0_sm1_repeated_crossings_impaired_network.gd`

at least **5 consecutive times** from the same immutable subject.

All 5 must exit `0`.

Record assertion/pass marker counts from each run.

Do not replace a failed run with a later successful run.

## 6. Canonical full world/core regression

Run exactly:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

with exact `GODOT_BIN`.

Required report:

`artifacts/test-results/world-regression-summary.json`

Verifier must independently parse and record:

```text
passed = true
declared_test_count = 304
discovered_test_count = 304
steps = 307
every step exit_code = 0
editor_import_parse = PASS
test_manifest_coverage = PASS
304 standalone tests = PASS
main_scene_cli_all = PASS
```

PowerShell audit example:

```powershell
$S = Get-Content .\artifacts\test-results\world-regression-summary.json -Raw | ConvertFrom-Json
$S.passed
$S.declared_test_count
$S.discovered_test_count
$S.steps.Count
$Bad = @($S.steps | Where-Object { $_.exit_code -ne 0 })
$Bad.Count
$S.steps[-1]
```

Do not rely only on the terminal success marker.

## 7. M5 timing observation rule

B5 recorded one historical `WAIT_CONVERGENCE_PEER` 150-second timeout.

Verifier rule:

- If the canonical B6 full regression passes first attempt: record that the historical timing observation did **not** reproduce.
- If M5 fails on the first B6 run: preserve the exact first failure and logs. A later rerun may be diagnostic only.
- A repeated/deterministic failure => `FAILED`.
- An ambiguous one-off machine/environment failure that cannot be classified => `INSUFFICIENT_EVIDENCE`.
- Never report only the successful rerun.

## 8. Project Control / PC0

After machine runtime validation, from the same exact subject checkout:

```powershell
git fetch origin --prune
.\CONTROL_PROJECT.ps1 -NoFailOnRed
```

Read the machine JSON reports, not just prose:

```text
artifacts/control/project-control-report.json
artifacts/control/directional-watch-report.json
```

Record:

- standard overall health;
- directional overall health;
- any explicit NON_RED/RED gate field if present;
- V0/SM1 relevant findings;
- critical directional hits;
- cross-branch overlaps;
- human-attention items.

Important:

A textual `YELLOW` must not automatically be rewritten as `NON_RED` unless the current machine contract/report or current policy explicitly establishes that gate mapping.

Conversely, if the report/policy explicitly defines YELLOW as NON_RED, record the exact machine/policy evidence rather than guessing.

Do not repair PC0 findings.

## 9. Freshness after execution

After all tests and PC0:

```powershell
git rev-parse HEAD
git rev-parse 'HEAD^{tree}'
git diff --exit-code
git diff --cached --exit-code
git status --short
```

Required:

```text
HEAD = SUBJECT_HEAD
TREE = SUBJECT_TREE
no tracked diff
no staged diff
```

Generated untracked Godot `.uid` files or artifacts may exist. List them exactly; do not commit them and do not call the tree "clean" without qualification.

## 10. Independent evidence cross-check

Read B4 and B5 from their immutable carriers using a second read-only checkout or `git show`.

Confirm:

- B4 Evidence Map evidence_head_sha == SUBJECT_HEAD;
- B5 reviewed_head_sha == SUBJECT_HEAD;
- B5 verdict == PASS;
- B5 required_fixes == [];
- subject is ancestor of both evidence carriers;
- neither B4 nor B5 changes runtime subject bytes.

Do not treat their verdicts as substitutes for execution.

## 11. Required Verifier output

If the machine evidence is sufficient, create exactly one control-only record after the verification is complete:

```text
config/control/harness/executions/E2026-08-24-V0-SM1-R1/verifications/V0-SM1-R1-WO-001-VERIFICATION-001.v1.json
```

Recommended schema:

```json
{
  "schema": "distributed_world_simulator.harness_verification.v1",
  "work_order_id": "V0-SM1-R1-WO-001",
  "verified_head_sha": "6fdfc047f54e727e6b398370e576c746c7949441",
  "verified_tree_sha": "b9b1202d959b3da4a0c73840091c7bf56070429e",
  "verifier": "INDEPENDENT_VERIFIER_<IDENTITY>",
  "verdict": "VERIFIED | FAILED | INSUFFICIENT_EVIDENCE",
  "verified_at_utc": "<UTC>",
  "environment": "<exact OS + Godot path/version>",
  "checks": {
    "focused_sm1": {},
    "repeated_impaired_network_5x": {},
    "full_world_core_regression": {},
    "pc0": {},
    "freshness": {}
  },
  "notes": "<evidence-grounded summary>"
}
```

The record must be committed only on a dedicated control-only verification branch descended from the latest evidence/review carrier. It must not alter the runtime subject.

## 12. VERIFIED requirements

`VERIFIED` requires all of:

- exact subject HEAD/TREE proven;
- exact custom double Godot proven;
- focused SM1 belt passes;
- repeated impaired-network test passes 5/5 without hidden failures;
- canonical full world/core regression passes on the first canonical B6 attempt;
- world regression summary is internally consistent and every step exit is 0;
- no deterministic M5 failure reproduced;
- no tracked runtime mutation during verification;
- B4/B5 identity binding is correct;
- PC0 machine state is captured honestly;
- no critical candidate-specific overlap/directional defect invalidates the subject.

A global/control finding may remain separate from implementation verification if current policy allows it, but it must remain an explicit checkpoint-proposal gap.

## 13. Forbidden conclusions

Verifier must not declare:

- SM1 ACCEPTED;
- checkpoint accepted/proposed;
- merge authorized;
- human gate satisfied;
- P7 activated;
- PC0 NON_RED unless actually machine/policy proven.

## 14. Next state

If `VERIFIED`:

```text
B6 = CLOSED
next = B7 checkpoint proposal preparation
remaining control gaps must be reconciled explicitly before proposal/acceptance
```

If `FAILED` or `INSUFFICIENT_EVIDENCE`:

```text
B6 = BLOCKED
B7 = BLOCKED
no runtime repair without a new authorized Repair Map / Director decision
```
