class_name PosedCataloguedFirstPersonEmbodiment
extends "res://scripts/characters/presentation/catalogued_first_person_embodiment.gd"

const HandRigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const HandPoseCatalogType = preload("res://scripts/characters/presentation/first_person_hand_pose_catalog.gd")

var hand_pose_catalog = HandPoseCatalogType.new()
var _hand_rig_by_hand: Dictionary = {}
var _pose_apply_count := 0
var _last_pose_by_hand: Dictionary = {}


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

	var viewmodel_layer := 19
	if p_presentation_profile != null:
		viewmodel_layer = int(p_presentation_profile.viewmodel_render_layer_index)
	var left_result := _install_hand_rig(HAND_LEFT, left_hand_root, viewmodel_layer)
	if not bool(left_result.get("success", false)):
		return left_result
	var right_result := _install_hand_rig(HAND_RIGHT, right_hand_root, viewmodel_layer)
	if not bool(right_result.get("success", false)):
		return right_result
	_refresh_adapter_visuals()

	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["articulated_hands"] = true
	details["hand_pose_catalog"] = hand_pose_catalog.create_report()
	details["hand_visual_provider_boundary"] = true
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
	var result: Dictionary = super.set_catalogued_hand_item(
		hand_id,
		item_id,
		display_name,
		item_color,
		visual_descriptor,
		grip_profile
	)
	if not bool(result.get("success", false)):
		return result
	var normalized_item_id := item_id.strip_edges()
	if normalized_item_id.is_empty():
		_apply_open_pose(hand_id)
		return result

	var pose: Dictionary = hand_pose_catalog.resolve(grip_profile, visual_descriptor)
	var pose_result: Dictionary = _apply_pose(hand_id, pose)
	if not bool(pose_result.get("success", false)):
		return pose_result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["hand_pose_id"] = String(pose.get("pose_id", ""))
	details["articulated_hand"] = true
	result["details"] = details
	return result


func clear_authoritative_hand_item(hand_id: String) -> Dictionary:
	var result: Dictionary = super.clear_authoritative_hand_item(hand_id)
	if bool(result.get("success", false)):
		_apply_open_pose(hand_id)
	return result


func get_hand_pose_report() -> Dictionary:
	var rigs: Dictionary = {}
	for hand in [HAND_LEFT, HAND_RIGHT]:
		var rig_value: Variant = _hand_rig_by_hand.get(hand)
		if rig_value != null and is_instance_valid(rig_value) and rig_value.has_method("create_report"):
			rigs[hand] = rig_value.call("create_report")
	return {
		"schema": "planet_simulator.fpe_r2_s3_hand_pose_composition.v2",
		"rigs": rigs,
		"last_pose_by_hand": _last_pose_by_hand.duplicate(true),
		"pose_apply_count": _pose_apply_count,
		"pose_catalog": hand_pose_catalog.create_report(),
		"articulated_skeleton": true,
		"procedural_segment_visuals": true,
		"hand_visual_provider_boundary": true,
		"external_compatible_visual_provider_supported": true,
		"external_skinned_hand_mesh_required": false,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["hand_pose"] = get_hand_pose_report()
	return report


func _install_hand_rig(hand: String, hand_root: Node3D, viewmodel_layer: int) -> Dictionary:
	if hand_root == null:
		return _failure("FPE_S3_HAND_ROOT_REQUIRED", {"hand_id": hand})
	var rig = HandRigType.new()
	rig.name = "%sArticulatedHandRig" % hand.capitalize()
	hand_root.add_child(rig)
	var setup_result: Dictionary = rig.setup(hand, viewmodel_layer)
	if not bool(setup_result.get("success", false)):
		rig.queue_free()
		return setup_result

	# The old FPE palm was a single box. Keep the sleeve but replace that palm with
	# the provider-driven Skeleton3D hand. The default provider reproduces the S3
	# procedural segments; a compatible later provider may substitute authored
	# visuals without changing pose/grip/two-hand logic.
	var old_palm: Node = hand_root.get_node_or_null("%sPalm" % hand.capitalize())
	if old_palm is GeometryInstance3D:
		(old_palm as GeometryInstance3D).visible = false
	_hand_rig_by_hand[hand] = rig
	var open_result: Dictionary = rig.apply_pose(hand_pose_catalog.get_open_pose())
	if not bool(open_result.get("success", false)):
		return open_result
	_last_pose_by_hand[hand] = "open"
	return _success({"hand_id": hand, "rig": rig.create_report()})


func _apply_open_pose(hand_id: String) -> Dictionary:
	return _apply_pose(hand_id, hand_pose_catalog.get_open_pose())


func _apply_pose(hand_id: String, pose: Dictionary) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_S3_INVALID_HAND", {"hand_id": hand_id})
	var rig_value: Variant = _hand_rig_by_hand.get(hand)
	if rig_value == null or not is_instance_valid(rig_value):
		return _failure("FPE_S3_HAND_RIG_UNAVAILABLE", {"hand_id": hand})
	var pose_id := String(pose.get("pose_id", ""))
	if String(_last_pose_by_hand.get(hand, "")) == pose_id and String(rig_value.current_pose_id) == pose_id:
		return _success({"changed": false, "hand_id": hand, "pose_id": pose_id})
	var result: Dictionary = rig_value.apply_pose(pose)
	if bool(result.get("success", false)):
		_last_pose_by_hand[hand] = pose_id
		_pose_apply_count += 1
	return result
