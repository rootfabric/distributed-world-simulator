extends RefCounted

const SCHEMA: String = "planet_simulator.container_state.v2"
const SCHEMA_VERSION: int = 2
const STORAGE_BULK: String = "BULK"
const STORAGE_SLOTS: String = "SLOTS"

var container_id: String = ""
var owner_kind: String = "SYSTEM"
var owner_id: String = ""
var parent_container_id: String = ""
var storage_mode: String = STORAGE_BULK
var slot_count: int = 0
var slot_rules: Array = []
var slot_assignments: Dictionary = {}
var maximum_mass_kg: float = INF
var maximum_volume_l: float = INF
var allow_nested_containers: bool = true
var maximum_nested_depth: int = 8
var accepted_tags: PackedStringArray = PackedStringArray()
var accepted_definition_ids: PackedStringArray = PackedStringArray()
var item_ids: Array[String] = []
var revision: int = 0


func _init(data: Dictionary = {}) -> void:
	container_id = String(data.get("container_id", ""))
	owner_kind = String(data.get("owner_kind", "SYSTEM"))
	owner_id = String(data.get("owner_id", ""))
	parent_container_id = String(data.get("parent_container_id", ""))
	storage_mode = String(data.get("storage_mode", STORAGE_BULK)).to_upper()
	if storage_mode != STORAGE_SLOTS:
		storage_mode = STORAGE_BULK
	slot_count = maxi(0, int(data.get("slot_count", 0)))
	var raw_rules = data.get("slot_rules", [])
	if raw_rules is Array:
		for rule_value in raw_rules:
			slot_rules.append(Dictionary(rule_value).duplicate(true) if rule_value is Dictionary else {})
	var raw_assignments = data.get("slot_assignments", {})
	if raw_assignments is Dictionary:
		for slot_key in raw_assignments.keys():
			slot_assignments[int(slot_key)] = String(raw_assignments[slot_key])
	maximum_mass_kg = _decode_capacity(data.get("maximum_mass_kg", INF))
	maximum_volume_l = _decode_capacity(data.get("maximum_volume_l", INF))
	allow_nested_containers = bool(data.get("allow_nested_containers", true))
	maximum_nested_depth = maxi(0, int(data.get("maximum_nested_depth", 8)))
	accepted_tags = PackedStringArray(data.get("accepted_tags", []))
	accepted_definition_ids = PackedStringArray(data.get("accepted_definition_ids", []))
	for item_id in data.get("item_ids", []):
		item_ids.append(String(item_id))
	revision = int(data.get("revision", 0))


func is_slot_container() -> bool:
	return storage_mode == STORAGE_SLOTS


func has_free_slot() -> bool:
	if is_slot_container():
		return find_first_free_slot() >= 0
	return slot_count == 0 or item_ids.size() < slot_count


func find_first_free_slot() -> int:
	if not is_slot_container():
		return -1
	for slot_index in range(slot_count):
		if not slot_assignments.has(slot_index):
			return slot_index
	return -1


func get_item_at_slot(slot_index: int) -> String:
	return String(slot_assignments.get(slot_index, ""))


func get_slot_for_item(item_id: String) -> int:
	for slot_key in slot_assignments.keys():
		if String(slot_assignments[slot_key]) == item_id:
			return int(slot_key)
	return -1


func get_slot_rule(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= slot_count or slot_index >= slot_rules.size():
		return {}
	var value = slot_rules[slot_index]
	return Dictionary(value).duplicate(true) if value is Dictionary else {}


func can_accept_definition_in_slot(definition, slot_index: int) -> bool:
	if definition == null or slot_index < 0 or slot_index >= slot_count:
		return false
	var rule := get_slot_rule(slot_index)
	var accepted_ids := PackedStringArray(rule.get("accepted_definition_ids", []))
	if not accepted_ids.is_empty() and not accepted_ids.has(String(definition.id)):
		return false
	var accepted_slot_tags := PackedStringArray(rule.get("accepted_tags", []))
	if not accepted_slot_tags.is_empty():
		var matched := false
		for tag in accepted_slot_tags:
			if definition.has_tag(String(tag)):
				matched = true
				break
		if not matched:
			return false
	return true


func assign_item(item_id: String, requested_slot: int = -1) -> int:
	if item_id.is_empty():
		return -1
	if not item_ids.has(item_id):
		item_ids.append(item_id)
	if not is_slot_container():
		return -1
	var existing := get_slot_for_item(item_id)
	if existing >= 0:
		return existing
	var resolved_slot := requested_slot
	if resolved_slot < 0:
		resolved_slot = find_first_free_slot()
	if resolved_slot < 0 or resolved_slot >= slot_count or slot_assignments.has(resolved_slot):
		item_ids.erase(item_id)
		return -1
	slot_assignments[resolved_slot] = item_id
	return resolved_slot


func remove_item(item_id: String) -> bool:
	var removed: bool = item_ids.has(item_id)
	if removed:
		item_ids.erase(item_id)
	var slot_index: int = get_slot_for_item(item_id)
	if slot_index >= 0:
		slot_assignments.erase(slot_index)
		removed = true
	return removed


func to_dict() -> Dictionary:
	var serialized_assignments: Dictionary = {}
	var assignment_keys := slot_assignments.keys()
	assignment_keys.sort()
	for slot_index in assignment_keys:
		serialized_assignments[str(int(slot_index))] = String(slot_assignments[slot_index])
	return {
		"schema": SCHEMA,
		"schema_version": SCHEMA_VERSION,
		"container_id": container_id,
		"owner_kind": owner_kind,
		"owner_id": owner_id,
		"parent_container_id": parent_container_id,
		"storage_mode": storage_mode,
		"slot_count": slot_count,
		"slot_rules": slot_rules.duplicate(true),
		"slot_assignments": serialized_assignments,
		"maximum_mass_kg": _encode_capacity(maximum_mass_kg),
		"maximum_volume_l": _encode_capacity(maximum_volume_l),
		"allow_nested_containers": allow_nested_containers,
		"maximum_nested_depth": maximum_nested_depth,
		"accepted_tags": Array(accepted_tags),
		"accepted_definition_ids": Array(accepted_definition_ids),
		"item_ids": item_ids.duplicate(),
		"revision": revision,
	}


func _encode_capacity(value: float) -> float:
	return -1.0 if is_inf(value) else maxf(0.0, value)


func _decode_capacity(value) -> float:
	if value == null:
		return INF
	var parsed := float(value)
	return INF if parsed < 0.0 or is_inf(parsed) else parsed
