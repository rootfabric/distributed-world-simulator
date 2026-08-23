# Accepted M7 validation marker: v16.10.6.1-testing-m7-playable-networked-playground
# Accepted architecture coverage marker: v16.10.6-architecture-a3-single-server-multiplayer
$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportDirectory = Join-Path $ProjectRoot "artifacts/test-results"
$ReportPath = Join-Path $ReportDirectory "world-regression-summary.json"
New-Item -ItemType Directory -Force -Path $ReportDirectory | Out-Null

# Every regression run receives a clean user profile. Old user:// manifests from
# another checkpoint must never influence persistence or checksum contracts.
$IsolatedProfileRoot = Join-Path $ReportDirectory ("world-profile-{0}" -f $PID)
$IsolatedDataRoot = Join-Path $IsolatedProfileRoot "data"
$IsolatedConfigRoot = Join-Path $IsolatedProfileRoot "config"
$IsolatedCacheRoot = Join-Path $IsolatedProfileRoot "cache"
foreach ($Path in @($IsolatedProfileRoot, $IsolatedDataRoot, $IsolatedConfigRoot, $IsolatedCacheRoot)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}
$env:APPDATA = $IsolatedDataRoot
$env:LOCALAPPDATA = $IsolatedDataRoot
$env:USERPROFILE = $IsolatedProfileRoot
$env:HOME = $IsolatedProfileRoot
$env:XDG_DATA_HOME = $IsolatedDataRoot
$env:XDG_CONFIG_HOME = $IsolatedConfigRoot
$env:XDG_CACHE_HOME = $IsolatedCacheRoot
# World regression is a deterministic baseline suite. Dedicated inventory
# profile contracts switch to Rust/7DTD explicitly inside their own process.
$env:PLANET_SIMULATOR_INVENTORY_PROFILE = "planet_default"

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
    "res://tests/network/test_network_transport_boundary.gd",
    "res://tests/network/test_n1_enet_snapshot_contracts.gd",
    "res://tests/network/test_n1_enet_snapshot_processes.gd",
    "res://tests/network/test_n1_remote_item_command_contracts.gd",
    "res://tests/network/test_n1_remote_item_command_processes.gd",
    "res://tests/network/test_n1_reconnect_replay_contracts.gd",
    "res://tests/network/test_n1_reconnect_replay_processes.gd",
    "res://tests/testing/test_n2_process_harness_contracts.gd",
    "res://tests/testing/test_n2_process_harness_processes.gd",
    "res://tests/persistence/test_r3_authoritative_recovery_contracts.gd",
    "res://tests/persistence/test_r3_authoritative_recovery_processes.gd",
    "res://tests/runtime/test_h0_listen_host_contracts.gd",
    "res://tests/runtime/test_h0_listen_host_processes.gd",
    "res://tests/runtime/test_h1_playable_listen_host_contracts.gd",
    "res://tests/runtime/test_h1_playable_listen_host_integration.gd",
    "res://tests/runtime/test_h2_player_ownership_contracts.gd",
    "res://tests/runtime/test_h2_host_client_processes.gd",
    "res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd",
    "res://tests/runtime/test_h3_dedicated_multiplayer_processes.gd",
    "res://tests/runtime/test_a2_networked_gameplay_architecture.gd",
    "res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd",
    "res://tests/runtime/test_m1_networked_gameplay_contracts.gd",
    "res://tests/runtime/test_m1_unified_networked_gameplay_service.gd",
    "res://tests/runtime/test_m2_graphical_client_contracts.gd",
    "res://tests/runtime/test_m2_dedicated_graphical_processes.gd",
    "res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd",
    "res://tests/runtime/test_m3_graphical_multiplayer_processes.gd",
    "res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd",
    "res://tests/runtime/test_m4_graphical_shared_gameplay_processes.gd",
    "res://tests/runtime/test_m4_networked_playground_extension.gd",
    "res://tests/runtime/test_m5_graphical_acceptance_preparation.gd",
    "res://tests/runtime/test_m5_graphical_acceptance_contracts.gd",
    "res://tests/runtime/test_m5_graphical_multiplayer_acceptance.gd",
    "res://tests/runtime/test_m6_dedicated_recovery_contracts.gd",
    "res://tests/runtime/test_m6_dedicated_recovery_processes.gd",
    "res://tests/runtime/test_a3_single_server_multiplayer_architecture.gd",
    "res://tests/runtime/test_m7_playable_networked_playground.gd",
    "res://tests/runtime/test_m7_playable_networked_processes.gd",
    "res://tests/runtime/test_m7_playable_networked_recovery_processes.gd",
    "res://tests/simulation/test_a1_generic_aggregate_contracts.gd",
    "res://tests/simulation/test_a1_generic_aggregate_integration.gd",
    "res://tests/simulation/test_s0_spatial_substrate_contracts.gd",
    "res://tests/simulation/test_s0_spatial_substrate_integration.gd",
    "res://tests/network/test_t1_multi_peer_transport_contracts.gd",
    "res://tests/network/test_t1_multi_peer_transport_processes.gd",
    "res://tests/network/test_nx0_network_experience_preparation.gd",
    "res://tests/network/test_nx0_observability_baseline.gd",
    "res://tests/network/test_nx0_observability_handshake_processes.gd",
    "res://tests/network/test_nx1_deterministic_network_condition_simulator.gd",
    "res://tests/network/test_nx1_network_condition_processes.gd",
    "res://tests/network/test_nx2_realtime_traffic_separation.gd",
    "res://tests/network/test_nx3_fixed_tick_authoritative_simulation.gd",
    "res://tests/network/test_nx4_client_prediction_reconciliation.gd",
    "res://tests/network/test_b0_message_bus_contracts.gd",
    "res://tests/network/test_b0_message_bus_integration.gd",
    "res://tests/simulation/test_m0_aggregate_transaction_contracts.gd",
    "res://tests/simulation/test_m0_aggregate_transaction_integration.gd",
    "res://tests/simulation/test_s1_distributed_compute_contracts.gd",
    "res://tests/simulation/test_s1_distributed_compute_integration.gd",
    "res://tests/network/test_n0_extended_contracts.gd",
    "res://tests/network/test_n0_contract_mutation_matrix.gd",
    "res://tests/network/test_n0_golden_fixtures.gd",
    "res://tests/network/test_loopback_replication_transport.gd",
    "res://tests/network/test_n0_review_regressions.gd",
    "res://tests/network/test_handoff_state_machine.gd",
    "res://tests/network/test_handoff_transition_matrix.gd",
    "res://tests/entities/test_authority_revision_semantics.gd",
    "res://tests/runtime/test_kernel_ports.gd",
    "res://tests/entities/test_world_entity_aggregate.gd",
    "res://tests/entities/test_world_entity_store_failures.gd",
    "res://tests/items/test_world_item_aggregate_migration.gd",
    "res://tests/construction/test_c1_construction_contracts.gd",
    "res://tests/construction/test_c1_construct_aggregate.gd",
    "res://tests/construction/test_c2a_item_graph_contracts.gd",
    "res://tests/construction/test_c2a_item_graph_transactions.gd",
    "res://tests/construction/test_c2b_authoritative_item_graph_contracts.gd",
    "res://tests/construction/test_c2b_authoritative_item_graph_integration.gd",
    "res://tests/construction/test_c3_build_plan_contracts.gd",
    "res://tests/construction/test_c3_build_plan_integration.gd",
    "res://tests/construction/test_c4_composite_definition_contracts.gd",
    "res://tests/construction/test_c4_composite_definition_integration.gd",
    "res://tests/construction/test_c5_capability_affordance_contracts.gd",
    "res://tests/construction/test_c5_capability_affordance_integration.gd",
    "res://tests/construction/test_c6_mobile_construct_contracts.gd",
    "res://tests/construction/test_c6_mobile_construct_integration.gd",
    "res://tests/construction/test_c7_spatial_construct_contracts.gd",
    "res://tests/construction/test_c7_spatial_construct_integration.gd",
    "res://tests/construction/test_c8_fabrication_cell_contracts.gd",
    "res://tests/construction/test_c8_fabrication_cell_integration.gd",
    "res://tests/construction/test_c9_damage_split_repair_contracts.gd",
    "res://tests/construction/test_c9_damage_split_repair_integration.gd",
    "res://tests/construction/test_c10_parametric_members_contracts.gd",
    "res://tests/construction/test_c10_parametric_members_integration.gd",
    "res://tests/construction/test_c11_local_geometry_editing_contracts.gd",
    "res://tests/construction/test_c11_local_geometry_editing_integration.gd",
    "res://tests/construction/test_c12_multiplayer_construction_contracts.gd",
    "res://tests/construction/test_c12_multiplayer_construction_integration.gd",
    "res://tests/construction/test_c13_runtime_projection_contracts.gd",
    "res://tests/construction/test_c13_runtime_projection_integration.gd",
    "res://tests/construction/test_c14_structural_integrity_contracts.gd",
    "res://tests/construction/test_c14_structural_integrity_integration.gd",
    "res://tests/construction/test_c15_executable_utilities_contracts.gd",
    "res://tests/construction/test_c15_executable_utilities_integration.gd",
    "res://tests/construction/test_c16_interaction_ux_contracts.gd",
    "res://tests/construction/test_c16_interaction_ux_integration.gd",
    "res://tests/construction/test_c17_distributed_authority_contracts.gd",
    "res://tests/construction/test_c17_distributed_authority_integration.gd",
    "res://tests/construction/test_c18_streaming_lod_contracts.gd",
    "res://tests/construction/test_c18_streaming_lod_integration.gd",
    "res://tests/construction/test_c19_agent_automation_contracts.gd",
    "res://tests/construction/test_c19_agent_automation_integration.gd",
    "res://tests/construction/test_c20_logistics_economy_contracts.gd",
    "res://tests/construction/test_c20_logistics_economy_integration.gd",
    "res://tests/construction/test_c21_large_scale_acceptance_contracts.gd",
    "res://tests/construction/test_c21_large_scale_acceptance_integration.gd",
    "res://tests/construction/test_c21_large_scale_acceptance_soak.gd",
    "res://tests/construction/test_c22_compiled_proxy_contracts.gd",
    "res://tests/construction/test_c22_compiled_proxy_integration.gd",
    "res://tests/construction/test_c22_compiled_proxy_graphical.gd",
    "res://tests/construction/test_c22_compiled_proxy_scale_soak.gd",
    "res://tests/construction/test_c22_incremental_local_rebuild.gd",
    "res://tests/construction/test_c23_production_hardening_contracts.gd",
    "res://tests/construction/test_c23_production_hardening_integration.gd",
    "res://tests/construction/test_c23_production_hardening_chaos.gd",
    "res://tests/construction/test_c23_production_hardening_soak.gd",
    "res://tests/construction/test_c24_proxy_mesh_backend_contracts.gd",
    "res://tests/construction/test_c24_proxy_mesh_backend_integration.gd",
    "res://tests/construction/test_c24_proxy_mesh_backend_graphical.gd",
    "res://tests/construction/test_c24_proxy_mesh_backend_scale_soak.gd",
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
    "res://tests/ui/test_inventory_ui_i0_architecture.gd",
    "res://tests/ui/test_inventory_ui_i1_interactions.gd",
    "res://tests/ui/test_inventory_ui_i2_large_storage.gd",
    "res://tests/ui/test_inventory_interaction_profiles.gd",
    "res://tests/ui/test_inventory_seven_days_interface.gd",
    "res://tests/integration/test_unified_planetary_runtime.gd",
    "res://tests/integration/test_unified_runtime_boot.gd",
    "res://tests/runtime/test_world_switch_during_generation.gd",
    "res://tests/runtime/test_world_boot_matrix.gd",
    "res://tests/network/test_nx2_physical_channel_processes.gd",
    "res://tests/network/test_nx5_remote_snapshot_interpolation.gd",
    "res://tests/network/test_nx5_remote_snapshot_interpolation_integration.gd",
    "res://tests/network/test_nx6_predicted_item_interactions.gd",
    "res://tests/network/test_nx6_predicted_item_interactions_integration.gd",
    "res://tests/persistence/test_authoritative_tick_progression.gd",
    "res://tests/runtime/test_int0_project_uid_contracts.gd",
    "res://tests/runtime/test_int0_m3_replica_resync_composition.gd",
    "res://tests/matter/contracts/test_mw0_matter_contracts.gd",
    "res://tests/matter/generation/test_mw1_fixed_seed_asteroid.gd",
    "res://tests/matter/spatial/test_mw2_sparse_bricks_and_query.gd",
    "res://tests/matter/presentation/test_mw3_local_meshing.gd",
    "res://tests/matter/mutation/test_mw4_matter_mutations.gd",
    "res://tests/matter/persistence/test_mw5_matter_persistence.gd",
    "res://tests/matter/network/test_mw6_matter_network_replication.gd",
    "res://tests/matter/interest/test_mw7_matter_interest_replication.gd",
    "res://tests/matter/handoff/test_mw8_regional_authority_handoff.gd",
    "res://tests/matter/handoff/test_mw9_durable_handoff_recovery.gd",
    "res://tests/matter/handoff/test_mw9_durable_handoff_processes.gd",
    "res://tests/matter/handoff/test_mw9_lock_release_retry.gd",
    "res://tests/matter/transactions/test_mw10_cross_region_transactions.gd",
    "res://tests/matter/transactions/test_mw10_cross_region_processes.gd",
    "res://tests/representation/test_rl0_representation_contracts.gd",
    "res://tests/representation/test_rl1_matter_summary_pyramid.gd",
    "res://tests/representation/test_rl2_matter_multiresolution_meshing.gd",
    "res://tests/representation/test_rl2_real_asteroid_multiresolution.gd",
    "res://tests/representation/test_rl3_representation_aware_network_streaming.gd",
    "res://tests/representation/test_rl3_representation_streaming_processes.gd"
)

$Summary = [ordered]@{
    schema = "planet_simulator.world_regression_summary.v1"
    checkpoint = "v16.14.0-network-nx4-client-prediction-reconciliation"
    runtime_base_checkpoint = "v16.10.8-network-nx0-observability-baseline"
    build_id = "nx4-client-prediction-reconciliation"
    started_at_utc = [DateTime]::UtcNow.ToString("o")
    finished_at_utc = $null
    godot = $Godot
    project_root = $ProjectRoot
    isolated_user_profile = $IsolatedProfileRoot
    declared_test_count = $Tests.Count
    discovered_test_count = 0
    passed = $false
    steps = @()
}

function Write-JsonFileAtomically {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Depth = 8,
        [int]$MaxReplaceAttempts = 20,
        [int]$RetryDelayMs = 25
    )

    $Directory = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($Directory)) {
        $Directory = (Get-Location).Path
    }
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null

    $FileName = [IO.Path]::GetFileName($Path)
    $Suffix = "$PID.$([Guid]::NewGuid().ToString('N'))"
    $TemporaryPath = Join-Path $Directory ".$FileName.$Suffix.tmp"
    $BackupPath = Join-Path $Directory ".$FileName.$Suffix.bak"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    $BackupCreated = $false

    try {
        $Json = $Value | ConvertTo-Json -Depth $Depth
        if ([string]::IsNullOrWhiteSpace($Json)) {
            throw "JSON serialization produced an empty summary"
        }
        $Payload = $Json + [Environment]::NewLine
        $Bytes = $Utf8NoBom.GetBytes($Payload)
        if ($Bytes.Length -le 0) {
            throw "JSON serialization produced a zero-byte summary"
        }

        $Stream = [IO.File]::Open(
            $TemporaryPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        try {
            $Stream.Write($Bytes, 0, $Bytes.Length)
            $Stream.Flush($true)
        }
        finally {
            $Stream.Dispose()
        }

        $TemporaryInfo = Get-Item -LiteralPath $TemporaryPath -ErrorAction Stop
        if ($TemporaryInfo.Length -le 0) {
            throw "Temporary summary is zero bytes: $TemporaryPath"
        }
        $TemporaryText = [IO.File]::ReadAllText($TemporaryPath, $Utf8NoBom)
        $null = $TemporaryText | ConvertFrom-Json -ErrorAction Stop

        $Replaced = $false
        for ($Attempt = 1; $Attempt -le $MaxReplaceAttempts; $Attempt++) {
            try {
                if ([IO.File]::Exists($Path)) {
                    if ([IO.File]::Exists($BackupPath)) {
                        [IO.File]::Delete($BackupPath)
                    }
                    [IO.File]::Replace($TemporaryPath, $Path, $BackupPath, $true)
                    $BackupCreated = [IO.File]::Exists($BackupPath)
                }
                else {
                    [IO.File]::Move($TemporaryPath, $Path)
                }
                $Replaced = $true
                break
            }
            catch {
                if ($Attempt -ge $MaxReplaceAttempts) {
                    throw
                }
                Start-Sleep -Milliseconds $RetryDelayMs
            }
        }
        if (-not $Replaced) {
            throw "Atomic summary replacement did not complete: $Path"
        }

        $FinalInfo = Get-Item -LiteralPath $Path -ErrorAction Stop
        if ($FinalInfo.Length -le 0) {
            throw "Final summary is zero bytes after atomic replacement: $Path"
        }
        $FinalText = [IO.File]::ReadAllText($Path, $Utf8NoBom)
        $null = $FinalText | ConvertFrom-Json -ErrorAction Stop

        if ($BackupCreated -and [IO.File]::Exists($BackupPath)) {
            [IO.File]::Delete($BackupPath)
            $BackupCreated = $false
        }
    }
    catch {
        if ($BackupCreated -and [IO.File]::Exists($BackupPath)) {
            try {
                if ([IO.File]::Exists($Path)) {
                    [IO.File]::Delete($Path)
                }
                [IO.File]::Move($BackupPath, $Path)
                $BackupCreated = $false
            }
            catch {
                Write-Warning "Failed to restore previous summary from $BackupPath"
            }
        }
        throw
    }
    finally {
        foreach ($CleanupPath in @($TemporaryPath, $BackupPath)) {
            if ([IO.File]::Exists($CleanupPath)) {
                try {
                    [IO.File]::Delete($CleanupPath)
                }
                catch {
                    Write-Warning "Failed to remove temporary summary file: $CleanupPath"
                }
            }
        }
    }
}

function Save-Summary {
    $Summary.finished_at_utc = [DateTime]::UtcNow.ToString("o")
    Write-JsonFileAtomically -Value $Summary -Path $ReportPath -Depth 8
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
    $Captured = @()
    $PreviousErrorActionPreference = $ErrorActionPreference
    $NativePreference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $PreviousNativePreference = if ($null -ne $NativePreference) { $NativePreference.Value } else { $null }
    try {
        # Expected Godot diagnostics may be emitted on stderr even when the
        # test succeeds. Capture them without turning NativeCommandError into
        # a terminating PowerShell exception.
        $ErrorActionPreference = "Continue"
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false
        }
        & $Godot @Arguments 2>&1 | Tee-Object -Variable Captured | ForEach-Object { Write-Host $_ }
        $RawExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
        if ($null -ne $NativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $PreviousNativePreference
        }
    }
    $OutputText = ($Captured | Out-String)
    # Keep failure-marker detection case-sensitive: successful assertion text
    # may legitimately contain phrases such as "PASS: Failed durable restore...".
    $HasFailureMarker = $OutputText -cmatch '(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)'
    $ExitCode = if ($RawExitCode -ne 0) { $RawExitCode } elseif ($HasFailureMarker) { 1 } else { 0 }
    $Duration = ([DateTime]::UtcNow - $Started).TotalSeconds
    Add-StepResult -Name $Name -Kind $Kind -ExitCode $ExitCode -DurationSeconds $Duration -Target $Target
    Save-Summary
    if ($ExitCode -ne 0) {
        throw "Regression step failed: $Name (exit code $ExitCode)"
    }
}

try {
    Write-Host "Godot: $Godot"
    Write-Host "Checkpoint: v16.14.0-network-nx4-client-prediction-reconciliation (NX4 candidate over accepted NX3 fixed-tick authoritative simulation)"

    # Scripts below a directory named `fixtures` are support types loaded by
    # standalone tests. They intentionally keep the `test_*.gd` prefix so
    # their purpose is obvious, but they must not be executed as SceneTree
    # entry points or counted as independent regression tests.
    $ExcludedTestDirectoryNames = @("fixtures")

    function Test-IsStandaloneTestScript {
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo]$File
        )

        $TestsRoot = Join-Path $ProjectRoot "tests"
        $RelativeToTests = $File.FullName.Substring($TestsRoot.Length).TrimStart([char[]]@('\', '/'))
        $PathSegments = @($RelativeToTests.Replace('\', '/').Split('/'))
        for ($Index = 0; $Index -lt ($PathSegments.Count - 1); $Index++) {
            if ($PathSegments[$Index] -in $ExcludedTestDirectoryNames) {
                return $false
            }
        }
        return $true
    }

    $DiscoveredTestFiles = @(
        Get-ChildItem -Path (Join-Path $ProjectRoot "tests") -Recurse -File -Filter "test_*.gd" |
            Where-Object { Test-IsStandaloneTestScript -File $_ }
    )
    $DiscoveredTests = $DiscoveredTestFiles |
        ForEach-Object {
            $RelativePath = $_.FullName.Substring($ProjectRoot.Length).TrimStart([char[]]@('\', '/'))
            "res://" + $RelativePath.Replace('\', '/')
        } |
        Sort-Object -Unique

    $Summary.discovered_test_count = $DiscoveredTests.Count
    $MissingFromProject = @($Tests | Where-Object { $_ -notin $DiscoveredTests })
    if ($MissingFromProject.Count -gt 0) {
        $CoverageMessage = @(
            "Regression runner references tests that are missing from the project."
            "Missing from project: $($MissingFromProject -join ', ')"
        ) -join [Environment]::NewLine
        Add-StepResult -Name "test_manifest_coverage" -Kind "static" -ExitCode 1 -DurationSeconds 0.0 -Target $CoverageMessage
        throw $CoverageMessage
    }

    # Keep the historically curated core order, but never allow newly-added
    # standalone tests to sit outside the world/core gate merely because the
    # static list was not hand-edited in the same change. Newly discovered
    # tests are appended deterministically after the canonical ordered list.
    $DiscoveredAdditions = @($DiscoveredTests | Where-Object { $_ -notin $Tests })
    if ($DiscoveredAdditions.Count -gt 0) {
        $Tests += @($DiscoveredAdditions | Sort-Object -Unique)
    }
    $Summary.declared_test_count = $Tests.Count
    $UncoveredTests = @($DiscoveredTests | Where-Object { $_ -notin $Tests })
    if ($UncoveredTests.Count -gt 0) {
        $CoverageMessage = "Regression runner failed to include discovered tests: $($UncoveredTests -join ', ')"
        Add-StepResult -Name "test_manifest_coverage" -Kind "static" -ExitCode 1 -DurationSeconds 0.0 -Target $CoverageMessage
        throw $CoverageMessage
    }
    Add-StepResult -Name "test_manifest_coverage" -Kind "static" -ExitCode 0 -DurationSeconds 0.0 -Target "$($Tests.Count) tests; appended $($DiscoveredAdditions.Count) discovered overlays"

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
    Write-Host "All world/core regression tests through NX4 client prediction and reconciliation passed."
    Write-Host "Report: $ReportPath"
}
catch {
    $Summary.passed = $false
    Save-Summary
    Write-Host $_ -ForegroundColor Red
    exit 1
}
