extends SceneTree

const ClientScript = preload("res://scripts/labs/t1/t1a6_m3_runtime_client_adapter.gd")

const RUNTIME_IDS: Dictionary = {
	"DOOR": "runtime/t1a5/d0/door",
	"LAMP": "runtime/t1a5/d0/lamp",
}

var _client
var _result_file: String = ""
var _peer_file: String = ""
var _client_id: String = "a"
var _phase: int = 1
var _started_ms: int = 0
var _done: bool = false


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	_result_file = String(args.get("result-file", ""))
	_peer_file = String(args.get("peer-file", ""))
	_client_id = String(args.get("client-id", "a"))
	_phase = int(args.get("phase", "1"))
	_client = ClientScript.new()
	root.add_child(_client)
	var setup: Dictionary = _client.setup({
		"host": String(args.get("host", "127.0.0.1")),
		"port": int(args.get("port", "0")),
		"logical_player_id": _client_id,
		"connect_timeout_ms": 30000,
		"command_timeout_ms": 10000,
		"automated_acceptance": true,
		"t1a6_presentation": true,
	})
	if not bool(setup.get("success", false)):
		_finish(false, "SETUP_FAILED", {"setup": setup})
		return
	_started_ms = Time.get_ticks_msec()
	process_frame.connect(_tick)


func _tick() -> void:
	if _done:
		return
	if Time.get_ticks_msec() - _started_ms > 90000:
		_finish(false, "TIMEOUT", {})
		return
	if not _client.is_ready():
		return
	if int(_client.get_construction_runtime_snapshot().get("revision", 0)) < 4:
		return
	if _phase == 1:
		_phase_a()
	else:
		_phase_b()


func _phase_a() -> void:
	var opened: Dictionary = _client.execute_construction_runtime_blocking(
		"DOOR", "OPEN_DOOR", "operation/t1a6/d0/door/open-a", 0
	)
	if not bool(opened.get("success", false)):
		_finish(false, "OPEN_FAILED", {"open": opened})
		return
	if not _wait_subject_revision("DOOR", 1, 15000):
		_finish(false, "OPEN_REPLICA_TIMEOUT", {"open": opened})
		return
	_client.force_t1a6_presentation_sync()
	_write(_report("A_OPEN_DONE", true, {"open": opened}))
	if not _wait_for_peer("B_LAMP_DONE", 30000):
		_finish(false, "WAIT_B_LAMP_TIMEOUT", {})
		return
	if not _wait_subject_revision("LAMP", 1, 15000):
		_finish(false, "LAMP_REPLICA_TIMEOUT", {})
		return
	var closed: Dictionary = _client.execute_construction_runtime_blocking(
		"DOOR", "CLOSE_DOOR", "operation/t1a6/d0/door/close-a", 1
	)
	if not bool(closed.get("success", false)):
		_finish(false, "CLOSE_FAILED", {"close": closed})
		return
	if not _wait_subject_revision("DOOR", 2, 15000) or not _wait_runtime_revision(7, 15000):
		_finish(false, "FINAL_REPLICA_TIMEOUT", {"close": closed})
		return
	_client.force_t1a6_presentation_sync()
	var presentation: Dictionary = _client.get_t1a6_presentation_report()
	var passed := not bool(presentation.get("door_open", true)) and bool(presentation.get("lamp_visible", false))
	_finish(passed, "COMPLETE", {"open": opened, "close": closed})


func _phase_b() -> void:
	if not _wait_for_peer("A_OPEN_DONE", 30000):
		_finish(false, "WAIT_A_OPEN_TIMEOUT", {})
		return
	if not _wait_subject_revision("DOOR", 1, 15000):
		_finish(false, "DOOR_OPEN_REPLICA_TIMEOUT", {})
		return
	_client.force_t1a6_presentation_sync()
	if not bool(_client.get_t1a6_presentation_report().get("door_open", false)):
		_finish(false, "DOOR_OPEN_PRESENTATION_MISMATCH", {})
		return
	var toggled: Dictionary = _client.execute_construction_runtime_blocking(
		"LAMP", "TOGGLE_LIGHT", "operation/t1a6/d0/lamp/toggle-b", 0
	)
	if not bool(toggled.get("success", false)):
		_finish(false, "LAMP_TOGGLE_FAILED", {"toggle": toggled})
		return
	if not _wait_subject_revision("LAMP", 1, 15000):
		_finish(false, "LAMP_TOGGLE_REPLICA_TIMEOUT", {"toggle": toggled})
		return
	_client.force_t1a6_presentation_sync()
	_write(_report("B_LAMP_DONE", true, {"toggle": toggled}))
	if not _wait_subject_revision("DOOR", 2, 30000) or not _wait_runtime_revision(7, 30000):
		_finish(false, "FINAL_DOOR_REPLICA_TIMEOUT", {})
		return
	_client.force_t1a6_presentation_sync()
	var presentation: Dictionary = _client.get_t1a6_presentation_report()
	var passed := not bool(presentation.get("door_open", true)) and bool(presentation.get("lamp_visible", false))
	_finish(passed, "COMPLETE", {"toggle": toggled})


func _wait_runtime_revision(revision: int, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		_client._poll_blocking_once()
		if int(_client.get_construction_runtime_snapshot().get("revision", 0)) >= revision:
			return true
		OS.delay_msec(5)
	return false


func _wait_subject_revision(kind: String, revision: int, timeout_ms: int) -> bool:
	var runtime_id := String(RUNTIME_IDS.get(kind, ""))
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		_client._poll_blocking_once()
		if int(_client.get_construction_runtime_subject(runtime_id).get("revision", -1)) >= revision:
			return true
		OS.delay_msec(5)
	return false


func _wait_for_peer(state: String, timeout_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_ms:
		_client._poll_blocking_once()
		var peer := _read(_peer_file)
		if String(peer.get("state", "")) == state:
			return true
		OS.delay_msec(10)
	return false


func _finish(passed: bool, state: String, details: Dictionary) -> void:
	if _done:
		return
	_done = true
	_client.force_t1a6_presentation_sync()
	_write(_report(state, passed, details))
	if _client != null:
		_client.request_graceful_leave(2000)
		_client.stop()
	quit(0 if passed else 1)


func _report(state: String, passed: bool, details: Dictionary) -> Dictionary:
	return {
		"schema": "planet_simulator.t1a6_runtime_client_report.v1",
		"state": state,
		"passed": passed,
		"client_id": _client_id,
		"phase": _phase,
		"display_server": DisplayServer.get_name(),
		"runtime_snapshot": _client.get_construction_runtime_snapshot() if _client != null else {},
		"presentation": _client.get_t1a6_presentation_report() if _client != null else {},
		"client": _client.get_report() if _client != null else {},
		"details": details.duplicate(true),
	}


func _write(value: Dictionary) -> void:
	if _result_file.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_result_file.get_base_dir())
	var file := FileAccess.open(_result_file, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "  "))
		file.close()


func _read(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return Dictionary(parsed) if parsed is Dictionary else {}


func _parse_args(values: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for value in values:
		var text := String(value)
		if text.begins_with("--") and text.contains("="):
			var parts := text.substr(2).split("=", true, 1)
			out[parts[0]] = parts[1]
	return out
