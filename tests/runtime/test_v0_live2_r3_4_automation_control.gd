extends SceneTree

const Bridge = preload(
	"res://scripts/runtime/automation/live2_automation_control_bridge.gd"
)

const TOKEN := "r3-4-automation-test-token"


class FakeRegistry:
	extends RefCounted

	func list_commands(_category: String = "") -> Array[Dictionary]:
		return [
			{
				"id": "player.interact",
				"description": "fixture",
				"usage": "player.interact",
				"category": "gameplay",
				"aliases": [],
				"owner_id": "active_world",
			},
		]


class FakeRuntime:
	extends Node

	var movement_calls: Array[Dictionary] = []
	var stop_calls := 0
	var view_calls: Array[Dictionary] = []

	func automation_set_movement_intent(params: Dictionary) -> Dictionary:
		movement_calls.append(params.duplicate(true))
		return {
			"success": true,
			"error_code": "",
			"details": {
				"movement_enabled": true,
				"movement_intent": params.duplicate(true),
			},
		}

	func automation_stop_movement() -> Dictionary:
		stop_calls += 1
		return {
			"success": true,
			"error_code": "",
			"details": {"movement_enabled": false},
		}

	func automation_set_view(params: Dictionary) -> Dictionary:
		view_calls.append(params.duplicate(true))
		return {
			"success": true,
			"error_code": "",
			"details": params.duplicate(true),
		}

	func automation_get_state() -> Dictionary:
		return {
			"schema": "fixture.automation_state.v1",
			"movement_calls": movement_calls.size(),
			"stop_calls": stop_calls,
			"view_calls": view_calls.size(),
		}


class InputProbe:
	extends Node

	var keys: Array[Dictionary] = []
	var motions: Array[Dictionary] = []
	var buttons: Array[Dictionary] = []

	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			keys.append({
				"keycode": event.keycode,
				"pressed": event.pressed,
			})
		elif event is InputEventMouseMotion:
			motions.append({
				"position": event.position,
				"relative": event.relative,
			})
		elif event is InputEventMouseButton:
			buttons.append({
				"position": event.position,
				"button_index": event.button_index,
				"pressed": event.pressed,
			})


class FakeApp:
	extends Node

	var command_registry = FakeRegistry.new()
	var runtime := FakeRuntime.new()
	var commands: Array[String] = []

	func _ready() -> void:
		add_child(runtime)

	func execute_runtime_command(line: String) -> Dictionary:
		commands.append(line)
		if line == "runtime.snapshot":
			return {
				"success": true,
				"snapshot": {
					"schema": "fixture.runtime.v1",
					"world_id": "earth",
				},
			}
		if line == "network.jitter.snapshot":
			return {
				"success": true,
				"jitter": {
					"local": {"hard_corrections": 0},
					"remotes": {},
				},
			}
		return {
			"success": true,
			"error_code": "",
			"output": "fixture-ok",
		}

	func get_current_runtime():
		return runtime

	func get_current_world_id() -> String:
		return "earth"


var assertions := 0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var app := FakeApp.new()
	root.add_child(app)
	var input_probe := InputProbe.new()
	root.add_child(input_probe)
	await process_frame

	var bridge := Bridge.new()
	app.add_child(bridge)
	var port := 0
	var setup: Dictionary = {}
	for candidate in range(29651, 29670):
		setup = bridge.setup(app, {
			"port": candidate,
			"token": TOKEN,
			"output_dir": "user://r3-4-automation-test",
		})
		if bool(setup.get("success", false)):
			port = candidate
			break
	_assert(port > 0, "automation bridge binds a localhost test port")
	if port <= 0:
		bridge.queue_free()
		app.queue_free()
		_finish()
		return

	var report: Dictionary = bridge.get_report()
	_assert(String(report.get("bind_address", "")) == "127.0.0.1", "bridge is loopback-only")
	_assert(int(report.get("port", 0)) == port, "bridge reports bound port")

	var peer := StreamPeerTCP.new()
	var connect_error := peer.connect_to_host("127.0.0.1", port)
	_assert(connect_error == OK, "external TCP client starts connecting")
	var connected := false
	for _index in range(240):
		peer.poll()
		await process_frame
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			connected = true
			break
	_assert(connected, "external TCP client connects to bridge")
	if not connected:
		bridge.queue_free()
		app.queue_free()
		_finish()
		return

	var ping := await _exchange(peer, _request("ping-1", "ping", {}))
	_assert(bool(ping.get("ok", false)), "ping succeeds")
	_assert(String(ping.get("result", {}).get("world_id", "")) == "earth", "ping exposes world identity")

	var commands := await _exchange(peer, _request("commands-1", "commands.list", {}))
	_assert(bool(commands.get("ok", false)), "commands.list succeeds")
	_assert(commands.get("result", {}).get("commands", []).size() == 1, "commands.list is structured")

	var command := await _exchange(peer, _request(
		"command-1",
		"command.execute",
		{"line": "player.interact"}
	))
	_assert(bool(command.get("ok", false)), "command.execute succeeds")
	_assert(app.commands.has("player.interact"), "command.execute routes through app command registry surface")

	var movement := await _exchange(peer, _request(
		"move-1",
		"movement.set",
		{
			"move_x": 0.5,
			"move_z": -1.0,
			"look_yaw": 0.25,
			"sprint": true,
			"ttl_ms": 600,
		}
	))
	_assert(bool(movement.get("ok", false)), "movement.set succeeds")
	_assert(app.runtime.movement_calls.size() == 1, "movement.set reaches runtime seam")
	_assert(is_equal_approx(float(app.runtime.movement_calls[0].get("move_x", 0.0)), 0.5), "movement payload preserved")

	var view := await _exchange(peer, _request(
		"view-1",
		"view.set",
		{"yaw": 1.0, "pitch": -0.2}
	))
	_assert(bool(view.get("ok", false)), "view.set succeeds")
	_assert(app.runtime.view_calls.size() == 1, "view.set reaches runtime seam")

	var key_down := await _exchange(peer, _request(
		"key-1",
		"input.key",
		{"key": "G", "pressed": true}
	))
	_assert(bool(key_down.get("ok", false)), "input.key succeeds")
	await process_frame
	_assert(not input_probe.keys.is_empty(), "injected key reaches Godot input pipeline")
	_assert(int(input_probe.keys.back().get("keycode", 0)) == KEY_G, "injected keycode preserved")
	_assert(bool(input_probe.keys.back().get("pressed", false)), "injected key press preserved")

	var pointer_move := await _exchange(peer, _request(
		"pointer-1",
		"input.pointer_move",
		{"x": 120.0, "y": 80.0, "dx": 5.0, "dy": -2.0}
	))
	_assert(bool(pointer_move.get("ok", false)), "pointer move succeeds")
	await process_frame
	_assert(not input_probe.motions.is_empty(), "pointer move reaches Godot input pipeline")
	_assert(
		(input_probe.motions.back().get("position", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(120.0, 80.0)),
		"pointer position preserved"
	)

	var pointer_button := await _exchange(peer, _request(
		"button-1",
		"input.pointer_button",
		{"x": 120.0, "y": 80.0, "button": "left", "pressed": true}
	))
	_assert(bool(pointer_button.get("ok", false)), "pointer button succeeds")
	await process_frame
	_assert(not input_probe.buttons.is_empty(), "pointer button reaches Godot input pipeline")
	_assert(int(input_probe.buttons.back().get("button_index", 0)) == MOUSE_BUTTON_LEFT, "pointer button preserved")

	var automation_state := await _exchange(peer, _request(
		"state-1",
		"state.get",
		{"kind": "automation"}
	))
	_assert(bool(automation_state.get("ok", false)), "automation state succeeds")
	_assert(
		int(automation_state.get("result", {}).get("automation", {}).get("movement_calls", 0)) == 1,
		"automation state is structured"
	)

	var runtime_state := await _exchange(peer, _request(
		"state-2",
		"state.get",
		{"kind": "runtime"}
	))
	_assert(bool(runtime_state.get("ok", false)), "runtime state succeeds")
	_assert(
		String(runtime_state.get("result", {}).get("snapshot", {}).get("world_id", "")) == "earth",
		"runtime snapshot returned"
	)

	var jitter_state := await _exchange(peer, _request(
		"state-3",
		"state.get",
		{"kind": "jitter"}
	))
	_assert(bool(jitter_state.get("ok", false)), "jitter state succeeds")
	_assert(
		int(jitter_state.get("result", {}).get("jitter", {}).get("local", {}).get("hard_corrections", -1)) == 0,
		"jitter snapshot returned"
	)

	var stopped := await _exchange(peer, _request("stop-1", "movement.stop", {}))
	_assert(bool(stopped.get("ok", false)), "movement.stop succeeds")
	_assert(app.runtime.stop_calls == 1, "movement.stop reaches runtime seam")

	var unauthorized_request := _request("auth-1", "ping", {})
	unauthorized_request["token"] = "wrong-token"
	var unauthorized := await _exchange(peer, unauthorized_request)
	_assert(not bool(unauthorized.get("ok", true)), "wrong token rejected")
	_assert(String(unauthorized.get("error_code", "")) == "AUTOMATION_UNAUTHORIZED", "wrong token has explicit error")

	var unknown := await _exchange(peer, _request("unknown-1", "god_mode", {}))
	_assert(not bool(unknown.get("ok", true)), "unknown method rejected")
	_assert(String(unknown.get("error_code", "")) == "AUTOMATION_METHOD_UNKNOWN", "unknown method fails closed")

	peer.disconnect_from_host()
	bridge.stop()
	bridge.queue_free()
	app.queue_free()
	input_probe.queue_free()
	await process_frame
	_finish()


func _request(id: String, method: String, params: Dictionary) -> Dictionary:
	return {
		"schema": Bridge.REQUEST_SCHEMA,
		"id": id,
		"token": TOKEN,
		"method": method,
		"params": params.duplicate(true),
	}


func _exchange(peer: StreamPeerTCP, payload: Dictionary) -> Dictionary:
	var write_error := peer.put_data(
		(JSON.stringify(payload, "", false, true) + "\n").to_utf8_buffer()
	)
	_assert(write_error == OK, "automation request writes to socket")
	var buffer := ""
	for _index in range(240):
		peer.poll()
		await process_frame
		var available := peer.get_available_bytes()
		if available <= 0:
			continue
		var read = peer.get_partial_data(available)
		if not read is Array or read.size() < 2 or int(read[0]) != OK:
			return {}
		buffer += (read[1] as PackedByteArray).get_string_from_utf8()
		if buffer.contains("\n"):
			var line := buffer.left(buffer.find("\n"))
			var parsed = JSON.parse_string(line)
			return Dictionary(parsed) if parsed is Dictionary else {}
	return {}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		push_error(failure)
	print("V0-LIVE.2 R3.4 automation control: %d assertions, %d failures" % [
		assertions,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)
