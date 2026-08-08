class_name WearableBodyCoverageCatalog
extends RefCounted

var _entries: Dictionary = {}


func register_coverage(
	presentation_id: String,
	rig_profile_id: String,
	body_regions: Array
) -> Dictionary:
	if not CharacterEquipmentDomain.is_valid_semantic_id(presentation_id):
		return _result(false, "INVALID_PRESENTATION_ID")
	if not CharacterEquipmentDomain.is_valid_semantic_id(rig_profile_id):
		return _result(false, "INVALID_RIG_PROFILE")
	var regions: Array[String] = []
	for raw_region in body_regions:
		var region := String(raw_region).strip_edges()
		if not CharacterEquipmentDomain.is_valid_semantic_id(region):
			return _result(false, "INVALID_BODY_REGION", {"body_region": region})
		if region not in regions:
			regions.append(region)
	regions.sort()
	_entries[_key(presentation_id, rig_profile_id)] = {
		"presentation_id": presentation_id,
		"rig_profile_id": rig_profile_id,
		"body_regions": regions,
	}
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"presentation_id": presentation_id,
		"rig_profile_id": rig_profile_id,
		"body_regions": regions.duplicate(),
	})


func resolve(presentation_id: String, rig_profile_id: String) -> Dictionary:
	var key := _key(presentation_id, rig_profile_id)
	if not _entries.has(key):
		return _result(false, "COVERAGE_NOT_REGISTERED", {
			"presentation_id": presentation_id,
			"rig_profile_id": rig_profile_id,
		})
	var entry: Dictionary = _entries[key]
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"presentation_id": String(entry.get("presentation_id", "")),
		"rig_profile_id": String(entry.get("rig_profile_id", "")),
		"body_regions": (entry.get("body_regions", []) as Array).duplicate(),
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
