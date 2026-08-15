extends SceneTree

const LaunchOptionsScript = preload("res://scripts/runtime/launch_options.gd")
const MVP_LAUNCHER_PATH := "res://RUN_V0_MVP.ps1"

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	var server: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=dedicated-server",
		"--network-mvp",
		"--server-port=24580",
	]))
	_assert(bool(server.get("success", false)), "dedicated server accepts --network-mvp")
	var server_options: Dictionary = server.get("options", {})
	_assert(bool(server_options.get("network_mvp", false)), "server preserves network_mvp flag")
	_assert(String(server_options.get("world", "")) == "earth", "network MVP defaults to Earth")
	_assert(
		String(server_options.get("m3_result_file", "")) == LaunchOptionsScript.NETWORK_MVP_RUNTIME_SENTINEL,
		"network MVP activates accepted M3 runtime without acceptance phase"
	)
	_assert(int(server_options.get("m3_phase", -1)) == 0, "network MVP does not start M3 acceptance driver")

	var client: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=game-client",
		"--world=earth",
		"--network-mvp=true",
		"--network-debug",
		"--network-debug-stay-open",
		"--player-identity=a",
	]))
	_assert(bool(client.get("success", false)), "graphical client accepts --network-mvp")
	var client_options: Dictionary = client.get("options", {})
	_assert(bool(client_options.get("network_debug", false)), "network MVP keeps network debug logging")
	_assert(bool(client_options.get("network_debug_stay_open", false)), "network MVP keeps client window on connection error")

	var wrong_world: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=game-client",
		"--world=moon",
		"--network-mvp",
		"--player-identity=a",
	]))
	_assert(not bool(wrong_world.get("success", true)), "network MVP rejects non-Earth world")

	var wrong_role: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=listen-host",
		"--network-mvp",
	]))
	_assert(not bool(wrong_role.get("success", true)), "network MVP rejects listen-host role")

	var mixed_modes: Dictionary = LaunchOptionsScript.parse(PackedStringArray([
		"--role=game-client",
		"--network-mvp",
		"--network-playground",
		"--player-identity=a",
	]))
	_assert(not bool(mixed_modes.get("success", true)), "network MVP rejects mixed playground mode")

	_test_runtime_bridge_process_isolation()

	if failures.is_empty():
		print("V0-S1 MVP launch options: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-S1 MVP launch options: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_runtime_bridge_process_isolation() -> void:
	_assert(FileAccess.file_exists(MVP_LAUNCHER_PATH), "V0 launcher source exists")
	if not FileAccess.file_exists(MVP_LAUNCHER_PATH):
		return
	var launcher := FileAccess.get_file_as_string(MVP_LAUNCHER_PATH)
	_assert(
		launcher.contains('[ValidateSet("client-a", "server", "none")]'),
		"launcher exposes one explicit runtime bridge owner"
	)
	_assert(
		launcher.contains('[string]$RuntimeBridgeOwner = "client-a"'),
		"client A is the default MCP-managed runtime"
	)
	_assert(
		launcher.contains('BREAKPOINT_RUNTIME_DISABLED'),
		"launcher isolates runtime bridge ownership through child environment"
	)
	_assert(
		launcher.contains('$ServerRuntimeBridgeEnabled = ($RuntimeBridgeOwner -eq "server")'),
		"dedicated server does not own runtime bridge by default"
	)
	_assert(
		launcher.contains('$ClientRuntimeBridgeEnabled = ($RuntimeBridgeOwner -eq "client-a" -and $Identity -eq "a")'),
		"only client A owns the default runtime bridge port"
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
