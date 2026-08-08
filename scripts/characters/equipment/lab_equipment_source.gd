class_name LabEquipmentSource
extends CharacterEquipmentDomain.Source

const EquipmentLayering = preload("res://scripts/characters/equipment/character_equipment_layering.gd")

var owner_entity_id := ""
var layout: CharacterEquipmentDomain.Layout
var revision := 0

var _profiles: Dictionary = {}
var _entries_by_item: Dictionary = {}


func setup(p_owner_entity_id: String, p_layout: CharacterEquipmentDomain.Layout, profiles: Array = []) -> Dictionary:
	owner_entity_id = p_owner_entity_id.strip_edges()
	layout = p_layout
	revision = 0
	_profiles.clear()
	_entries_by_item.clear()
	for raw_profile in profiles:
		if raw_profile is CharacterEquipmentDomain.Profile and raw_profile.is_valid():
			_profiles[raw_profile.profile_id] = raw_profile
	if owner_entity_id.is_empty():
		return _result(false, CharacterEquipmentDomain.RESULT_INVALID_ITEM_ID, {"field": "owner_entity_id"})
	if layout == null or not layout.is_valid():
		return _result(false, CharacterEquipmentDomain.RESULT_INVALID_LAYOUT)
	return _result(true, CharacterEquipmentDomain.RESULT_OK)


func register_profile(profile: CharacterEquipmentDomain.Profile) -> Dictionary:
	if profile == null or not profile.is_valid():
		return _result(false, CharacterEquipmentDomain.RESULT_INVALID_PROFILE)
	_profiles[profile.profile_id] = profile
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"profile_id": profile.profile_id})


func equip(item_id: String, profile_id: String) -> Dictionary:
	var profile = _profiles.get(profile_id)
	if not profile is CharacterEquipmentDomain.Profile:
		return _result(false, CharacterEquipmentDomain.RESULT_INVALID_PROFILE, {"profile_id": profile_id})
	var validation := CharacterEquipmentDomain.validate_equip(layout, profile, _entries(), item_id)
	if not bool(validation.get("success", false)):
		return validation
	var entry := CharacterEquipmentDomain.create_entry(item_id, profile)
	_entries_by_item[item_id] = entry
	revision += 1
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"item_id": item_id,
		"profile_id": profile_id,
		"revision": revision,
	})


func plan_equip(item_id: String, profile_id: String) -> Dictionary:
	var profile = _profiles.get(profile_id)
	if not profile is CharacterEquipmentDomain.Profile:
		return _result(false, CharacterEquipmentDomain.RESULT_INVALID_PROFILE, {"profile_id": profile_id})
	return EquipmentLayering.plan_equip(layout, profile, _entries(), item_id)


func equip_replacing_conflicts(item_id: String, profile_id: String) -> Dictionary:
	var profile = _profiles.get(profile_id)
	if not profile is CharacterEquipmentDomain.Profile:
		return _result(false, CharacterEquipmentDomain.RESULT_INVALID_PROFILE, {"profile_id": profile_id})

	var plan: Dictionary = EquipmentLayering.plan_equip(layout, profile, _entries(), item_id)
	if not bool(plan.get("success", false)):
		return plan
	var conflicting_item_ids: Array[String] = EquipmentLayering.conflicting_item_ids(plan)
	for conflicting_item_id in conflicting_item_ids:
		_entries_by_item.erase(conflicting_item_id)

	var entry := CharacterEquipmentDomain.create_entry(item_id, profile)
	_entries_by_item[item_id] = entry
	revision += 1
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"item_id": item_id,
		"profile_id": profile_id,
		"revision": revision,
		"replacement": not conflicting_item_ids.is_empty(),
		"replaced_item_ids": conflicting_item_ids,
		"conflict_plan": plan.get("details", {}).duplicate(true),
	})


func unequip(item_id: String) -> Dictionary:
	if not _entries_by_item.has(item_id):
		return _result(false, CharacterEquipmentDomain.RESULT_ITEM_NOT_EQUIPPED, {"item_id": item_id})
	_entries_by_item.erase(item_id)
	revision += 1
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"item_id": item_id,
		"revision": revision,
	})


func reset() -> Dictionary:
	if _entries_by_item.is_empty():
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {"revision": revision, "changed": false})
	_entries_by_item.clear()
	revision += 1
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"revision": revision, "changed": true})


func replace_layout(p_layout: CharacterEquipmentDomain.Layout, clear_equipment := true) -> Dictionary:
	if p_layout == null or not p_layout.is_valid():
		return _result(false, CharacterEquipmentDomain.RESULT_INVALID_LAYOUT)
	var changed := layout == null or layout.layout_id != p_layout.layout_id
	layout = p_layout
	if clear_equipment and not _entries_by_item.is_empty():
		_entries_by_item.clear()
		changed = true
	if changed:
		revision += 1
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {
		"layout_id": layout.layout_id,
		"revision": revision,
		"changed": changed,
	})


func get_snapshot() -> CharacterEquipmentDomain.Snapshot:
	var layout_id := layout.layout_id if layout != null else ""
	return CharacterEquipmentDomain.Snapshot.new(owner_entity_id, layout_id, revision, _entries())


func has_item(item_id: String) -> bool:
	return _entries_by_item.has(item_id)


func registered_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _profiles.keys():
		result.append(String(key))
	result.sort()
	return result


func _entries() -> Array:
	var item_ids: Array[String] = []
	for raw_id in _entries_by_item.keys():
		item_ids.append(String(raw_id))
	item_ids.sort()
	var result: Array = []
	for item_id in item_ids:
		result.append(_entries_by_item[item_id])
	return result


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
