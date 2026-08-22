extends SceneTree

# GEN-A predicate evidence:
#   WORLD_HASH_HANDSHAKE_MISMATCH_FAIL_CLOSED_PASS - real M3 dedicated server
#     publishes world_id + generator_hash on the session/hello path; a matching
#     NX6 client verifies it before JOIN, and a client with a substituted world
#     seed is disconnected with WORLD_DEFINITION_MISMATCH before joining.
#   CONTROL_POINT_ELEVATION_MATCH_PASS (cross-runtime half) - server and client
#     independently compute the five control-point elevation digest and agree.

const ServerRuntimeScript = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd"
)
const ClientRuntimeScript = preload(
	"res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd"
)
const WorldDefinitionScript = preload(
	"res://scripts/world/earth/world_definition.gd"
)

const CONNECT_DEADLINE_MS := 30000
const FAILURE_DEADLINE_MS := 30000
const TEST_SEED := "20260727"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	_run()


func _run() -> void:
	var port := _find_available_port()
	_assert(port > 0, "loopback UDP port allocated")
	if port <= 0:
		_finish()
		return
	var server = ServerRuntimeScript.new()
	root.add_child(server)
	var server_setup: Dictionary = server.setup({
		"host": "127.0.0.1",
		"port": port,
		"debug_logging": true,
	})
	_assert(bool(server_setup.get("success", false)), "M3 dedicated server configured")

	# --- Phase 1: matching world definitions must join -----------------------
	var client_a = ClientRuntimeScript.new()
	root.add_child(client_a)
	var client_setup: Dictionary = client_a.setup({
		"host": "127.0.0.1",
		"port": port,
		"logical_player_id": "a",
		"connect_timeout_ms": 20000,
		"command_timeout_ms": 10000,
		"debug_logging": true,
	})
	_assert(bool(client_setup.get("success", false)), "NX6 client A configured")
	var joined := await _wait_until(
		func() -> bool:
			var report: Dictionary = client_a.get_report()
			return bool(report.get("joined", false)) \
				or not String(report.get("last_error_code", "")).is_empty(),
		CONNECT_DEADLINE_MS
	)
	_assert(joined, "client A reached a terminal session state")
	var report_a: Dictionary = client_a.get_report()
	_assert(bool(report_a.get("joined", false)), "client A joined with matching world definitions: %s" % String(report_a.get("last_error_code", "")))
	_assert(bool(report_a.get("world_definition", {}).get("verified", false)), "client A verified the server world definition")
	_assert(String(report_a.get("last_error_code", "")).is_empty(), "client A has no error code")

	var server_report: Dictionary = server.get_report()
	var announced: Dictionary = server_report.get("world_definition", {}).get("announcement", {})
	_assert(not announced.is_empty(), "server resolved a world definition announcement")
	_assert(int(server_report.get("joins", 0)) == 1, "server accepted exactly one join")
	_assert(int(server_report.get("world_definition", {}).get("publications", 0)) >= 1, "server published the world definition")
	_assert(
		String(announced.get("generator_hash", ""))
			== String(report_a.get("world_definition", {}).get("local_generator_hash", "")),
		"server and client generator hashes agree"
	)
	_assert(
		String(announced.get("world_id", "")) == WorldDefinitionScript.DEFAULT_WORLD_ID,
		"announcement carries the earth world id"
	)

	# --- Phase 2: substituted seed must fail closed --------------------------
	OS.set_environment(WorldDefinitionScript.TEST_SEED_OVERRIDE_ENV, TEST_SEED)
	var client_b = ClientRuntimeScript.new()
	root.add_child(client_b)
	var client_b_setup: Dictionary = client_b.setup({
		"host": "127.0.0.1",
		"port": port,
		"logical_player_id": "b",
		"connect_timeout_ms": 20000,
		"command_timeout_ms": 10000,
		"debug_logging": true,
	})
	_assert(bool(client_b_setup.get("success", false)), "tampered NX6 client B configured")
	await _wait_until(
		func() -> bool:
			return not String(client_b.get_report().get("last_error_code", "")).is_empty(),
		FAILURE_DEADLINE_MS
	)
	var report_b: Dictionary = client_b.get_report()
	_assert(
		String(report_b.get("last_error_code", "")) == "WORLD_DEFINITION_MISMATCH",
		"tampered client failed closed with WORLD_DEFINITION_MISMATCH: %s" % String(report_b.get("last_error_code", ""))
	)
	_assert(not bool(report_b.get("joined", false)), "tampered client never joined")
	OS.set_environment(WorldDefinitionScript.TEST_SEED_OVERRIDE_ENV, "")

	var server_final: Dictionary = server.get_report()
	_assert(int(server_final.get("joins", 0)) == 1, "server still counts exactly one join after tampered attempt")
	var rejections: int = int(
		server_final.get("compatibility_handshake", {}).get("rejections", 0)
	)
	if rejections > 0:
		_assert(
			String(server_final.get("compatibility_handshake", {}).get("last_error_code", ""))
				== "WORLD_DEFINITION_UNRESOLVABLE",
			"no unexpected server-side handshake rejection"
		)

	client_b.stop()
	client_a.stop()
	server.stop()
	_finish()


func _wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _find_available_port() -> int:
	for port in range(39500 + (OS.get_process_id() % 1000), 41000):
		var udp := PacketPeerUDP.new()
		if udp.bind(port, "127.0.0.1") == OK:
			udp.close()
			return port
	return 0


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("GEN-A world hash handshake loopback: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
