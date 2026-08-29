[CmdletBinding()]
param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) { $ProjectRoot = $PSScriptRoot }
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$Analyzer = Join-Path $ProjectRoot "ANALYZE_V0_SM0_P4_GLOBAL_WRITERS.ps1"
if (-not (Test-Path -LiteralPath $Analyzer -PathType Leaf)) {
    throw "SM0-P4 aggregate writer analyzer missing: $Analyzer"
}

$Root = Join-Path ([IO.Path]::GetTempPath()) ("dws-sm0-p4-writer-audit-{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Force -Path $Root | Out-Null

function New-Sm0EventLine {
    param(
        [string]$Event,
        [string]$AuthorityId,
        [int]$WriterCount,
        [Int64]$WallUsec,
        [Int64]$Sequence,
        [string]$Incarnation
    )
    $Payload = [ordered]@{
        event = $Event
        authority_id = $AuthorityId
        writer_count = $WriterCount
        wall_time_unix_usec = $WallUsec
        process_event_sequence = $Sequence
        process_incarnation_id = $Incarnation
    }
    return "[SM0_EVENT] " + ($Payload | ConvertTo-Json -Compress)
}

function Write-Fixture {
    param(
        [string]$Directory,
        [bool]$Overlap
    )
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    $A = @(
        (New-Sm0EventLine "SM0_P4_HARDENING_READY" "authority/sm0/a" 0 1000000 1 "inc-a-1"),
        (New-Sm0EventLine "SM0_CLIENT_JOINED" "authority/sm0/a" 1 1000100 2 "inc-a-1")
    )
    $B = @(
        (New-Sm0EventLine "SM0_P4_HARDENING_READY" "authority/sm0/b" 0 1000000 1 "inc-b-1")
    )
    if (-not $Overlap) {
        $A += (New-Sm0EventLine "SM0_SOURCE_RETIRED" "authority/sm0/a" 0 1000200 3 "inc-a-1")
        $B += (New-Sm0EventLine "SM0_TARGET_ACTIVATED" "authority/sm0/b" 1 1000300 2 "inc-b-1")
    }
    else {
        $B += (New-Sm0EventLine "SM0_STALE_JOIN_ACCEPTED_FIXTURE" "authority/sm0/b" 1 1000150 2 "inc-b-1")
    }
    Set-Content -LiteralPath (Join-Path $Directory "server-a.log") -Value $A -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Directory "server-b.log") -Value $B -Encoding UTF8
}

try {
    $PassDir = Join-Path $Root "pass"
    Write-Fixture -Directory $PassDir -Overlap:$false
    & $Analyzer -LogDirectory $PassDir
    if ($LASTEXITCODE -ne 0) {
        throw "Aggregate writer analyzer rejected the valid retire-before-activate fixture."
    }
    $PassSummary = Get-Content -LiteralPath (Join-Path $PassDir "p4-global-writer-audit.json") -Raw | ConvertFrom-Json
    if ([string]$PassSummary.result -ne "PASS" -or [int]$PassSummary.max_aggregate_writer_count -ne 1) {
        throw "Valid fixture produced unexpected analyzer result."
    }

    $FailDir = Join-Path $Root "fail"
    Write-Fixture -Directory $FailDir -Overlap:$true
    & $Analyzer -LogDirectory $FailDir
    $NegativeExit = $LASTEXITCODE
    if ($NegativeExit -eq 0) {
        throw "Aggregate writer analyzer FALSE-PASSED the prohibited A=1 + B=1 fixture."
    }
    $FailSummary = Get-Content -LiteralPath (Join-Path $FailDir "p4-global-writer-audit.json") -Raw | ConvertFrom-Json
    if ([string]$FailSummary.result -ne "FAIL" -or [int]$FailSummary.max_aggregate_writer_count -lt 2) {
        throw "Negative fixture did not record the expected aggregate writer overlap."
    }

    Write-Host "SM0-P4 aggregate writer analyzer self-test: PASS" -ForegroundColor Green
    Write-Host "  valid retire-before-activate fixture : rejected overlap = no"
    Write-Host "  prohibited A=1 + B=1 fixture         : detected = yes"
    exit 0
}
finally {
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
