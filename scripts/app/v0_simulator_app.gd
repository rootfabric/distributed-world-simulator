extends "res://scripts/app/simulator_app.gd"

const Live3Launch = preload("res://scripts/runtime/networked_gameplay/live3/live3_launch_options.gd")
const Live3HostControl = preload("res://scripts/runtime/networked_gameplay/live3/live3_host_control.gd")

var _live3_control
var _live3_bound := false
var _live3_stop_completed := false

# --network-mvp is still distinct from --network-playground at validation.
# LIVE3 is explicit (--world-slot); old LIVE2/test invocations are unchanged.
func _parse_launch_options() -> Dictionary:
	var has_live3 := false
	for raw in OS.get_cmdline_user_args():
		if String(raw).trim_prefix("--").get_slice("=", 0) in Live3Launch.EXTRA_KEYS:
			has_live3 = true
	var options: Dictionary
	if has_live3:
		var parsed: Dictionary = Live3Launch.parse(OS.get_cmdline_user_args())
		launch_option_errors.clear()
		launch_option_errors.append_array(parsed.get("errors", []))
		options = parsed.get("options", {})
		if launch_option_errors.is_empty():
			var preflight: Dictionary = Live3Launch.preflight_slot(options)
			if not bool(preflight.get("success", false)):
				launch_option_errors.append(String(preflight.get("error_code", "LIVE3_SLOT_PREFLIGHT_FAILED")))
	else:
		options = super._parse_launch_options()
	if launch_option_errors.is_empty() and bool(options.get("network_mvp", false)):
		options["network_playground"] = true
		options["v0_playable_sandbox_bridge"] = true
		options["v0_p1_playable_sandbox_bridge"] = true
	return options

func _ready() -> void:
	super._ready()
	if not launch_option_errors.is_empty() or not bool(launch_options.get("live3_enabled", false)):
		return
	_live3_control = Live3HostControl.new()
	_live3_control.name = "Live3HostControl"
	add_child(_live3_control)
	_live3_control.setup(self, launch_options)
	var server = dedicated_gameplay_server_runtime
	if server == null or not bool(server.get_report().get("configured", false)):
		_live3_control.publish("FAILED", {"saved": false, "error_code": "LIVE3_SERVER_NOT_READY"})
		request_graceful_shutdown("live3_server_not_ready", 20)
		return
	# Parent setup is synchronous; no transport poll/admission executes between
	# it and this bind. Recovery finishes before the next process iteration.
	server.set_process(false)
	var service = server.get("_service")
	var bridge = server.get("_construction_bridge")
	var bound: Dictionary = service.bind_live3_construction(bridge)
	if not bool(bound.get("success", false)):
		server.call("_enter_persistence_failure", String(bound.get("error_code", "LIVE3_RECOVERY_BIND_FAILED")))
		_live3_control.publish("FAILED", {"saved": false, "cause": bound})
		request_graceful_shutdown("live3_recovery_bind_failed", 21)
		return
	_live3_bound = true
	# M6's existing snapshot/checksum/commit path now includes native
	# Construction state, build progress and terminal command receipts.
	var persisted: Dictionary = server.call("_persist_checkpoint", "")
	if not bool(persisted.get("success", false)):
		server.call("_enter_persistence_failure", String(persisted.get("error_code", "LIVE3_INITIAL_CUT_FAILED")))
		_live3_control.publish("FAILED", {"saved": false, "cause": persisted})
		request_graceful_shutdown("live3_initial_cut_failed", 22)
		return
	var ready: Dictionary = _live3_control.publish("READY", {
		"saved": false,
		"recovered": bool(server.get("_recovered")),
		"generation": int(server.get("_checkpoint_generation")),
		"native_construction_bound": true,
		"durable_checksum": String(service.export_durable_state().get("checksum", "")),
	})
	if not bool(ready.get("success", false)):
		request_graceful_shutdown("live3_status_sink_failed", 23)
		return
	server.set_process(true)

func request_graceful_shutdown(reason: String = "shutdown", exit_code: int = 0) -> Dictionary:
	# Once draining starts, no new gameplay mutation can enter the final cut.
	if bool(launch_options.get("live3_enabled", false)) and dedicated_gameplay_server_runtime != null:
		dedicated_gameplay_server_runtime.set_process(false)
	return super.request_graceful_shutdown(reason, exit_code)

func _stop_networked_gameplay_runtimes() -> void:
	if not bool(launch_options.get("live3_enabled", false)):
		super._stop_networked_gameplay_runtimes()
		return
	# The parent calls this both from graceful shutdown and _exit_tree. Never
	# replace the first, authoritative stop result with a second empty stop.
	if _live3_stop_completed:
		return
	_live3_stop_completed = true
	if graphical_game_client_runtime != null and is_instance_valid(graphical_game_client_runtime):
		graphical_game_client_runtime.stop()
	var result: Dictionary = {"success": false, "error_code": "LIVE3_NO_BOUND_PERSISTENT_SERVER"}
	var generation := 0
	var server = dedicated_gameplay_server_runtime
	if server != null and is_instance_valid(server):
		result = server.stop()
		generation = int(server.get("_checkpoint_generation"))
	var saved := _live3_bound and bool(result.get("success", false))
	if not saved and _requested_exit_code == 0:
		_requested_exit_code = 24
	if _live3_control != null and is_instance_valid(_live3_control):
		var written: Dictionary = _live3_control.publish("STOPPED" if saved else "FAILED", {
			"saved": saved,
			"exit_code": _requested_exit_code,
			"generation": generation,
			"stop_result": result,
		})
		if not bool(written.get("success", false)) and _requested_exit_code == 0:
			_requested_exit_code = 25
