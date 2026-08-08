class_name CharacterEquipmentLayering
extends RefCounted

const RESULT_CONFLICT_PLAN := "EQUIPMENT_LAYER_CONFLICT_PLAN"


static func plan_equip(
	layout: CharacterEquipmentDomain.Layout,
	profile: CharacterEquipmentDomain.Profile,
	current_entries: Array,
	item_id: String
) -> Dictionary:
	var validation := CharacterEquipmentDomain.validate_equip(layout, profile, current_entries, item_id)
	if bool(validation.get("success", false)):
		return _result(true, CharacterEquipmentDomain.RESULT_OK, {
			"item_id": item_id,
			"profile_id": profile.profile_id if profile != null else "",
			"requested_channels": profile.occupied_channels() if profile != null else [],
			"conflicting_item_ids": [],
			"conflicts": [],
			"can_equip_without_replacement": true,
			"requires_replacement": false,
		})

	if String(validation.get("code", "")) != CharacterEquipmentDomain.RESULT_EQUIPMENT_CHANNEL_OCCUPIED:
		return validation

	var requested_channels: Array[String] = profile.occupied_channels()
	var requested_set: Dictionary = {}
	for channel in requested_channels:
		requested_set[channel] = true

	var conflicts: Array[Dictionary] = []
	var conflict_items: Dictionary = {}
	for raw_entry in current_entries:
		if not raw_entry is CharacterEquipmentDomain.Entry:
			continue
		var entry := raw_entry as CharacterEquipmentDomain.Entry
		for channel in entry.occupied_channels():
			if not requested_set.has(channel):
				continue
			conflicts.append({
				"channel": channel,
				"occupied_by_item_id": entry.item_id,
				"occupied_by_profile_id": entry.profile_id,
			})
			conflict_items[entry.item_id] = true

	conflicts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_channel := String(left.get("channel", ""))
		var right_channel := String(right.get("channel", ""))
		if left_channel == right_channel:
			return String(left.get("occupied_by_item_id", "")) < String(right.get("occupied_by_item_id", ""))
		return left_channel < right_channel
	)
	var conflicting_item_ids := CharacterEquipmentDomain._sorted_keys(conflict_items)
	return _result(true, RESULT_CONFLICT_PLAN, {
		"item_id": item_id,
		"profile_id": profile.profile_id,
		"requested_channels": requested_channels,
		"conflicting_item_ids": conflicting_item_ids,
		"conflicts": conflicts,
		"can_equip_without_replacement": conflicts.is_empty(),
		"requires_replacement": not conflicts.is_empty(),
	})


static func conflicting_item_ids(plan: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var details: Dictionary = plan.get("details", {})
	for raw_id in details.get("conflicting_item_ids", []):
		result.append(String(raw_id))
	result.sort()
	return result


static func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
