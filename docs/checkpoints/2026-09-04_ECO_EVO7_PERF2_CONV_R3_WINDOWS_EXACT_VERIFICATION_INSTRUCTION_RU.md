# ECO.EVO7 PERF2.CONV R3 — WINDOWS EXACT VERIFICATION INSTRUCTION

Дата: 2026-09-04

Статус: VALIDATION ONLY / DO NOT MERGE INTO SUBJECT

## Exact subject

```text
branch
feature/eco-evo7-perf2-conv-stream1-vis4-r3

HEAD
81a0b3fa60664684b02d8387e4693c5f328dbe28

TREE
a192950483267dd428baf2d1daa25de915df2370
```

Subject нельзя двигать, чинить или дополнять внутри verification campaign. Любое изменение HEAD/TREE = BLOCKED/NEW CANDIDATE.

## Exact prerequisites already embedded in ancestry

Accepted PERF2.4 R12 runtime:

```text
HEAD 840cfcea62ef7192b510235f915b849829654c6c
TREE 967d674c0ba2349db949193969f16f91553761ea
accepted control ab115385e81375b224eb397cf6a9de071bd4e79e
report hash 16d3407abef3d3ff30cbe4293cb1278e1b18845b0b5332589587d543b134853b
```

Exact-tested VIS4.9:

```text
HEAD ab44617d8961add81a6c9f245c99d0b68eaeab52
TREE 9d543a3db4f54a676e9f25152785c36a72c56a30
```

True ancestry merge:

```text
HEAD 3d41fe4542782e24a33bbac388404679756b4d67
TREE 415152ef85bd46b0c3f95bf3da826ec3f3dbb75f
```

PERF2.4 is immutable accepted evidence. Do not rerun the PERF2.4 benchmark inside PERF2.CONV verification.

## Canonical Windows Godot

```text
path
C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe

version
4.7.1.stable.double.custom_build.a13da4feb

SHA-256
3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

Any Godot identity mismatch = BLOCKED.

## Frozen PERF2.CONV shape and budgets

The integrated gate runs:

```text
warmup generations      2 per repetition
measured generations   12 per repetition
repetitions             3
total measured samples 36
```

Frozen acceptance budgets:

```text
p50 combined/simulation ratio <= 2.50
p95 combined/simulation ratio <= 4.00
max single combined generation <= 5000 ms
max cache entries per record <= 5
minimum foreground frames per generation >= 1
```

Required green claims:

```text
perf2_5_vis4_materialization_profiling = true
perf2_6_ph5_lod_cache_bounded = true
perf2_7_stream1_vis4_integrated_load = true
perf2_8_play1_performance_acceptance = true
```

Required correctness summary:

```text
stream_contract_green = true
cache_bounded_green = true
source_seals_green = true
single_flight_green = true
foreground_progress_green = true
timing_budget_green = true
```

The gate also requires exact ecology/presentation/morphology source seals, deterministic final ecology hash across all three fresh repetitions, optimized STREAM1 only, zero legacy STREAM1 calls, zero chunk-local parent/candidate/route/recruitment sorts, bounded parent working set, bounded PH5 cache, and accepted R10/R12 + tested VIS4.9 source guards.

## One-command verifier

Use the validation carrier helper. It creates a fresh detached worktree at the exact subject, verifies Godot SHA/version and prerequisite identities, runs the integrated campaign once, validates the JSON artifact, checks final HEAD/TREE/cleanliness, and prints the acceptance summary.

```powershell
$Repo = "C:\distributed-world-simulator\distributed-world-simulator"
cd $Repo

git fetch origin validation/eco-perf2-conv-r3-windows-r1 feature/eco-evo7-perf2-conv-stream1-vis4-r3

git show origin/validation/eco-perf2-conv-r3-windows-r1:tools/verification/RUN_ECO_EVO7_PERF2_CONV_R3_WINDOWS_EXACT.ps1 `
  | Set-Content -Encoding UTF8 "$env:TEMP\RUN_ECO_EVO7_PERF2_CONV_R3_WINDOWS_EXACT.ps1"

& "$env:TEMP\RUN_ECO_EVO7_PERF2_CONV_R3_WINDOWS_EXACT.ps1" `
  -Repo $Repo `
  -GodotPath "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Do not check out the validation branch as the runtime subject. The helper always pins and creates a fresh detached worktree at `81a0b3fa60664684b02d8387e4693c5f328dbe28`.

## Direct manual fallback

If the helper itself is unavailable, use a fresh detached worktree and the subject-owned runner:

```powershell
$Repo = "C:\distributed-world-simulator\distributed-world-simulator"
$Head = "81a0b3fa60664684b02d8387e4693c5f328dbe28"
$Tree = "a192950483267dd428baf2d1daa25de915df2370"
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$Wt = "C:\dws-perf2-conv-r3-win-$(Get-Date -Format yyyyMMdd-HHmmss)"

git -C $Repo fetch origin feature/eco-evo7-perf2-conv-stream1-vis4-r3
if ((git -C $Repo rev-parse refs/remotes/origin/feature/eco-evo7-perf2-conv-stream1-vis4-r3).Trim() -ne $Head) { throw "subject moved" }

git -C $Repo worktree add --detach $Wt $Head
if ((git -C $Wt rev-parse HEAD).Trim() -ne $Head) { throw "HEAD mismatch" }
if ((git -C $Wt rev-parse "HEAD^{tree}").Trim() -ne $Tree) { throw "TREE mismatch" }
if ((git -C $Wt rev-parse --abbrev-ref HEAD).Trim() -ne "HEAD") { throw "not detached" }

if ((& $Godot --version | Select-Object -First 1).Trim() -ne "4.7.1.stable.double.custom_build.a13da4feb") { throw "Godot version mismatch" }
if ((Get-FileHash $Godot -Algorithm SHA256).Hash.ToLowerInvariant() -ne "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5") { throw "Godot SHA mismatch" }

$env:ECO_PERF2_CONV_TARGET_HEAD = $Head
$env:ECO_PERF2_CONV_TARGET_TREE = $Tree
$env:BREAKPOINT_RUNTIME_DISABLED = "1"
$env:GODOT_BIN = $Godot
$env:GODOT_DOUBLE_BIN = $Godot

& "$Wt\RUN_ECO_EVO7_PERF2_CONV_TESTS.ps1" -GodotPath $Godot 2>&1 `
  | Tee-Object "$Wt\perf2-conv-r3-win-exact.log"
```

Expected artifact:

```text
<fresh-worktree>\artifacts\perf2\perf2-conv-stream1-vis4-r1.json
```

## Rerun rule

Run the completed integrated campaign exactly once.

- `PASS`: accept the completed campaign.
- `PERFORMANCE RED`: if the report exists and any frozen timing budget is red, do NOT rerun to fish for a pass.
- `CORRECTNESS RED`: source seal, deterministic hash, STREAM1 contract, cache, single-flight, source guards, artifact validation, or other semantic failure. Do NOT rerun; repair requires a new candidate.
- `BLOCKED / INFRA ABORT`: wrong/missing Godot, exact subject unavailable/moved, worktree failure, machine sleep/termination before a completed report, console spawn failure before a completed report. Retry the same exact HEAD only after fixing the infrastructure blocker.

## What to return

Return the verifier's final summary plus the following:

```text
PERF2.CONV R3 WINDOWS EXACT VERIFICATION COMPLETED: PASS/RED/BLOCKED
subject HEAD / TREE
Godot version / SHA-256
host descriptor / fingerprint
assertion PASS/FAIL line from the log
samples / repetitions
p50 combined/sim ratio
p95 combined/sim ratio
p50/p95 combined ms
p50/p95 simulation ms
p50/p95 presentation overhead ms
max combined ms
max cache entries
max record count
min foreground frames
all four PERF2.5..PERF2.8 claims
report_hash
artifact file SHA-256
tracked clean YES/NO
log path
artifact path
```

If PASS, end with:

```text
Работа закончена.
Следующий шаг: формально зафиксировать PERF2.CONV ACCEPTED и перейти по roadmap к следующему post-convergence frontier.
```

If RED, include the exact first failing frozen assertion/claim/budget and do not rerun a completed campaign.
