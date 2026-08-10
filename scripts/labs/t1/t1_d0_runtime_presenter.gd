extends Node3D

const SnapshotScript = preload("res://scripts/runtime/networked_gameplay/contracts/construction_runtime_snapshot.gd")

const SCHEMA: String = "planet_simulator.t1a6_d0_runtime_presenter.v1"
const DOOR_RUNTIME_ID: String = "runtime/t1a5/d0/door"
const GENERATOR_RUNTIME_ID: String = "runtime/t1a5/d0/generator"
const LAMP_RUNTIME_ID: String = "runtime/t1a5/d0/lamp"
const CONSOLE_RUNTIME_ID: String = "runtime/t1a5/d0/console"
const DOOR_OPEN_YAW: float = -1.57079632679
const DOOR_SPEED_RAD_PER_SEC: float = 5.5

var _door_hinge: Node3D
var _lamp: OmniLight3D
var _console_indicator: MeshInstance3D
var _generator_indicator: MeshInstance3D
var _target_door_yaw: float = 0.0
var _snapshot_revision: int = -1
var _snapshot_checksum: String = ""
var _updates: int = 0
var _configured: bool = false


func setup(snapshot: Dictionary = {}) -> Dictionary:
	if _configured:
		return _failure("T1A6_PRESENTER_ALREADY_CONFIGURED")
	_build_visuals()
	_configured = true
	set_process(true)
	if not snapshot.is_empty():
		var applied: Dictionary = apply_snapshot(snapshot, true)
		if not bool(applied.get("success", false)):
			return applied
	return _success()


func apply_snapshot(snapshot: Dictionary, snap: bool = false) -> Dictionary:
	if not _configured:
		return _failure("T1A6_PRESENTER_NOT_CONFIGURED")
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var runtime_state: Dictionary = Dictionary(snapshot.get("runtime_state", {}))
	var door: Dictionary = _subject(runtime_state, DOOR_RUNTIME_ID)
	var generator: Dictionary = _subject(runtime_state, GENERATOR_RUNTIME_ID)
	var lamp: Dictionary = _subject(runtime_state, LAMP_RUNTIME_ID)
	var console: Dictionary = _subject(runtime_state, CONSOLE_RUNTIME_ID)
	if door.is_empty() or generator.is_empty() or lamp.is_empty() or console.is_empty():
		return _failure("T1A6_PRESENTATION_SUBJECT_MISSING")

	_target_door_yaw = DOOR_OPEN_YAW if String(Dictionary(door.get("state", {})).get("position", "")) == "OPEN" else 0.0
	_lamp.visible = bool(Dictionary(lamp.get("state", {})).get("on", false))
	_console_indicator.visible = bool(Dictionary(console.get("state", {})).get("active", false))
	_generator_indicator.visible = bool(Dictionary(generator.get("state", {})).get("running", false))
	if snap:
		_door_hinge.rotation.y = _target_door_yaw
	_snapshot_revision = int(snapshot.get("revision", -1))
	_snapshot_checksum = String(snapshot.get("state_checksum", ""))
	_updates += 1
	return _success({"revision": _snapshot_revision})


func force_sync() -> void:
	if _door_hinge != null:
		_door_hinge.rotation.y = _target_door_yaw


func _process(delta: float) -> void:
	if not _configured or _door_hinge == null:
		return
	_door_hinge.rotation.y = move_toward(
		_door_hinge.rotation.y,
		_target_door_yaw,
		DOOR_SPEED_RAD_PER_SEC * maxf(delta, 0.0)
	)


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"snapshot_revision": _snapshot_revision,
		"state_checksum": _snapshot_checksum,
		"updates": _updates,
		"door_open": is_equal_approx(_target_door_yaw, DOOR_OPEN_YAW),
		"door_target_yaw": _target_door_yaw,
		"door_visual_yaw": _door_hinge.rotation.y if _door_hinge != null else 0.0,
		"lamp_visible": _lamp.visible if _lamp != null else false,
		"console_active": _console_indicator.visible if _console_indicator != null else false,
		"generator_running": _generator_indicator.visible if _generator_indicator != null else false,
	}


func _build_visuals() -> void:
	name = "T1A6_D0_RuntimePresenter"

	_door_hinge = Node3D.new()
	_door_hinge.name = "DoorHinge"
	_door_hinge.position = Vector3(-2.0, 1.0, 0.0)
	add_child(_door_hinge)
	var door_mesh := MeshInstance3D.new()
	door_mesh.name = "DoorPanel"
	var door_box := BoxMesh.new()
	door_box.size = Vector3(1.4, 2.0, 0.12)
	door_mesh.mesh = door_box
	door_mesh.position = Vector3(0.7, 0.0, 0.0)
	_door_hinge.add_child(door_mesh)

	_lamp = OmniLight3D.new()
	_lamp.name = "RuntimeLamp"
	_lamp.position = Vector3(0.0, 2.4, 0.0)
	_lamp.omni_range = 7.0
	_lamp.light_energy = 4.0
	_lamp.visible = false
	add_child(_lamp)
	var lamp_mesh := MeshInstance3D.new()
	lamp_mesh.name = "LampFixture"
	var lamp_sphere := SphereMesh.new()
	lamp_sphere.radius = 0.16
	lamp_sphere.height = 0.32
	lamp_mesh.mesh = lamp_sphere
	lamp_mesh.position = _lamp.position
	add_child(lamp_mesh)

	_console_indicator = MeshInstance3D.new()
	_console_indicator.name = "ConsoleActiveIndicator"
	var console_box := BoxMesh.new()
	console_box.size = Vector3(0.7, 0.5, 0.15)
	_console_indicator.mesh = console_box
	_console_indicator.position = Vector3(2.0, 1.0, 0.0)
	_console_indicator.visible = false
	add_child(_console_indicator)

	_generator_indicator = MeshInstance3D.new()
	_generator_indicator.name = "GeneratorRunningIndicator"
	var generator_box := BoxMesh.new()
	generator_box.size = Vector3(0.7, 0.7, 0.7)
	_generator_indicator.mesh = generator_box
	_generator_indicator.position = Vector3(0.0, 0.5, -2.0)
	_generator_indicator.visible = false
	add_child(_generator_indicator)


static func _subject(runtime_state: Dictionary, runtime_id: String) -> Dictionary:
	for subject_value in runtime_state.get("subjects", []):
		if subject_value is Dictionary and String(subject_value.get("runtime_id", "")) == runtime_id:
			return Dictionary(subject_value).duplicate(true)
	return {}


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
