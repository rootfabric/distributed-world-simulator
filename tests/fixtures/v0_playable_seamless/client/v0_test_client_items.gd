extends SceneTree

# Test-only graphical diagnostic client.
# Canonical networking and Item Graph commands are executed by the existing M3/M4 client runtime.

const Client = preload("res://scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime.gd")
const Support = preload("res://scripts/runtime/networked_gameplay/m5/m5_graphical_acceptance_support.gd")

const DEMO_COMMANDS := [
	{"label": "pickup beacon", "command": "item.pickup", "payload": {"item_id": "item/shared/beacon/1"}},
	{"label": "select hotbar 2", "command": "inventory.select_hotbar", "payload": {"selected_hotbar_index": 2}},
	{"label": "mount beacon", "command": "item.mount", "payload": {"item_id": "item/shared/beacon/1", "mount_id": "mount/shared/socket/1"}},
	{"label": "detach beacon", "command": "item.detach", "payload": {"mount_id": "mount/shared/socket/1"}},
	{"label": "open shared crate", "command": "container.open", "payload": {"container_id": "container/shared/crate/1"}},
	{"label": "move beacon to crate", "command": "item.move_to_container", "payload": {"item_id": "item/shared/beacon/1", "container_id": "container/shared/crate/1"}},
	{"label": "close shared crate", "command": "container.close", "payload": {"container_id": "container/shared/crate/1"}},
]

var _client
var _args: Dictionary = {}
var _client_id := ""
var _result_file := ""
var _peer_file := ""
var _stage := "BOOT"
var _command_index := 0
var _command_results: Array = []
var _started_ms := 0
var _next_action_ms := 0
var _step_ms := 700
var _timeout_ms := 120000
var _finished := false
var _target_checksum := ""
var _last_action := "starting"

var _status: Label
var _item_status: Label
var _progress: ProgressBar


func _init() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	_client_id = String(_args.get("client-id", "")).strip_edges().to_lower()
	_result_file = String(_args.get("result-file", "")).strip_edges()
	_peer_file = String(_args.get("peer-file", "")).strip_edges()
	_step_ms = maxi(100, int(_args.get("step-ms", "700")))
	_timeout_ms = maxi(30000, int(_args.get("timeout-ms", "120000")))
	if _client_id not in ["a", "b"] or _result_file.is_empty() or _peer_file.is_empty():
		_finish(false, "INVALID_OPTIONS")
		return
	if DisplayServer.get_name().to_lower() in ["", "headless", "dummy"]:
		_finish(false, "GRAPHICAL_DISPLAY_REQUIRED")
		return

	_build_ui()
	_client = Client.new()
	root.add_child(_client)
	var setup: Dictionary = _client.setup({
		"host": String(_args.get("host", "127.0.0.1")),
		"port": int(_args.get("port", "0")),
		"logical_player_id": _client_id,
		"connect_timeout_ms": 30000,
		"command_timeout_ms": 10000,
		"automated_acceptance": true,
	})
	if not bool(setup.get("success", false)):
		_finish(false, "SETUP_FAILED", {"setup": setup})
		return
	_started_ms = Time.get_ticks_msec()
	_stage = "WAIT_READY"
	_write_state("CONNECTING")
	process_frame.connect(_tick)


func _tick() -> void:
	if _finished:
		return
	var now := Time.get_ticks_msec()
	if now - _started_ms > _timeout_ms:
		_finish(false, "TIMEOUT", {"stage": _stage})
		return
	_update_ui()
	if _client == null or not _client.is_ready():
		return

	if _stage == "WAIT_READY":
		if _client_id == "b":
			_stage = "WAIT_A_DONE"
			_last_action = "ready; observing Client A"
			_write_state("B_READY")
		else:
			var peer := Support.read(_peer_file)
			if String(peer.get("state", "")) != "B_READY":
				return
			_stage = "RUN_DEMO"
			_last_action = "both clients ready"
			_next_action_ms = now + _step_ms
			_write_state("A_READY")
		return

	if now < _next_action_ms:
		return

	if _client_id == "a":
		_tick_client_a(now)
	else:
		_tick_client_b(now)


func _tick_client_a(now: int) -> void:
	match _stage:
		"RUN_DEMO":
			if _command_index >= DEMO_COMMANDS.size():
				_stage = "PUBLISH_A_DONE"
				_next_action_ms = now + _step_ms
				return
			var spec: Dictionary = Dictionary(DEMO_COMMANDS[_command_index])
			_last_action = String(spec.get("label", "command"))
			var result: Dictionary = _client.execute_item_command_blocking(
				String(spec.get("command", "")),
				Dictionary(spec.get("payload", {})).duplicate(true)
			)
			_command_results.append({
				"index": _command_index,
				"label": _last_action,
				"result": result.duplicate(true),
			})
			if not bool(result.get("success", false)):
				_finish(false, "COMMAND_REJECTED", {
					"index": _command_index,
					"label": _last_action,
					"result": result,
				})
				return
			_command_index += 1
			_write_state("A_RUNNING")
			_next_action_ms = now + _step_ms
		"PUBLISH_A_DONE":
			var snapshot: Dictionary = _client.get_item_graph_snapshot()
			_target_checksum = String(snapshot.get("checksum", ""))
			if _target_checksum.is_empty():
				_finish(false, "EMPTY_ITEM_GRAPH_CHECKSUM")
				return
			_last_action = "waiting for Client B convergence"
			_stage = "WAIT_B_CONVERGED"
			_write_state("A_DONE")
			_next_action_ms = now + 100
		"WAIT_B_CONVERGED":
			var peer := Support.read(_peer_file)
			if String(peer.get("state", "")) != "COMPLETE" or not bool(peer.get("passed", false)):
				_next_action_ms = now + 100
				return
			var own_checksum := String(_client.get_item_graph_snapshot().get("checksum", ""))
			var peer_checksum := String(peer.get("item_graph", {}).get("checksum", ""))
			if own_checksum != peer_checksum or own_checksum != _target_checksum:
				_finish(false, "FINAL_CHECKSUM_MISMATCH", {
					"own": own_checksum,
					"peer": peer_checksum,
					"target": _target_checksum,
				})
				return
			_last_action = "A/B Item Graph converged"
			_finish(true, "COMPLETE")


func _tick_client_b(now: int) -> void:
	if _stage != "WAIT_A_DONE":
		return
	var peer := Support.read(_peer_file)
	if String(peer.get("state", "")) not in ["A_DONE", "COMPLETE"]:
		_next_action_ms = now + 100
		return
	_target_checksum = String(peer.get("item_graph", {}).get("checksum", ""))
	if _target_checksum.is_empty():
		_next_action_ms = now + 100
		return
	_client._poll_blocking_once()
	var own_checksum := String(_client.get_item_graph_snapshot().get("checksum", ""))
	if own_checksum != _target_checksum:
		_last_action = "waiting for Item Graph revision from A"
		_next_action_ms = now + 100
		return
	_last_action = "observed exact Item Graph checksum from A"
	_finish(true, "COMPLETE")


func _build_ui() -> void:
	root.title = "DWS Test Client %s — Items" % _client_id.to_upper()
	root.size = Vector2i(720, 420)
	var screen_size := DisplayServer.screen_get_size()
	if _client_id == "a":
		root.position = Vector2i(40, 80)
	else:
		root.position = Vector2i(maxi(40, screen_size.x - 760), 80)

	var background := ColorRect.new()
	background.color = Color(0.045, 0.035, 0.055, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var title := Label.new()
	title.text = "DWS TEST CLIENT %s  /  ITEM GRAPH" % _client_id.to_upper()
	title.position = Vector2(28, 22)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	_status = Label.new()
	_status.position = Vector2(28, 70)
	_status.size = Vector2(660, 165)
	_status.add_theme_font_size_override("font_size", 17)
	root.add_child(_status)

	_item_status = Label.new()
	_item_status.position = Vector2(28, 242)
	_item_status.size = Vector2(660, 95)
	_item_status.add_theme_font_size_override("font_size", 16)
	root.add_child(_item_status)

	_progress = ProgressBar.new()
	_progress.position = Vector2(28, 350)
	_progress.size = Vector2(660, 28)
	_progress.min_value = 0
	_progress.max_value = DEMO_COMMANDS.size()
	_progress.show_percentage = false
	root.add_child(_progress)

	var footer := Label.new()
	footer.text = "A performs canonical commands; B is an independent replica observer."
	footer.position = Vector2(28, 386)
	footer.size = Vector2(660, 24)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)


func _update_ui() -> void:
	if _status == null:
		return
	var snapshot: Dictionary = _client.get_item_graph_snapshot() if _client != null else {}
	var checksum := String(snapshot.get("checksum", ""))
	var revision := int(snapshot.get("revision", 0))
	var report: Dictionary = _client.get_report() if _client != null else {}
	_status.text = (
		"stage: %s\n"
		+ "client/player: %s\n"
		+ "Item Graph revision: %d\n"
		+ "checksum: %s\n"
		+ "last action: %s"
	) % [
		_stage,
		_client_id,
		revision,
		checksum.left(28) + ("…" if checksum.length() > 28 else ""),
		_last_action,
	]
	_item_status.text = (
		"beacon location: %s\n"
		+ "items visible: %d\n"
		+ "runtime ready: %s"
	) % [
		_find_item_location(snapshot, "item/shared/beacon/1"),
		Array(snapshot.get("items", [])).size(),
		str(_client.is_ready() if _client != null else false),
	]
	_progress.value = _command_index if _client_id == "a" else (DEMO_COMMANDS.size() if _target_checksum != "" else 0)
	if not report.is_empty():
		root.title = "DWS Test Client %s — Items — rev %d" % [_client_id.to_upper(), revision]


func _find_item_location(snapshot: Dictionary, item_id: String) -> String:
	for raw_container in snapshot.get("containers", []):
		var container: Dictionary = Dictionary(raw_container)
		if item_id in Array(container.get("slots", [])):
			return String(container.get("container_id", "container/?"))
	return "world / not contained"


func _write_state(state: String, passed: bool = false, extra: Dictionary = {}) -> void:
	var value := {
		"schema": "distributed_world_simulator.v0_test_client_items.v1",
		"state": state,
		"passed": passed,
		"process_id": OS.get_process_id(),
		"client_id": _client_id,
		"display_server": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"stage": _stage,
		"command_index": _command_index,
		"command_results": _command_results.duplicate(true),
		"last_action": _last_action,
		"item_graph": _client.get_item_graph_snapshot() if _client != null else {},
		"client_runtime": _client.get_report() if _client != null else {},
	}
	for key in extra.keys():
		value[String(key)] = extra[key]
	Support.write(_result_file, value)


func _finish(passed: bool, state: String, details: Dictionary = {}) -> void:
	if _finished:
		return
	_finished = true
	_stage = state
	_update_ui()
	var leave_result: Dictionary = {}
	if _client != null:
		leave_result = _client.request_graceful_leave(3000)
		if not bool(leave_result.get("success", false)):
			passed = false
			details["leave_result"] = leave_result
	_write_state(state if passed else "FAILED", passed, {
		"details": details.duplicate(true),
		"leave_result": leave_result.duplicate(true),
	})
	if _client != null:
		_client.stop()
	quit(0 if passed else 1)


func _parse_args(values: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for raw in values:
		var text := String(raw)
		if not text.begins_with("--") or not text.contains("="):
			continue
		var split := text.find("=")
		out[text.substr(2, split - 2)] = text.substr(split + 1)
	return out
