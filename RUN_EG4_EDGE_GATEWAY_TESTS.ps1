param(
    [string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "eg4-edge-gateway-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

function Resolve-GodotExecutable {
    param([string]$RequestedPath)
    $Candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $Candidates += $RequestedPath }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) { $Candidates += $env:GODOT_BIN }

    if ($env:HOME) {
        $Candidates += (Join-Path $env:HOME ".local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64")
    }

    $Candidates += @(
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )

    foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
        $Command = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Command) { $Candidates += $Command.Source }
    }

    foreach ($Candidate in ($Candidates | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path $Candidate)) {
            return (Resolve-Path $Candidate).Path
        }
    }
    throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath."
}

function Write-JsonFileAtomically {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 8
    )

    $Directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($Directory)) { $Directory = (Get-Location).Path }
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null

    $FileName = [IO.Path]::GetFileName($Path)
    $Suffix = "$PID.$([Guid]::NewGuid().ToString('N'))"
    $TemporaryPath = Join-Path $Directory ".$FileName.$Suffix.tmp"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    try {
        $Json = $Value | ConvertTo-Json -Depth $Depth
        if ([string]::IsNullOrWhiteSpace($Json)) { throw "JSON serialization produced an empty summary" }
        $Bytes = $Utf8NoBom.GetBytes($Json + [Environment]::NewLine)
        $Stream = [IO.File]::Open($TemporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $Stream.Write($Bytes, 0, $Bytes.Length)
            $Stream.Flush($true)
        }
        finally {
            $Stream.Dispose()
        }
        $null = [IO.File]::ReadAllText($TemporaryPath, $Utf8NoBom) | ConvertFrom-Json -ErrorAction Stop
        # Review R2-D: publish atomically. Move-Item -Force overwrites the
        # destination in one step (mv -f semantics); the previous explicit
        # Delete followed by Move left a window with NO summary file at all.
        Move-Item -LiteralPath $TemporaryPath -Destination $Path -Force
    }
    catch {
        if ([IO.File]::Exists($TemporaryPath)) { [IO.File]::Delete($TemporaryPath) }
        throw
    }
}

# Native stderr redirected with 2>&1 must not become a terminating error:
# Godot prints benign diagnostics on stderr, so capture with Continue and let
# exit codes plus marker scanning decide.
function Invoke-GodotCapture {
    param([string[]]$GodotArguments)
    $PreviousEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $RawOutput = & $Godot @GodotArguments 2>&1
        $Code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousEap
    }
    return [pscustomobject]@{
        ExitCode = $Code
        Lines = @($RawOutput | ForEach-Object { "$_" })
    }
}

$Godot = Resolve-GodotExecutable -RequestedPath $GodotPath
$Tests = @(
    "res://tests/network/test_eg4_world_fixture.gd",
    "res://tests/network/test_eg4_view_planner.gd",
    "res://tests/network/test_eg4_interest_aggregator.gd",
    "res://tests/network/test_eg4_projection_aggregation.gd",
    "res://tests/network/test_eg4_projection_lifecycle.gd",
    "res://tests/network/test_eg4_two_worlds_one_transport.gd",
    "res://tests/network/test_eg4_gateway_processes.gd"
)

# Failure markers any EG4 test may print on an assertion breach.
$FailureMarkers = @("][FAIL]", '"verdict": "FAIL"', "SCRIPT ERROR:", "PREDICATE_NOT_DEMONSTRATED")

$Summary = [ordered]@{
    schema = "planet_simulator.eg4_edge_gateway_suite_summary.v1"
    stage = "EG4_WORLD_GRAPH_DRIVEN_PROJECTION_AGGREGATION"
    godot = $Godot
    started_at_utc = ([DateTime]::UtcNow.ToString("o"))
    passed = $false
    tests = @()
}

function Save-Summary {
    Write-JsonFileAtomically -Value $Summary -Path $ReportPath
}

$previous = $env:BREAKPOINT_RUNTIME_DISABLED
try {
    Write-Host "Godot: $Godot"
    Write-Host "Stage: EG4 WORLD_GRAPH_DRIVEN_PROJECTION_AGGREGATION"
    $env:BREAKPOINT_RUNTIME_DISABLED = "1"

    $EditorRun = Invoke-GodotCapture -GodotArguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit")
    if ($EditorRun.ExitCode -ne 0) { throw "Godot editor import/parse failed with exit code $($EditorRun.ExitCode)" }
    $EditorText = $EditorRun.Lines -join [Environment]::NewLine
    foreach ($Marker in $FailureMarkers) {
        if ($EditorText.Contains($Marker)) { throw "Editor import transcript contains failure marker: $Marker" }
    }

    foreach ($Test in $Tests) {
        $Name = [IO.Path]::GetFileNameWithoutExtension($Test)
        Write-Host "[$Test]" -ForegroundColor Cyan
        $Run = Invoke-GodotCapture -GodotArguments @("--headless", "--path", $ProjectRoot, "--script", $Test)
        $TranscriptText = $Run.Lines -join [Environment]::NewLine
        $MarkerHits = @($FailureMarkers | Where-Object { $TranscriptText.Contains($_) })
        $VerdictLine = @($Run.Lines | Where-Object { $_ -like '*"verdict":*' } | Select-Object -Last 1)
        $Entry = [ordered]@{
            test = $Name
            exit_code = $Run.ExitCode
            failure_markers = $MarkerHits
            verdict_line = $VerdictLine
            passed = ($Run.ExitCode -eq 0 -and $MarkerHits.Count -eq 0)
        }
        $Summary.tests += $Entry
        Save-Summary
        Write-Host $VerdictLine
        if (-not $Entry.passed) {
            throw "$Test failed (exit code $($Run.ExitCode), markers: $($MarkerHits -join ', '))"
        }
    }

    $Summary.passed = $true
    Save-Summary
    Write-Host "EG4 world-graph-driven projection aggregation suite: PASS" -ForegroundColor Green
    Write-Host "Report: $ReportPath"
    exit 0
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}
finally {
    if ($null -eq $previous) {
        Remove-Item Env:\BREAKPOINT_RUNTIME_DISABLED -ErrorAction SilentlyContinue
    }
    else {
        $env:BREAKPOINT_RUNTIME_DISABLED = $previous
    }
}
