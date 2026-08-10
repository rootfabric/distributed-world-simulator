extends SceneTree

const RuntimeScript = preload("res://scripts/labs/t1/t1_d0_interactive_runtime_executor.gd")
const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")
const PresenterScript = preload("res://scripts/labs/t1/t1_d0_runtime_presenter.gd")

var _runtime
var _presenter
var _label: Label
var _server_tick: int = 1
var _last_pressed: Dictionary = {}


func _init() -> void:
	var world := Node3D.new()
	world.name = "T1A6VisualLab"
	root.add_child(world)

	_runtime = RuntimeScript.new()
	var setup: Dictionary = _runtime.setup("user://t1a6-visual-lab-m0")
	if not bool(setup.get("success", false)):
		push_error("T1A.6 visual lab runtime setup failed: %s" % setup)
		quit(1)
		return

	_presenter = PresenterScript.new()
	world.add_child(_presenter)
	var presenter_setup: Dictionary = _presenter.setup(_snapshot())
	if not bool(presenter_setup.get("success", false)):
		push_error("T1A.6 visual lab presenter setup failed: %s" % presenter_setup)
		quit(1)
		return
	_presenter.force_sync()

	_build_room(world)
	_build_camera(world)
	_build_ui()
	_update_ui()
	process_frame.connect(_tick)


func _tick() -> void:
	if _pressed_once(KEY_ESCAPE):
		quit(0)
		return
	if _pressed_once(KEY_1):
		_toggle_door()
	if _pressed_once(KEY_2):
		_toggle_lamp()
	if _pressed_once(KEY_3):
		_toggle_generator()
	if _pressed_once(KEY_4):
		_use_console()
	_presenter.force_sync()
	_update_ui()


func _toggle_door() -> void:
	var subject: Dictionary = _runtime.get_subject("DOOR")
	var open := String(Dictionary(subject.get("state", {})).get("position", "")) == "OPEN"
	_execute("DOOR", "CLOSE_DOOR" if open else "OPEN_DOOR", int(subject.get("revision", 0)))


func _toggle_lamp() -> void:
	var subject: Dictionary = _runtime.get_subject("LAMP")
	_execute("LAMP", "TOGGLE_LIGHT", int(subject.get("revision", 0)))


func _toggle_generator() -> void:
	var subject: Dictionary = _runtime.get_subject("GENERATOR")
	var running := bool(Dictionary(subject.get("state", {})).get("running", false))
	_execute("GENERATOR", "STOP_GENERATOR" if running else "START_GENERATOR", int(subject.get("revision", 0)))


func _use_console() -> void:
	var subject: Dictionary = _runtime.get_subject("CONSOLE")
	_execute("CONSOLE", "USE_WORKSTATION", int(subject.get("revision", 0)))


func _execute(kind: String, action: String, expected_revision: int) -> void:
	var operation_id := "operation/t1a6/visual/%s/%d" % [action.to_lower(), Time.get_ticks_usec()]
	var result: Dictionary = _runtime.execute(kind, action, operation_id, expected_revision)
	if not bool(result.get("success", false)):
		push_warning("T1A.6 visual action rejected: %s" % result)
		return
	_server_tick += 1
	_presenter.apply_snapshot(_snapshot(), false)


func _snapshot() -> Dictionary:
	var report: Dictionary = _runtime.get_report()
	return SnapshotScript.create(
		String(report.get("construct_id", "")),
		1,
		_server_tick,
		Dictionary(report.get("runtime_state", {}))
	)


func _build_room(world: Node3D) -> void:
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(8.0, 0.15, 8.0)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(0.0, -0.15, 0.0)
	world.add_child(floor_mesh)

	for row in [
		{"position": Vector3(0.0, 1.5, -4.0), "size": Vector3(8.0, 3.0, 0.15)},
		{"position": Vector3(4.0, 1.5, 0.0), "size": Vector3(0.15, 3.0, 8.0)},
		{"position": Vector3(-4.0, 1.5, 0.0), "size": Vector3(0.15, 3.0, 8.0)},
	]:
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = row["size"]
		wall.mesh = box
		wall.position = row["position"]
		world.add_child(wall)

	var ambient := DirectionalLight3D.new()
	ambient.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	ambient.light_energy = 0.7
	world.add_child(ambient)


func _build_camera(world: Node3D) -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.2, 7.5)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.0, 0.0), Vector3.UP)
	camera.current = true
	world.add_child(camera)


func _build_ui() -> void:
	_label = Label.new()
	_label.position = Vector2(18.0, 18.0)
	_label.size = Vector2(680.0, 220.0)
	root.add_child(_label)


func _update_ui() -> void:
	var door: Dictionary = _runtime.get_subject("DOOR")
	var generator: Dictionary = _runtime.get_subject("GENERATOR")
	var lamp: Dictionary = _runtime.get_subject("LAMP")
	var console: Dictionary = _runtime.get_subject("CONSOLE")
	var power: Dictionary = _runtime.get_report().get("power_execution_profile", {})
	var storage: Dictionary = _runtime.get_report().get("power_storage", {})
	_label.text = (
		"T1A.6 Runtime Presentation Lab\n"
		+ "1 Door  |  2 Lamp  |  3 Generator  |  4 Console  |  Esc Exit\n\n"
		+ "Door: %s   Generator: %s   Lamp: %s\n" % [
			String(Dictionary(door.get("state", {})).get("position", "?")),
			"RUNNING" if bool(Dictionary(generator.get("state", {})).get("running", false)) else "STOPPED",
			"ON" if bool(Dictionary(lamp.get("state", {})).get("on", false)) else "OFF",
		]
		+ "Console uses: %d   Power: %s   Battery: %.2f\n" % [
			int(Dictionary(console.get("state", {})).get("use_count", 0)),
			String(power.get("status", "?")),
			float(storage.get("stored_amount", 0.0)),
		]
		+ "canonical runtime state -> derived presenter (presentation is not authority)"
	)


func _pressed_once(keycode: Key) -> bool:
	var pressed := Input.is_key_pressed(keycode)
	var was_pressed := bool(_last_pressed.get(keycode, false))
	_last_pressed[keycode] = pressed
	return pressed and not was_pressed
