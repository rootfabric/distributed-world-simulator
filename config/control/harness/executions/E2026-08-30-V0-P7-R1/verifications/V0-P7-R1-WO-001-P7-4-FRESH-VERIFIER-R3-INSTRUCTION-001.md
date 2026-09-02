# V0 P7.4 — Fresh Independent Windows Verifier R3

Role: **fresh independent VERIFIER R3**, read-only with respect to runtime source.

R1 and R2 both ended correctly as `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT` without executing the gate. Under the platform amendment `V0-P7-R1-P7-4-VERIFIER-PLATFORM-AMENDMENT-001` (authorized by human directive on 2026-08-31), R3 is dispatched on the **canonical Windows x86_64 exact double-Godot path** and must run a completely fresh campaign against the **same frozen runtime subject**.

If any identity, environment, import, stage, log, or cleanliness invariant fails, do not repair runtime source. Record `NOT_VERIFIED`.

## Frozen runtime subject

```text
runtime PR:
#396

runtime branch:
feature/v0-p7-bounded-terrain-mutation

HEAD:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

TREE:
1efad34a075af63169c48dd5055c2537c8d7e6ef

P7.4 canonical base:
0ad8c41f04b1d115da7de4a24a1c0390761c3ae1

runtime Project Control:
33374295322 = SUCCESS
```

Do not rebase. Do not modify the runtime branch.

## Prior gates

Reviewer R1:

```text
commit:
abd753941f2bc4f9ff771e8501f261505b61c7de

verdict:
PASS

Project Control:
33388053145 = SUCCESS
```

Verifier R1:

```text
result commit:
38ddb506fed104ad419c1a94c9564a3ae6c654b4

verdict:
NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT

execution_performed:
false
```

Verifier R2:

```text
result commit:
bbe791580bdc36729668d15208cdf9902ee1ebc8

verdict:
NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT

execution_performed:
false
```

**R1 and R2 contribute zero runtime execution evidence to R3.** No stage may be inherited from R1, R2, Implementer, or Reviewer.

## Platform amendment

This round executes under:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/evidence/
V0-P7-R1-P7-4-VERIFIER-PLATFORM-AMENDMENT-001.v1.json
```

It authorizes, for P7.4 verifier rounds R3+, the canonical Windows x86_64 exact double-Godot path **in addition to** the unchanged Ubuntu path, under identical invariants. The R2 sentence "This does not permit Windows Godot" is superseded for R3+ by the amendment; R1/R2 verdicts remain historical control evidence.

## Exact Windows double Godot — identity proof

Canonical console binary:

```powershell
$GodotBin = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
```

Required proofs (all must hold):

```powershell
Test-Path $GodotBin
# True

(& $GodotBin --version 2>&1 | Select-Object -First 1).Trim()
# must equal exactly:
# 4.7.1.stable.double.custom_build.a13da4feb

(Get-FileHash -Algorithm SHA256 $GodotBin).Hash.ToLower()
# must equal the control-surface-observed identity:
# 3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5
```

Identity block of the authorized engine:

```text
version:      4.7.1.stable.double.custom_build.a13da4feb
build commit: a13da4feb8d8aefc283c3763d33a2f170a18d541
platform:     windows
target:       editor
arch:         x86_64
precision:    double
```

If `--version` differs, or the binary hash differs from the recorded identity without a recorded control-surface explanation, stop with `NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT`.

The GUI binary `C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe` must not be used as the gate runner.

## Fresh source materialization

Do not reuse an Implementer, Reviewer, R1, or R2 worktree.

This machine's git store is a bare repository guarded by `safe.bareRepository=explicit`; always pass `--git-dir` explicitly.

```powershell
$Store     = "C:\distributed-world-simulator\.git-store\repo.git"
$VerifyDir = "C:\dws-p7-4-verifier-r3-windows"

git --git-dir=$Store worktree remove --force $VerifyDir 2>$null
git --git-dir=$Store worktree add --detach $VerifyDir 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
Set-Location $VerifyDir
```

Required proofs:

```powershell
git rev-parse HEAD
# 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

git rev-parse "HEAD^{tree}"
# 1efad34a075af63169c48dd5055c2537c8d7e6ef

git rev-parse origin/feature/v0-p7-bounded-terrain-mutation
# 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

git status --porcelain --untracked-files=no
# must be empty
```

Any mismatch = `NOT_VERIFIED`. Never rebase to fix identity.

## Canonical R3 execution

No external 180-second timeout is allowed. The gate may run for a long time; run it in a background job and wait for real completion. A timeout is not PASS.

Run exactly, from the root of the fresh worktree:

```powershell
Set-Location $VerifyDir
.\RUN_V0_P7_4_PERSISTENCE_RESTART_GATE.ps1 `
    -GodotExe "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe" `
    -ExpectedHead "9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292"
```

Required final exit:

```text
0
```

Required final banner:

```text
V0-P7.4 PERSISTENCE RESTART COMPOSITION GATE GREEN
EXACT_HEAD=9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
GODOT=4.7.1.stable.double.custom_build.a13da4feb
```

Do not run the gate anywhere except the fresh detached worktree root. Do not invoke Godot test scripts manually.

## Required 16 fresh stages

```text
P7.4 seed                         21 / 0
P7.4 recover-deliver              25 / 0
P7.4 recover-replay               17 / 0
P7.3 material delivery           116 / 0
P7.2 bubble                       53 / 0
P7.2 seam                         50 / 0
P7.1 authority                    83 / 0
P7.1 Tool→MW4                     30 / 0
P5 mining tool                    36 / 0
P3 resource domain                79 / 0
P3 aggregate recovery             33 / 0
M6 recovery contracts            126 / 0
M6 recovery processes            128 / 0
MW4                               187 / 0
MW5                               142 / 0
MW6                               130 / 0
```

These counts are the counts of prior canonical runs; record the actual counts from this campaign's logs. A material deviation is a finding to record (the runner's own PASS summaries are binding).

Especially close freshly:

```text
P7.2 bubble
MW4
MW5
MW6
M6 recovery processes
```

## Required 17 logs

All logs appear under `artifacts\runtime\v0-p7-4-persistence-restart\` inside the fresh worktree. Require exactly:

```text
import.log
p7-4-seed.log
p7-4-recover-deliver.log
p7-4-recover-replay.log
p7-3-material-delivery.log
p7-2-bubble.log
p7-2-seam.log
p7-1-authority.log
p7-1-tool-to-mw4.log
p5-mining-tool.log
p3-resource-domain.log
p3-aggregate-recovery.log
m6-recovery-contracts.log
m6-recovery-processes.log
mw4.log
mw5.log
mw6.log
```

```text
1 import log
3 P7.4 restart phase logs
13 regression-stage logs
17 total
```

Independently scan all 17 logs for:

```text
SCRIPT ERROR:
Parse Error:
Compile Error:
Failed to instantiate an autoload
Failed to load script
```

Any match = `NOT_VERIFIED`, even if a PASS line is present.

Record SHA-256 for every log.

## Final exact-head and cleanliness fence

After execution:

```powershell
git rev-parse HEAD                    # 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
git rev-parse "HEAD^{tree}"           # 1efad34a075af63169c48dd5055c2537c8d7e6ef
git diff --exit-code                  # must be clean
git diff --cached --exit-code         # must be clean
git status --porcelain --untracked-files=no   # must be empty
```

Untracked Godot-generated sidecars (`.uid`) and the `artifacts\` directory may exist but must not be committed.

## Control checks

Confirm independently what is reachable; record every check:

```text
runtime PR #396 is open and exactly at HEAD 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
  (verify with: gh pr view 396 --json state,headRefName,headRefOid)

origin/feature/v0-p7-bounded-terrain-mutation == 9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292
  (re-fetched on the control surface 2026-08-31T19:32Z)

Reviewer R1 commit abd753941f... = PASS, PC 33388053145 = SUCCESS
Verifier R1 commit 38ddb506fed1... = NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT, PC 33393399665 = SUCCESS
Verifier R2 commit bbe791580bdc... = NOT_VERIFIED / INSUFFICIENT_ENVIRONMENT
immutable export 33374385318 = SUCCESS
carrier PC 33374385340 = SUCCESS
```

R1/R2 NOT_VERIFIED results are historical control evidence only, never runtime execution evidence.

## Durable R3 result

Create exactly:

```text
config/control/harness/executions/E2026-08-30-V0-P7-R1/verifications/
V0-P7-R1-WO-001-P7-4-VERIFICATION-003.v1.json
```

Required identity:

```text
schema:
distributed_world_simulator.harness_verification.v1

verification_id:
V0-P7-R1-WO-001-P7-4-VERIFICATION-003

work_order_id:
V0-P7-R1-WO-001

project_epoch:
E2026-08-30-V0-P7-R1

verified_head_sha:
9deb31b85a5f46ae30b5eeaa6e2e3a1f6a37f292

verified_tree_sha:
1efad34a075af63169c48dd5055c2537c8d7e6ef

verifier:
INDEPENDENT_VERIFIER_P7_4_FRESH_WINDOWS_EXACT_SOURCE_R3
```

Allowed verdicts:

```text
VERIFIED
NOT_VERIFIED
```

Record:
- environment type: Windows x86_64 (canonical workspace layout per docs/GODOT_LOCAL_TESTING_RU.md);
- exact Godot path / version / binary SHA-256 (console);
- the platform amendment id this round executes under;
- exact HEAD/TREE/origin branch and the fresh detached worktree path;
- fresh import;
- all 16 fresh stage actual assertion counts;
- canonical runner exit code and final banner lines;
- all 17 log SHA-256 values;
- fatal-log scan result;
- tracked-clean before/after;
- all control identities above;
- findings.

## R3 result branch

Create the result branch from the **exact final R3 dispatch control HEAD** (the head of `control/v0-p7-4-fresh-verifier-dispatch-r3`), never from runtime HEAD or main:

```text
control/v0-p7-4-fresh-verifier-result-r3
```

Only `V0-P7-R1-WO-001-P7-4-VERIFICATION-003.v1.json` may be added on that branch.

Commit message:

```text
verify(p7.4): record fresh Windows verifier R3 <VERIFIED | NOT_VERIFIED (...)>
```

## Success boundary

`VERIFIED` opens only the Human `RUNTIME_FEATURE_MERGE` gate for exact PR #396.

No merge is performed by the verifier.

At VERIFIED finish exactly:

```text
P7.4 Fresh Windows Verifier R3 VERIFIED opens Human RUNTIME_FEATURE_MERGE only.
No merge performed.
```

At NOT_VERIFIED, state the exact blocker/failing stage and the next repair or rerun required.
