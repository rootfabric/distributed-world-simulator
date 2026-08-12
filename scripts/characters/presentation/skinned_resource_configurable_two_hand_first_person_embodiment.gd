class_name SkinnedResourceConfigurableTwoHandFirstPersonEmbodiment
extends "res://scripts/characters/presentation/resource_configurable_two_hand_first_person_embodiment.gd"

const S8SubstitutableRigType = preload("res://scripts/characters/presentation/substitutable_first_person_hand_rig.gd")
const SkinnedProviderType = preload("res://scripts/characters/presentation/skinned_first_person_hand_visual_provider.gd")

var _skinned_hand_visual_resource_by_hand: Dictionary = {}


func configure_skinned_hand_visual_resource(
	hand_id: String,
	packed_scene: PackedScene,
	resource_path: String = ""
) -> Dictionary:
	var hand := _normalize_hand(hand_id)
	if hand.is_empty():
		return _failure("FPE_S8_INVALID_HAND", {"hand_id": hand_id})
	if packed_scene == null:
		return _failure("FPE_S8_SKINNED_HAND_SCENE_REQUIRED", {"hand_id": hand})
	_skinned_hand_visual_resource_by_hand[hand] = {
		"scene": packed_scene,
		"resource_path": resource_path.strip_edges(),
	}
	return _success({
		"hand_id": hand,
		"resource_path": resource_path.strip_edges(),
		"configured": true,
	})


func get_skinned_hand_visual_report() -> Dictionary:
	var configured: Dictionary = {}
	for hand in [HAND_LEFT, HAND_RIGHT]:
		var entry: Dictionary = Dictionary(_skinned_hand_visual_resource_by_hand.get(hand, {}))
		configured[hand] = {
			"configured": not entry.is_empty(),
			"resource_path": String(entry.get("resource_path", "")),
		}
	return {
		"schema": "planet_simulator.fpe_r2_s8_skinned_hand_visual_config.v1",
		"configured": configured,
		"skinned_resource_supported": true,
		"fallback_to_s7_or_procedural_when_unconfigured": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func _install_hand_rig(hand: String, hand_root: Node3D, viewmodel_layer: int) -> Dictionary:
	var config: Dictionary = Dictionary(_skinned_hand_visual_resource_by_hand.get(hand, {}))
	if config.is_empty():
		return super._install_hand_rig(hand, hand_root, viewmodel_layer)
	if hand_root == null:
		return _failure("FPE_S3_HAND_ROOT_REQUIRED", {"hand_id": hand})

	var scene_value: Variant = config.get("scene")
	if not scene_value is PackedScene:
		return _failure("FPE_S8_SKINNED_HAND_SCENE_INVALID", {"hand_id": hand})
	var provider = SkinnedProviderType.new()
	var provider_setup: Dictionary = provider.setup(
		scene_value as PackedScene,
		String(config.get("resource_path", ""))
	)
	if not bool(provider_setup.get("success", false)):
		return provider_setup

	var rig = S8SubstitutableRigType.new()
	rig.name = "%sArticulatedHandRig" % hand.capitalize()
	hand_root.add_child(rig)
	var setup_result: Dictionary = rig.setup(hand, viewmodel_layer, provider)
	if not bool(setup_result.get("success", false)):
		rig.queue_free()
		return setup_result

	var old_palm: Node = hand_root.get_node_or_null("%sPalm" % hand.capitalize())
	if old_palm is GeometryInstance3D:
		(old_palm as GeometryInstance3D).visible = false
	_hand_rig_by_hand[hand] = rig
	var open_result: Dictionary = rig.apply_pose(hand_pose_catalog.get_open_pose())
	if not bool(open_result.get("success", false)):
		return open_result
	_last_pose_by_hand[hand] = "open"
	return _success({
		"hand_id": hand,
		"rig": rig.create_report(),
		"skinned_resource_backed": true,
	})


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["skinned_hand_visual"] = get_skinned_hand_visual_report()
	return report
