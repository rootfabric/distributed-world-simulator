class_name CataloguedThirdPersonHeldItemPresenter
extends "res://scripts/characters/presentation/third_person_held_item_presenter.gd"

const VisualFactoryType = preload("res://scripts/characters/presentation/held_item_visual_factory.gd")

var _catalog_visual_factory = VisualFactoryType.new()
var current_visual_profile := ""
var current_grip_profile := ""
var catalogued_updates := 0


func present_catalogued_item(
	item_id: String,
	display_name: String,
	item_color: Color,
	visual_descriptor: Dictionary,
	grip_profile: Dictionary
) -> Dictionary:
	if not _configured:
		return _failure("THIRD_PERSON_HELD_NOT_CONFIGURED")
	var normalized_item_id := item_id.strip_edges()
	if normalized_item_id.is_empty():
		return clear_item()

	var visual_profile := String(visual_descriptor.get("profile_id", "generic_box"))
	var grip_profile_id := String(grip_profile.get("profile_id", "generic"))
	if (
		current_item_id == normalized_item_id
		and current_visual_profile == visual_profile
		and current_grip_profile == grip_profile_id
		and _proxy != null
		and is_instance_valid(_proxy)
	):
		_apply_proxy_metadata(normalized_item_id, display_name, item_color)
		return _success({
			"changed": false,
			"item_id": normalized_item_id,
			"attachment_mode": attachment_mode,
			"visual_profile": visual_profile,
			"grip_profile": grip_profile_id,
			"catalogued": true,
		})

	_clear_proxy()
	if _grip_root == null:
		return _failure("THIRD_PERSON_HELD_GRIP_ROOT_UNAVAILABLE")
	_grip_root.position = Vector3.ZERO
	_grip_root.rotation_degrees = Vector3.ZERO
	_grip_root.scale = Vector3.ONE
	_catalog_visual_factory.apply_local_transform(_grip_root, Dictionary(grip_profile.get("third_person", {})))

	var built: Dictionary = _catalog_visual_factory.create_proxy(
		visual_descriptor,
		item_color,
		"CataloguedThirdPersonHeldItemProxy",
		world_layer_index
	)
	if not bool(built.get("success", false)):
		return built
	var proxy_value: Variant = Dictionary(built.get("details", {})).get("proxy")
	if not proxy_value is MeshInstance3D:
		return _failure("THIRD_PERSON_CATALOG_PROXY_INVALID")
	_proxy = proxy_value as MeshInstance3D
	_grip_root.add_child(_proxy)
	_apply_proxy_metadata(normalized_item_id, display_name, item_color)
	_proxy.set_meta("held_grip_profile", grip_profile_id)
	current_visual_profile = visual_profile
	current_grip_profile = grip_profile_id
	catalogued_updates += 1
	return _success({
		"changed": true,
		"item_id": normalized_item_id,
		"display_name": display_name,
		"attachment_mode": attachment_mode,
		"matched_bone_name": matched_bone_name,
		"world_layer_index": world_layer_index,
		"visual_profile": visual_profile,
		"visual_kind": String(visual_descriptor.get("visual_kind", "BOX")),
		"grip_profile": grip_profile_id,
		"catalogued": true,
		"presentation_only": true,
	})


func clear_item() -> Dictionary:
	var result: Dictionary = super.clear_item()
	current_visual_profile = ""
	current_grip_profile = ""
	return result


func create_report() -> Dictionary:
	var report: Dictionary = super.create_report()
	report["catalogued"] = {
		"enabled": true,
		"visual_profile": current_visual_profile,
		"grip_profile": current_grip_profile,
		"updates": catalogued_updates,
		"presentation_only": true,
		"owns_item_state": false,
		"owns_network_state": false,
		"owns_gameplay_transform": false,
	}
	return report
