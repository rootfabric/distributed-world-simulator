class_name QuaterniusFirstPersonEmbodimentLab
extends "res://scripts/characters/lab/quaternius_playable_network_equipment_lab.gd"

const FirstPersonEmbodimentType = preload("res://scripts/characters/presentation/first_person_embodiment.gd")
const GrabAuthorityBridgeType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")

var first_person_embodiment
var grab_authority_bridge
var fpe_setup_result: Dictionary = {}
var _last_hotbar_item_id := ""
var _last_equipment_fingerprint := ""
var _last_upper_clothing_enabled := false
var _last_fpe_status_code := ""
var _sandbox_targets: Array[RigidBody3D] = []


func _ready() -> void:
	super._ready()
	_setup_first_person_embodiment()
	_spawn_local_grab_sandbox()
	set_first_person_mode(true)
	_refresh_status()


func _process(_delta: float) -> void:
	if first_person_embodiment == null or character_gameplay_controller == null:
		return
	_sync_authoritative_hotbar_presentation()
	_sync_equipment_viewmodel()


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if character_gameplay_controller == null or character_gameplay_controller.inventory_open:
		return
	var hotbar_index := _hotbar_index_for_key(event.physical_keycode)
	if hotbar_index < 0:
		return
	var result: Dictionary = character_gameplay_controller.select_hotbar(hotbar_index)
	_last_fpe_status_code = String(result.get("error_code", result.get("code", "OK")))
	_refresh_status()
	get_viewport().set_input_as_handled()


func _setup_first_person_embodiment() -> void:
	grab_authority_bridge = GrabAuthorityBridgeType.new()
	# CH9.6 has canonical network item/equipment authority but no accepted
	# hand.grab world-physics command. Canonical targets therefore fail closed;
	# local sandbox bodies remain available for testing hand UX.
	grab_authority_bridge.setup(Callable(), true)

	var source_skeleton: Skeleton3D = null
	if layered_rig_adapter != null and layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value = layered_rig_adapter.call("resolve_pose_skeleton", avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	first_person_embodiment = FirstPersonEmbodimentType.new()
	first_person_embodiment.name = "FirstPersonEmbodiment"
	player.add_child(first_person_embodiment)
	fpe_setup_result = first_person_embodiment.setup(
		player,
		avatar,
		first_person_adapter,
		presentation_profile,
		first_person_camera,
		third_person_camera,
		grab_authority_bridge,
		source_skeleton
	)
	if not bool(fpe_setup_result.get("success", false)):
		push_error("FPE prototype setup failed: %s" % JSON.stringify(fpe_setup_result))
		return
	# The first-person ray starts at the camera inside the player capsule. Keep
	# self-collision out explicitly instead of relying on hit-from-inside details.
	if first_person_embodiment.interaction_raycast != null:
		first_person_embodiment.interaction_raycast.add_exception(player)
	first_person_embodiment.interaction_result_changed.connect(_on_fpe_interaction_result_changed)
	first_person_embodiment.grab_state_changed.connect(_on_fpe_grab_state_changed)


func _sync_authoritative_hotbar_presentation() -> void:
	if not network_ready:
		return
	var selected_item_id := character_gameplay_controller.get_selected_hotbar_item_id()
	if selected_item_id == _last_hotbar_item_id:
		return
	_last_hotbar_item_id = selected_item_id
	if selected_item_id.is_empty():
		first_person_embodiment.clear_authoritative_hand_item("right")
		_refresh_status()
		return
	var item = character_gameplay_controller.get_item(selected_item_id)
	if item == null:
		first_person_embodiment.clear_authoritative_hand_item("right")
		return
	var definition = character_gameplay_controller.get_definition(String(item.definition_id))
	var display_name := String(item.definition_id)
	var item_color := Color(0.65, 0.68, 0.72, 1.0)
	if definition != null:
		display_name = String(definition.display_name)
		item_color = _metadata_color(definition.metadata, item_color)
	first_person_embodiment.set_authoritative_hand_item(
		"right",
		selected_item_id,
		display_name,
		item_color
	)
	_refresh_status()


func _sync_equipment_viewmodel() -> void:
	if item_graph_equipment_source == null:
		return
	var snapshot = item_graph_equipment_source.get_snapshot()
	if snapshot == null:
		return
	var fingerprint := snapshot.fingerprint()
	if fingerprint == _last_equipment_fingerprint:
		return
	_last_equipment_fingerprint = fingerprint

	var upper_enabled := false
	var sleeve_color := Color(0.46, 0.25, 0.18, 1.0)
	for raw_entry in snapshot.entries():
		if raw_entry == null or String(raw_entry.profile_id) != UPPER_PROFILE_ID:
			continue
		upper_enabled = true
		var item = character_gameplay_controller.get_item(String(raw_entry.item_id))
		if item != null:
			var definition = character_gameplay_controller.get_definition(String(item.definition_id))
			if definition != null:
				sleeve_color = _metadata_color(definition.metadata, sleeve_color)
		break
	_last_upper_clothing_enabled = upper_enabled
	var clothing_result: Dictionary = first_person_embodiment.set_upper_clothing_enabled(
		upper_enabled,
		sleeve_color
	)
	if not bool(clothing_result.get("success", false)):
		_last_fpe_status_code = String(clothing_result.get("error_code", "FPE_CLOTHING_SYNC_FAILED"))
	_refresh_status()


func _spawn_local_grab_sandbox() -> void:
	for index in range(3):
		var body := RigidBody3D.new()
		body.name = "FPELocalGrabTarget%d" % (index + 1)
		body.position = Vector3((float(index) - 1.0) * 0.62, 1.50, -2.15)
		body.gravity_scale = 0.0
		body.linear_damp = 3.0
		body.angular_damp = 4.0
		# Sandbox targets remain ray-queryable on layer 1 but do not produce
		# physical contacts with the gameplay capsule while carried.
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("fpe_local_sandbox_grabbable", true)
		body.set_meta("fpe_demo_target", true)
		add_child(body)

		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.32, 0.32, 0.32)
		collision.shape = shape
		body.add_child(collision)

		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.32, 0.32, 0.32)
		visual.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = [
			Color(0.35, 0.62, 0.86, 1.0),
			Color(0.82, 0.55, 0.25, 1.0),
			Color(0.42, 0.72, 0.42, 1.0),
		][index]
		material.roughness = 0.75
		visual.material_override = material
		body.add_child(visual)
		_sandbox_targets.append(body)


func _metadata_color(metadata_value, fallback: Color) -> Color:
	if not metadata_value is Dictionary:
		return fallback
	var raw_color = Dictionary(metadata_value).get("icon_color")
	if raw_color is Color:
		return raw_color as Color
	if raw_color is Array and raw_color.size() >= 3:
		return Color(
			float(raw_color[0]),
			float(raw_color[1]),
			float(raw_color[2]),
			float(raw_color[3]) if raw_color.size() >= 4 else 1.0
		)
	return fallback


func _hotbar_index_for_key(keycode: Key) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
		KEY_7:
			return 6
		KEY_8:
			return 7
		KEY_9:
			return 8
		KEY_0:
			return 9
	return -1


func _on_fpe_interaction_result_changed(result: Dictionary) -> void:
	_last_fpe_status_code = String(result.get("error_code", "OK"))
	_refresh_status()


func _on_fpe_grab_state_changed(_hand_id: String, _occupied: bool, _target_path: String) -> void:
	_refresh_status()


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	return {
		"schema": "planet_simulator.quaternius_first_person_embodiment_lab.v1",
		"setup": fpe_setup_result.duplicate(true),
		"network_ready": network_ready,
		"selected_hotbar_item_id": _last_hotbar_item_id,
		"equipment_fingerprint": _last_equipment_fingerprint,
		"upper_clothing_enabled": _last_upper_clothing_enabled,
		"embodiment": first_person_embodiment.create_report() if first_person_embodiment != null else {},
		"grab_authority": grab_authority_bridge.create_report() if grab_authority_bridge != null else {},
		"sandbox_target_count": _sandbox_targets.size(),
		"canonical_world_grab_contract": "PENDING_SEPARATE_AUTHORITY_FRONTIER",
	}


func _refresh_status() -> void:
	super._refresh_status()
	if status_label == null:
		return
	var embodiment_report: Dictionary = first_person_embodiment.create_report() if first_person_embodiment != null else {}
	var grab_report: Dictionary = grab_authority_bridge.create_report() if grab_authority_bridge != null else {}
	var sleeve_mode := "REAL_QUATERNIUS" if bool(embodiment_report.get("real_quaternius_sleeves_ready", false)) else "PROCEDURAL" if _last_upper_clothing_enabled else "OFF"
	status_label.text += (
		"\n\nFPE research prototype — FirstPersonEmbodiment"
		+ "\nC — 1/3 лицо | Q — левая рука | E — правая рука | 1..0 — network hotbar"
		+ "\nAim at floating cubes: Q/E grabs locally; press the same key again to release"
		+ "\nviewmodel: %s | sleeves: %s | selected item: %s"
		+ "\nworld grab authority: %s | local sandbox: %s | last: %s"
	) % [
		String(embodiment_report.get("view_policy", "PENDING")),
		sleeve_mode,
		_last_hotbar_item_id if not _last_hotbar_item_id.is_empty() else "EMPTY",
		"READY" if bool(grab_report.get("canonical_grab_authority_ready", false)) else "FAIL_CLOSED_PENDING_CONTRACT",
		"ON" if bool(grab_report.get("local_sandbox_enabled", false)) else "OFF",
		_last_fpe_status_code if not _last_fpe_status_code.is_empty() else "OK",
	]
