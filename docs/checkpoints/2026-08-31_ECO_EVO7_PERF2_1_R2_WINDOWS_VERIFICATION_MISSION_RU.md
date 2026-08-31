# ECO.EVO7 PERF2.1 R2 — Optional Windows Cross-Platform Evidence Mission

> Governance R18: Windows verification is **optional/non-blocking** for PERF2.1. One fresh exact local PASS on Ubuntu **or** Windows is sufficient for runtime acceptance because this stage executes the same OS-neutral GDScript path. Use this mission only when additional Windows cross-platform evidence is desired.

Target branch:

```text
feature/eco-evo7-perf2-1-stream1-generation-profiling-r2
```

Resolve and test the exact remote tip in a fresh detached worktree.

## Setup

```powershell
$Repo = 'C:\distributed-world-simulator\distributed-world-simulator'
$Branch = 'feature/eco-evo7-perf2-1-stream1-generation-profiling-r2'
$Verify = 'C:\distributed-world-simulator\eco-perf2-1-r2-verify'
$Godot = 'C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe'

Set-Location $Repo
git fetch origin $Branch
$Target = (git rev-parse "origin/$Branch").Trim()
git worktree add --detach $Verify $Target
Set-Location $Verify

$Head = (git rev-parse HEAD).Trim()
$Tree = (git rev-parse 'HEAD^{tree}').Trim()
if ($Head -ne $Target) { throw 'exact HEAD mismatch' }

$Version = (& $Godot --version | Select-Object -First 1).Trim()
if ($Version -ne '4.7.1.stable.double.custom_build.a13da4feb') {
    throw "Godot mismatch: $Version"
}
```

## Fresh import

```powershell
$env:BREAKPOINT_RUNTIME_DISABLED = '1'
& $Godot --headless --import --path .
if ($LASTEXITCODE -ne 0) { throw "import failed: $LASTEXITCODE" }
```

Legacy ECO5 BOM parse warnings are outside PERF2.1 scope; classify only with existing
byte-level evidence. Do not repair them in this worktree.

## Canonical workflow

```powershell
.\RUN_ECO_TEST_WORKFLOW.ps1 -Suite perf2.1 -GodotPath $Godot
if ($LASTEXITCODE -ne 0) { throw "PERF2.1 failed: $LASTEXITCODE" }
```

Required markers:

```text
branch=<detached-head>
PERF1 PASS
STREAM1 exact generation comparisons: 108
ECO.EVO7 STREAM1 Bounded Generation Stream: PASS (195 assertions)
PERF2.0 PASS
PERF2.1 R2 PASS
PERF2.1 cross-configuration exact result pairs: 9/9
PERF2_1_REPORT_SAMPLES=12
PERF2_1_REPORT_SUMMARIES=32
PERF2_1_REPORT_COMPARISONS=3
ECO.EVO7 PERF2.1 transitive generation-profiling R2 acceptance: PASS
ECO repository-local test workflow: PASS
```

## Artifact checks

```powershell
$ReportPath = '.\artifacts\perf2\perf2-1-generation-profile-r2.json'
$Report = Get-Content $ReportPath -Raw | ConvertFrom-Json

if (@($Report.samples).Count -ne 12) { throw 'samples != 12' }
if (@($Report.summaries).Count -ne 32) { throw 'summaries != 32' }
if (@($Report.comparisons).Count -ne 3) { throw 'comparisons != 3' }

$Report.comparisons | Format-Table stream_chunk_size,exact_pairs,observed_wall_ratio_serial_over_stream,observed_generation_ratio_serial_over_stream,optimization_claim
```

Every comparison must show:

```text
exact_pairs = 3
optimization_claim = False
```

## Final integrity

```powershell
if ((git rev-parse HEAD).Trim() -ne $Head) { throw 'HEAD moved' }
if ((git rev-parse 'HEAD^{tree}').Trim() -ne $Tree) { throw 'TREE moved' }

$Tracked = @(git status --porcelain --untracked-files=no)
if ($Tracked.Count -ne 0) {
    $Tracked
    throw 'tracked tree dirty'
}
```

## Report format

```text
ECO.EVO7 PERF2.1 R2 — WINDOWS VERIFICATION

HEAD:
TREE:
BASE:
07bffc0e7f30bac4479f1b7e53dee3fee3a818f6

Godot:
4.7.1.stable.double.custom_build.a13da4feb

fresh detached:
import:
protected runtime diff:

PERF1:
STREAM1:
STREAM1 exact:
PERF2.0:
PERF2.1:

cross-configuration exact pairs:
9/9

samples:
12

summaries:
32

comparisons:
3

chunk 1 wall ratio:
chunk 1 generation ratio:
chunk 7 wall ratio:
chunk 7 generation ratio:
chunk 64 wall ratio:
chunk 64 generation ratio:

artifact:
report hash:

canonical workflow:
tracked tree clean:

VERDICT:
PASS / FAIL

RECOMMENDATION:
Record this as optional Windows cross-platform evidence. Acceptance does not require a second OS pass if an exact Ubuntu PASS already exists.
```

No local repair in the verification worktree.


## JSON numeric round-trip regression

The verifier must require the PERF2.1 focused test to pass the artifact write → parse →
validate round-trip. Godot JSON may represent integral numbers as floating-point Variant
values after parsing; integer-equivalent values such as `7.0` are valid, while fractional
(`7.5`) or string (`"7"`) pseudo-integers must fail closed.

Do not repair the artifact manually.
