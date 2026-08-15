extends SceneTree

const LaunchOptionsScript = preload("res://scripts/runtime/launch_options.gd")
const CanonicalItemGraph = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
)
const MVP_LAUNCHER_PATH := "res://RUN_V0_MVP.ps1"
const MAIN_SCENE_PATH := "res://main.tscn"
const V0_P1_BOOTSTRAP_PATH := "res://scripts/app/v0_p1_simulator_app.gd"

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
	_assert(not bool(server_options.get("network_playground", false)), "LaunchOptions keeps product MVP distinct from playground validation")
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

	_test_p1_product_composition_bridge()
	_test_item_graph_player_materialization_clock()
	_test_runtime_bridge_process_isolation()

	if failures.is_empty():
		print("V0-S1 MVP launch options: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("V0-S1 MVP launch options: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)


func _test_p1_product_composition_bridge() -> void:
	_assert(FileAccess.file_exists(MAIN_SCENE_PATH), "main scene source exists")
	_assert(FileAccess.file_exists(V0_P1_BOOTSTRAP_PATH), "V0-P1 product bootstrap source exists")
	if not FileAccess.file_exists(MAIN_SCENE_PATH) or not FileAccess.file_exists(V0_P1_BOOTSTRAP_PATH):
		return
	var main_scene := FileAccess.get_file_as_string(MAIN_SCENE_PATH)
	var bootstrap := FileAccess.get_file_as_string(V0_P1_BOOTSTRAP_PATH)
	_assert(
		main_scene.contains("res://scripts/app/v0_p1_simulator_app.gd"),
		"main scene routes through bounded V0-P1 product bootstrap"
	)
	_assert(
		bootstrap.contains('bool(options.get("network_mvp", false))'),
		"V0-P1 bootstrap detects the validated network MVP product mode"
	)
	_assert(
		bootstrap.contains('options["network_playground"] = true'),
		"network MVP enables the inherited playable-sandbox capability before M3 setup"
	)


func _test_item_graph_player_materialization_clock() -> void:
	var graph = CanonicalItemGraph.new()
	_assert(
		bool(graph.setup("authority/v0-p1/r4-clock", 1, {"playable_sandbox": true}).get("success", false)),
		"R4 canonical Item Graph configures"
	)
	var initial: Dictionary = graph.create_snapshot()
	graph.ensure_player("a")
	var first: Dictionary = graph.create_snapshot()
	_assert(
		int(first.get("revision", -1)) == int(initial.get("revision", -1)) + 1,
		"first player materialization advances canonical Item Graph revision exactly once"
	)
	_assert(
		int(first.get("tick", -1)) == int(initial.get("tick", -1)) + 1,
		"first player materialization advances canonical Item Graph tick exactly once"
	)
	_assert(
		Dictionary(first.get("inventories", {})).has("a"),
		"first materialization publishes player A inventory"
	)
	var first_checksum := String(first.get("checksum", ""))
	graph.ensure_player("a")
	var replay: Dictionary = graph.create_snapshot()
	_assert(
		int(replay.get("revision", -1)) == int(first.get("revision", -1))
		and int(replay.get("tick", -1)) == int(first.get("tick", -1))
		and String(replay.get("checksum", "")) == first_checksum,
		"reconnect materialization is revision/checksum idempotent"
	)
	graph.ensure_player("b")
	var second: Dictionary = graph.create_snapshot()
	_assert(
		int(second.get("revision", -1)) == int(first.get("revision", -1)) + 1,
		"second player materialization advances canonical revision instead of same-revision mutation"
	)
	_assert(
		String(second.get("checksum", "")) != first_checksum,
		"second player materialization publishes a distinct checksum at a newer revision"
	)


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
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)
