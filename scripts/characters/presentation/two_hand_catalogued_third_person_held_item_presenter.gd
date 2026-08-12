class_name TwoHandCataloguedThirdPersonHeldItemPresenter
extends "res://scripts/characters/presentation/catalogued_third_person_held_item_presenter.gd"

const SecondarySupportType = preload("res://scripts/characters/presentation/third_person_secondary_hand_support.gd")
const SecondaryTransformFactoryType = preload("res://scripts/characters/presentation/held_item_visual_factory.gd")

var secondary_hand_support
var _secondary_grip_target: Node3D
var _secondary_target_builds := 0
var _secondary_target_clears := 0


func setup(
	p_world_presentation: Node,
	p_source_skeleton: Skeleton3D = null,
	p_world_layer_index: int = DEFAULT_WORLD_LAYER_INDEX
) -> Dictionary:
	var result: Dictionary = super.setup(p_world_presentation, p_source_skeleton, p_world_layer_index)
	if not bool(result.get("success", false)):
		return result
	secondary_hand_support = SecondarySupportType.new()
	secondary_hand_support.name = "FpeR2S5ThirdPersonSecondaryHandSupport"
	add_child(secondary_hand_support)
	var support_setup: Dictionary = secondary_hand_support.setup(
		p_world_presentation,
		source_skeleton,
		p_world_layer_index
	)
	if not bool(support_setup.get("success", false)):
		return support_setup
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["secondary_hand_support"] = support_setup.get("details", {}).duplicate(true)
	result["details"] = details
	return result


func present_catalogued_item(
	item_id: String,
	display_name: String,
	item_color: Color,
	visual_descriptor: Dictionary,
	grip_profile: Dictionary
) -> Dictionary:
	_clear_secondary_support("PRIMARY_ITEM_REPLACED")
	var result: Dictionary = super.present_catalogued_item(
		item_id,
		display_name,
		item_color,
		visual_descriptor,
		grip_profile
	)
	if not bool(result.get("success", false)):
		return result
	if String(item_id).strip_edges().is_empty():
		return result

	var two_hand: Dictionary = Dictionary(grip_profile.get("two_hand", {})).duplicate(true)
	if not bool(two_hand.get("required", false)):
		var one_details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
		one_details["secondary_world_hand_required"] = false
		one_details["secondary_world_hand_active"] = false
		result["details"] = one_details
		return result
	if _grip_root == null or secondary_hand_support == null:
		return _failure("FPE_S5_THIRD_PERSON_SUPPORT_UNAVAILABLE")

	_secondary_grip_target = Node3D.new()
	_secondary_grip_target.name = "FpeR2S5ThirdPersonSecondaryGripTarget"
	_grip_root.add_child(_secondary_grip_target)
	var target_descriptor: Dictionary = Dictionary(
		two_hand.get("third_person_secondary_anchor", two_hand.get("secondary_anchor", {}))
	).duplicate(true)
	SecondaryTransformFactoryType.new().apply_local_transform(_secondary_grip_target, target_descriptor)
	_secondary_target_builds += 1

	var support_result: Dictionary = secondary_hand_support.activate(
		_secondary_grip_target,
		item_id,
		grip_profile
	)
	if not bool(support_result.get("success", false)):
		_clear_secondary_support("ACTIVATION_FAILED")
		return support_result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	details["secondary_world_hand_required"] = true
	details["secondary_world_hand_active"] = true
	details["secondary_world_hand_mode"] = String(support_result.get("details", {}).get("mode", ""))
	details["secondary_target_present"] = true
	result["details"] = details
	return result


func clear_item() -> Dictionary:
	_clear_secondary_support("ITEM_CLEARED")
	return super.clear_item()


func get_secondary_hand_report() -> Dictionary:
	return secondary_hand_support.create_report() if secondary_hand_support != null else {
		"schema": "planet_simulator.fpe_r2_s5_third_person_secondary_hand.v1",
		"configured": false,
		"active": false,
		"mode": "UNAVAILABLE",
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["secondary_hand"] = get_secondary_hand_report()
	report["secondary_target_present"] = _secondary_grip_target != null and is_instance_valid(_secondary_grip_target)
	report["secondary_target_builds"] = _secondary_target_builds
	report["secondary_target_clears"] = _secondary_target_clears
	return report


func _clear_secondary_support(reason: String) -> void:
	if secondary_hand_support != null:
		secondary_hand_support.deactivate(reason)
	if _secondary_grip_target != null and is_instance_valid(_secondary_grip_target):
		_secondary_grip_target.queue_free()
		_secondary_target_clears += 1
	_secondary_grip_target = null


func _exit_tree() -> void:
	_clear_secondary_support("PRESENTER_EXIT")
	super._exit_tree()
