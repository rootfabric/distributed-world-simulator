extends SceneTree

const ClientRuntime = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m6/m6_process_support.gd")

var client
var client_id := ""
var phase := ""
var result_file := ""
var control_file := ""
var phase_started := false
var waiting_for_crash := false
var replay_completed := false
var finished := false
var results: Dictionary = {}


func _init() -> void:
	var options := Support.parse_arguments(OS.get_cmdline_user_args())
	client_id = String(options.get("client-id", "")).strip_edges().to_lower()
	phase = String(options.get("phase", "")).strip_edges().to_lower()
	result_file = String(options.get("result-file", "")).strip_edges()
	control_file = String(options.get("control-file", "")).strip_edges()
	var port := int(String(options.get("port", "0")))
	if client_id not in ["a", "b"] or phase not in ["seed", "recover"] or result_file.is_empty() or port < 1:
		_write("FAILED", false, {"error_code": "INVALID_M6_CLIENT_WORKER_ARGUMENTS"})
		quit(2)
		return
	client = ClientRuntime.new()
	client.name = "M6RecoveryClient%s" % client_id.to_upper()
	root.add_child(client)
	client.session_ready.connect(_on_session_ready)
	client.connection_failed.connect(_on_connection_failed)
	client.server_disconnected.connect(_on_server_disconnected)
	var setup: Dictionary = client.setup({
		"host": "127.0.0.1",
		"port": port,
		"logical_player_id": client_id,
		"connect_timeout_ms": 45000,
		"command_timeout_ms": 12000,
		"automated_acceptance": true,
		"result_file": "",
	})
	if not bool(setup.get("success", false)):
		_write("FAILED", false, {"error_code": String(setup.get("error_code", "M6_CLIENT_SETUP_FAILED")), "setup": setup})
		quit(3)


func _process(_delta: float) -> bool:
	if finished or phase != "recover" or not phase_started:
		return false
	var control := Support.read(control_file)
	if not replay_completed and bool(control.get("allow_replay", false)):
		if client_id == "a":
			_run_replay_probe()
		else:
			replay_completed = true
			_write("REPLAY_BARRIER", false)
	if replay_completed and bool(control.get("allow_finish", false)):
		_run_recovered_continuation()
	return false


func _on_session_ready(_runtime) -> void:
	if phase_started:
		return
	phase_started = true
	results["initial_ownership_epoch"] = int(client.get_report().get("ownership_epoch", 0))
	results["player_entity_id"] = String(client.get_report().get("player_entity_id", ""))
	results["join_operation_id"] = String(client.get_report().get("join_operation_id", ""))
	if phase == "seed":
		_run_seed_phase()
	else:
		_write("RECOVER_READY", false)


func _run_seed_phase() -> void:
	results["move"] = client.move_blocking(3.0 if client_id == "a" else -2.0, 1.0 if client_id == "a" else 4.0)
	if client_id == "a":
		results["pickup"] = client.execute_item_command_blocking(
			"item.pickup", {"item_id": "item/shared/ore/1"},
			"operation/m6/process/a/pickup-ore/1"
		)
		results["hotbar"] = client.execute_item_command_blocking(
			"inventory.assign_hotbar", Support.HOTBAR_PAYLOAD,
			Support.HOTBAR_OPERATION_ID
		)
	else:
		results["pickup"] = client.execute_item_command_blocking(
			"item.pickup", {"item_id": "item/shared/beacon/1"},
			"operation/m6/process/b/pickup-beacon/1"
		)
	var passed := _result_success(results.get("move", {})) and _result_success(results.get("pickup", {}))
	if client_id == "a":
		passed = passed and _result_success(results.get("hotbar", {}))
	waiting_for_crash = passed
	_write("SEEDED" if passed else "FAILED", false, {"error_code": "" if passed else "M6_SEED_COMMAND_FAILED"})
	if not passed:
		_finish_client(false, 4)


func _run_replay_probe() -> void:
	var before: Dictionary = client.get_item_graph_snapshot()
	results["replay_before_checksum"] = String(before.get("checksum", ""))
	results["replay_before_revision"] = int(before.get("revision", -1))
	results["replay"] = client.execute_item_command_blocking(
		"inventory.assign_hotbar",
		Support.HOTBAR_PAYLOAD,
		Support.HOTBAR_OPERATION_ID,
		1
	)
	var after: Dictionary = client.get_item_graph_snapshot()
	results["replay_after_checksum"] = String(after.get("checksum", ""))
	results["replay_after_revision"] = int(after.get("revision", -2))
	results["replay_marked"] = _result_replay_marked(results.get("replay", {}))
	replay_completed = _result_success(results.get("replay", {})) and bool(results.get("replay_marked", false))
	_write("REPLAY_COMPLETE" if replay_completed else "FAILED", false, {
		"error_code": "" if replay_completed else "M6_RECOVERED_REPLAY_FAILED",
	})
	if not replay_completed:
		_finish_client(false, 5)


func _run_recovered_continuation() -> void:
	if finished:
		return
	results["continuation_move"] = client.move_blocking(1.0 if client_id == "a" else -1.0, 0.5)
	results["final_item_checksum"] = String(client.get_item_graph_snapshot().get("checksum", ""))
	results["final_player_checksum"] = String(client.get_snapshot().get("checksum", ""))
	var passed := _result_success(results.get("continuation_move", {}))
	var leave_result: Dictionary = client.request_graceful_leave(5000)
	results["leave"] = leave_result
	passed = passed and bool(leave_result.get("success", false))
	_write("COMPLETE" if passed else "FAILED", passed, {"error_code": "" if passed else "M6_RECOVERED_CONTINUATION_FAILED"})
	_finish_client(passed, 0 if passed else 6)


func _on_server_disconnected(_report: Dictionary) -> void:
	if phase == "seed" and waiting_for_crash and not finished:
		results["disconnect_report"] = client.get_report()
		_write("DISCONNECTED_AFTER_CRASH", true)
		_finish_client(true, 0)
	elif not finished:
		_write("FAILED", false, {"error_code": "UNEXPECTED_M6_SERVER_DISCONNECT"})
		_finish_client(false, 7)


func _on_connection_failed(error_code: String, details: Dictionary) -> void:
	if finished:
		return
	_write("FAILED", false, {"error_code": error_code, "connection_details": details})
	_finish_client(false, 8)


func _write(state: String, passed: bool, extra: Dictionary = {}) -> void:
	var report: Dictionary = {
		"schema": "planet_simulator.m6_recovery_client_worker.v1",
		"checkpoint": Support.CHECKPOINT,
		"build_id": Support.BUILD_ID,
		"state": state,
		"passed": passed,
		"client_id": client_id,
		"phase": phase,
		"process_id": OS.get_process_id(),
		"client_runtime": client.get_report() if client != null else {},
		"results": results.duplicate(true),
	}
	for key in extra.keys():
		report[key] = extra[key]
	Support.write(result_file, report)


func _finish_client(_passed: bool, exit_code: int) -> void:
	if finished:
		return
	finished = true
	if client != null:
		client.stop()
	quit(exit_code)


func _result_success(value) -> bool:
	return value is Dictionary and bool(Dictionary(value).get("success", false))


func _result_replay_marked(value) -> bool:
	if not value is Dictionary:
		return false
	var command_result: Dictionary = Dictionary(value).get("details", {}).get("result", {})
	return bool(command_result.get("details", {}).get("replay", false))
