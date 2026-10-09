class_name EarthLocalAvatarPresenter
extends Node3D

const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")
const Host = preload(
	"res://scripts/characters/avatar/player_avatar_host.gd"
)
const Bootstrap = preload(
	"res://scripts/characters/runtime/production_avatar_bootstrap.gd"
)
const Projector = preload(
	"res://scripts/app/earth_surface_render_projector.gd"
)

var _earth_world
var _earth_explorer
var _host
var _projection_updates := 0
var _motion_updates := 0
var _network_motion_updates := 0
var _last_error_code := ""
var _network_record_seen := false
var _first_person_mode := true
var _eye_height_m := 1.62
var _visual_vertical_offset_m := -1.62

func setup(
	earth_world,
	earth_explorer,
	initial_character_id: String = ""
) -> Dictionary:
	if earth_world == null or earth_explorer == null:
		return Contract.failure("CHAR1_EARTH_DEPENDENCY_MISSING")
	_earth_world = earth_world
	_earth_explorer = earth_explorer
	var runtime: Dictionary = Bootstrap.create_runtime()
	if not bool(runtime.get("success", false)):
		return runtime
	_host = Host.new()
	_host.name = "PlayerAvatarHost"
	add_child(_host)
	var details: Dictionary = runtime.get("details", {})
	var host_setup: Dictionary = _host.setup(
		details.get("catalog"),
		details.get("providers"),
		initial_character_id,
		true
	)
	if not bool(host_setup.get("success", false)):
		_host.queue_free()
		_host = null
		return host_setup
	_host.set_first_person_mode(_first_person_mode)
	# Local first-person world-model preview policy: hide the whole avatar.
	# Other clients render their independent remote presenters unaffected.
	_host.visible = not _first_person_mode
	_refresh_definition_projection_options()
	refresh_projection()
	return Contract.success({
		"character_id": _host.get_active_character_id(),
		"first_person_mode": true,
	})

func apply_player_record(record: Dictionary) -> Dictionary:
	if _host == null:
		return Contract.failure("CHAR1_AVATAR_HOST_NOT_READY")
	var velocity: Dictionary = Dictionary(record.get("velocity", {}))
	var state := {
		"schema": Contract.MOTION_SCHEMA,
		"velocity": {
			"x": float(velocity.get("x", 0.0)),
			"y": float(velocity.get("y", 0.0)),
			"z": float(velocity.get("z", 0.0)),
		},
		"grounded": absf(float(velocity.get("y", 0.0))) < 0.05,
		"facing_yaw": float(record.get("orientation_yaw", 0.0)),
		"state_revision": maxi(0, int(record.get("state_revision", 0))),
	}
	var result: Dictionary = _host.apply_motion_state(state)
	if bool(result.get("success", false)):
		_motion_updates += 1
		_network_motion_updates += 1
		_network_record_seen = true
	else:
		_last_error_code = String(
			result.get("error_code", "CHAR1_MOTION_REJECTED")
		)
	return result

func apply_explorer_motion() -> Dictionary:
	if _network_record_seen or _host == null or _earth_explorer == null:
		return Contract.success({"skipped": true})
	var velocity_value = _earth_explorer.get("linear_velocity_mps")
	var velocity: Vector3 = (
		velocity_value
		if velocity_value is Vector3
		else Vector3.ZERO
	)
	var state := {
		"schema": Contract.MOTION_SCHEMA,
		"velocity": {
			"x": velocity.x,
			"y": velocity.y,
			"z": velocity.z,
		},
		"grounded": true,
		"facing_yaw": float(
			_earth_explorer.get_surface_relative_yaw()
		),
		"state_revision": _motion_updates,
	}
	var result: Dictionary = _host.apply_motion_state(state)
	if bool(result.get("success", false)):
		_motion_updates += 1
	else:
		_last_error_code = String(
			result.get("error_code", "CHAR1_MOTION_REJECTED")
		)
	return result

func refresh_projection() -> void:
	if (
		_earth_world == null
		or _earth_explorer == null
		or _host == null
	):
		return
	var canonical_position: Vector3 = (
		_earth_explorer.get_frame_position()
	)
	if canonical_position.length_squared() < 0.000001:
		return
	var anchor := Projector.create_surface_anchor(
		canonical_position,
		_visual_vertical_offset_m
	)
	transform = Projector.project_anchor(
		anchor,
		_earth_world.get_render_origin(),
		_earth_world.basis
	)
	_projection_updates += 1

func switch_avatar(character_id: String) -> Dictionary:
	if _host == null:
		return Contract.failure("CHAR1_AVATAR_HOST_NOT_READY")
	var result: Dictionary = _host.switch_avatar(character_id)
	if bool(result.get("success", false)):
		_refresh_definition_projection_options()
	else:
		_last_error_code = String(
			result.get("error_code", "CHAR1_AVATAR_SWAP_FAILED")
		)
	return result

func get_character_ids() -> Array[String]:
	if _host == null:
		return []
	var report: Dictionary = _host.create_report()
	var ids: Array[String] = []
	for value in report.get("catalog", {}).get("character_ids", []):
		ids.append(String(value))
	return ids

func get_active_character_id() -> String:
	return (
		_host.get_active_character_id()
		if _host != null
		else ""
	)

func set_first_person_mode(enabled: bool) -> void:
	_first_person_mode = enabled
	if _host != null:
		_host.set_first_person_mode(enabled)
		_host.visible = not enabled
	_refresh_definition_projection_options()
	refresh_projection()

static func resolve_visual_vertical_offset(
	definition: Dictionary,
	first_person_mode: bool
) -> float:
	if first_person_mode:
		return -float(definition.get("eye_height_m", 1.62))
	return float(definition.get("visual_vertical_offset_m", -0.85))

func _refresh_definition_projection_options() -> void:
	if _host == null:
		return
	var definition: Dictionary = _host.get_active_definition()
	_eye_height_m = float(definition.get("eye_height_m", 1.62))
	_visual_vertical_offset_m = resolve_visual_vertical_offset(
		definition,
		_first_person_mode
	)

func shutdown() -> void:
	if _host != null:
		_host.shutdown()

func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.earth_local_avatar_presenter.v1",
		"active_character_id": get_active_character_id(),
		"first_person_mode": _first_person_mode,
		"local_body_visible": _host.visible if _host != null else false,
		"eye_height_m": _eye_height_m,
		"visual_vertical_offset_m": _visual_vertical_offset_m,
		"projection_updates": _projection_updates,
		"motion_updates": _motion_updates,
		"network_motion_updates": _network_motion_updates,
		"network_record_seen": _network_record_seen,
		"last_error_code": _last_error_code,
		"host": _host.create_report() if _host != null else {},
	}
