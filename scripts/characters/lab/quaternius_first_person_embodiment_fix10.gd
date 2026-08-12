class_name QuaterniusFirstPersonEmbodimentFix10
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_fix9.gd"

const CataloguedFirstPersonType = preload("res://scripts/characters/presentation/catalogued_first_person_embodiment.gd")
const CataloguedThirdPersonType = preload("res://scripts/characters/presentation/catalogued_third_person_held_item_presenter.gd")
const HeldStateCatalogType = preload("res://scripts/characters/presentation/held_item_presentation_state.gd")
const ItemViewmodelCatalogType = preload("res://scripts/characters/presentation/item_viewmodel_catalog.gd")
const GripProfileCatalogType = preload("res://scripts/characters/presentation/held_item_grip_profile_catalog.gd")
const GrabBridgeCatalogType = preload("res://scripts/characters/interaction/first_person_grab_authority_bridge.gd")

var item_viewmodel_catalog = ItemViewmodelCatalogType.new()
var held_item_grip_catalog = GripProfileCatalogType.new()
var _r2_s2_last_visual_descriptor: Dictionary = {}
var _r2_s2_last_grip_profile: Dictionary = {}
var _r2_s2_profile_resolutions := 0
var _r2_s2_first_person_applies := 0
var _r2_s2_third_person_applies := 0


func _setup_first_person_embodiment() -> void:
	if (
		base_lab.player == null
		or base_lab.avatar == null
		or base_lab.first_person_adapter == null
		or base_lab.presentation_profile == null
		or base_lab.first_person_camera == null
	):
		fpe_setup_result = _failure("FPE_BASE_PRESENTATION_NOT_READY")
		return

	grab_authority_bridge = GrabBridgeCatalogType.new()
	grab_authority_bridge.setup(Callable(), true)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	first_person_embodiment = CataloguedFirstPersonType.new()
	first_person_embodiment.name = "CataloguedFirstPersonEmbodiment"
	base_lab.player.add_child(first_person_embodiment)
	fpe_setup_result = first_person_embodiment.setup(
		base_lab.player,
		base_lab.avatar,
		base_lab.first_person_adapter,
		base_lab.presentation_profile,
		base_lab.first_person_camera,
		base_lab.third_person_camera,
		grab_authority_bridge,
		source_skeleton
	)
	if not bool(fpe_setup_result.get("success", false)):
		push_error("FPE R2 S2 catalogued first-person setup failed: %s" % JSON.stringify(fpe_setup_result))
		return
	if first_person_embodiment.interaction_raycast != null:
		first_person_embodiment.interaction_raycast.add_exception(base_lab.player)
	first_person_embodiment.interaction_result_changed.connect(_on_fpe_interaction_result_changed)
	first_person_embodiment.grab_state_changed.connect(_on_fpe_grab_state_changed)


func _setup_shared_held_item_presentation() -> void:
	if base_lab == null or base_lab.player == null or base_lab.avatar == null:
		_held_item_setup_result = _failure("FPE_R2_BASE_PRESENTATION_NOT_READY")
		return

	held_item_presentation_state = HeldStateCatalogType.new()
	held_item_presentation_state.changed.connect(_on_held_item_presentation_changed)

	var source_skeleton: Skeleton3D = null
	if base_lab.layered_rig_adapter != null and base_lab.layered_rig_adapter.has_method("resolve_pose_skeleton"):
		var skeleton_value: Variant = base_lab.layered_rig_adapter.call("resolve_pose_skeleton", base_lab.avatar)
		if skeleton_value is Skeleton3D:
			source_skeleton = skeleton_value as Skeleton3D

	third_person_held_item_presenter = CataloguedThirdPersonType.new()
	third_person_held_item_presenter.name = "FpeR2S2CataloguedThirdPersonHeldItemPresenter"
	base_lab.player.add_child(third_person_held_item_presenter)
	var world_layer_index := 20
	if base_lab.presentation_profile != null:
		world_layer_index = int(base_lab.presentation_profile.world_render_layer_index)
	_held_item_setup_result = third_person_held_item_presenter.setup(
		base_lab.avatar,
		source_skeleton,
		world_layer_index
	)
	if not bool(_held_item_setup_result.get("success", false)):
		_last_fpe_status_code = String(_held_item_setup_result.get("error_code", "FPE_R2_S2_THIRD_PERSON_SETUP_FAILED"))
		return

	if base_lab.character_gameplay_controller != null:
		_apply_hotbar_presentation_for_index(int(base_lab.character_gameplay_controller.selected_hotbar_index))


func _apply_held_item_snapshot(hand_id: String, snapshot: Dictionary) -> Dictionary:
	if hand_id != "right":
		return _failure("FPE_R2_S2_UNSUPPORTED_HELD_HAND", {"hand_id": hand_id})
	var item_id := String(snapshot.get("item_id", ""))
	if item_id.is_empty():
		_r2_s2_last_visual_descriptor.clear()
		_r2_s2_last_grip_profile.clear()
		return super._apply_held_item_snapshot(hand_id, snapshot)
	if first_person_embodiment == null or not first_person_embodiment.has_method("set_catalogued_hand_item"):
		return _failure("FPE_R2_S2_CATALOGUED_FIRST_PERSON_REQUIRED")
	if third_person_held_item_presenter == null or not third_person_held_item_presenter.has_method("present_catalogued_item"):
		return _failure("FPE_R2_S2_CATALOGUED_THIRD_PERSON_REQUIRED")
	if base_lab == null or base_lab.character_gameplay_controller == null:
		return _failure("FPE_R2_S2_CONTROLLER_REQUIRED")

	var controller = base_lab.character_gameplay_controller
	var item: Variant = controller.get_item(item_id)
	var definition_id := item_id
	var tags = []
	var metadata: Dictionary = {}
	var world_scene_path := ""
	if item != null:
		definition_id = String(item.definition_id)
		var definition: Variant = controller.get_definition(definition_id)
		if definition != null:
			tags = definition.tags
			metadata = Dictionary(definition.metadata).duplicate(true)
			world_scene_path = String(definition.world_scene_path)

	var display_name := String(snapshot.get("display_name", definition_id))
	var fallback_color := _snapshot_color(snapshot, Color(0.65, 0.68, 0.72, 1.0))
	var visual_descriptor: Dictionary = item_viewmodel_catalog.resolve(
		definition_id,
		tags,
		metadata,
		world_scene_path,
		fallback_color
	)
	var grip_profile: Dictionary = held_item_grip_catalog.resolve(
		definition_id,
		visual_descriptor,
		tags,
		metadata
	)
	_r2_s2_profile_resolutions += 1
	_r2_s2_last_visual_descriptor = visual_descriptor.duplicate(true)
	_r2_s2_last_grip_profile = grip_profile.duplicate(true)

	var first_value = first_person_embodiment.call(
		"set_catalogued_hand_item",
		"right",
		item_id,
		display_name,
		fallback_color,
		visual_descriptor,
		grip_profile
	)
	if not first_value is Dictionary:
		return _failure("FPE_R2_S2_FIRST_PERSON_RESULT_INVALID")
	var first_result: Dictionary = Dictionary(first_value).duplicate(true)
	if bool(first_result.get("success", false)):
		_r2_s2_first_person_applies += 1
	else:
		return first_result

	var third_value = third_person_held_item_presenter.call(
		"present_catalogued_item",
		item_id,
		display_name,
		fallback_color,
		visual_descriptor,
		grip_profile
	)
	if not third_value is Dictionary:
		return _failure("FPE_R2_S2_THIRD_PERSON_RESULT_INVALID")
	var third_result: Dictionary = Dictionary(third_value).duplicate(true)
	if bool(third_result.get("success", false)):
		_r2_s2_third_person_applies += 1
		_third_person_updates += 1
	else:
		return third_result

	return {
		"success": true,
		"error_code": "",
		"details": {
			"item_id": item_id,
			"definition_id": definition_id,
			"first_person_applied": true,
			"third_person_applied": true,
			"visual_profile": String(visual_descriptor.get("profile_id", "")),
			"visual_kind": String(visual_descriptor.get("visual_kind", "")),
			"grip_profile": String(grip_profile.get("profile_id", "")),
			"catalogued": true,
			"presentation_only": true,
		},
	}


func get_r2_s2_catalog_report() -> Dictionary:
	return {
		"schema": "planet_simulator.fpe_r2_s2_catalog.v1",
		"profile_resolutions": _r2_s2_profile_resolutions,
		"first_person_applies": _r2_s2_first_person_applies,
		"third_person_applies": _r2_s2_third_person_applies,
		"last_visual_descriptor": _r2_s2_last_visual_descriptor.duplicate(true),
		"last_grip_profile": _r2_s2_last_grip_profile.duplicate(true),
		"shared_catalog": true,
		"metadata_overrides_supported": true,
		"definition_tags_supported": true,
		"procedural_fallback_supported": true,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}


func get_first_person_embodiment_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = super.get_first_person_embodiment_debug_snapshot()
	snapshot["r2_s2"] = get_r2_s2_catalog_report()
	return snapshot
