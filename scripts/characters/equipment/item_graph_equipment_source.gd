class_name ItemGraphEquipmentSource
extends CharacterEquipmentDomain.Source

const ItemRelations = preload("res://scripts/items/domain/item_relations.gd")

const RESULT_ITEM_GRAPH_PORT_INVALID := "ITEM_GRAPH_PORT_INVALID"
const RESULT_EQUIPMENT_CONTAINER_NOT_FOUND := "EQUIPMENT_CONTAINER_NOT_FOUND"
const RESULT_EQUIPMENT_CONTAINER_NOT_SLOTTED := "EQUIPMENT_CONTAINER_NOT_SLOTTED"
const RESULT_EQUIPMENT_CONTAINER_OWNER_MISMATCH := "EQUIPMENT_CONTAINER_OWNER_MISMATCH"
const RESULT_EQUIPMENT_SLOT_MAPPING_INVALID := "EQUIPMENT_SLOT_MAPPING_INVALID"
const RESULT_EQUIPMENT_SLOT_UNRESTRICTED := "EQUIPMENT_SLOT_UNRESTRICTED"
const RESULT_EQUIPMENT_SLOT_PROFILE_MISSING := "EQUIPMENT_SLOT_PROFILE_MISSING"
const RESULT_EQUIPMENT_SLOT_ITEM_MISSING := "EQUIPMENT_SLOT_ITEM_MISSING"
const RESULT_EQUIPMENT_ITEM_RELATION_MISMATCH := "EQUIPMENT_ITEM_RELATION_MISMATCH"
const RESULT_EQUIPMENT_ITEM_DEFINITION_MISSING := "EQUIPMENT_ITEM_DEFINITION_MISSING"
const RESULT_EQUIPMENT_ITEM_REJECTED_BY_SLOT := "EQUIPMENT_ITEM_REJECTED_BY_SLOT"
const RESULT_EQUIPMENT_ITEM_QUANTITY_INVALID := "EQUIPMENT_ITEM_QUANTITY_INVALID"

var owner_entity_id := ""
var equipment_container_id := ""
var layout: CharacterEquipmentDomain.Layout

var _item_registry
var _container_registry
var _profiles: Dictionary = {}
var _slot_profile_ids: Dictionary = {}
var _last_snapshot: CharacterEquipmentDomain.Snapshot
var _last_result: Dictionary = {}


func setup(
	p_owner_entity_id: String,
	p_equipment_container_id: String,
	p_layout: CharacterEquipmentDomain.Layout,
	p_item_registry,
	p_container_registry,
	slot_profile_ids: Dictionary,
	profiles: Array = []
) -> Dictionary:
	owner_entity_id = p_owner_entity_id.strip_edges()
	equipment_container_id = p_equipment_container_id.strip_edges()
	layout = p_layout
	_item_registry = p_item_registry
	_container_registry = p_container_registry
	_profiles.clear()
	_slot_profile_ids.clear()

	if owner_entity_id.is_empty():
		return _store_result(_result(false, CharacterEquipmentDomain.RESULT_INVALID_ITEM_ID, {"field": "owner_entity_id"}))
	if equipment_container_id.is_empty():
		return _store_result(_result(false, RESULT_EQUIPMENT_CONTAINER_NOT_FOUND, {"field": "equipment_container_id"}))
	if layout == null or not layout.is_valid():
		return _store_result(_result(false, CharacterEquipmentDomain.RESULT_INVALID_LAYOUT))
	if not _valid_item_registry(_item_registry) or not _valid_container_registry(_container_registry):
		return _store_result(_result(false, RESULT_ITEM_GRAPH_PORT_INVALID))

	for raw_profile in profiles:
		if raw_profile is CharacterEquipmentDomain.Profile and raw_profile.is_valid():
			_profiles[raw_profile.profile_id] = raw_profile

	var mapping_result: Dictionary = _normalize_slot_mapping(slot_profile_ids)
	if not bool(mapping_result.get("success", false)):
		return _store_result(mapping_result)
	_slot_profile_ids = Dictionary(mapping_result.get("details", {}).get("mapping", {})).duplicate(true)

	var container_result: Dictionary = _validate_equipment_container()
	if not bool(container_result.get("success", false)):
		return _store_result(container_result)

	_last_snapshot = CharacterEquipmentDomain.Snapshot.new(owner_entity_id, layout.layout_id, 0, [])
	return refresh()


func register_profile(profile: CharacterEquipmentDomain.Profile) -> Dictionary:
	if profile == null or not profile.is_valid():
		return _store_result(_result(false, CharacterEquipmentDomain.RESULT_INVALID_PROFILE))
	_profiles[profile.profile_id] = profile
	return _store_result(_result(true, CharacterEquipmentDomain.RESULT_OK, {"profile_id": profile.profile_id}))


func refresh() -> Dictionary:
	if layout == null or not layout.is_valid():
		return _store_result(_result(false, CharacterEquipmentDomain.RESULT_INVALID_LAYOUT))
	if not _valid_item_registry(_item_registry) or not _valid_container_registry(_container_registry):
		return _store_result(_result(false, RESULT_ITEM_GRAPH_PORT_INVALID))

	var container_result: Dictionary = _validate_equipment_container()
	if not bool(container_result.get("success", false)):
		return _store_result(container_result)
	var container = container_result.get("details", {}).get("container")
	if container == null:
		return _store_result(_result(false, RESULT_EQUIPMENT_CONTAINER_NOT_FOUND))

	var entries: Array = []
	var slot_indices: Array[int] = []
	for raw_slot in _slot_profile_ids.keys():
		slot_indices.append(int(raw_slot))
	slot_indices.sort()

	for slot_index in slot_indices:
		var item_id := String(container.get_item_at_slot(slot_index)).strip_edges()
		if item_id.is_empty():
			continue
		var profile_id := String(_slot_profile_ids.get(slot_index, ""))
		var profile = _profiles.get(profile_id)
		if not profile is CharacterEquipmentDomain.Profile:
			return _store_result(_result(false, RESULT_EQUIPMENT_SLOT_PROFILE_MISSING, {
				"slot_index": slot_index,
				"profile_id": profile_id,
			}))

		var item = _item_registry.get_item(item_id)
		if item == null:
			return _store_result(_result(false, RESULT_EQUIPMENT_SLOT_ITEM_MISSING, {
				"slot_index": slot_index,
				"item_id": item_id,
			}))
		if int(item.quantity) != 1:
			return _store_result(_result(false, RESULT_EQUIPMENT_ITEM_QUANTITY_INVALID, {
				"slot_index": slot_index,
				"item_id": item_id,
				"quantity": int(item.quantity),
			}))

		var relation: Dictionary = ItemRelations.canonicalize(item.relation)
		if (
			ItemRelations.kind_of(relation) != ItemRelations.CONTAINER
			or String(relation.get("container_id", "")) != equipment_container_id
			or int(relation.get("slot_index", -1)) != slot_index
		):
			return _store_result(_result(false, RESULT_EQUIPMENT_ITEM_RELATION_MISMATCH, {
				"slot_index": slot_index,
				"item_id": item_id,
				"relation": relation,
			}))

		var definition = _item_registry.get_definition(String(item.definition_id))
		if definition == null:
			return _store_result(_result(false, RESULT_EQUIPMENT_ITEM_DEFINITION_MISSING, {
				"slot_index": slot_index,
				"item_id": item_id,
				"definition_id": String(item.definition_id),
			}))
		if not bool(container.can_accept_definition_in_slot(definition, slot_index)):
			return _store_result(_result(false, RESULT_EQUIPMENT_ITEM_REJECTED_BY_SLOT, {
				"slot_index": slot_index,
				"item_id": item_id,
				"definition_id": String(item.definition_id),
			}))

		var validation: Dictionary = CharacterEquipmentDomain.validate_equip(layout, profile, entries, item_id)
		if not bool(validation.get("success", false)):
			var details: Dictionary = Dictionary(validation.get("details", {})).duplicate(true)
			details["slot_index"] = slot_index
			details["profile_id"] = profile_id
			details["item_id"] = item_id
			return _store_result(_result(false, String(validation.get("code", CharacterEquipmentDomain.RESULT_INVALID_PROFILE)), details))
		entries.append(CharacterEquipmentDomain.create_entry(item_id, profile))

	entries.sort_custom(func(a, b): return String(a.item_id) < String(b.item_id))
	var revision := maxi(0, int(container.revision))
	var next_snapshot := CharacterEquipmentDomain.Snapshot.new(owner_entity_id, layout.layout_id, revision, entries)
	var changed := _last_snapshot == null or _last_snapshot.state_fingerprint() != next_snapshot.state_fingerprint() or _last_snapshot.revision != next_snapshot.revision
	_last_snapshot = next_snapshot
	return _store_result(_result(true, CharacterEquipmentDomain.RESULT_OK, {
		"owner_entity_id": owner_entity_id,
		"equipment_container_id": equipment_container_id,
		"container_revision": revision,
		"equipped_item_count": entries.size(),
		"changed": changed,
		"state_fingerprint": next_snapshot.state_fingerprint(),
	}))


func get_snapshot() -> CharacterEquipmentDomain.Snapshot:
	var result: Dictionary = refresh()
	if not bool(result.get("success", false)) and _last_snapshot == null:
		return CharacterEquipmentDomain.Snapshot.new(owner_entity_id, layout.layout_id if layout != null else "", 0, [])
	return _last_snapshot


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func create_report() -> Dictionary:
	var snapshot := _last_snapshot
	return {
		"schema": "planet_simulator.item_graph_equipment_source_report.v1",
		"owner_entity_id": owner_entity_id,
		"equipment_container_id": equipment_container_id,
		"layout_id": layout.layout_id if layout != null else "",
		"registered_profile_ids": registered_profile_ids(),
		"slot_profile_ids": _sorted_slot_mapping(),
		"last_success": bool(_last_result.get("success", false)),
		"last_code": String(_last_result.get("code", "")),
		"snapshot_revision": snapshot.revision if snapshot != null else 0,
		"equipped_item_count": snapshot.entries().size() if snapshot != null else 0,
		"state_fingerprint": snapshot.state_fingerprint() if snapshot != null else "",
		"read_only": true,
		"canonical_source": "ITEM_REGISTRY_PLUS_EQUIPMENT_CONTAINER",
		"owns_item_mutation": false,
		"owns_network_state": false,
		"owns_persistence": false,
	}


func has_item(item_id: String) -> bool:
	if _last_snapshot == null:
		return false
	return _last_snapshot.find_item(item_id) != null


func registered_profile_ids() -> Array[String]:
	var result: Array[String] = []
	for key in _profiles.keys():
		result.append(String(key))
	result.sort()
	return result


func _normalize_slot_mapping(raw_mapping: Dictionary) -> Dictionary:
	if raw_mapping.is_empty():
		return _result(false, RESULT_EQUIPMENT_SLOT_MAPPING_INVALID, {"reason": "EMPTY_MAPPING"})
	var normalized: Dictionary = {}
	for raw_slot in raw_mapping.keys():
		var slot_text := String(raw_slot).strip_edges()
		if not slot_text.is_valid_int():
			return _result(false, RESULT_EQUIPMENT_SLOT_MAPPING_INVALID, {"slot": slot_text})
		var slot_index := int(slot_text)
		var profile_id := String(raw_mapping[raw_slot]).strip_edges()
		if slot_index < 0 or profile_id.is_empty():
			return _result(false, RESULT_EQUIPMENT_SLOT_MAPPING_INVALID, {
				"slot_index": slot_index,
				"profile_id": profile_id,
			})
		if not _profiles.has(profile_id):
			return _result(false, RESULT_EQUIPMENT_SLOT_PROFILE_MISSING, {
				"slot_index": slot_index,
				"profile_id": profile_id,
			})
		normalized[slot_index] = profile_id
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"mapping": normalized})


func _validate_equipment_container() -> Dictionary:
	var container = _container_registry.get_container(equipment_container_id)
	if container == null:
		return _result(false, RESULT_EQUIPMENT_CONTAINER_NOT_FOUND, {"container_id": equipment_container_id})
	if not bool(container.is_slot_container()):
		return _result(false, RESULT_EQUIPMENT_CONTAINER_NOT_SLOTTED, {"container_id": equipment_container_id})
	if String(container.owner_id) != owner_entity_id:
		return _result(false, RESULT_EQUIPMENT_CONTAINER_OWNER_MISMATCH, {
			"container_id": equipment_container_id,
			"expected_owner_id": owner_entity_id,
			"actual_owner_id": String(container.owner_id),
			"owner_kind": String(container.owner_kind),
		})

	for raw_slot in _slot_profile_ids.keys():
		var slot_index := int(raw_slot)
		if slot_index < 0 or slot_index >= int(container.slot_count):
			return _result(false, RESULT_EQUIPMENT_SLOT_MAPPING_INVALID, {
				"slot_index": slot_index,
				"slot_count": int(container.slot_count),
			})
		var rule: Dictionary = container.get_slot_rule(slot_index)
		var accepted_ids := PackedStringArray(rule.get("accepted_definition_ids", []))
		var accepted_tags := PackedStringArray(rule.get("accepted_tags", []))
		if accepted_ids.is_empty() and accepted_tags.is_empty():
			return _result(false, RESULT_EQUIPMENT_SLOT_UNRESTRICTED, {
				"slot_index": slot_index,
				"profile_id": String(_slot_profile_ids[slot_index]),
			})
	return _result(true, CharacterEquipmentDomain.RESULT_OK, {"container": container})


func _valid_item_registry(value) -> bool:
	return value != null and value.has_method("get_item") and value.has_method("get_definition")


func _valid_container_registry(value) -> bool:
	return value != null and value.has_method("get_container")


func _sorted_slot_mapping() -> Array:
	var slots: Array[int] = []
	for raw_slot in _slot_profile_ids.keys():
		slots.append(int(raw_slot))
	slots.sort()
	var rows: Array = []
	for slot_index in slots:
		rows.append({"slot_index": slot_index, "profile_id": String(_slot_profile_ids[slot_index])})
	return rows


func _store_result(result: Dictionary) -> Dictionary:
	_last_result = result.duplicate(true)
	return _last_result.duplicate(true)


func _result(success: bool, code: String, details: Dictionary = {}) -> Dictionary:
	return {
		"success": success,
		"code": code,
		"details": details.duplicate(true),
	}
