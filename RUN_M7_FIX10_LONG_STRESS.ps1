param(
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [int]$DurationSeconds = 330,
    [string]$NetworkProfile = "LOCAL",
    [switch]$DiagnosticOnly
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path
$DurationSeconds = [Math]::Max($DurationSeconds, $(if ($DiagnosticOnly) { 20 } else { 300 }))
$DurationMs = $DurationSeconds * 1000
$ServerShutdownMs = $DurationMs + 120000
$NetworkProfile = $NetworkProfile.Trim().ToUpperInvariant()
if ($NetworkProfile -ne "LOCAL") {
    throw "FIX10 final acceptance runner currently requires NetworkProfile=LOCAL"
}

function Get-FreeTcpPort {
    $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $Listener.Start()
        return ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
    }
    finally {
        $Listener.Stop()
    }
}

function Read-JsonSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Wait-JsonState {
    param(
        [string]$Path,
        [string[]]$States,
        [int]$TimeoutMs,
        [System.Diagnostics.Process]$Process = $null
    )
    $Started = [Environment]::TickCount64
    while (([Environment]::TickCount64 - $Started) -lt $TimeoutMs) {
        $Value = Read-JsonSafe -Path $Path
        if ($null -ne $Value -and $States -contains [string]$Value.state) {
            return $Value
        }
        if ($null -ne $Process -and $Process.HasExited) {
            return $Value
        }
        Start-Sleep -Milliseconds 100
    }
    return (Read-JsonSafe -Path $Path)
}

function Start-IsolatedGodot {
    param(
        [string[]]$Arguments,
        [string]$UserRoot
    )
    $Names = @(
        "HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME",
        "APPDATA", "LOCALAPPDATA", "BREAKPOINT_RUNTIME_DISABLED",
        "GODOT_SILENCE_ROOT_WARNING"
    )
    $Saved = @{}
    foreach ($Name in $Names) {
        $Saved[$Name] = [pscustomobject]@{
            Exists = [Environment]::GetEnvironmentVariable($Name, "Process") -ne $null
            Value = [Environment]::GetEnvironmentVariable($Name, "Process")
        }
    }
    foreach ($Path in @(
        $UserRoot,
        (Join-Path $UserRoot "data"),
        (Join-Path $UserRoot "config"),
        (Join-Path $UserRoot "cache")
    )) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
    try {
        [Environment]::SetEnvironmentVariable("HOME", $UserRoot, "Process")
        [Environment]::SetEnvironmentVariable("XDG_DATA_HOME", (Join-Path $UserRoot "data"), "Process")
        [Environment]::SetEnvironmentVariable("XDG_CONFIG_HOME", (Join-Path $UserRoot "config"), "Process")
        [Environment]::SetEnvironmentVariable("XDG_CACHE_HOME", (Join-Path $UserRoot "cache"), "Process")
        [Environment]::SetEnvironmentVariable("APPDATA", (Join-Path $UserRoot "data"), "Process")
        [Environment]::SetEnvironmentVariable("LOCALAPPDATA", (Join-Path $UserRoot "data"), "Process")
        [Environment]::SetEnvironmentVariable("BREAKPOINT_RUNTIME_DISABLED", "1", "Process")
        [Environment]::SetEnvironmentVariable("GODOT_SILENCE_ROOT_WARNING", "1", "Process")
        return Start-Process -FilePath $Godot -ArgumentList $Arguments -PassThru
    }
    finally {
        foreach ($Name in $Names) {
            if ($Saved[$Name].Exists) {
                [Environment]::SetEnvironmentVariable($Name, [string]$Saved[$Name].Value, "Process")
            }
            else {
                [Environment]::SetEnvironmentVariable($Name, $null, "Process")
            }
        }
    }
}

function Stop-ProcessSafe {
    param([System.Diagnostics.Process]$Process)
    if ($null -eq $Process) {
        return
    }
    try {
        if (-not $Process.HasExited) {
            Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    catch {}
}

function Write-LiveDiagnosticSummary {
    param([object]$Result, [string]$Label)
    if ($null -eq $Result) {
        return
    }
    $Prediction = $Result.world_report.m7_prediction_report
    if ($null -eq $Prediction -and $null -ne $Result.runtime_report.client_prediction) {
        $Prediction = $Result.runtime_report.client_prediction.runtime
    }
    $Transport = $Result.runtime_report.fix10_prediction_ack_transport
    Write-Host ("Client {0} live: state={1}, duration={2:N1}s, corrections={3}, max_error={4:N4}m, phase matched/mismatch={5}/{6}, hold_delta={7}, transition_error={8:N6}m, latch_suppressions={9}" -f `
        $Label, [string]$Result.state, ([double]$Result.details.stress_duration_ms / 1000.0), `
        [int]$Prediction.corrections, [double]$Prediction.maximum_error_m, `
        [int]$Prediction.fix10_fix6_phase_matched_ack_reconciliations, `
        [int]$Prediction.fix10_fix6_phase_mismatch_authority_reconciliations, `
        [int]$Prediction.fix10_fix6_max_hold_delta_ticks, `
        [double]$Prediction.fix10_fix6_max_transition_delta_error_m, `
        [int]$Transport.fix6_same_tick_input_update_suppressions)
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ModeName = if ($DiagnosticOnly) { "diagnostic" } else { "long" }
$OutDir = Join-Path $ProjectRoot "artifacts\test-results\m7-fix10-$ModeName-$Timestamp"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ServerJson = Join-Path $OutDir "server.json"
$ClientAJson = Join-Path $OutDir "a.json"
$ClientBJson = Join-Path $OutDir "b.json"
$ServerLog = Join-Path $OutDir "server.log"
$ClientALog = Join-Path $OutDir "a.log"
$ClientBLog = Join-Path $OutDir "b.log"
$AnalysisJson = Join-Path $OutDir "fix10-fix6-analysis.json"
$Port = Get-FreeTcpPort

$ServerProcess = $null
$ClientAProcess = $null
$ClientBProcess = $null

Write-Host "M7 FIX10 fix6 prediction stress" -ForegroundColor Cyan
Write-Host "Project: $ProjectRoot"
Write-Host "Output:  $OutDir"
Write-Host "Profile: $NetworkProfile"
Write-Host "Mode:    $(if ($DiagnosticOnly) { 'VISUAL DIAGNOSTIC - NOT ACCEPTANCE' } else { 'FINAL ACCEPTANCE' })"
Write-Host "Stress:  $DurationSeconds seconds"

try {
    $ServerArgs = @(
        "--headless", "--quiet", "--path", $ProjectRoot,
        "--log-file", $ServerLog,
        "--",
        "--role=dedicated-server",
        "--network-playground",
        "--world=playground",
        "--node-id=m7-fix10-long-server",
        "--server-address=127.0.0.1",
        "--server-port=$Port",
        "--m7-result-file=$ServerJson",
        "--shutdown-after-ms=$ServerShutdownMs"
    )
    $ServerProcess = Start-IsolatedGodot -Arguments $ServerArgs -UserRoot (Join-Path $OutDir "user-server")
    $ServerReady = Wait-JsonState -Path $ServerJson -States @("READY", "FAILED") -TimeoutMs 30000 -Process $ServerProcess
    if ($null -eq $ServerReady -or [string]$ServerReady.state -ne "READY") {
        throw "FIX10 prediction stress dedicated server did not reach READY"
    }
    Write-Host "Server READY on 127.0.0.1:$Port" -ForegroundColor Green

    $CommonClientArgs = @(
        "--quiet", "--path", $ProjectRoot,
        "--rendering-method", "gl_compatibility",
        "--audio-driver", "Dummy"
    )
    $DiagnosticArg = if ($DiagnosticOnly) { "--diagnostic=1" } else { "--diagnostic=0" }
    $ClientAArgs = $CommonClientArgs + @(
        "--log-file", $ClientALog,
        "--script", "res://tools/runtime/m7_fix10_long_prediction_client.gd",
        "--",
        "--host=127.0.0.1",
        "--port=$Port",
        "--client-id=a",
        "--phase=1",
        "--result-file=$ClientAJson",
        "--peer-file=$ClientBJson",
        "--server-file=$ServerJson",
        "--network-profile=$NetworkProfile",
        "--duration-ms=$DurationMs",
        $DiagnosticArg
    )
    $ClientBArgs = $CommonClientArgs + @(
        "--log-file", $ClientBLog,
        "--script", "res://tools/runtime/m7_fix10_long_prediction_client.gd",
        "--",
        "--host=127.0.0.1",
        "--port=$Port",
        "--client-id=b",
        "--phase=2",
        "--result-file=$ClientBJson",
        "--peer-file=$ClientAJson",
        "--server-file=$ServerJson",
        "--network-profile=$NetworkProfile",
        "--duration-ms=$DurationMs",
        $DiagnosticArg
    )

    $ClientAProcess = Start-IsolatedGodot -Arguments $ClientAArgs -UserRoot (Join-Path $OutDir "user-a")
    $ClientBProcess = Start-IsolatedGodot -Arguments $ClientBArgs -UserRoot (Join-Path $OutDir "user-b")

    $ClientTimeoutMs = $DurationMs + 120000
    $ClientAResult = Wait-JsonState -Path $ClientAJson -States @("COMPLETE", "FAILED") -TimeoutMs $ClientTimeoutMs -Process $ClientAProcess
    $ClientBResult = Wait-JsonState -Path $ClientBJson -States @("COMPLETE", "FAILED") -TimeoutMs $ClientTimeoutMs -Process $ClientBProcess

    if ($null -eq $ClientAResult -or [string]$ClientAResult.state -ne "COMPLETE" -or -not [bool]$ClientAResult.passed) {
        Write-LiveDiagnosticSummary -Result $ClientAResult -Label "A"
        Write-LiveDiagnosticSummary -Result $ClientBResult -Label "B"
        throw "FIX10 prediction stress client A failed/stopped; inspect $ClientALog and $ClientAJson"
    }
    if ($null -eq $ClientBResult -or [string]$ClientBResult.state -ne "COMPLETE" -or -not [bool]$ClientBResult.passed) {
        Write-LiveDiagnosticSummary -Result $ClientAResult -Label "A"
        Write-LiveDiagnosticSummary -Result $ClientBResult -Label "B"
        throw "FIX10 prediction stress client B failed/stopped; inspect $ClientBLog and $ClientBJson"
    }

    Start-Sleep -Milliseconds 1500
    $ServerFinal = Read-JsonSafe -Path $ServerJson
    if ($null -eq $ServerFinal -or [string]$ServerFinal.state -notin @("READY", "PASS")) {
        throw "FIX10 prediction stress server report is not healthy after client completion"
    }

    Write-LiveDiagnosticSummary -Result $ClientAResult -Label "A"
    Write-LiveDiagnosticSummary -Result $ClientBResult -Label "B"
    Write-Host "Two-client prediction-only stress completed." -ForegroundColor Green

    if ($DiagnosticOnly) {
        Write-Host ""
        Write-Host "M7 FIX10 fix6 visual diagnostic completed - NOT AN ACCEPTANCE PASS." -ForegroundColor Yellow
        Write-Host "Results: $OutDir"
        return
    }

    Write-Host ""
    $Analyzer = Join-Path $ProjectRoot "ANALYZE_M7_FIX10_FIX6_RESULTS.ps1"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Analyzer `
        -ServerJson $ServerJson `
        -ClientAJson $ClientAJson `
        -ClientBJson $ClientBJson `
        -OutputJson $AnalysisJson
    if ($LASTEXITCODE -ne 0) {
        throw "FIX10 fix6 semantic acceptance analyzer failed"
    }

    Write-Host ""
    Write-Host "M7 FIX10 fix6 long prediction acceptance: PASS" -ForegroundColor Green
    Write-Host "Results: $OutDir"
}
finally {
    Stop-ProcessSafe -Process $ClientAProcess
    Stop-ProcessSafe -Process $ClientBProcess
    Stop-ProcessSafe -Process $ServerProcess
}