class_name NetworkCharacterEquipmentProjection
extends RefCounted

const EquipmentDomain = preload("res://scripts/characters/equipment/character_equipment_domain.gd")
const EquipmentCatalog = preload("res://scripts/characters/equipment/network_character_equipment_catalog.gd")

const RESULT_INVALID_CANONICAL_SNAPSHOT := "INVALID_CANONICAL_EQUIPMENT_SNAPSHOT"
const RESULT_PLAYER_ID_REQUIRED := "EQUIPMENT_PLAYER_ID_REQUIRED"
const RESULT_EQUIPMENT_CONTAINER_MISSING := "NETWORK_EQUIPMENT_CONTAINER_MISSING"
const RESULT_EQUIPMENT_CONTAINER_INVALID := "NETWORK_EQUIPMENT_CONTAINER_INVALID"
const RESULT_EQUIPMENT_ITEM_MISSING := "NETWORK_EQUIPMENT_ITEM_MISSING"
const RESULT_EQUIPMENT_ITEM_RELATION_INVALID := "NETWORK_EQUIPMENT_ITEM_RELATION_INVALID"
const RESULT_EQUIPMENT_PROFILE_INVALID := "NETWORK_EQUIPMENT_PROFILE_INVALID"

var _last_snapshot: CharacterEquipmentDomain.Snapshot
var _last_result: Dictionary = {}


func project(canonical_snapshot: Dictionary, logical_player_id: String) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return _store(_failure(RESULT_PLAYER_ID_REQUIRED))
	if String(canonical_snapshot.get("schema", "")) != "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1":
		return _store(_failure(RESULT_INVALID_CANONICAL_SNAPSHOT))
	var container_id := EquipmentCatalog.equipment_container_id(player_id)
	var container := _find_container(canonical_snapshot, container_id)
	if container.is_empty():
		return _store(_failure(RESULT_EQUIPMENT_CONTAINER_MISSING, {"container_id": container_id}))
	if (
		String(container.get("container_kind", "")) != EquipmentCatalog.EQUIPMENT_CONTAINER_KIND
		or String(container.get("owner_player_id", "")) != player_id
		or int(container.get("capacity", -1)) != EquipmentCatalog.EQUIPMENT_SLOT_COUNT
		or not container.get("equipment_slots", {}) is Dictionary
	):
		return _store(_failure(RESULT_EQUIPMENT_CONTAINER_INVALID, {"container": container}))

	var item_map := _item_map(canonical_snapshot)
	var entries: Array = []
	var layout := EquipmentCatalog.layout()
	var equipment_slots: Dictionary = Dictionary(container.get("equipment_slots", {}))
	for slot_index in range(EquipmentCatalog.EQUIPMENT_SLOT_COUNT):
		var item_id := String(equipment_slots.get(str(slot_index), ""))
		if item_id.is_empty():
			continue
		if not item_map.has(item_id):
			return _store(_failure(RESULT_EQUIPMENT_ITEM_MISSING, {"item_id": item_id, "slot_index": slot_index}))
		var item: Dictionary = item_map[item_id]
		var location: Dictionary = Dictionary(item.get("location", {}))
		if (
			String(location.get("kind", "")) != "CONTAINER"
			or String(location.get("container_id", "")) != container_id
			or int(location.get("slot_index", -1)) != slot_index
			or int(item.get("quantity", 0)) != 1
			or String(item.get("definition_id", "")) != EquipmentCatalog.canonical_definition_for_slot(slot_index)
		):
			return _store(_failure(RESULT_EQUIPMENT_ITEM_RELATION_INVALID, {
				"item_id": item_id,
				"slot_index": slot_index,
				"item": item,
			}))
		var profile := EquipmentCatalog.profile_for_slot(slot_index)
		if profile == null:
			return _store(_failure(RESULT_EQUIPMENT_PROFILE_INVALID, {"slot_index": slot_index}))
		var validation: Dictionary = EquipmentDomain.validate_equip(layout, profile, entries, item_id)
		if not bool(validation.get("success", false)):
			return _store(_failure(String(validation.get("code", RESULT_EQUIPMENT_PROFILE_INVALID)), {
				"item_id": item_id,
				"slot_index": slot_index,
				"cause": validation,
			}))
		entries.append(EquipmentDomain.create_entry(item_id, profile))

	entries.sort_custom(func(a, b): return String(a.item_id) < String(b.item_id))
	_last_snapshot = EquipmentDomain.Snapshot.new(
		EquipmentCatalog.owner_entity_id(player_id),
		layout.layout_id,
		maxi(0, int(canonical_snapshot.get("revision", 0))),
		entries
	)
	return _store({
		"success": true,
		"code": EquipmentDomain.RESULT_OK,
		"details": {
			"logical_player_id": player_id,
			"equipment_container_id": container_id,
			"equipped_item_count": entries.size(),
			"snapshot": _last_snapshot,
			"state_fingerprint": _last_snapshot.state_fingerprint(),
		},
	})


func get_snapshot() -> CharacterEquipmentDomain.Snapshot:
	return _last_snapshot


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func create_report() -> Dictionary:
	return {
		"schema": "planet_simulator.network_character_equipment_projection.v1",
		"last_success": bool(_last_result.get("success", false)),
		"last_code": String(_last_result.get("code", _last_result.get("error_code", ""))),
		"equipped_item_count": _last_snapshot.entries().size() if _last_snapshot != null else 0,
		"owns_network_state": false,
		"owns_item_mutation": false,
		"presentation_neutral": true,
	}


func _find_container(snapshot: Dictionary, container_id: String) -> Dictionary:
	for value in snapshot.get("containers", []):
		if value is Dictionary and String(value.get("container_id", "")) == container_id:
			return Dictionary(value).duplicate(true)
	return {}


func _item_map(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for value in snapshot.get("items", []):
		if value is Dictionary:
			var item: Dictionary = value
			result[String(item.get("item_id", ""))] = item.duplicate(true)
	return result


func _store(result: Dictionary) -> Dictionary:
	_last_result = result.duplicate(true)
	return result


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "code": code, "error_code": code, "details": details.duplicate(true)}
