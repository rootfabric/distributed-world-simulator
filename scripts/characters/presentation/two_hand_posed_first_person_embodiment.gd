class_name TwoHandPosedFirstPersonEmbodiment
extends "res://scripts/characters/presentation/posed_catalogued_first_person_embodiment.gd"

var _left_default_parent: Node
var _left_default_transform := Transform3D.IDENTITY
var _left_default_captured := false
var _secondary_anchor: Node3D
var _two_hand_active := false
var _two_hand_item_id := ""
var _two_hand_profile_id := ""
var _secondary_pose_id := ""
var _secondary_activation_count := 0
var _secondary_release_count := 0
var _secondary_block_count := 0
var _last_secondary_result: Dictionary = {}


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
	var result: Dictionary = super.setup(
		p_player,
		p_world_presentation,
		p_first_person_adapter,
		p_presentation_profile,
		p_first_person_camera,
		p_third_person_camera,
		p_grab_authority_bridge,
		p_source_skeleton
	)
	if not bool(result.get("success", false)):
		return result
	_capture_left_default()
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["two_hand_support"] = true
	result["details"] = details
	return result


func set_catalogued_hand_item(
	hand_id: String,
	item_id: String,
	display_name: String,
	item_color: Color,
	visual_descriptor: Dictionary,
	grip_profile: Dictionary
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_INVALID_HAND", {"hand_id": hand_id})

	# A secondary hand is parented under the current right-hand proxy. Restore it
	# before the inherited catalog replaces/frees that proxy, otherwise deleting
	# one item presentation could accidentally delete the left hand hierarchy.
	if hand == HAND_RIGHT and _two_hand_active:
		_release_secondary_support("PRIMARY_ITEM_REPLACED")

	var result: Dictionary = super.set_catalogued_hand_item(
		hand,
		item_id,
		display_name,
		item_color,
		visual_descriptor,
		grip_profile
	)
	if not bool(result.get("success", false)):
		return result
	if hand != HAND_RIGHT or item_id.strip_edges().is_empty():
		return result

	var two_hand: Dictionary = Dictionary(grip_profile.get("two_hand", {})).duplicate(true)
	var secondary_result := _apply_secondary_contract(item_id, grip_profile, two_hand)
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["two_hand_required"] = bool(two_hand.get("required", false))
	details["secondary_hand_active"] = bool(secondary_result.get("details", {}).get("active", false))
	details["secondary_result"] = secondary_result.duplicate(true)
	result["details"] = details
	return result


func clear_authoritative_hand_item(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand == HAND_RIGHT and _two_hand_active:
		_release_secondary_support("PRIMARY_ITEM_CLEARED")
	return super.clear_authoritative_hand_item(hand_id)


func try_grab(hand_id: String) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand == HAND_LEFT and _two_hand_active:
		_secondary_block_count += 1
		_last_secondary_result = _failure("FPE_S4_SECONDARY_HAND_RESERVED", {
			"item_id": _two_hand_item_id,
			"profile_id": _two_hand_profile_id,
		})
		return _last_secondary_result.duplicate(true)
	return super.try_grab(hand_id)


func get_two_hand_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_r2_s4_two_hand_presentation.v1",
		"active": _two_hand_active,
		"item_id": _two_hand_item_id,
		"profile_id": _two_hand_profile_id,
		"secondary_hand": HAND_LEFT,
		"secondary_pose_id": _secondary_pose_id,
		"secondary_anchor_present": _secondary_anchor != null and is_instance_valid(_secondary_anchor),
		"left_default_captured": _left_default_captured,
		"activations": _secondary_activation_count,
		"releases": _secondary_release_count,
		"blocked": _secondary_block_count,
		"last_result": _last_secondary_result.duplicate(true),
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["two_hand"] = get_two_hand_report()
	return report


func _apply_secondary_contract(item_id: String, grip_profile: Dictionary, two_hand: Dictionary) -> Dictionary:
	if not bool(two_hand.get("required", false)):
		_last_secondary_result = _success({
			"active": false,
			"required": false,
			"item_id": item_id,
		})
		return _last_secondary_result.duplicate(true)
	if String(two_hand.get("primary_hand", HAND_RIGHT)) != HAND_RIGHT:
		return _failure("FPE_S4_PRIMARY_HAND_UNSUPPORTED")
	if String(two_hand.get("secondary_hand", HAND_LEFT)) != HAND_LEFT:
		return _failure("FPE_S4_SECONDARY_HAND_UNSUPPORTED")
	if is_hand_locally_occupied(HAND_LEFT) or not String(_authoritative_item_id_by_hand.get(HAND_LEFT, "")).is_empty():
		_secondary_block_count += 1
		_last_secondary_result = _success({
			"active": false,
			"required": true,
			"blocked": true,
			"reason": "LEFT_HAND_OCCUPIED",
			"item_id": item_id,
		})
		return _last_secondary_result.duplicate(true)

	_capture_left_default()
	if not _left_default_captured or left_hand_root == null:
		return _failure("FPE_S4_LEFT_HAND_DEFAULT_UNAVAILABLE")
	var proxy_value: Variant = _authoritative_proxy_by_hand.get(HAND_RIGHT)
	if not proxy_value is Node3D or not is_instance_valid(proxy_value):
		return _failure("FPE_S4_PRIMARY_PROXY_REQUIRED")
	var proxy := proxy_value as Node3D

	_secondary_anchor = Node3D.new()
	_secondary_anchor.name = "FpeR2S4SecondaryGripAnchor"
	proxy.add_child(_secondary_anchor)
	_apply_transform_descriptor(_secondary_anchor, Dictionary(two_hand.get("secondary_anchor", {})))

	left_hand_root.reparent(_secondary_anchor, false)
	left_hand_root.transform = Transform3D.IDENTITY
	_apply_transform_descriptor(left_hand_root, Dictionary(two_hand.get("secondary_hand_transform", {})))

	_secondary_pose_id = String(two_hand.get("secondary_pose_id", "support_wrap")).strip_edges()
	if _secondary_pose_id.is_empty():
		_secondary_pose_id = "support_wrap"
	var pose_result: Dictionary = _apply_pose(HAND_LEFT, hand_pose_catalog.get_pose(_secondary_pose_id))
	if not bool(pose_result.get("success", false)):
		_restore_left_default()
		return pose_result

	_two_hand_active = true
	_two_hand_item_id = item_id
	_two_hand_profile_id = String(grip_profile.get("profile_id", ""))
	_secondary_activation_count += 1
	_last_secondary_result = _success({
		"active": true,
		"required": true,
		"item_id": item_id,
		"profile_id": _two_hand_profile_id,
		"secondary_hand": HAND_LEFT,
		"secondary_pose_id": _secondary_pose_id,
		"presentation_only": true,
	})
	return _last_secondary_result.duplicate(true)


func _release_secondary_support(reason: String) -> Dictionary:
	if not _two_hand_active and _secondary_anchor == null:
		return _success({"changed": false, "active": false, "reason": reason})
	_restore_left_default()
	_two_hand_active = false
	_two_hand_item_id = ""
	_two_hand_profile_id = ""
	_secondary_pose_id = ""
	_secondary_release_count += 1
	var pose_result: Dictionary = _apply_open_pose(HAND_LEFT)
	_last_secondary_result = _success({
		"changed": true,
		"active": false,
		"reason": reason,
		"open_pose_success": bool(pose_result.get("success", false)),
	})
	return _last_secondary_result.duplicate(true)


func _capture_left_default() -> void:
	if _left_default_captured or left_hand_root == null:
		return
	_left_default_parent = left_hand_root.get_parent()
	if _left_default_parent == null:
		return
	_left_default_transform = left_hand_root.transform
	_left_default_captured = true


func _restore_left_default() -> void:
	if left_hand_root != null and is_instance_valid(left_hand_root) and _left_default_parent != null and is_instance_valid(_left_default_parent):
		if left_hand_root.get_parent() != _left_default_parent:
			left_hand_root.reparent(_left_default_parent, false)
		left_hand_root.transform = _left_default_transform
	if _secondary_anchor != null and is_instance_valid(_secondary_anchor):
		_secondary_anchor.queue_free()
	_secondary_anchor = null


func _apply_transform_descriptor(target: Node3D, descriptor: Dictionary) -> void:
	if target == null:
		return
	target.position = _descriptor_vector3(descriptor.get("position"), target.position)
	target.rotation_degrees = _descriptor_vector3(descriptor.get("rotation_deg"), target.rotation_degrees)
	target.scale = _descriptor_vector3(descriptor.get("scale"), target.scale)


func _descriptor_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array:
		var components: Array = value
		if components.size() >= 3:
			return Vector3(float(components[0]), float(components[1]), float(components[2]))
	return fallback
