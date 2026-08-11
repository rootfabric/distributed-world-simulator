class_name FirstPersonEmbodiment
extends Node

signal grab_state_changed(hand_id: String, occupied: bool, target_path: String)
signal interaction_result_changed(result: Dictionary)

const PresentationProfile = preload("res://scripts/characters/presentation/controllable_presentation_profile.gd")
const PresentationProxy = preload("res://scripts/characters/presentation/first_person_embodiment_presentation_proxy.gd")
const SelectiveGarmentFactory = preload("res://scripts/characters/equipment/selective_garment_scene_factory.gd")
const SkinnedGarmentPoseBridge = preload("res://scripts/characters/equipment/skinned_garment_pose_bridge.gd")

const HAND_LEFT := "left"
const HAND_RIGHT := "right"
const DEFAULT_INTERACTION_DISTANCE_M := 3.0
const MALE_PEASANT_PATH := "res://assets/external/quaternius/modular_outfits_fantasy/Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Peasant.gltf"
const PEASANT_ARMS_MESH_NAME := "Male_Peasant_Arms"

var player: CharacterBody3D
var world_presentation: Node
var first_person_camera: Camera3D
var third_person_camera: Camera3D
var first_person_adapter
var presentation_profile: Resource
var grab_authority_bridge

var presentation_proxy
var viewmodel_root: Node3D
var interaction_raycast: RayCast3D
var left_hand_root: Node3D
var right_hand_root: Node3D
var left_held_root: Node3D
var right_held_root: Node3D

var _procedural_sleeves: Array[MeshInstance3D] = []
var _hand_material: StandardMaterial3D
var _sleeve_material: StandardMaterial3D
var _quaternius_sleeve_bridge
var _source_skeleton: Skeleton3D
var _upper_clothing_enabled := false
var _real_sleeves_ready := false

var _sandbox_state_by_hand: Dictionary = {}
var _authoritative_item_id_by_hand: Dictionary = {HAND_LEFT: "", HAND_RIGHT: ""}
var _authoritative_proxy_by_hand: Dictionary = {}
var _look_sway_target := Vector2.ZERO
var _look_sway := Vector2.ZERO
var _motion_time := 0.0
var _last_interaction_result: Dictionary = {}
var _configured := false


func setup(
	p_player: CharacterBody3D,
	p_world_presentation: Node,
	p_first_person_adapter,
	p_presentation_profile: Resource,
	p_first_person_camera: Camera3D,
	p_third_person_camera: Camera3D = null,
	p_grab_authority_bridge = null,
	p_source_skeleton: Skeleton3D = null
) -> Dictionary:
	if p_player == null:
		return _failure("FPE_PLAYER_REQUIRED")
	if p_world_presentation == null:
		return _failure("FPE_WORLD_PRESENTATION_REQUIRED")
	if p_first_person_adapter == null:
		return _failure("FPE_VIEW_ADAPTER_REQUIRED")
	if p_presentation_profile == null:
		return _failure("FPE_PRESENTATION_PROFILE_REQUIRED")
	if p_first_person_camera == null:
		return _failure("FPE_FIRST_PERSON_CAMERA_REQUIRED")

	player = p_player
	world_presentation = p_world_presentation
	first_person_adapter = p_first_person_adapter
	presentation_profile = p_presentation_profile
	first_person_camera = p_first_person_camera
	third_person_camera = p_third_person_camera
	grab_authority_bridge = p_grab_authority_bridge
	_source_skeleton = p_source_skeleton

	_build_viewmodel()
	presentation_proxy = PresentationProxy.new()
	presentation_proxy.name = "FirstPersonEmbodimentPresentationProxy"
	add_child(presentation_proxy)
	var proxy_result: Dictionary = presentation_proxy.setup(world_presentation, viewmodel_root)
	if not bool(proxy_result.get("success", false)):
		return proxy_result

	# Reuse the accepted CH5/CH7 camera-layer adapter. Only presentation policy is
	# changed here: gameplay body, animation, equipment state and networking stay
	# on their existing owners.
	presentation_profile.first_person_policy = PresentationProfile.FirstPersonPolicy.VIEWMODEL
	if first_person_adapter.has_method("unbind_cameras"):
		first_person_adapter.call("unbind_cameras")
	if first_person_adapter.has_method("unbind_avatar"):
		first_person_adapter.call("unbind_avatar")
	var bind_avatar_value = first_person_adapter.call("bind_avatar", presentation_proxy, presentation_profile)
	if bind_avatar_value is Dictionary and not bool(Dictionary(bind_avatar_value).get("success", false)):
		return Dictionary(bind_avatar_value).duplicate(true)
	var bind_camera_value = first_person_adapter.call("bind_cameras", first_person_camera, third_person_camera)
	if bind_camera_value is Dictionary and not bool(Dictionary(bind_camera_value).get("success", false)):
		return Dictionary(bind_camera_value).duplicate(true)

	_configured = true
	return _success(create_report())


func set_source_skeleton(source_skeleton: Skeleton3D) -> Dictionary:
	_source_skeleton = source_skeleton
	if _upper_clothing_enabled:
		return _refresh_upper_clothing_viewmodel()
	return _success({"source_skeleton_bound": _source_skeleton != null})


func set_upper_clothing_enabled(enabled: bool, sleeve_color: Color = Color(0.46, 0.25, 0.18, 1.0)) -> Dictionary:
	_upper_clothing_enabled = enabled
	if _sleeve_material != null:
		_sleeve_material.albedo_color = sleeve_color
	return _refresh_upper_clothing_viewmodel()


func set_authoritative_hand_item(
	hand_id: String,
	item_id: String,
	display_name: String = "",
	item_color: Color = Color(0.65, 0.68, 0.72, 1.0)
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_INVALID_HAND", {"hand_id": hand_id})
	var normalized_item_id := item_id.strip_edges()
	if String(_authoritative_item_id_by_hand.get(hand, "")) == normalized_item_id:
		return _success({"changed": false, "hand_id": hand, "item_id": normalized_item_id})
	_clear_authoritative_proxy(hand)
	_authoritative_item_id_by_hand[hand] = normalized_item_id
	if normalized_item_id.is_empty():
		return _success({"changed": true, "hand_id": hand, "item_id": ""})

	var held_root := _held_root(hand)
	if held_root == null:
		return _failure("FPE_HAND_ROOT_UNAVAILABLE", {"hand_id": hand})
	var proxy := MeshInstance3D.new()
	proxy.name = "AuthoritativeItemProxy_%s" % hand.capitalize()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.13, 0.17, 0.30)
	proxy.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = item_color
	material.roughness = 0.72
	proxy.material_override = material
	proxy.position = Vector3(0.0, 0.0, -0.17)
	proxy.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	proxy.set_meta("canonical_item_id", normalized_item_id)
	proxy.set_meta("display_name", display_name)
	held_root.add_child(proxy)
	_authoritative_proxy_by_hand[hand] = proxy
	_update_hand_proxy_visibility(hand)
	_refresh_adapter_visuals()
	return _success({
		"changed": true,
		"hand_id": hand,
		"item_id": normalized_item_id,
		"display_name": display_name,
		"presentation_only": true,
	})


func clear_authoritative_hand_item(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_INVALID_HAND", {"hand_id": hand_id})
	_clear_authoritative_proxy(hand)
	_authoritative_item_id_by_hand[hand] = ""
	return _success({"hand_id": hand})


func is_hand_locally_occupied(hand_id: String) -> bool:
	var hand := _normalize_hand(hand_id)
	return not hand.is_empty() and _sandbox_state_by_hand.has(hand)


func get_last_interaction_result() -> Dictionary:
	return _last_interaction_result.duplicate(true)


func _process(delta: float) -> void:
	if not _configured or viewmodel_root == null:
		return
	_motion_time += delta
	_look_sway = _look_sway.lerp(_look_sway_target, clampf(delta * 18.0, 0.0, 1.0))
	_look_sway_target = _look_sway_target.lerp(Vector2.ZERO, clampf(delta * 10.0, 0.0, 1.0))
	var horizontal_speed := 0.0
	if player != null:
		horizontal_speed = Vector2(player.velocity.x, player.velocity.z).length()
	var movement_weight := clampf(horizontal_speed / 7.5, 0.0, 1.0)
	var bob := Vector3(
		sin(_motion_time * 9.0) * 0.008,
		absf(cos(_motion_time * 9.0)) * 0.007,
		0.0
	) * movement_weight
	var sway := Vector3(-_look_sway.x * 0.6, _look_sway.y * 0.45, 0.0)
	viewmodel_root.position = viewmodel_root.position.lerp(bob + sway, clampf(delta * 14.0, 0.0, 1.0))
	viewmodel_root.rotation.z = lerp_angle(viewmodel_root.rotation.z, _look_sway.x * 0.15, clampf(delta * 12.0, 0.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not _configured or not _is_first_person_active():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_sway_target = Vector2(
			clampf(event.relative.x * 0.0012, -0.035, 0.035),
			clampf(event.relative.y * 0.0012, -0.035, 0.035)
		)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var hand := ""
	if event.physical_keycode == KEY_Q:
		hand = HAND_LEFT
	elif event.physical_keycode == KEY_E:
		hand = HAND_RIGHT
	if hand.is_empty():
		return
	var result := release_hand(hand) if is_hand_locally_occupied(hand) else try_grab(hand)
	_store_interaction_result(result)
	get_viewport().set_input_as_handled()


func try_grab(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_INVALID_HAND", {"hand_id": hand_id})
	if interaction_raycast == null:
		return _failure("FPE_INTERACTION_RAY_UNAVAILABLE")
	interaction_raycast.force_raycast_update()
	if not interaction_raycast.is_colliding():
		return _failure("FPE_NO_GRAB_TARGET", {"hand_id": hand})
	var collider = interaction_raycast.get_collider()
	if not collider is Node:
		return _failure("FPE_GRAB_TARGET_NOT_NODE", {"hand_id": hand})
	if grab_authority_bridge == null or not grab_authority_bridge.has_method("request_grab"):
		return _failure("FPE_GRAB_AUTHORITY_BRIDGE_REQUIRED")
	var authority_value = grab_authority_bridge.call(
		"request_grab",
		hand,
		collider as Node,
		interaction_raycast.get_collision_point(),
		interaction_raycast.get_collision_normal()
	)
	if not authority_value is Dictionary:
		return _failure("FPE_INVALID_GRAB_AUTHORITY_RESULT")
	var authority_result: Dictionary = Dictionary(authority_value).duplicate(true)
	if not bool(authority_result.get("success", false)):
		return authority_result
	var details: Dictionary = Dictionary(authority_result.get("details", {}))
	if bool(details.get("local_sandbox", false)):
		return _attach_local_sandbox_target(hand, collider as Node)
	# Canonical objects are never moved here. Their visual state must follow the
	# authoritative completion / replica path supplied by the networking layer.
	return authority_result


func release_hand(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_INVALID_HAND", {"hand_id": hand_id})
	if _sandbox_state_by_hand.has(hand):
		return _release_local_sandbox_target(hand)
	var canonical_item_id := String(_authoritative_item_id_by_hand.get(hand, ""))
	if canonical_item_id.is_empty():
		return _success({"hand_id": hand, "changed": false})
	if grab_authority_bridge == null or not grab_authority_bridge.has_method("request_release"):
		return _failure("FPE_GRAB_AUTHORITY_BRIDGE_REQUIRED")
	var value = grab_authority_bridge.call("request_release", hand, canonical_item_id)
	return Dictionary(value).duplicate(true) if value is Dictionary else _failure("FPE_INVALID_RELEASE_AUTHORITY_RESULT")


func create_report() -> Dictionary:
	var adapter_report: Dictionary = {}
	if first_person_adapter != null and first_person_adapter.has_method("create_report"):
		var value = first_person_adapter.call("create_report")
		if value is Dictionary:
			adapter_report = Dictionary(value).duplicate(true)
	return {
		"schema": "planet_simulator.first_person_embodiment.v1",
		"configured": _configured,
		"viewmodel_root_present": viewmodel_root != null,
		"interaction_raycast_present": interaction_raycast != null,
		"left_hand_present": left_hand_root != null,
		"right_hand_present": right_hand_root != null,
		"left_local_grab": is_hand_locally_occupied(HAND_LEFT),
		"right_local_grab": is_hand_locally_occupied(HAND_RIGHT),
		"left_authoritative_item_id": String(_authoritative_item_id_by_hand.get(HAND_LEFT, "")),
		"right_authoritative_item_id": String(_authoritative_item_id_by_hand.get(HAND_RIGHT, "")),
		"upper_clothing_enabled": _upper_clothing_enabled,
		"real_quaternius_sleeves_ready": _real_sleeves_ready,
		"source_skeleton_bound": _source_skeleton != null,
		"view_policy": String(adapter_report.get("first_person_policy", "")),
		"world_hidden_from_first_person": bool(adapter_report.get("world_hidden_from_first_person", false)),
		"world_visible_to_third_person": bool(adapter_report.get("world_visible_to_third_person", false)),
		"shadow_proxy_active": bool(adapter_report.get("shadow_proxy_active", false)),
		"last_interaction_result": _last_interaction_result.duplicate(true),
		"moves_gameplay_body": false,
		"owns_network_state": false,
		"owns_item_state": false,
	}


func _build_viewmodel() -> void:
	viewmodel_root = Node3D.new()
	viewmodel_root.name = "FirstPersonViewmodelRoot"
	first_person_camera.add_child(viewmodel_root)

	_hand_material = StandardMaterial3D.new()
	_hand_material.albedo_color = Color(0.72, 0.54, 0.43, 1.0)
	_hand_material.roughness = 0.82
	_sleeve_material = StandardMaterial3D.new()
	_sleeve_material.albedo_color = Color(0.46, 0.25, 0.18, 1.0)
	_sleeve_material.roughness = 0.9

	var left := _build_hand(HAND_LEFT, -1.0)
	left_hand_root = left["root"]
	left_held_root = left["held_root"]
	var right := _build_hand(HAND_RIGHT, 1.0)
	right_hand_root = right["root"]
	right_held_root = right["held_root"]

	interaction_raycast = RayCast3D.new()
	interaction_raycast.name = "FirstPersonInteractionRay"
	interaction_raycast.target_position = Vector3(0.0, 0.0, -DEFAULT_INTERACTION_DISTANCE_M)
	interaction_raycast.collide_with_areas = true
	interaction_raycast.collide_with_bodies = true
	interaction_raycast.enabled = true
	first_person_camera.add_child(interaction_raycast)


func _build_hand(hand_id: String, side: float) -> Dictionary:
	var root := Node3D.new()
	root.name = "%sHandViewmodel" % hand_id.capitalize()
	root.position = Vector3(0.26 * side, -0.24, -0.48)
	root.rotation_degrees = Vector3(-8.0, -5.0 * side, 8.0 * side)
	viewmodel_root.add_child(root)

	var sleeve := MeshInstance3D.new()
	sleeve.name = "%sSleeve" % hand_id.capitalize()
	var sleeve_mesh := CapsuleMesh.new()
	sleeve_mesh.radius = 0.075
	sleeve_mesh.height = 0.42
	sleeve.mesh = sleeve_mesh
	sleeve.material_override = _sleeve_material
	sleeve.position = Vector3(0.0, 0.10, 0.06)
	sleeve.rotation_degrees.x = 68.0
	root.add_child(sleeve)
	_procedural_sleeves.append(sleeve)

	var palm := MeshInstance3D.new()
	palm.name = "%sPalm" % hand_id.capitalize()
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.11, 0.055, 0.16)
	palm.mesh = palm_mesh
	palm.material_override = _hand_material
	palm.position = Vector3(0.0, -0.08, -0.17)
	root.add_child(palm)

	var held_root := Node3D.new()
	held_root.name = "%sGrip" % hand_id.capitalize()
	held_root.position = Vector3(0.0, -0.075, -0.20)
	root.add_child(held_root)
	return {"root": root, "held_root": held_root}


func _refresh_upper_clothing_viewmodel() -> Dictionary:
	if not _upper_clothing_enabled:
		_clear_quaternius_sleeves()
		_set_procedural_sleeves_visible(false)
		_refresh_adapter_visuals()
		return _success({"upper_clothing_enabled": false, "real_sleeves_ready": false})

	if _source_skeleton != null:
		var real_result := _ensure_quaternius_sleeves()
		if bool(real_result.get("success", false)):
			_set_procedural_sleeves_visible(false)
			_refresh_adapter_visuals()
			return real_result
	_set_procedural_sleeves_visible(true)
	_refresh_adapter_visuals()
	return _success({
		"upper_clothing_enabled": true,
		"real_sleeves_ready": false,
		"fallback": "PROCEDURAL_SLEEVES",
	})


func _ensure_quaternius_sleeves() -> Dictionary:
	if _quaternius_sleeve_bridge != null and is_instance_valid(_quaternius_sleeve_bridge):
		_real_sleeves_ready = true
		return _success({"upper_clothing_enabled": true, "real_sleeves_ready": true, "reused": true})
	var source_value = load(MALE_PEASANT_PATH)
	if not source_value is PackedScene:
		return _failure("FPE_QUATERNIUS_PEASANT_SOURCE_UNAVAILABLE")
	var selected: Dictionary = SelectiveGarmentFactory.create(
		source_value as PackedScene,
		[PEASANT_ARMS_MESH_NAME]
	)
	if not bool(selected.get("success", false)):
		return selected
	var sleeves_scene = Dictionary(selected.get("details", {})).get("scene")
	if not sleeves_scene is PackedScene:
		return _failure("FPE_QUATERNIUS_SLEEVES_SCENE_INVALID")
	var bridge = SkinnedGarmentPoseBridge.new()
	bridge.name = "FirstPersonQuaterniusSleeves"
	viewmodel_root.add_child(bridge)
	var viewmodel_basis := Basis.from_euler(Vector3(0.0, PI, 0.0))
	var setup_result: Dictionary = bridge.setup(
		_source_skeleton,
		sleeves_scene as PackedScene,
		Transform3D(viewmodel_basis, Vector3(0.0, -1.48, 0.08))
	)
	if not bool(setup_result.get("success", false)):
		viewmodel_root.remove_child(bridge)
		bridge.queue_free()
		return setup_result
	_quaternius_sleeve_bridge = bridge
	_real_sleeves_ready = true
	return _success({
		"upper_clothing_enabled": true,
		"real_sleeves_ready": true,
		"selected_mesh": PEASANT_ARMS_MESH_NAME,
		"pose_bridge": bridge.create_report(),
	})


func _clear_quaternius_sleeves() -> void:
	if _quaternius_sleeve_bridge != null and is_instance_valid(_quaternius_sleeve_bridge):
		_quaternius_sleeve_bridge.clear()
		_quaternius_sleeve_bridge.queue_free()
	_quaternius_sleeve_bridge = null
	_real_sleeves_ready = false


func _set_procedural_sleeves_visible(visible: bool) -> void:
	for sleeve in _procedural_sleeves:
		if sleeve != null and is_instance_valid(sleeve):
			sleeve.visible = visible


func _attach_local_sandbox_target(hand: String, target: Node) -> Dictionary:
	if not target is RigidBody3D:
		return _failure("FPE_LOCAL_SANDBOX_TARGET_NOT_RIGID_BODY", {"hand_id": hand})
	for state_value in _sandbox_state_by_hand.values():
		if state_value is Dictionary and Dictionary(state_value).get("target") == target:
			return _failure("FPE_TARGET_ALREADY_HELD", {"hand_id": hand})
	var body := target as RigidBody3D
	var original_parent := body.get_parent()
	if original_parent == null:
		return _failure("FPE_GRAB_TARGET_PARENT_REQUIRED")
	var state := {
		"target": body,
		"original_parent": original_parent,
		"freeze": body.freeze,
		"gravity_scale": body.gravity_scale,
	}
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze = true
	body.reparent(_held_root(hand), true)
	body.position = Vector3(0.0, 0.0, -0.20)
	body.rotation = Vector3.ZERO
	_sandbox_state_by_hand[hand] = state
	_update_hand_proxy_visibility(hand)
	grab_state_changed.emit(hand, true, String(body.get_path()))
	return _success({
		"hand_id": hand,
		"local_sandbox": true,
		"target_path": String(body.get_path()),
		"presentation_only": true,
	})


func _release_local_sandbox_target(hand: String) -> Dictionary:
	if not _sandbox_state_by_hand.has(hand):
		return _success({"hand_id": hand, "changed": false})
	var state: Dictionary = Dictionary(_sandbox_state_by_hand[hand])
	var target = state.get("target")
	var original_parent = state.get("original_parent")
	_sandbox_state_by_hand.erase(hand)
	if target is RigidBody3D and is_instance_valid(target) and original_parent is Node and is_instance_valid(original_parent):
		var body := target as RigidBody3D
		var preserved_transform := body.global_transform
		body.reparent(original_parent as Node, true)
		body.global_transform = preserved_transform
		body.freeze = bool(state.get("freeze", false))
		body.gravity_scale = float(state.get("gravity_scale", 1.0))
	_update_hand_proxy_visibility(hand)
	grab_state_changed.emit(hand, false, "")
	return _success({"hand_id": hand, "local_sandbox": true, "released": true})


func _clear_authoritative_proxy(hand: String) -> void:
	var proxy = _authoritative_proxy_by_hand.get(hand)
	if proxy is Node and is_instance_valid(proxy):
		(proxy as Node).queue_free()
	_authoritative_proxy_by_hand.erase(hand)
	_refresh_adapter_visuals()


func _update_hand_proxy_visibility(hand: String) -> void:
	var proxy = _authoritative_proxy_by_hand.get(hand)
	if proxy is Node3D and is_instance_valid(proxy):
		(proxy as Node3D).visible = not is_hand_locally_occupied(hand)


func _refresh_adapter_visuals() -> void:
	if first_person_adapter != null and first_person_adapter.has_method("refresh_presentation_visuals"):
		first_person_adapter.call("refresh_presentation_visuals")


func _is_first_person_active() -> bool:
	if first_person_adapter == null or not first_person_adapter.has_method("create_report"):
		return false
	var value = first_person_adapter.call("create_report")
	return value is Dictionary and bool(Dictionary(value).get("first_person_enabled", false))


func _held_root(hand: String) -> Node3D:
	return left_held_root if hand == HAND_LEFT else right_held_root if hand == HAND_RIGHT else null


func _normalize_hand(hand_id: String) -> String:
	var hand := hand_id.strip_edges().to_lower()
	return hand if hand in [HAND_LEFT, HAND_RIGHT] else ""


func _store_interaction_result(result: Dictionary) -> void:
	_last_interaction_result = result.duplicate(true)
	interaction_result_changed.emit(_last_interaction_result.duplicate(true))


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
