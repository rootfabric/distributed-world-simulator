param(
    [Parameter(Mandatory = $true)][string]$GodotPath
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Godot = (Resolve-Path $GodotPath).Path
$ProbeRoot = Join-Path $ProjectRoot "artifacts/runtime/m7-item-replica-validation"
$ProbePath = Join-Path $ProbeRoot "probe.gd"
$ProbeUidPath = "$ProbePath.uid"
New-Item -ItemType Directory -Force -Path $ProbeRoot | Out-Null

function Invoke-GodotCheck {
    param([string]$Name, [string[]]$Arguments)
    Write-Host ""
    Write-Host "[$Name]" -ForegroundColor Cyan

    # Windows PowerShell converts native stderr records into ErrorRecord objects.
    # With the global Stop policy that can abort here before we can inspect the
    # Godot diagnostics. Temporarily allow the native process to complete, then
    # fail explicitly from exit code or fatal script diagnostics below.
    $PreviousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $Output = @(& $Godot @Arguments 2>&1)
        $ExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $PreviousErrorActionPreference
    }

    foreach ($Line in $Output) {
        Write-Host $Line
    }

    $Text = ($Output | ForEach-Object { $_.ToString() }) -join "`n"
    $FatalScriptPatterns = @(
        "SCRIPT ERROR:",
        "Parse Error:",
        "Compile Error:",
        "Failed to load script"
    )

    foreach ($Pattern in $FatalScriptPatterns) {
        if ($Text.Contains($Pattern)) {
            throw "$Name emitted fatal Godot script diagnostics: $Pattern"
        }
    }

    if ($ExitCode -ne 0) {
        throw "$Name failed with exit code $ExitCode"
    }

    Write-Host "${Name}: PASS" -ForegroundColor Green
}

$ProbeSource = @'
extends SceneTree

const CanonicalItemGraph = preload("res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd")
const GraphicalClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")

var failures: Array[String] = []
var assertions: int = 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var graph = CanonicalItemGraph.new()
    var setup: Dictionary = graph.setup("authority/probe", 1, {"playable_sandbox": true})
    _assert(bool(setup.get("success", false)), "canonical graph setup")
    var initial: Dictionary = graph.create_snapshot()
    _assert(Dictionary(initial.get("inventories", {})).is_empty(), "sandbox starts before player materialization")
    var initial_revision := int(initial.get("revision", -1))
    var seeded: Dictionary = graph.ensure_player_for_join("player-a")
    _assert(bool(seeded.get("success", false)), "join materialization succeeds")
    _assert(bool(seeded.get("details", {}).get("created", false)), "first join creates player inventory")
    var after: Dictionary = graph.create_snapshot()
    _assert(int(after.get("revision", -1)) == initial_revision + 1, "player materialization advances item revision exactly once")
    _assert(int(after.get("tick", -1)) == int(initial.get("tick", -1)) + 1, "player materialization advances item tick exactly once")
    var inventories: Dictionary = Dictionary(after.get("inventories", {}))
    _assert(inventories.has("player-a"), "first authoritative snapshot contains player inventory")
    var inventory: Dictionary = Dictionary(inventories.get("player-a", {}))
    var inventory_ids: Array = Array(inventory.get("inventory", []))
    _assert("item/player/player-a/beacons" in inventory_ids, "starter beacons exist before first item command")
    _assert("item/player/player-a/mount-bases" in inventory_ids, "starter mount bases exist before first item command")
    _assert("item/player/player-a/battery" in inventory_ids, "starter battery exists before first item command")
    _assert(Array(inventory.get("hotbar", [])).size() == 10, "starter hotbar exists before first item command")
    var battery_location: Dictionary = {}
    for item_value in after.get("items", []):
        if item_value is Dictionary and String(item_value.get("item_id", "")) == "item/player/player-a/battery":
            battery_location = Dictionary(item_value.get("location", {}))
            break
    _assert(int(battery_location.get("slot_index", -1)) == 2, "starter non-hotbar inventory item has authoritative slot identity")
    var seeded_again: Dictionary = graph.ensure_player_for_join("player-a")
    _assert(bool(seeded_again.get("success", false)), "replayed player materialization succeeds")
    _assert(not bool(seeded_again.get("details", {}).get("created", true)), "replayed player materialization is idempotent")
    _assert(int(graph.create_snapshot().get("revision", -1)) == int(after.get("revision", -2)), "replayed materialization preserves item revision")

    var runtime = GraphicalClientRuntime.new()
    var current := {
        "authority_owner_id": "authority/probe",
        "authority_epoch": 1,
        "revision": 7,
        "server_tick": 100,
        "players": [{"logical_player_id":"player-a","position":{"x":1.0,"y":0.0,"z":2.0}}],
        "shared_item": {"available": true},
        "checksum": "old",
    }
    var newer: Dictionary = current.duplicate(true)
    newer["server_tick"] = 104
    newer["checksum"] = "newer-clock"
    _assert(runtime._same_snapshot_semantics_except_clock(current, newer), "newer clock-only snapshot is semantically identical")
    _assert(runtime._same_snapshot_semantics_except_clock(newer, current), "older clock-only snapshot is a superseded semantic replay")
    var mutated: Dictionary = newer.duplicate(true)
    var mutated_players: Array = Array(mutated.get("players", [])).duplicate(true)
    var mutated_player: Dictionary = Dictionary(mutated_players[0]).duplicate(true)
    mutated_player["position"] = {"x":9.0,"y":0.0,"z":2.0}
    mutated_players[0] = mutated_player
    mutated["players"] = mutated_players
    _assert(not runtime._same_snapshot_semantics_except_clock(current, mutated), "same-revision semantic mutation remains rejected")
    runtime.free()

    if failures.is_empty():
        print("M7 network item replica focused probe: PASS (%d assertions)" % assertions)
        quit(0)
        return
    for failure in failures:
        push_error(failure)
    print("M7 network item replica focused probe: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
    quit(1)

func _assert(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        failures.append(message)
'@

try {
    Invoke-GodotCheck -Name "Editor import / composition parse" -Arguments @(
        "--headless", "--editor", "--path", $ProjectRoot, "--quit"
    )

    Set-Content -Path $ProbePath -Value $ProbeSource -Encoding UTF8
    Invoke-GodotCheck -Name "M7 item join and snapshot semantics" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://artifacts/runtime/m7-item-replica-validation/probe.gd"
    )

    Invoke-GodotCheck -Name "M7 slot-aware item transfers" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/network/test_m7_slot_aware_item_transfers.gd"
    )

    Invoke-GodotCheck -Name "M7 inventory rev6 fix7 enhancer parse" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--check-only",
        "--script", "res://scripts/ui/inventory/inventory_network_rev6_enhancer_fix7.gd"
    )

    Invoke-GodotCheck -Name "M7 inventory carry / stack / sort rev6" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/ui/test_inventory_network_rev6.gd"
    )

    Invoke-GodotCheck -Name "M7 inventory rev6 fix6 activation" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/ui/test_inventory_network_rev6_fix6.gd"
    )

    Invoke-GodotCheck -Name "M7 inventory rev6 fix7 reactive presentation" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/ui/test_inventory_network_rev6_fix7.gd"
    )

    Invoke-GodotCheck -Name "NX6 predicted item interactions" -Arguments @(
        "--headless", "--path", $ProjectRoot,
        "--script", "res://tests/network/test_nx6_predicted_item_interactions.gd"
    )

    Write-Host ""
    Write-Host "Focused M7 network item replica validation passed." -ForegroundColor Green
}
finally {
    Remove-Item $ProbePath,$ProbeUidPath -Force -ErrorAction SilentlyContinue
}
