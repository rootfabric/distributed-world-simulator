extends "res://scripts/app/earth_m3_remote_spectator_presenter.gd"

# CHAR2 local-only presentation adapter over the accepted NX5 interpolator.
# Server/player authority, snapshot clocks, position and owner-map are inherited.
# The only replacement is the rendered mesh (legacy capsule -> AvatarProvider).
const Bootstrap = preload("res://scripts/characters/runtime/production_avatar_bootstrap.gd")
const AvatarHost = preload("res://scripts/characters/avatar/player_avatar_host.gd")
const Contract = preload("res://scripts/characters/avatar/avatar_contract.gd")

var _avatar_host
var _avatar_setup_error := ""
var _avatar_motion_updates := 0
var _avatar_motion_failures := 0
var _avatar_character_id := "character/quaternius/regular"
var _remote_legacy_body: GeometryInstance3D


func set_visual_character_id(character_id: String) -> void:
	# Local-only display selection; never treat this as a canonical remote ID.
	_avatar_character_id = character_id.strip_edges().to_lower()


# R3C.2: visual model/animation instantiation belongs to the world-loading
# phase, not the synchronous JOIN_ACK / CONNECTED network callback. Call this
# on the Earth scene before transport admission; it creates NO network owner.
# The same presenter/rig can be rebound to a later transport snapshot.
func prewarm_visual(character_id: String = "") -> Dictionary:
	var requested := character_id.strip_edges().to_lower()
	if not requested.is_empty() and _avatar_host == null:
		_avatar_character_id = requested
	if _avatar_host != null:
		if not requested.is_empty() and requested != _avatar_character_id:
			return {"success": false, "error_code": "R3C2_AVATAR_PREWARM_IDENTITY_MISMATCH"}
		return {"success": true, "error_code": "", "details": {"reused": true}}
	var runtime: Dictionary = Bootstrap.create_runtime()
	if not bool(runtime.get("success", false)):
		_avatar_setup_error = String(runtime.get("error_code", "CHAR2_BOOTSTRAP_FAILED"))
		return runtime
	var details: Dictionary = runtime.get("details", {})
	_avatar_host = AvatarHost.new()
	_avatar_host.name = "RemoteAvatarHost"
	add_child(_avatar_host)
	var installed: Dictionary = _avatar_host.setup(
		details.get("catalog"),
		details.get("providers"),
		_avatar_character_id,
		false
	)
	if not bool(installed.get("success", false)):
		_avatar_setup_error = String(installed.get("error_code", "CHAR2_PROVIDER_FAILED"))
		_avatar_host.queue_free()
		_avatar_host = null
		return installed
	_avatar_host.set_first_person_mode(false)
	_avatar_setup_error = ""
	return {"success": true, "error_code": "", "details": {"reused": false}}


func setup(record: Dictionary, snapshot: Dictionary, map_position: Callable) -> Dictionary:
	# A retired visual is allowed to rebind to a genuinely new canonical
	# transport epoch. The old derived NX5 delegate is discarded; the costly
	# provider/Quaternius rig is retained and never becomes authoritative.
	if _delegate != null:
		_delegate.free()
		_delegate = null
	var inherited: Dictionary = super.setup(record, snapshot, map_position)
	if not bool(inherited.get("success", false)):
		return inherited
	var prepared: Dictionary = prewarm_visual(_avatar_character_id)
	if not bool(prepared.get("success", false)):
		return prepared
	var definition: Dictionary = _avatar_host.get_active_definition()
	_avatar_host.position = Vector3(
		0.0, -float(definition.get("eye_height_m", 1.62)), 0.0
	)
	_avatar_host.set_first_person_mode(false)
	_remote_legacy_body = _delegate.get_node_or_null("RemoteBody") as GeometryInstance3D
	if _remote_legacy_body != null:
		_remote_legacy_body.visible = false
	_apply_avatar_sample()
	return inherited

func _process(delta: float) -> void:
	# Preserve interpolation, Earth floating origin and render-frame projection.
	super._process(delta)
	_apply_avatar_sample()


func _apply_avatar_sample() -> void:
	if _avatar_host == null or _delegate == null:
		return
	var velocity: Vector3 = _delegate.target_velocity
	var record := {
		"schema": Contract.MOTION_SCHEMA,
		"velocity": {"x": velocity.x, "y": velocity.y, "z": velocity.z},
		"grounded": absf(velocity.y) < 0.35,
		"facing_yaw": _delegate.target_orientation_yaw,
		"state_revision": maxi(0, int(_delegate.replica_revision)),
	}
	var applied: Dictionary = _avatar_host.apply_motion_state(record)
	if bool(applied.get("success", false)):
		_avatar_motion_updates += 1
		_avatar_setup_error = ""
	else:
		_avatar_motion_failures += 1
		_avatar_setup_error = String(applied.get("error_code", "CHAR2_MOTION_REJECTED"))


func has_input_authority() -> bool:
	return false


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	var avatar: Dictionary = _avatar_host.create_report() if _avatar_host != null else {}
	var engine: Dictionary = Dictionary(avatar.get("presenter", {})).get("engine", {})
	report["char2_remote_avatar"] = {
		"ready": _avatar_host != null and _avatar_setup_error.is_empty(),
		"character_id": _avatar_host.get_active_character_id() if _avatar_host != null else "",
		"provider_id": String(avatar.get("presenter", {}).get("provider_id", "")),
		"asset_mode": String(engine.get("asset_mode", avatar.get("presenter", {}).get("asset_mode", ""))),
		"motion_updates": _avatar_motion_updates,
		"motion_failures": _avatar_motion_failures,
		"last_error_code": _avatar_setup_error,
		"legacy_capsule_visible": _remote_legacy_body.visible if _remote_legacy_body != null else false,
		"provider_state": avatar,
		"input_authority": false,
	}
	return report


func create_visual_observation(camera: Camera3D) -> Dictionary:
	if camera == null or _avatar_host == null or not is_inside_tree():
		return {"available": false}
	var viewport_rect := camera.get_viewport().get_visible_rect()
	var points: Dictionary = {}
	var all_in_frame := true
	# Anatomical anchors in the actual displayed host transform, not server XY.
	for anchor in {"feet": 0.0, "torso": 0.9, "head": 1.7}:
		var height := float({"feet": 0.0, "torso": 0.9, "head": 1.7}[anchor])
		var world_point: Vector3 = _avatar_host.to_global(Vector3(0.0, height, 0.0))
		var pixel := camera.unproject_position(world_point)
		var in_frame := not camera.is_position_behind(world_point) and viewport_rect.has_point(pixel)
		all_in_frame = all_in_frame and in_frame
		points[anchor] = {"pixel": [pixel.x, pixel.y], "in_frame": in_frame}
	return {
		"available": true,
		"visible_in_tree": _avatar_host.is_visible_in_tree(),
		"anchors_in_frame": all_in_frame,
		"anchors": points,
		"viewport_size": [viewport_rect.size.x, viewport_rect.size.y],
		"animation": _avatar_host.create_visual_observation(),
		"planar_presented": [_presented_planar_position.x, _presented_planar_position.y],
		"occlusion_tested": false,
	}


func _exit_tree() -> void:
	if _avatar_host != null and is_instance_valid(_avatar_host):
		_avatar_host.shutdown()
