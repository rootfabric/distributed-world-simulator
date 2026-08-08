class_name WearablePresentationCatalog
extends RefCounted

const STRATEGY_RIGID_ATTACHMENT := "RIGID_ATTACHMENT"
const STRATEGY_SKINNED_GARMENT := "SKINNED_GARMENT"

var _entries: Dictionary = {}


func register_scene(
	presentation_id: String,
	rig_profile_id: String,
	strategy: String,
	scene: PackedScene,
	hide_body_regions: Array = [],
	local_transform: Transform3D = Transform3D.IDENTITY,
	body_replacement_scene: PackedScene = null,
	body_replacement_transform: Transform3D = Transform3D.IDENTITY,
	visible_mesh_names: Array = []
) -> Dictionary:
	if not CharacterEquipmentDomain.is_valid_semantic_id(presentation_id):
		return _result(false, "INVALID_PRESENTATION_ID")
	if not CharacterEquipmentDomain.is_valid_semantic_id(rig_profile_id):
		return _result(false, "INVALID_RIG_PROFILE")
	if strategy not in [STRATEGY_RIGID_ATTACHMENT, STRATEGY_SKINNED_GARMENT]:
		return _result(false, "UNSUPPORTED_PRESENTATION_STRATEGY")
	if scene == null:
		return _result(false, "MISSING_PRESENTATION_SCENE")
	if body_replacement_scene != null and strategy != STRATEGY_SKINNED_GARMENT:
		return _result(false, "BODY_REPLACEMENT_REQUIRES_SKINNED_GARMENT")

	var regions: Array[String] = []
	for raw_region in hide_body_regions:
		var region := String(raw_region).strip_edges()
		if CharacterEquipmentDomain.is_valid_semantic_id(region) and region not in regions:
			regions.append(region)
	regions.sort()

	var mesh_names: Array[String] = []
	for raw_name in visible_mesh_names:
		var mesh_name := String(raw_name).strip_edges()
		if not mesh_name.is_empty() and mesh_name not in mesh_names:
			mesh_names.append(mesh_name)
	mesh_names.sort()
	if not mesh_names.is_empty() and strategy != STRATEGY_SKINNED_GARMENT:
		return _result(false, "MESH_FILTER_REQUIRES_SKINNED_GARMENT")

	var key := _key(presentation_id, rig_profile_id)
	_entries[key] = {
		"presentation_id": presentation_id,
		"rig_profile_id": rig_profile_id,
		"strategy": strategy,
		"scene": scene,
		"hide_body_regions": regions,
		"local_transform": local_transform,
		"body_replacement_scene": body_replacement_scene,
		"body_replacement_transform": body_replacement_transform,
		"visible_mesh_names": mesh_names,
	}
	return _result(true, CharacterEquipmentDomain.RESULT_OK)


func resolve(presentation_id: String, rig_profile_id: String) -> Dictionary:
	var key := _key(presentation_id, rig_profile_id)
	if not _entries.has(key):
		return _result(false, "UNSUPPORTED_PRESENTATION", {
			"presentation_id": presentation_id,
			"rig_profile_id": rig_profile_id,
		})
	var entry: Dictionary = _entries[key]
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"presentation_id": String(entry.get("presentation_id", "")),
		"rig_profile_id": String(entry.get("rig_profile_id", "")),
		"strategy": String(entry.get("strategy", "")),
		"scene": entry.get("scene"),
		"hide_body_regions": (entry.get("hide_body_regions", []) as Array).duplicate(),
		"local_transform": entry.get("local_transform", Transform3D.IDENTITY),
		"body_replacement_scene": entry.get("body_replacement_scene"),
		"body_replacement_transform": entry.get("body_replacement_transform", Transform3D.IDENTITY),
		"visible_mesh_names": (entry.get("visible_mesh_names", []) as Array).duplicate(),
	})


func has(presentation_id: String, rig_profile_id: String) -> bool:
	return _entries.has(_key(presentation_id, rig_profile_id))


func entry_count() -> int:
	return _entries.size()


func _key(presentation_id: String, rig_profile_id: String) -> String:
	return "%s|%s" % [presentation_id, rig_profile_id]


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
