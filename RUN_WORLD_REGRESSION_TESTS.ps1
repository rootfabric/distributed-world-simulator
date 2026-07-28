$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "world-regression-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

$Candidates = @()
if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN)) {
    $Candidates += $env:GODOT_BIN
}

foreach ($CommandName in @(
    "godot.windows.editor.double.x86_64.console.exe",
    "godot.windows.editor.double.x86_64.exe",
    "godot4",
    "godot"
)) {
    $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        $Candidates += $Command.Source
    }
}

$Candidates += @(
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.console.exe",
    "C:\Godot\bin\godot.windows.editor.double.x86_64.exe"
)

$Godot = $Candidates |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) } |
    Select-Object -Unique |
    Select-Object -First 1

if ($null -eq $Godot) {
    throw "Double-precision Godot editor was not found. Set GODOT_BIN or add Godot to PATH."
}

$Tests = @(
    "res://tests/core/test_double_precision_contract.gd",
    "res://tests/unit/test_simulation_clock.gd",
    "res://tests/core/test_command_registry.gd",
    "res://tests/core/test_world_catalog.gd",
    "res://tests/core/test_controller_profiles.gd",
    "res://tests/core/test_hotkey_contract.gd",
    "res://tests/runtime/test_launch_options.gd",
    "res://tests/runtime/test_lifecycle_coordinator.gd",
    "res://tests/runtime/test_simulator_shutdown_failures.gd",
    "res://tests/network/test_network_contracts.gd",
    "res://tests/network/test_loopback_command_transport.gd",
    "res://tests/network/test_n0_extended_contracts.gd",
    "res://tests/network/test_n0_contract_mutation_matrix.gd",
    "res://tests/network/test_n0_golden_fixtures.gd",
    "res://tests/network/test_loopback_replication_transport.gd",
    "res://tests/network/test_handoff_state_machine.gd",
    "res://tests/network/test_handoff_transition_matrix.gd",
    "res://tests/entities/test_authority_revision_semantics.gd",
    "res://tests/runtime/test_kernel_ports.gd",
    "res://tests/entities/test_world_entity_aggregate.gd",
    "res://tests/entities/test_world_entity_store_failures.gd",
    "res://tests/items/test_world_item_aggregate_migration.gd",
    "res://tests/runtime/test_simulation_kernel_boundary.gd",
    "res://tests/unit/test_jetpack_controller.gd",
    "res://tests/unit/test_reference_frame_graph.gd",
    "res://tests/unit/test_celestial_motion.gd",
    "res://tests/unit/test_gravity_field.gd",
    "res://tests/unit/test_partition_address_v2.gd",
    "res://tests/unit/test_cube_sphere_grid.gd",
    "res://tests/unit/test_partition_foundation.gd",
    "res://tests/unit/test_atmosphere_layer.gd",
    "res://tests/unit/test_earth_generation_pipeline.gd",
    "res://tests/integration/test_controller_profiles.gd",
    "res://tests/integration/test_entity_registry_migration.gd",
    "res://tests/integration/test_first_person_interaction.gd",
    "res://tests/integration/test_persistence_roundtrip.gd",
    "res://tests/integration/test_terrain_streaming_contract.gd",
    "res://tests/items/test_item_domain.gd",
    "res://tests/items/test_item_identity_and_state_store.gd",
    "res://tests/items/test_item_graph_persistence.gd",
    "res://tests/items/test_item_operation_ledger.gd",
    "res://tests/items/test_item_physics_environment.gd",
    "res://tests/items/test_player_inventory_flow.gd",
    "res://tests/items/test_item_stack_transfers.gd",
    "res://tests/items/test_item_placement_and_admin.gd",
    "res://tests/items/test_item_lab_integration.gd",
    "res://tests/ui/test_console_system_menu_and_flashlight.gd",
    "res://tests/integration/test_unified_planetary_runtime.gd",
    "res://tests/integration/test_unified_runtime_boot.gd",
    "res://tests/runtime/test_world_switch_during_generation.gd",
    "res://tests/runtime/test_world_boot_matrix.gd"
)

$Summary = [ordered]@{
    schema = "planet_simulator.world_regression_summary.v1"
    checkpoint = "v16.4.0-foundation-n0"
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    finished_at_utc = $null
    godot = $Godot
    project_root = $ProjectRoot
    declared_test_count = $Tests.Count
    discovered_test_count = 0
    passed = $false
    steps = @()
}

function Save-Summary {
    $Summary.finished_at_utc = [DateTime]::UtcNow.ToString("o")
    $Summary | ConvertTo-Json -Depth 8 | Set-Content -Path $ReportPath -Encoding UTF8
}

function Add-StepResult {
    param(
        [string]$Name,
        [string]$Kind,
        [int]$ExitCode,
        [double]$DurationSeconds,
        [string]$Target = ""
    )

    $Summary.steps += [ordered]@{
        name = $Name
        kind = $Kind
        target = $Target
        exit_code = $ExitCode
        duration_seconds = [Math]::Round($DurationSeconds, 3)
        passed = ($ExitCode -eq 0)
    }
}

function Invoke-GodotStep {
    param(
        [string]$Name,
        [string]$Kind,
        [string[]]$Arguments,
        [string]$Target = ""
    )

    Write-Host "Running $Name"
    $Started = [DateTime]::UtcNow
    & $Godot @Arguments
    $ExitCode = $LASTEXITCODE
    $Duration = ([DateTime]::UtcNow - $Started).TotalSeconds
    Add-StepResult -Name $Name -Kind $Kind -ExitCode $ExitCode -DurationSeconds $Duration -Target $Target
    Save-Summary
    if ($ExitCode -ne 0) {
        throw "Regression step failed: $Name (exit code $ExitCode)"
    }
}

try {
    Write-Host "Godot: $Godot"

    $DiscoveredTests = Get-ChildItem -Path (Join-Path $ProjectRoot "tests") -Recurse -File -Filter "test_*.gd" |
        ForEach-Object {
            $RelativePath = $_.FullName.Substring($ProjectRoot.Length).TrimStart([char[]]@('\', '/'))
            "res://" + $RelativePath.Replace('\', '/')
        } |
        Sort-Object -Unique

    $Summary.discovered_test_count = $DiscoveredTests.Count
    $MissingFromRunner = @($DiscoveredTests | Where-Object { $_ -notin $Tests })
    $MissingFromProject = @($Tests | Where-Object { $_ -notin $DiscoveredTests })
    if ($MissingFromRunner.Count -gt 0 -or $MissingFromProject.Count -gt 0) {
        $CoverageMessage = @(
            "Regression runner coverage mismatch."
            "Missing from runner: $($MissingFromRunner -join ', ')"
            "Missing from project: $($MissingFromProject -join ', ')"
        ) -join [Environment]::NewLine
        Add-StepResult -Name "test_manifest_coverage" -Kind "static" -ExitCode 1 -DurationSeconds 0.0 -Target $CoverageMessage
        throw $CoverageMessage
    }
    Add-StepResult -Name "test_manifest_coverage" -Kind "static" -ExitCode 0 -DurationSeconds 0.0 -Target "$($Tests.Count) tests"

    Invoke-GodotStep `
        -Name "editor_import_parse" `
        -Kind "editor" `
        -Arguments @("--headless", "--editor", "--path", $ProjectRoot, "--quit") `
        -Target "res://"

    foreach ($TestScript in $Tests) {
        Invoke-GodotStep `
            -Name ([IO.Path]::GetFileNameWithoutExtension($TestScript)) `
            -Kind "headless_script" `
            -Arguments @("--headless", "--path", $ProjectRoot, "--script", $TestScript) `
            -Target $TestScript
    }

    Invoke-GodotStep `
        -Name "main_scene_cli_all" `
        -Kind "main_scene_cli" `
        -Arguments @("--headless", "--path", $ProjectRoot, "--", "--world=playground", "--run-tests=all") `
        -Target "playground:test.run all"

    $Summary.passed = $true
    Save-Summary
    Write-Host "All world/core regression tests passed."
    Write-Host "Report: $ReportPath"
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}
