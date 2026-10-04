extends Node

# Operator-owned filesystem channel, NOT a client RPC, save store or world
# authority. The fresh per-launch nonce prevents stale requests after restart.
const REQUEST_SCHEMA := "dws.live3.host_request.v1"
const STATUS_SCHEMA := "dws.live3.host_status.v1"
const MAX_REQUEST_BYTES := 4096

var _app
var _options: Dictionary = {}
var _elapsed := 0.0
var _requested := false
var _last_request_id := ""

func setup(app, options: Dictionary) -> Dictionary:
	_app = app
	_options = options.duplicate(true)
	set_process(not String(_options.get("live3_control_file", "")).is_empty())
	return {"success": true}

static func validate_request(value, token: String, process_id: int) -> Dictionary:
	if not value is Dictionary or value.size() != 5:
		return {"success": false, "error_code": "LIVE3_HOST_REQUEST_INVALID"}
	if value.get("schema") != REQUEST_SCHEMA or value.get("action") != "SAVE_AND_STOP":
		return {"success": false, "error_code": "LIVE3_HOST_ACTION_INVALID"}
	if token.length() < 32 or value.get("token") != token or value.get("process_id") != process_id:
		return {"success": false, "error_code": "LIVE3_HOST_REQUEST_STALE_OR_UNAUTHORIZED"}
	return {"success": true}

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25 or _requested:
		return
	_elapsed = 0.0
	var path := String(_options.get("live3_control_file", ""))
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var value = null
	if file.get_length() <= MAX_REQUEST_BYTES:
		value = JSON.parse_string(file.get_as_text())
	file.close()
	var checked := validate_request(value, String(_options.get("live3_control_token", "")), OS.get_process_id())
	# The launcher publishes by atomic rename; consume exactly one request.
	var removed := DirAccess.remove_absolute(path)
	if removed != OK:
		publish("CONTROL_REJECTED", {"error_code": "LIVE3_HOST_REQUEST_CONSUME_FAILED"})
		return
	if not bool(checked.get("success", false)):
		publish("CONTROL_REJECTED", checked)
		return
	_requested = true
	publish("DRAINING", {"saved": false})
	_app.request_graceful_shutdown("live3_operator_save_and_stop", 0)

func publish(phase: String, details: Dictionary = {}) -> Dictionary:
	var value := details.duplicate(true)
	value["schema"] = STATUS_SCHEMA
	value["phase"] = phase
	value["process_id"] = OS.get_process_id()
	value["slot"] = String(_options.get("live3_slot", ""))
	value["persistence_root"] = String(_options.get("m6_persistence_root", ""))
	value["time_msec"] = Time.get_ticks_msec()
	# The nonce is deliberately never written to logs or reports.
	print("[live3_host] ", JSON.stringify(value))
	var path := String(_options.get("live3_status_file", ""))
	if path.is_empty():
		return {"success": true, "sink_configured": false}
	var made := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK and made != ERR_ALREADY_EXISTS:
		return {"success": false, "error_code": "LIVE3_STATUS_DIRECTORY_FAILED"}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"success": false, "error_code": "LIVE3_STATUS_WRITE_FAILED"}
	file.store_string(JSON.stringify(value, "", true, true) + "\n")
	file.flush()
	var error := file.get_error()
	file.close()
	return {"success": error == OK, "error_code": "" if error == OK else "LIVE3_STATUS_FLUSH_FAILED"}
