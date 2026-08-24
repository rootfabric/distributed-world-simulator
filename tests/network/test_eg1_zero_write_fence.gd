extends SceneTree

## EG1 zero-write fence: gateway production paths must contain ZERO domain
## references. The domain convergence point may only appear in SIM-side EG1
## process tooling, never in scripts/network/gateway/runtime/ nor in the
## gateway or client worker processes. Also asserts that the gateway node's
## report surface carries no domain fields.

const GatewayNodeScript = preload("res://scripts/network/gateway/runtime/eg1_gateway_node.gd")

const FORBIDDEN_DOMAIN_TOKENS: Array[String] = [
	"canonical_multiplayer_item_graph",
	"networked_gameplay_service",
	"handle_canonical_item_command",
	"submit_movement_intent",
	"create_canonical_item_graph_snapshot",
	"persistence",
	"save",
]
# Files whose whole purpose is the SIM-side domain admission: these are the
# ONLY EG1 paths allowed to reference the domain service.
const SIM_SIDE_ALLOWED_FILES: Array[String] = [
	"res://tools/network/eg1_process_support.gd",
	"res://tools/network/eg1_sim_server_worker.gd",
]
const STRICT_ZERO_WRITE_PATHS: Array[String] = [
	"res://scripts/network/gateway/runtime/eg1_gateway_route_table.gd",
	"res://scripts/network/gateway/runtime/eg1_gateway_forwarder.gd",
	"res://scripts/network/gateway/runtime/eg1_gateway_session_control.gd",
	"res://scripts/network/gateway/runtime/eg1_gateway_node.gd",
	"res://tools/network/eg1_gateway_worker.gd",
	"res://tools/network/eg1_client_worker.gd",
]

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg1-fence][FAIL] %s" % message)


func _scan_source(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _init() -> void:
	# --- strict zero-write zone ---
	for path in STRICT_ZERO_WRITE_PATHS:
		var source := _scan_source(path)
		_assert(not source.is_empty(), "fence could not read %s" % path)
		for token in FORBIDDEN_DOMAIN_TOKENS:
			_assert(not source.contains(token),
					"%s contains forbidden domain reference '%s'" % [path.get_file(), token])

	# --- domain calls live ONLY in the declared sim-side files ---
	var support_source := _scan_source(SIM_SIDE_ALLOWED_FILES[0])
	_assert(not support_source.is_empty(), "fence could not read eg1_process_support.gd")
	_assert(support_source.contains("networked_gameplay_service") and support_source.contains("handle_canonical_item_command"),
			"eg1_process_support.gd no longer declares the sim-side domain admission point")
	var sim_worker_source := _scan_source(SIM_SIDE_ALLOWED_FILES[1])
	_assert(not sim_worker_source.is_empty(), "fence could not read eg1_sim_server_worker.gd")
	_assert(sim_worker_source.contains("handle_canonical_item_command") and sim_worker_source.contains("submit_movement_intent"),
			"eg1_sim_server_worker.gd no longer declares the sim-side domain admission point")
	for path in SIM_SIDE_ALLOWED_FILES:
		# ...and even sim tooling must not drag gateway runtime internals in:
		# the published wire mapping comes from the shared contract utils.
		var source := _scan_source(path)
		_assert(not source.contains("res://scripts/network/gateway/runtime"),
				"%s must not preload gateway runtime internals" % path.get_file())

	# --- every other file under scripts/network/gateway/runtime stays in the fence ---
	var runtime_dir := "res://scripts/network/gateway/runtime"
	var dir := DirAccess.open(runtime_dir)
	_assert(dir != null, "cannot open gateway runtime directory")
	if dir != null:
		for file_name in dir.get_files():
			if not file_name.ends_with(".gd"):
				continue
			var source := _scan_source("%s/%s" % [runtime_dir, file_name])
			for token in FORBIDDEN_DOMAIN_TOKENS:
				_assert(not source.contains(token),
						"runtime file %s contains forbidden domain reference '%s'" % [file_name, token])

	# --- report surface fence: get_report() carries forwarding data only ---
	var node := GatewayNodeScript.new()
	var started: Dictionary = node.start(
			{"transport": "LOOPBACK", "name": "eg1-fence-client"},
			{"transport": "LOOPBACK", "name": "eg1-fence-backend"},
			"gateway/eg1/fence")
	_assert(bool(started.get("success", false)), "fence gateway start failed")
	var report: Dictionary = node.get_report()
	_assert(_has_no_domain_fields(report), "gateway report leaked domain fields")
	_assert(report.has("identity") and report.has("counters") and report.has("sessions"),
			"gateway report lost its forwarding/session-control sections")
	node.stop()

	_finish()


func _has_no_domain_fields(value, path: String = "$") -> bool:
	var forbidden_keys: Array[String] = [
		"logical_player_id", "player_entity_id", "world_id",
		"canonical_multiplayer_item_graph", "canonical_item_graph",
		"inventories", "items", "checksum", "operation_ledger",
		"authority_owner_id", "player_registry", "ownership_service",
	]
	match typeof(value):
		TYPE_DICTIONARY:
			for raw_key in value.keys():
				var key := String(raw_key)
				var next_path := "%s.%s" % [path, key]
				if forbidden_keys.has(key):
					print("[eg1-fence][FAIL] domain field at %s" % next_path)
					return false
				if not _has_no_domain_fields(value[raw_key], next_path):
					return false
		TYPE_ARRAY:
			for index in range(value.size()):
				if not _has_no_domain_fields(value[index], "%s[%d]" % [path, index]):
					return false
	return true


func _finish() -> void:
	var summary := {
		"test": "eg1_zero_write_fence_l0",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg1-fence] ZERO-WRITE FENCE PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg1-fence] ZERO-WRITE FENCE FAIL")
		quit(1)
