param([string]$GodotPath = "", [string]$Scenario = "")
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Candidates = @($GodotPath, $env:GODOT_BIN,
  "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
  "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe")
foreach ($Name in @("godot.windows.editor.double.x86_64.console.exe", "godot4", "godot")) {
  $Command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -ne $Command) { $Candidates += $Command.Source }
}
$Godot = $Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } | Select-Object -Unique | Select-Object -First 1
if ($null -eq $Godot) { throw "Double-precision Godot was not found. Set GODOT_BIN or pass -GodotPath." }

function Invoke-GodotChecked {
  param([string]$Name, [string[]]$Arguments)
  $Captured = @()
  $PreviousErrorActionPreference = $ErrorActionPreference
  $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
  $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
  try {
    # Windows PowerShell 5.1 converts native stderr records into non-terminating
    # NativeCommandError objects. Keep collecting them as diagnostics instead
    # of allowing the runner-wide Stop preference to abort a successful test.
    $ErrorActionPreference = "Continue"
    if ($null -ne $NativePreference) {
      Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
    }
    & $Godot @Arguments 2>&1 | Tee-Object -Variable Captured | ForEach-Object { Write-Host $_ }
    $ExitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $PreviousErrorActionPreference
    if ($null -ne $NativePreference) {
      Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
    }
  }
  $OutputText = ($Captured | Out-String)
  if ($ExitCode -ne 0 -or $OutputText -match '(?m): FAIL(?:\s|\()') {
    throw "$Name failed (exit code $ExitCode)"
  }
}
function Read-JsonReportWithRetry {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$TimeoutMs = 5000,
    [int]$PollMs = 50
  )
  $Deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
  $LastError = $null
  do {
    if (Test-Path -LiteralPath $Path) {
      try {
        $Text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
          return ($Text | ConvertFrom-Json -ErrorAction Stop)
        }
      }
      catch {
        $LastError = $_
      }
    }
    Start-Sleep -Milliseconds $PollMs
  } while ([DateTime]::UtcNow -lt $Deadline)
  if ($null -ne $LastError) {
    throw "JSON report was not complete after ${TimeoutMs}ms: $Path. Last error: $LastError"
  }
  throw "JSON report was not produced after ${TimeoutMs}ms: $Path"
}

$ReportRoot = Join-Path $ProjectRoot "artifacts/test-results"
New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null
Invoke-GodotChecked -Name "Editor import" -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit")
foreach ($Test in @("res://tests/testing/test_n2_process_harness_contracts.gd", "res://tests/testing/test_n2_process_harness_processes.gd")) {
  Invoke-GodotChecked -Name $Test -Arguments @("--headless", "--path", $ProjectRoot, "--script", $Test)
}
$Args = @("--headless", "--path", $ProjectRoot, "--script", "res://tools/testing/n2_process_harness_runner.gd", "--",
  "--result-file=$(Join-Path $ReportRoot 'n2-process-harness-summary.json')",
  "--junit-file=$(Join-Path $ReportRoot 'n2-process-harness-junit.xml')",
  "--output-root=$(Join-Path $ReportRoot 'n2-process-runs')")
if (-not [string]::IsNullOrWhiteSpace($Scenario)) { $Args += "--scenario=$Scenario" }
Invoke-GodotChecked -Name "N2 process harness" -Arguments $Args
$HarnessSummary = Read-JsonReportWithRetry -Path (Join-Path $ReportRoot "n2-process-harness-summary.json")
if (-not $HarnessSummary.passed) { throw "N2 process harness summary reported failure" }
Write-Host "N2 process harness tests passed." -ForegroundColor Green
