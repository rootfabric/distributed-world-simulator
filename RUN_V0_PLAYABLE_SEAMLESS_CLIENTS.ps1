param(
    [string]$GodotPath = "",
    [ValidateSet("Seam","Items","All")]
    [string]$Scenario = "All",
    [switch]$Observe,
    [ValidateRange(100,5000)]
    [int]$StepMs = 800
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExpectedGodot = "4.7.1.stable.double.custom_build.a13da4feb"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
        $GodotPath = $env:GODOT_BIN
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:GODOT)) {
        $GodotPath = $env:GODOT
    }
}

if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path $GodotPath)) {
    throw "GodotPath is required. Point it to the Godot 4.7.1 double Windows executable."
}

$ActualGodot = ((& $GodotPath --version 2>&1) | Select-Object -First 1).ToString().Trim()
if ($ActualGodot -ne $ExpectedGodot) {
    throw "Godot version mismatch. Expected '$ExpectedGodot', actual '$ActualGodot'."
}

$GitHead = (& git -C $Root rev-parse HEAD 2>$null).Trim()
if ([string]::IsNullOrWhiteSpace($GitHead)) {
    throw "Git HEAD is unavailable. Run from a repository checkout."
}

$OriginalObserve = [Environment]::GetEnvironmentVariable("DWS_TEST_CLIENT_OBSERVE", "Process")
$OriginalStep = [Environment]::GetEnvironmentVariable("DWS_TEST_CLIENT_STEP_MS", "Process")
if ($Observe) { $env:DWS_TEST_CLIENT_OBSERVE = "1" } else { $env:DWS_TEST_CLIENT_OBSERVE = "0" }
$env:DWS_TEST_CLIENT_STEP_MS = $StepMs.ToString()

function Invoke-TestClientGate {
    param(
        [string]$Name,
        [string]$Script
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host " DWS TEST CLIENT: $Name" -ForegroundColor Cyan
    Write-Host " HEAD: $GitHead"
    Write-Host " Godot: $ActualGodot"
    Write-Host " Observe: $Observe   StepMs: $StepMs"
    Write-Host "============================================================" -ForegroundColor DarkCyan

    & $GodotPath --headless --path $Root --script $Script

    if ($LASTEXITCODE -ne 0) {
        throw "Test client gate '$Name' failed with exit code $LASTEXITCODE."
    }

    Write-Host "PASS: $Name" -ForegroundColor Green
}

try {
    switch ($Scenario) {
        "Seam" {
            Invoke-TestClientGate -Name "SEAM / 2 clients + Gateway + Authority A/B" -Script "res://tests/runtime/test_v0_test_client_seam_processes.gd"
        }
        "Items" {
            Invoke-TestClientGate -Name "ITEMS / 2 clients + canonical Item Graph" -Script "res://tests/runtime/test_v0_test_client_items_processes.gd"
        }
        "All" {
            Invoke-TestClientGate -Name "SEAM / 2 clients + Gateway + Authority A/B" -Script "res://tests/runtime/test_v0_test_client_seam_processes.gd"
            Invoke-TestClientGate -Name "ITEMS / 2 clients + canonical Item Graph" -Script "res://tests/runtime/test_v0_test_client_items_processes.gd"
        }
    }
}
finally {
    if ($null -eq $OriginalObserve) {
        Remove-Item Env:DWS_TEST_CLIENT_OBSERVE -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable("DWS_TEST_CLIENT_OBSERVE", $OriginalObserve, "Process")
    }

    if ($null -eq $OriginalStep) {
        Remove-Item Env:DWS_TEST_CLIENT_STEP_MS -ErrorAction SilentlyContinue
    }
    else {
        [Environment]::SetEnvironmentVariable("DWS_TEST_CLIENT_STEP_MS", $OriginalStep, "Process")
    }
}

Write-Host ""
Write-Host "V0 PLAYABLE SEAMLESS TEST CLIENTS: PASS" -ForegroundColor Green
Write-Host "Scenario: $Scenario"
Write-Host "Exact HEAD: $GitHead"
Write-Host "Artifacts: $Root\artifacts\test-results\v0-test-client-*"
