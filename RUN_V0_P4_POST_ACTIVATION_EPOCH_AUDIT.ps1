[CmdletBinding()]
param(
    [string]$MainRef = "origin/main",
    [string]$ExpectedHead = "",
    [string]$ExpectedProductBaseBranch = "repair/v0-p3-visual-interaction-r1",
    [string]$ExpectedProductBaseSha = "ef3ad5f0afc433802d639171d938e4720b3a46ec",
    [string]$ExcludedRepairSha = "11819f6dd1ea3728382a04737d30a5300de622f7",
    [int]$MinimumRegistryGeneration = 80,
    [string]$PythonExe = "python",
    [string]$AuditOutputPath = "",
    [switch]$SkipFetch,
    [switch]$SkipPostMainProjectControl
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$PassportPath = "config/control/branches/feature__v0-p4-construction-real-resources.v1.json"
$Checkpoint = "V0_P4_REAL_RESOURCE_CONSTRUCTION"
$ArtifactRoot = Join-Path $ProjectRoot "artifacts\control\v0-p4-post-activation"
$DefaultAuditJson = Join-Path $ArtifactRoot "epoch-base-audit.json"
$AuditJson = if ([string]::IsNullOrWhiteSpace($AuditOutputPath)) {
    $DefaultAuditJson
} elseif ([System.IO.Path]::IsPathRooted($AuditOutputPath)) {
    $AuditOutputPath
} else {
    Join-Path $ProjectRoot $AuditOutputPath
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $Output = & git -C $ProjectRoot @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed: $($Output -join [Environment]::NewLine)"
    }
    return ($Output -join "`n").Trim()
}

function Test-GitAncestor {
    param([string]$Ancestor, [string]$Descendant)
    & git -C $ProjectRoot merge-base --is-ancestor $Ancestor $Descendant 2>$null
    return $LASTEXITCODE -eq 0
}

function Get-GitJsonAtRef {
    param([string]$Ref, [string]$Path)
    $Raw = Invoke-Git show "$Ref`:$Path"
    try {
        return $Raw | ConvertFrom-Json -Depth 100
    } catch {
        throw "Invalid JSON at $Ref`:$Path : $($_.Exception.Message)"
    }
}

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Code)
    if ($Actual -ne $Expected) {
        throw "$Code expected='$Expected' actual='$Actual'"
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Code)
    if (-not $Condition) { throw $Code }
}

function Test-AllowedPreDispatchPath {
    param([string]$Path)
    if ($Path -like "docs/evidence/2026-08-16_V0_P4_*") { return $true }
    if ($Path -like "docs/checkpoints/2026-08-16_V0_P4_*") { return $true }
    if ($Path -like "tests/construction/test_v0_p4_*") { return $true }
    if ($Path -like "RUN_V0_P4_*") { return $true }
    if ($Path -eq $PassportPath) { return $true }
    return $false
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git"))) {
    throw "V0_P4_AUDIT_NOT_GIT_CHECKOUT"
}

$RefsFetchPerformed = $false
if (-not $SkipFetch) {
    Write-Host "[V0-P4 audit] Fetching current branch refs..."
    & git -C $ProjectRoot fetch origin '+refs/heads/*:refs/remotes/origin/*' --prune
    if ($LASTEXITCODE -ne 0) { throw "V0_P4_AUDIT_FETCH_FAILED" }
    $RefsFetchPerformed = $true
} else {
    Write-Host "[V0-P4 audit] Fetch skipped: result will be non-authorizing." -ForegroundColor Yellow
}

$ActualHead = Invoke-Git rev-parse HEAD
if ($ActualHead -notmatch '^[0-9a-fA-F]{40}$') { throw "V0_P4_AUDIT_HEAD_INVALID" }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead)) {
    Assert-Equal $ActualHead.ToLowerInvariant() $ExpectedHead.Trim().ToLowerInvariant() "V0_P4_AUDIT_HEAD_MISMATCH"
}
if (git -C $ProjectRoot status --porcelain) {
    throw "V0_P4_AUDIT_DIRTY_CHECKOUT"
}

$MainSha = Invoke-Git rev-parse $MainRef
$Registry = Get-GitJsonAtRef $MainRef "config/control/project-program-registry.v1.json"
$Catalog = Get-GitJsonAtRef $MainRef "config/control/harness/checkpoint-catalog.v1.json"
$Goals = Get-GitJsonAtRef $MainRef "config/control/harness/project-goals.v1.json"
$Scheduler = Get-GitJsonAtRef $MainRef "config/control/harness/scheduler-policy.v1.json"

Assert-True ([int]$Registry.registry_generation -ge $MinimumRegistryGeneration) "V0_P4_AUDIT_CONTROL_NOT_ACTIVATED"
$V0 = $Registry.programs.V0
Assert-True ($null -ne $V0) "V0_P4_AUDIT_V0_REGISTRY_MISSING"
$DeclaredBase = $V0.product_execution_base
Assert-True ($null -ne $DeclaredBase) "V0_P4_AUDIT_PRODUCT_EXECUTION_BASE_MISSING"
Assert-Equal ([string]$DeclaredBase.branch) $ExpectedProductBaseBranch "V0_P4_AUDIT_PRODUCT_BASE_BRANCH_MISMATCH"
Assert-Equal ([string]$DeclaredBase.sha).ToLowerInvariant() $ExpectedProductBaseSha.ToLowerInvariant() "V0_P4_AUDIT_PRODUCT_BASE_SHA_MISMATCH"
Assert-Equal ([bool]$DeclaredBase.declares_checkpoint_acceptance) $false "V0_P4_AUDIT_EXECUTION_BASE_FALSE_ACCEPTANCE"

Assert-True ($null -ne $Catalog.checkpoints.$Checkpoint) "V0_P4_AUDIT_CHECKPOINT_MISSING"
$GoalMatch = @($Goals.current_goal_graph | Where-Object { $_.target_checkpoint -eq $Checkpoint })
Assert-True ($GoalMatch.Count -ge 1) "V0_P4_AUDIT_GOAL_MISSING"
Assert-True (@($Scheduler.parallel_product_checkpoints.checkpoints) -contains $Checkpoint) "V0_P4_AUDIT_SCHEDULER_CHECKPOINT_MISSING"
Assert-Equal ([bool]$Scheduler.parallel_product_checkpoints.rules.requires_main_declared_product_execution_base) $true "V0_P4_AUDIT_MAIN_DECLARED_BASE_RULE_MISSING"
Assert-Equal ([bool]$Scheduler.parallel_product_checkpoints.rules.product_execution_base_is_not_automatic_checkpoint_acceptance) $true "V0_P4_AUDIT_FALSE_ACCEPTANCE_GUARD_MISSING"
Assert-Equal ([int]$Scheduler.concurrency.pre_h0_3_total_autonomous_runtime_mutation_workers) 1 "V0_P4_AUDIT_MUTATION_WORKER_LIMIT_CHANGED"
$Lease = $Scheduler.pre_h0_3_runtime_mutation_lease
Assert-True ($null -ne $Lease) "V0_P4_AUDIT_GLOBAL_MUTATION_LEASE_MISSING"
Assert-Equal ([int]$Lease.capacity) 1 "V0_P4_AUDIT_GLOBAL_MUTATION_LEASE_CAPACITY_CHANGED"
Assert-Equal ([string]$Lease.holder_checkpoint) $Checkpoint "V0_P4_AUDIT_GLOBAL_MUTATION_LEASE_HOLDER_MISMATCH"
Assert-Equal ([string]$Lease.holder_branch) "feature/v0-p4-construction-real-resources" "V0_P4_AUDIT_GLOBAL_MUTATION_LEASE_BRANCH_MISMATCH"

$ExpectedBaseRef = "origin/$ExpectedProductBaseBranch"
$ExpectedBaseRefSha = Invoke-Git rev-parse $ExpectedBaseRef
Assert-Equal $ExpectedBaseRefSha.ToLowerInvariant() $ExpectedProductBaseSha.ToLowerInvariant() "V0_P4_AUDIT_PRODUCT_BASE_REF_MOVED"
Assert-True (Test-GitAncestor $ExpectedProductBaseSha $ActualHead) "V0_P4_AUDIT_P4_NOT_DESCENDED_FROM_DECLARED_BASE"

& git -C $ProjectRoot cat-file -e "$ExcludedRepairSha^{commit}" 2>$null
if ($LASTEXITCODE -eq 0 -and (Test-GitAncestor $ExcludedRepairSha $ActualHead)) {
    throw "V0_P4_AUDIT_EXCLUDED_PR117_IMPORTED"
}

$Passport = Get-Content -LiteralPath (Join-Path $ProjectRoot $PassportPath) -Raw | ConvertFrom-Json -Depth 100
Assert-Equal ([string]$Passport.base_commit).ToLowerInvariant() $ExpectedProductBaseSha.ToLowerInvariant() "V0_P4_AUDIT_PASSPORT_BASE_MISMATCH"
Assert-Equal ([string]$Passport.branch) "feature/v0-p4-construction-real-resources" "V0_P4_AUDIT_PASSPORT_BRANCH_MISMATCH"
Assert-True (@($Passport.runtime_paths).Count -eq 0) "V0_P4_AUDIT_RUNTIME_PATHS_ALREADY_DECLARED"

$ChangedRaw = Invoke-Git diff --name-only "$ExpectedProductBaseSha..$ActualHead"
$ChangedFiles = @($ChangedRaw -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$Unexpected = @($ChangedFiles | Where-Object { -not (Test-AllowedPreDispatchPath $_) })
if ($Unexpected.Count -gt 0) {
    throw "V0_P4_AUDIT_UNAUTHORIZED_PRE_DISPATCH_DIFF: $($Unexpected -join ', ')"
}

$StandardHealth = "NOT_RUN"
$DirectionalHealth = "NOT_RUN"
$ControlWorktree = $null
try {
    if (-not $SkipPostMainProjectControl) {
        $PythonCommand = Get-Command $PythonExe -ErrorAction SilentlyContinue
        if ($null -eq $PythonCommand) { throw "V0_P4_AUDIT_PYTHON_NOT_FOUND:$PythonExe" }

        & $PythonExe -c "import jsonschema" 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "V0_P4_AUDIT_PINNED_HARNESS_DEPENDENCY_MISSING: install scripts/harness/requirements.txt first"
        }

        $ControlWorktree = Join-Path ([System.IO.Path]::GetTempPath()) ("dws-v0-p4-control-" + [Guid]::NewGuid().ToString("N"))
        & git -C $ProjectRoot worktree add --detach $ControlWorktree $MainSha
        if ($LASTEXITCODE -ne 0) { throw "V0_P4_AUDIT_CONTROL_WORKTREE_CREATE_FAILED" }

        Push-Location $ControlWorktree
        try {
            & $PythonExe -m unittest tests.harness.test_v0_s1_networked_checkpoint_contract tests.harness.test_v0_generation80_safety_guards
            if ($LASTEXITCODE -ne 0) { throw "V0_P4_AUDIT_MAIN_V0_MACHINE_REGRESSION_RED" }

            & $PythonExe scripts/control/project_control.py --no-fetch --no-fail-on-red
            if ($LASTEXITCODE -ne 0) { throw "V0_P4_AUDIT_STANDARD_PC0_EXECUTION_FAILED" }
            $StandardReport = Get-Content -LiteralPath (Join-Path $ControlWorktree "artifacts\control\project-control-report.json") -Raw | ConvertFrom-Json -Depth 100
            $StandardHealth = [string]$StandardReport.overall_health
            Assert-Equal ([string]$StandardReport.main_head).ToLowerInvariant() $MainSha.ToLowerInvariant() "V0_P4_AUDIT_STANDARD_PC0_MAIN_HEAD_MISMATCH"
            Assert-True ([int]$StandardReport.registry_generation -ge $MinimumRegistryGeneration) "V0_P4_AUDIT_STANDARD_PC0_OLD_GENERATION"
            Assert-True ($StandardHealth -ne "RED") "V0_P4_AUDIT_STANDARD_PC0_RED"

            & $PythonExe scripts/control/project_control_directional_watch.py --no-fail-on-red
            if ($LASTEXITCODE -ne 0) { throw "V0_P4_AUDIT_DIRECTIONAL_PC0_EXECUTION_FAILED" }
            $DirectionalReport = Get-Content -LiteralPath (Join-Path $ControlWorktree "artifacts\control\directional-watch-report.json") -Raw | ConvertFrom-Json -Depth 100
            $DirectionalHealth = [string]$DirectionalReport.overall_health
            Assert-True ([int]$DirectionalReport.registry_generation -ge $MinimumRegistryGeneration) "V0_P4_AUDIT_DIRECTIONAL_PC0_OLD_GENERATION"
            Assert-True ($DirectionalHealth -ne "RED") "V0_P4_AUDIT_DIRECTIONAL_PC0_RED"
        } finally {
            Pop-Location
        }
    }
} finally {
    if ($null -ne $ControlWorktree -and (Test-Path -LiteralPath $ControlWorktree)) {
        & git -C $ProjectRoot worktree remove --force $ControlWorktree 2>$null | Out-Null
        & git -C $ProjectRoot worktree prune 2>$null | Out-Null
    }
}

$Decision = if (-not $RefsFetchPerformed) {
    "BASE_READY_REFS_NOT_REFRESHED"
} elseif ($SkipPostMainProjectControl) {
    "BASE_READY_PC0_NOT_RUN"
} else {
    "CONTINUE"
}
$AuthoritativeForDispatch = $Decision -eq "CONTINUE"
$AuditDirectory = Split-Path -Parent $AuditJson
if (-not [string]::IsNullOrWhiteSpace($AuditDirectory)) {
    New-Item -ItemType Directory -Force -Path $AuditDirectory | Out-Null
}
$Result = [ordered]@{
    schema = "distributed_world_simulator.v0_p4_post_activation_epoch_audit.v1"
    decision = $Decision
    authoritative_for_dispatch = $AuthoritativeForDispatch
    refs_fetch_performed = $RefsFetchPerformed
    p4_head = $ActualHead
    canonical_main_head = $MainSha
    registry_generation = [int]$Registry.registry_generation
    checkpoint = $Checkpoint
    declared_product_execution_base_branch = [string]$DeclaredBase.branch
    declared_product_execution_base_sha = [string]$DeclaredBase.sha
    excluded_repair_sha = $ExcludedRepairSha
    pre_dispatch_changed_files = $ChangedFiles
    standard_pc0_health = $StandardHealth
    directional_pc0_health = $DirectionalHealth
    production_runtime_mutation_present = $false
    director_dispatch_still_required = $true
}
$Result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $AuditJson -Encoding UTF8

Write-Host ""
switch ($Decision) {
    "BASE_READY_REFS_NOT_REFRESHED" {
        Write-Host "V0-P4 post-activation base audit: BASE_READY_REFS_NOT_REFRESHED" -ForegroundColor Yellow
    }
    "BASE_READY_PC0_NOT_RUN" {
        Write-Host "V0-P4 post-activation base audit: BASE_READY_PC0_NOT_RUN" -ForegroundColor Yellow
    }
    default {
        Write-Host "V0-P4 post-activation epoch/base audit: CONTINUE" -ForegroundColor Green
    }
}
Write-Host "  P4 HEAD:             $ActualHead"
Write-Host "  canonical main:      $MainSha"
Write-Host "  registry generation: $($Registry.registry_generation)"
Write-Host "  product base:        $ExpectedProductBaseSha"
Write-Host "  refs fetched:        $RefsFetchPerformed"
Write-Host "  standard PC0:        $StandardHealth"
Write-Host "  directional PC0:     $DirectionalHealth"
Write-Host "  report:              $AuditJson"
Write-Host ""
if ($AuthoritativeForDispatch) {
    Write-Host "Audit is authoritative for a separate Director dispatch when this JSON is committed and referenced by that dispatch event." -ForegroundColor Green
} else {
    Write-Host "Audit is diagnostic only and MUST NOT authorize runtime mutation." -ForegroundColor Yellow
}
Write-Host "Director dispatch remains required before any P4 production/runtime mutation." -ForegroundColor Yellow
