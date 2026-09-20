# ECO ARCH2 A10.5 / ECO-POLYGON-1 — launch/test tool (P13).
#
# Usage:
#   .\RUN_ECO_A10_5_POLYGON.ps1              open the polygon LAB scene in the Godot editor for manual GUI checks
#   .\RUN_ECO_A10_5_POLYGON.ps1 -Test        run ALL validation/ecology/evo_arch2_a10_5/test_*.gd headless,
#                                            one by one, with a PASS/FAIL summary table and total counts
#   .\RUN_ECO_A10_5_POLYGON.ps1 -Test <name> run ONE test (name with or without the .gd extension)
#
# Notes:
#   - Godot canonical console binary (docs/GODOT_LOCAL_TESTING_RU.md).
#   - Tests run via Start-Process + --log-file + a timeout watchdog
#     (RedirectStandardOutput deadlocks Godot on Windows).
#   - Heavy tests (world_compat, final e2e, batch) get 900s; the rest 300s.

param(
    [switch]$Test,
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"

$GodotBin  = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
$GodotGui  = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe"
$Project   = $PSScriptRoot
$TestDir   = Join-Path $Project "validation\ecology\evo_arch2_a10_5"
$LabScene  = "res://scenes/labs/ecology/eco_arch2_polygon_lab.tscn"
$LogDir    = Join-Path $Project "artifacts\runtime\eco-a10-5-polygon"

if (-not (Test-Path $GodotBin)) { throw "Godot console binary not found: $GodotBin" }

# --- GUI mode: manual lab checks --------------------------------------------------
if (-not $Test) {
    if (-not (Test-Path $GodotGui)) { throw "Godot GUI binary not found: $GodotGui" }
    Write-Host "ECO A10.5 POLYGON: opening lab scene $LabScene (GUI, manual checks)..."
    Start-Process -FilePath $GodotGui -ArgumentList @("--path", "`"$Project`"", "`"$LabScene`"")
    exit 0
}

# --- Headless test mode ------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Invoke-GodotTest {
    param([string]$TestPath, [int]$TimeoutSec)
    $testName = [IO.Path]::GetFileNameWithoutExtension($TestPath)
    $logFile  = Join-Path $LogDir "$testName.log"
    if (Test-Path $logFile) { Remove-Item $logFile -Force }
    $args = @("--headless", "--path", "`"$Project`"", "--log-file", "`"$logFile`"", "--script", "`"res://$($TestPath.Substring($Project.Length + 1).Replace('\','/'))`"")
    $proc = Start-Process -FilePath $GodotBin -ArgumentList $args -PassThru
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        Write-Warning "$testName TIMEOUT after ${TimeoutSec}s - killing Godot processes"
        Get-Process -Name "*godot*" -ErrorAction SilentlyContinue | Stop-Process -Force
        $proc.WaitForExit(10000) | Out-Null
        return @{ Name = $testName; Status = "TIMEOUT"; Exit = -1 }
    }
    $log = ""
    if (Test-Path $logFile) { $log = Get-Content $logFile -Raw }
    $passed  = $log -match "(?m)^EVO_ARCH2_A10_5\S+ PASS\s*$"
    $summary = ""
    if ($log -match "(?m)^(EVO_ARCH2_A10_5\S+ checks=\d+ failed=\d+)") { $summary = $Matches[1] }
    $status = if ($proc.ExitCode -eq 0 -and $passed) { "PASS" } else { "FAIL" }
    return @{ Name = $testName; Status = $status; Exit = $proc.ExitCode; Summary = $summary }
}

# Heavy tests get 900s; everything else 300s.
$heavyTests = @("test_world_compat", "test_final_polygon_e2e", "test_batch_compare", "test_portability", "test_controller_equivalence", "test_time_controls")

if ($Name -ne "") {
    if ($Name -notlike "*.gd") { $Name = "$Name.gd" }
    $targets = @(Get-ChildItem -Path $TestDir -Filter $Name -File)
    if ($targets.Count -eq 0) { throw "Test not found: $Name (in $TestDir)" }
} else {
    $targets = @(Get-ChildItem -Path $TestDir -Filter "test_*.gd" -File | Sort-Object Name)
}

$results = @()
foreach ($t in $targets) {
    $timeout = if ($heavyTests -contains $t.BaseName) { 900 } else { 300 }
    Write-Host ("[" + ($targets.IndexOf($t) + 1) + "/" + $targets.Count + "] " + $t.BaseName + " (timeout ${timeout}s) ...") -NoNewline
    $r = Invoke-GodotTest -TestPath $t.FullName -TimeoutSec $timeout
    $results += $r
    Write-Host (" " + $r.Status + "  " + $r.Summary)
}

# --- summary table -----------------------------------------------------------------
Write-Host ""
Write-Host "================ ECO A10.5 POLYGON — TEST SUMMARY ================"
$pass = 0; $fail = 0
foreach ($r in $results) {
    $mark = "[PASS]"; if ($r.Status -eq "PASS") { $pass++ } else { $mark = "[" + $r.Status + "]"; $fail++ }
    Write-Host ("{0} {1,-32} {2}" -f $mark, $r.Name, $r.Summary)
}
Write-Host "-------------------------------------------------------------------"
Write-Host ("TOTAL: {0} tests | PASS: {1} | FAIL: {2} | logs: {3}" -f $results.Count, $pass, $fail, $LogDir)
Write-Host "==================================================================="
if ($fail -gt 0) { exit 1 } else { exit 0 }
