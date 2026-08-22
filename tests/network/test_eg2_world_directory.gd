extends SceneTree

## EG2 L0 world directory: identifier-only resolution, unknown-world and
## outage degradation, catalog revision monotonicity, and the no-endpoint
## fence over every value the directory can return.

const DirectoryScript = preload("res://scripts/network/gateway/runtime/eg2_world_directory.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[eg2-directory-l0][FAIL] %s" % message)


func _err(result: Dictionary) -> String:
	return String(result.get("error_code", ""))


func _details(result: Dictionary) -> Dictionary:
	return result.get("details", {})


func _init() -> void:
	var directory := DirectoryScript.new()

	# --- registration validation ---
	_assert(_err(directory.register_world("not-a-world", "authority/eg2-a", "server-instance/eg2-a-1", 1)) == "INVALID_ID",
			"non-canonical world id was registered")
	_assert(_err(directory.register_world("world/eg2-main", "entity/not-an-authority", "server-instance/eg2-a-1", 1)) == "INVALID_ID",
			"cross-namespace authority id was registered")
	_assert(_err(directory.register_world("world/eg2-main", "authority/eg2-a", "gateway/eg2-x", 1)) == "INVALID_ID",
			"cross-namespace server instance id was registered")
	_assert(_err(directory.register_world("world/eg2-main", "authority/eg2-a", "server-instance/eg2-a-1", 0)) == "INVALID_CATALOG_REVISION",
			"non-positive catalog revision was registered")
	_assert(_err(directory.register_world("world/eg2-main", "authority/eg2-a", "server-instance/127.0.0.1", 1)) == "ENDPOINT_LIKE_IDENTITY_REJECTED",
			"host-like server instance id was registered")

	# --- resolution happy path: identifiers ONLY ---
	var registered: Dictionary = directory.register_world(
			"world/eg2-main", "authority/eg2-sim-a", "server-instance/eg2-sim-a-1", 3)
	_assert(bool(registered.get("success", false)), "initial registration failed: %s" % _err(registered))
	var resolved: Dictionary = directory.resolve_current_authority("world/eg2-main")
	_assert(bool(resolved.get("success", false)), "resolution failed: %s" % _err(resolved))
	if bool(resolved.get("success", false)):
		var details := _details(resolved)
		var keys: Array = details.keys()
		keys.sort()
		var expected_keys: Array[String] = ["authority_id", "catalog_revision", "server_instance_id", "world_id"]
		var keys_sorted: Array[String] = []
		for key in keys:
			keys_sorted.append(String(key))
		_assert(keys_sorted == expected_keys,
				"resolution exposed unexpected fields: %s" % str(keys_sorted))
		_assert(String(details["authority_id"]) == "authority/eg2-sim-a", "resolved wrong authority")
		_assert(String(details["server_instance_id"]) == "server-instance/eg2-sim-a-1", "resolved wrong instance")
		_assert(int(details["catalog_revision"]) == 3, "resolved wrong revision")
		for key in details.keys():
			var key_text := str(key)
			for forbidden_key in ["host", "port", "endpoint"]:
				_assert(not key_text.contains(forbidden_key), "resolution exposed endpoint-ish field '%s'" % key_text)
			var value_text := str(details[key])
			for forbidden_value in [":", "127.0.0.1", "localhost"]:
				_assert(not value_text.contains(forbidden_value),
						"resolution value for %s looks like an endpoint: %s" % [key_text, value_text])

	# --- unknown world ---
	var unknown := directory.resolve_current_authority("world/ghost")
	_assert(_err(unknown) == "UNKNOWN_WORLD", "unknown world resolved")
	_assert(_err(directory.set_unavailable("world/ghost")) == "UNKNOWN_WORLD",
			"outage declared for unknown world")

	# --- outage degradation + recovery ---
	_assert(bool(directory.set_unavailable("world/eg2-main").get("success", false)), "outage declaration failed")
	_assert(not directory.is_available("world/eg2-main"), "availability flag stuck during outage")
	var degraded := directory.resolve_current_authority("world/eg2-main")
	_assert(_err(degraded) == "DIRECTORY_UNAVAILABLE", "outage resolution did not degrade: %s" % _err(degraded))
	_assert(bool(directory.set_available("world/eg2-main").get("success", false)), "restoration failed")
	var restored := directory.resolve_current_authority("world/eg2-main")
	_assert(bool(restored.get("success", false)) and int(_details(restored)["catalog_revision"]) == 3,
			"restored resolution lost the registered truth")

	# --- revision monotonicity ---
	_assert(_err(directory.register_world("world/eg2-main", "authority/eg2-sim-b", "server-instance/eg2-sim-b-1", 2)) == "CATALOG_REVISION_REGRESSION",
			"revision regression was accepted")
	var idempotent: Dictionary = directory.register_world(
			"world/eg2-main", "authority/eg2-sim-a", "server-instance/eg2-sim-a-1", 3)
	_assert(bool(idempotent.get("success", false)) and bool(_details(idempotent)["changed"]) == false,
			"identical re-registration was not idempotent")
	_assert(_err(directory.register_world("world/eg2-main", "authority/eg2-sim-b", "server-instance/eg2-sim-b-1", 3)) == "CATALOG_REVISION_CONFLICT",
			"equal-revision authority change was accepted")
	var moved: Dictionary = directory.register_world(
			"world/eg2-main", "authority/eg2-sim-b", "server-instance/eg2-sim-b-1", 4)
	_assert(bool(moved.get("success", false)), "higher-revision move failed: %s" % _err(moved))
	var after_move := directory.resolve_current_authority("world/eg2-main")
	_assert(bool(after_move.get("success", false))
			and String(_details(after_move)["authority_id"]) == "authority/eg2-sim-b"
			and String(_details(after_move)["server_instance_id"]) == "server-instance/eg2-sim-b-1"
			and int(_details(after_move)["catalog_revision"]) == 4,
			"authority move did not become the current truth")

	# --- report surface stays identifier-only ---
	var report: Dictionary = directory.get_report()
	for world_entry_value in report["worlds"]:
		var world_entry: Dictionary = world_entry_value
		for key in world_entry.keys():
			var key_text := str(key)
			for forbidden_key in ["host", "port", "endpoint"]:
				_assert(not key_text.contains(forbidden_key), "directory report exposed endpoint-ish field '%s'" % key_text)

	_finish()


func _finish() -> void:
	var summary := {
		"test": "eg2_world_directory_l0",
		"verdict": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions,
		"failures": failures,
	}
	print(JSON.stringify(summary))
	if failures.is_empty():
		print("[eg2-directory-l0] L0 PASS (%d assertions)" % assertions)
		quit(0)
	else:
		print("[eg2-directory-l0] L0 FAIL")
		quit(1)
