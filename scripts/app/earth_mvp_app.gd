extends "res://scripts/app/earth_app.gd"

# V0 Earth is a playable tangent-plane projection over the canonical procedural
# planet. The server keeps authoritative M3 X/Z state; this adapter maps it to a
# deterministic land patch and consumes the already accepted NX4 prediction
# presentation instead of snapping the camera to 20 Hz authoritative updates.

const MVP_SURFACE_EYE_ALTITUDE_M := 1.75
const MVP_PREFERRED_BIOMES: Array[String] = ["grassland", "forest", "desert"]

var _mvp_surface_anchor_direction := Vector3.ZERO
var _mvp_surface_biome := "unknown"
var _mvp_prediction_enabled := false
var _mvp_prediction_signal_connected := false
var _mvp_authoritative_seed_applied := false
var _mvp_prediction_updates := 0
var _mvp_prediction_failures := 0
var _mvp_local_vertical_offset_m := 0.0


func attach_m3_multiplayer_client(runtime) -> Dictionary:
	_mvp_prediction_enabled = (
		runtime != null
		and runtime.has_method("advance_local_prediction")
		and runtime.has_signal("prediction_updated")
	)
	_mvp_authoritative_seed_applied = false
	_mvp_prediction_updates = 0
	_mvp_prediction_failures = 0
	_mvp_local_vertical_offset_m = 0.0
	_prepare_mvp_surface_anchor()

	var result: Dictionary = super.attach_m3_multiplayer_client(runtime)
	if not bool(result.get("success", false)):
		return result

	if _mvp_prediction_enabled:
		if not runtime.prediction_updated.is_connected(_on_mvp_prediction_updated):
			runtime.prediction_updated.connect(_on_mvp_prediction_updated)
		_mvp_prediction_signal_connected = true
	else:
		_mvp_prediction_signal_connected = false

	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["mode"] = "EARTH_NETWORK_PLAYABLE_MVP"
	details["prediction_enabled"] = _mvp_prediction_enabled
	details["surface_biome"] = _mvp_surface_biome
	details["surface_eye_altitude_m"] = MVP_SURFACE_EYE_ALTITUDE_M
	result["details"] = details
	return result


func _prepare_mvp_surface_anchor() -> void:
	if earth_world == null or earth_explorer == null:
		return
	_mvp_surface_anchor_direction = Vector3.ZERO
	_mvp_surface_biome = "unknown"
	for biome_name in MVP_PREFERRED_BIOMES:
		var candidate: Vector3 = earth_world.find_biome_direction(biome_name)
		if candidate.length_squared() < 0.5:
			continue
		var resolved_biome: String = earth_world.get_biome_name_at(candidate)
		if resolved_biome == "ocean":
			continue
		_mvp_surface_anchor_direction = candidate.normalized()
		_mvp_surface_biome = resolved_biome
		break
	if _mvp_surface_anchor_direction.length_squared() < 0.5:
		_mvp_surface_anchor_direction = earth_world.get_canonical_spawn_direction()
		_mvp_surface_biome = earth_world.get_biome_name_at(_mvp_surface_anchor_direction)

	# activate() prepares the high-detail local terrain around the chosen anchor.
	# Base attach immediately switches translation back to authoritative replica
	# mode while preserving local mouse-look.
	earth_explorer.activate(
		_mvp_surface_anchor_direction,
		MVP_SURFACE_EYE_ALTITUDE_M
	)


func _apply_m3_local_spectator_record(record: Dictionary) -> void:
	# The first authoritative state seeds the mapping. After prediction becomes
	# active, authoritative packets reconcile inside M3GraphicalClientRuntime and
	# arrive through prediction_updated; applying the raw packet here as well
	# would reintroduce visible snapshot snapping.
	if _mvp_prediction_enabled and _mvp_authoritative_seed_applied:
		return
	_apply_mvp_presentation_record(record)
	_mvp_authoritative_seed_applied = true


func _on_mvp_prediction_updated(
	_predicted_state: Dictionary,
	presentation_state: Dictionary,
	_report: Dictionary
) -> void:
	if not _m3_attached or presentation_state.is_empty():
		return
	_apply_mvp_presentation_record(presentation_state)
	_mvp_prediction_updates += 1


func _apply_mvp_presentation_record(record: Dictionary) -> void:
	if earth_world == null or earth_explorer == null:
		return
	var position_value = record.get("position", {})
	if not position_value is Dictionary:
		return
	var position: Dictionary = position_value
	var planar_x := float(position.get("x", 0.0))
	var planar_z := float(position.get("z", 0.0))
	var vertical_offset := maxf(float(position.get("y", 0.0)), 0.0)
	_m3_local_planar_position = Vector2(planar_x, planar_z)
	_mvp_local_vertical_offset_m = vertical_offset
	var mapped_direction: Vector3 = _map_m3_position_to_earth_direction(
		planar_x,
		planar_z
	)
	earth_explorer.apply_network_replica_pose(
		mapped_direction,
		MVP_SURFACE_EYE_ALTITUDE_M + vertical_offset
	)
	_sync_remote_presenter_origins()


func _sync_remote_presenter_origins() -> void:
	for logical_id_value in _m3_remote_presenters.keys():
		var presenter = _m3_remote_presenters.get(logical_id_value)
		if presenter == null or not is_instance_valid(presenter):
			continue
		presenter.set_local_planar_position(_m3_local_planar_position)
		if presenter.has_method("set_local_vertical_offset"):
			presenter.set_local_vertical_offset(_mvp_local_vertical_offset_m)


func _map_m3_position_to_earth_direction(x: float, z: float) -> Vector3:
	if earth_world == null:
		return Vector3.UP
	var up: Vector3 = (
		_mvp_surface_anchor_direction
		if _mvp_surface_anchor_direction.length_squared() >= 0.5
		else earth_world.get_canonical_spawn_direction()
	).normalized()
	var east: Vector3 = Vector3.UP.cross(up)
	if east.length_squared() < 0.000001:
		east = Vector3.RIGHT.cross(up)
	east = east.normalized()
	var north: Vector3 = up.cross(east).normalized()
	var surface: Vector3 = earth_world.get_surface_point(up)
	# M3 follows Godot's local convention: +X is right and -Z is forward.
	# Therefore north is mapped to -Z, matching the camera's local -Z heading.
	return (surface + east * x - north * z).normalized()


func _map_m3_position_to_earth_world(x: float, z: float) -> Vector3:
	var direction: Vector3 = _map_m3_position_to_earth_direction(x, z)
	return (
		earth_world.get_surface_point(direction)
		+ direction * MVP_SURFACE_EYE_ALTITUDE_M
	)


func _apply_m3_network_input(delta: float) -> void:
	if not _m3_attached or m3_multiplayer_client_runtime == null or not local_input_enabled:
		return
	if (
		m3_multiplayer_client_runtime.has_method("is_automated_acceptance")
		and m3_multiplayer_client_runtime.is_automated_acceptance()
	):
		return
	if not _mvp_prediction_enabled:
		super._apply_m3_network_input(delta)
		return

	var input_vector: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_forward",
		"move_back"
	)
	var intent := {
		"move_x": input_vector.x,
		"move_z": -input_vector.y,
		"look_yaw": earth_explorer.get_surface_relative_yaw(),
		"look_pitch": 0.0,
		"jump_pressed": Input.is_action_just_pressed("move_up"),
		"sprint": Input.is_action_pressed("boost"),
		"delta_seconds": maxf(delta, 0.000001),
	}
	var advanced: Dictionary = m3_multiplayer_client_runtime.advance_local_prediction(
		intent,
		delta
	)
	if not bool(advanced.get("success", false)):
		_mvp_prediction_failures += 1
		return

	# Real M3 emits prediction_updated. Keep the return-value path as a bounded
	# compatibility fallback for deterministic test doubles and future adapters.
	if not _mvp_prediction_signal_connected:
		var details: Dictionary = Dictionary(advanced.get("details", {}))
		var presentation_value = details.get("presentation_state", {})
		if presentation_value is Dictionary and not Dictionary(presentation_value).is_empty():
			_apply_mvp_presentation_record(Dictionary(presentation_value))
			_mvp_prediction_updates += 1


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["presentation_mode"] = (
		"NX4_PREDICTED_EARTH_SURFACE"
		if _mvp_prediction_enabled
		else "LEGACY_AUTHORITATIVE_EARTH_SURFACE"
	)
	report["prediction_enabled"] = _mvp_prediction_enabled
	report["prediction_updates"] = _mvp_prediction_updates
	report["prediction_failures"] = _mvp_prediction_failures
	report["playable_surface_biome"] = _mvp_surface_biome
	report["playable_surface_eye_altitude_m"] = MVP_SURFACE_EYE_ALTITUDE_M
	report["playable_surface_vertical_offset_m"] = _mvp_local_vertical_offset_m
	report["playable_surface_anchor_direction"] = [
		_mvp_surface_anchor_direction.x,
		_mvp_surface_anchor_direction.y,
		_mvp_surface_anchor_direction.z,
	]
	return report
