param(
    [string]$GodotPath = "",
    [int]$Port = 39965,
    [string]$EvidencePath = ""
)

$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot
$Launcher = Join-Path $Root "PLAY_CH9_6_NETWORK_EQUIPMENT_LAB.ps1"
$Garment = Join-Path $Root "assets\external\quaternius\modular_outfits_fantasy\Modular Character Outfits - Fantasy[Standard]\Exports\glTF (Godot-Unreal)\Outfits\Male_Peasant.gltf"
$PowerShellExe = if ($PSVersionTable.PSEdition -eq "Core") {
    Join-Path $PSHOME "pwsh.exe"
} else {
    Join-Path $PSHOME "powershell.exe"
}

if (-not (Test-Path -LiteralPath $Launcher -PathType Leaf)) {
    throw "CH9.6 launcher not found: $Launcher"
}
if (-not (Test-Path -LiteralPath $PowerShellExe -PathType Leaf)) {
    throw "PowerShell executable not found: $PowerShellExe"
}
if ($Port -lt 1024 -or $Port -gt 65535) {
    throw "Port must be in range 1024..65535."
}

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $Candidates = @(
        $env:GODOT_BIN,
        "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
        "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe"
    )
    foreach ($Candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($Candidate) -and (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
            $GodotPath = (Resolve-Path -LiteralPath $Candidate).Path
            break
        }
    }
}

if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable not found. Expected C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe or pass a valid -GodotPath. Do not insert a backslash before the underscore in x86_64."
}
if (-not (Test-Path -LiteralPath $Garment -PathType Leaf)) {
    throw "CH9.6 Quaternius garment asset is missing in this worktree: $Garment`nCopy/link the accepted assets into this checkout before graphical acceptance."
}

Write-Host "Godot preflight: PASS -> $GodotPath" -ForegroundColor Green
Write-Host "Quaternius asset preflight: PASS" -ForegroundColor Green

if ([string]::IsNullOrWhiteSpace($EvidencePath)) {
    $EvidenceDir = Join-Path $Root "artifacts\ch9-6-manual"
    New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
    $Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $EvidencePath = Join-Path $EvidenceDir "ch9-6-graphical-acceptance-$Stamp.json"
} elseif (-not [System.IO.Path]::IsPathRooted($EvidencePath)) {
    $EvidencePath = Join-Path $Root $EvidencePath
}

$EvidenceDirectory = Split-Path -Parent $EvidencePath
if (-not [string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
}

function Read-YesNo {
    param([Parameter(Mandatory = $true)][string]$Question)

    while ($true) {
        $Answer = (Read-Host "$Question [y/n]").Trim().ToLowerInvariant()
        if ($Answer -in @("y", "yes")) { return $true }
        if ($Answer -in @("n", "no")) { return $false }
        Write-Host "Enter y or n." -ForegroundColor Yellow
    }
}

function Invoke-Ch96Lab {
    param([switch]$ResetState)

    $ChildArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $Launcher,
        "-Port", [string]$Port,
        "-GodotPath", $GodotPath
    )
    if ($ResetState) { $ChildArgs += "-ResetState" }

    Write-Host "Launching graphical CH9.6 client..." -ForegroundColor Cyan
    & $PowerShellExe @ChildArgs
    return [int]$LASTEXITCODE
}

$Head = "UNKNOWN"
try {
    $HeadCandidate = (& git -C $Root rev-parse HEAD 2>$null | Select-Object -First 1)
    if ($null -ne $HeadCandidate -and -not [string]::IsNullOrWhiteSpace($HeadCandidate)) {
        $Head = $HeadCandidate.Trim()
    }
} catch { $Head = "UNKNOWN" }

Write-Host ""
Write-Host "CH9.6 MANUAL GRAPHICAL ACCEPTANCE" -ForegroundColor Cyan
Write-Host "Repository head: $Head" -ForegroundColor Cyan
Write-Host "This runner does not infer PASS. It records only your explicit visual observations." -ForegroundColor Yellow
Write-Host ""
Write-Host "PASS 1 / RESET STATE" -ForegroundColor Cyan
Write-Host "1. Wait for HUD status READY and the Inventory UI to open." -ForegroundColor Cyan
Write-Host "2. Drag lower/upper/feet wearables from backpack into equipment slots." -ForegroundColor Cyan
Write-Host "3. Confirm clothing appears on the real Quaternius character." -ForegroundColor Cyan
Write-Host "4. Press Tab, then verify walking, jump and crouch." -ForegroundColor Cyan
Write-Host "5. Close the application normally." -ForegroundColor Cyan
Write-Host ""

$FirstExit = Invoke-Ch96Lab -ResetState
if ($FirstExit -ne 0) {
    throw "CH9.6 first graphical launch failed before acceptance questions (exit code $FirstExit). No graphical PASS can be recorded."
}

$FirstReady = Read-YesNo "Did the lab reach READY with the Inventory UI available?"
$FirstPresentation = Read-YesNo "Did equipped clothing appear correctly on the real Quaternius character?"
$FirstMovement = Read-YesNo "Did walking, jump and crouch remain functional while equipped?"
$FirstNormalClose = Read-YesNo "Did you close the first run normally after the checks?"

Write-Host ""
Write-Host "PASS 2 / RECOVERY" -ForegroundColor Cyan
Write-Host "1. Do not equip anything manually at startup." -ForegroundColor Cyan
Write-Host "2. Confirm the equipment slots and Quaternius presentation restore automatically." -ForegroundColor Cyan
Write-Host "3. Drag one restored equipped item back to backpack." -ForegroundColor Cyan
Write-Host "4. Confirm that exact wearable disappears from the character." -ForegroundColor Cyan
Write-Host "5. Close the application normally." -ForegroundColor Cyan
Write-Host ""

$SecondExit = Invoke-Ch96Lab
if ($SecondExit -ne 0) {
    throw "CH9.6 recovery graphical launch failed before recovery questions (exit code $SecondExit). No graphical PASS can be recorded."
}

$Recovered = Read-YesNo "Were the previously equipped items restored automatically after restart?"
$RecoveredPresentation = Read-YesNo "Was the recovered equipment already visible on the Quaternius character without a new drag?"
$UnequipPresentation = Read-YesNo "After dragging a restored item back to backpack, did its visual disappear?"

$AllObservations = @($FirstReady,$FirstPresentation,$FirstMovement,$FirstNormalClose,$Recovered,$RecoveredPresentation,$UnequipPresentation)
$ObservationPass = -not ($AllObservations -contains $false)
$ProcessPass = ($FirstExit -eq 0 -and $SecondExit -eq 0)
$Decision = if ($ObservationPass -and $ProcessPass) { "OPERATOR_REPORTED_PASS" } else { "OPERATOR_REPORTED_FAIL" }

$Evidence = [ordered]@{
    schema = "planet_simulator.ch9_6_manual_graphical_acceptance_evidence.v1"
    stage = "CH9.6 Playable Network Equipment Lab"
    branch = "feature/ch9-6-playable-network-equipment-lab"
    tested_head = $Head
    recorded_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    launcher = "PLAY_CH9_6_NETWORK_EQUIPMENT_LAB.ps1"
    operator_runner = "ACCEPT_CH9_6_GRAPHICAL.ps1"
    first_launch = [ordered]@{ reset_state = $true; exit_code = $FirstExit }
    second_launch = [ordered]@{ reset_state = $false; exit_code = $SecondExit }
    observations = [ordered]@{
        ready_and_inventory_available = $FirstReady
        equipped_quaternius_presentation_visible = $FirstPresentation
        movement_jump_crouch_functional = $FirstMovement
        first_run_closed_normally = $FirstNormalClose
        equipment_restored_after_restart = $Recovered
        recovered_quaternius_presentation_visible_without_new_drag = $RecoveredPresentation
        unequipped_visual_removed = $UnequipPresentation
    }
    process_pass = $ProcessPass
    observation_pass = $ObservationPass
    decision = $Decision
}

$Evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $EvidencePath -Encoding utf8

Write-Host ""
Write-Host "Evidence: $EvidencePath" -ForegroundColor Cyan
if ($Decision -eq "OPERATOR_REPORTED_PASS") {
    Write-Host "CH9.6 manual graphical acceptance: OPERATOR REPORTED PASS" -ForegroundColor Green
    Write-Host "Send the console output or evidence JSON for canonical acceptance + post-acceptance PC0." -ForegroundColor Green
    exit 0
}

Write-Host "CH9.6 manual graphical acceptance: OPERATOR REPORTED FAIL" -ForegroundColor Red
Write-Host "Do not advance CH9.6. Preserve the evidence JSON for diagnosis." -ForegroundColor Red
exit 2
