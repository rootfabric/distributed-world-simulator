extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SNAPSHOT_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1"
const VIEW_SCHEMA := "planet_simulator.m5_item_graph_ui_projection.v1"
const CONTAINER_VIEW_SCHEMA := "planet_simulator.container_view.v2"
const PLAYER_CAPACITY := 32
const HOTBAR_CAPACITY := 8

const DEFINITION_METADATA := {
	"item/beacon": {
		"display_name": "Маяк",
		"tags": ["electronic", "beacon", "mountable"],
		"icon_color": [0.25, 0.85, 0.95, 1.0],
		"max_stack": 1,
	},
	"item/ore": {
		"display_name": "Руда",
		"tags": ["resource", "ore", "material"],
		"icon_color": [0.72, 0.58, 0.38, 1.0],
		"max_stack": 999,
	},
	"item/crate": {
		"display_name": "Контейнер",
		"tags": ["container", "construction"],
		"icon_color": [0.55, 0.38, 0.22, 1.0],
		"max_stack": 1,
	},
}

var _snapshot: Dictionary = {}
var _last_revision := -1
var _last_checksum := ""
var _accept_count := 0
var _replay_count := 0
var _rejection_count := 0


func accept_snapshot(snapshot: Dictionary) -> Dictionary:
	var validated := validate_snapshot(snapshot)
	if not bool(validated.get("success", false)):
		_rejection_count += 1
		return validated
	var revision := int(snapshot.get("revision", -1))
	var checksum := String(snapshot.get("checksum", ""))
	if revision < _last_revision:
		_rejection_count += 1
		return _failure("ITEM_GRAPH_REVISION_ROLLBACK")
	if revision == _last_revision:
		if checksum != _last_checksum:
			_rejection_count += 1
			return _failure("ITEM_GRAPH_SAME_REVISION_MUTATION")
		_replay_count += 1
		return _success({"replay": true, "revision": revision})
	_snapshot = snapshot.duplicate(true)
	_last_revision = revision
	_last_checksum = checksum
	_accept_count += 1
	return _success({"replay": false, "revision": revision})


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if String(snapshot.get("schema", "")) != SNAPSHOT_SCHEMA:
		return _failure("INVALID_ITEM_GRAPH_SCHEMA")
	for field in [
		"authority_owner_id", "authority_epoch", "revision", "tick", "items",
		"inventories", "containers", "mounts", "open_containers", "checksum",
	]:
		if not snapshot.has(field):
			return _failure("MISSING_ITEM_GRAPH_FIELD", {"field": field})
	if not snapshot.get("items") is Array:
		return _failure("INVALID_ITEM_GRAPH_ITEMS")
	if not snapshot.get("inventories") is Dictionary:
		return _failure("INVALID_ITEM_GRAPH_INVENTORIES")
	if not snapshot.get("containers") is Array:
		return _failure("INVALID_ITEM_GRAPH_CONTAINERS")
	if not snapshot.get("mounts") is Array:
		return _failure("INVALID_ITEM_GRAPH_MOUNTS")
	if not snapshot.get("open_containers") is Dictionary:
		return _failure("INVALID_ITEM_GRAPH_OPEN_CONTAINERS")
	var canonical := snapshot.duplicate(true)
	var checksum := String(canonical.get("checksum", ""))
	canonical.erase("checksum")
	if checksum.is_empty() or checksum != Utils.payload_hash(canonical):
		return _failure("CHECKSUM_MISMATCH")
	return _success()


func build_screen(
	logical_player_id: String,
	external_container_id: String = "",
	selected_item_id: String = "",
	transient_overlay: Dictionary = {}
) -> Dictionary:
	if _snapshot.is_empty():
		return {
			"schema": VIEW_SCHEMA,
			"success": false,
			"error_code": "ITEM_GRAPH_REPLICA_MISSING",
		}
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return {
			"schema": VIEW_SCHEMA,
			"success": false,
			"error_code": "PLAYER_ID_REQUIRED",
		}
	var inventory_record: Dictionary = Dictionary(
		_snapshot.get("inventories", {}).get(player_id, {})
	)
	var authoritative_external := String(
		_snapshot.get("open_containers", {}).get(player_id, "")
	)
	var requested_external := external_container_id.strip_edges()
	var resolved_external := authoritative_external
	if not requested_external.is_empty() and requested_external == authoritative_external:
		resolved_external = requested_external
	var player_model := _build_inventory_container(player_id, inventory_record, transient_overlay)
	var hotbar_model := _build_hotbar_container(player_id, inventory_record, transient_overlay)
	var external_model: Dictionary = {}
	if not resolved_external.is_empty():
		external_model = _build_external_container(resolved_external, transient_overlay)
	var selected_item := _build_item_inspector(selected_item_id)
	return {
		"schema": VIEW_SCHEMA,
		"success": true,
		"canonical_revision": _last_revision,
		"canonical_checksum": _last_checksum,
		"authority_epoch": int(_snapshot.get("authority_epoch", 0)),
		"logical_player_id": player_id,
		"player": player_model,
		"hotbar": hotbar_model,
		"external": external_model,
		"external_container_id": resolved_external,
		"selected_item_id": selected_item_id,
		"selected_item": selected_item,
		"world_items": _world_items(),
		"mounts": Array(_snapshot.get("mounts", [])).duplicate(true),
		"ui_transient": transient_overlay.duplicate(true),
	}


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_report() -> Dictionary:
	return {
		"schema": "planet_simulator.m5_item_graph_ui_projection_report.v1",
		"has_snapshot": not _snapshot.is_empty(),
		"revision": _last_revision,
		"checksum": _last_checksum,
		"accept_count": _accept_count,
		"replay_count": _replay_count,
		"rejection_count": _rejection_count,
		"authority_references": 0,
		"domain_references": 0,
		"snapshot_schema": SNAPSHOT_SCHEMA,
	}


func _build_inventory_container(
	player_id: String,
	inventory_record: Dictionary,
	transient_overlay: Dictionary
) -> Dictionary:
	var ids: Array = Array(inventory_record.get("inventory", [])).duplicate()
	return _build_slot_container(
		"inventory/%s" % player_id,
		"Рюкзак",
		ids,
		maxi(PLAYER_CAPACITY, ids.size()),
		-1,
		transient_overlay,
		"player"
	)


func _build_hotbar_container(
	player_id: String,
	inventory_record: Dictionary,
	transient_overlay: Dictionary
) -> Dictionary:
	var ids: Array = Array(inventory_record.get("hotbar", [])).duplicate()
	while ids.size() < HOTBAR_CAPACITY:
		ids.append("")
	if ids.size() > HOTBAR_CAPACITY:
		ids.resize(HOTBAR_CAPACITY)
	return _build_slot_container(
		"hotbar/%s" % player_id,
		"Быстрая панель",
		ids,
		HOTBAR_CAPACITY,
		clampi(int(inventory_record.get("selected_hotbar_index", 0)), 0, HOTBAR_CAPACITY - 1),
		transient_overlay,
		"hotbar"
	)


func _build_external_container(container_id: String, transient_overlay: Dictionary) -> Dictionary:
	var record := _container_by_id(container_id)
	if record.is_empty():
		return {}
	var ids: Array = Array(record.get("slots", [])).duplicate()
	var capacity := maxi(1, int(record.get("capacity", ids.size())))
	return _build_slot_container(
		container_id,
		"Внешний контейнер",
		ids,
		capacity,
		-1,
		transient_overlay,
		"external"
	)


func _build_slot_container(
	container_id: String,
	display_name: String,
	item_ids: Array,
	capacity: int,
	selected_slot_index: int,
	transient_overlay: Dictionary,
	role: String
) -> Dictionary:
	var hidden_ids := PackedStringArray(transient_overlay.get("hidden_item_ids", []))
	var pending_ids := PackedStringArray(transient_overlay.get("pending_item_ids", []))
	var cells: Array[Dictionary] = []
	for slot_index in range(capacity):
		var item_id := String(item_ids[slot_index]) if slot_index < item_ids.size() else ""
		var cell := _build_cell(item_id, container_id, slot_index, slot_index == selected_slot_index)
		cell["ui_transient_hidden"] = not item_id.is_empty() and hidden_ids.has(item_id)
		cell["ui_transient_pending"] = not item_id.is_empty() and pending_ids.has(item_id)
		cells.append(cell)
	return {
		"schema": CONTAINER_VIEW_SCHEMA,
		"container_id": container_id,
		"display_name": display_name,
		"storage_mode": "SLOTS",
		"is_slot_container": true,
		"slot_count": capacity,
		"used_entries": _non_empty_count(item_ids),
		"visual_capacity": capacity,
		"columns": 10 if role == "hotbar" else clampi(mini(capacity, 8), 1, 8),
		"cells": cells,
		"rendered_cell_count": cells.size(),
		"physical_cell_count": cells.size(),
		"projected_total_count": _non_empty_count(item_ids),
		"matched_count": _non_empty_count(item_ids),
		"unfiltered_count": _non_empty_count(item_ids),
		"virtualized": false,
		"page_index": 0,
		"page_count": 1,
		"page_size": capacity,
		"pooling_enabled": true,
		"current_mass_kg": 0.0,
		"maximum_mass_kg": -1.0,
		"current_volume_l": 0.0,
		"maximum_volume_l": -1.0,
		"allow_nested_containers": false,
		"revision": _last_revision,
		"canonical_checksum": _last_checksum,
		"visual_role": role,
	}


func _build_cell(item_id: String, container_id: String, slot_index: int, selected: bool) -> Dictionary:
	var item := _item_by_id(item_id)
	var definition_id := String(item.get("definition_id", ""))
	var metadata: Dictionary = Dictionary(DEFINITION_METADATA.get(definition_id, {}))
	var location: Dictionary = Dictionary(item.get("location", {}))
	return {
		"item_id": item_id,
		"definition_id": definition_id,
		"display_name": String(metadata.get("display_name", "Пусто" if item_id.is_empty() else definition_id)),
		"quantity": int(item.get("quantity", 0)),
		"revision": _last_revision if not item_id.is_empty() else -1,
		"activity_sequence": _last_revision if not item_id.is_empty() else 0,
		"tags": Array(metadata.get("tags", [])).duplicate(),
		"icon_color": Array(metadata.get("icon_color", [])).duplicate(),
		"unit_mass_kg": 0.0,
		"unit_volume_l": 0.0,
		"total_mass_kg": 0.0,
		"total_volume_l": 0.0,
		"max_stack": int(metadata.get("max_stack", 1)),
		"owns_container": definition_id == "item/crate",
		"relation_kind": String(location.get("kind", "")),
		"source_container_id": container_id,
		"source_slot_index": slot_index,
		"target_container_id": container_id,
		"target_slot_index": slot_index,
		"selected": selected,
		"inspected": false,
		"slot_rule": {},
		"projection_match": true,
	}


func _build_item_inspector(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	var item := _item_by_id(item_id)
	if item.is_empty():
		return {}
	var cell := _build_cell(item_id, "", -1, false)
	cell["relation"] = Dictionary(item.get("location", {})).duplicate(true)
	cell["mounted"] = bool(item.get("mounted", false))
	cell["definition_metadata"] = Dictionary(
		DEFINITION_METADATA.get(String(item.get("definition_id", "")), {})
	).duplicate(true)
	return cell


func _world_items() -> Array:
	var out: Array = []
	for item_value in _snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		if String(item.get("location", {}).get("kind", "")) == "WORLD":
			out.append(item.duplicate(true))
	return out


func _item_by_id(item_id: String) -> Dictionary:
	if item_id.is_empty():
		return {}
	for item_value in _snapshot.get("items", []):
		if item_value is Dictionary and String(item_value.get("item_id", "")) == item_id:
			return Dictionary(item_value).duplicate(true)
	return {}


func _container_by_id(container_id: String) -> Dictionary:
	for container_value in _snapshot.get("containers", []):
		if container_value is Dictionary and String(container_value.get("container_id", "")) == container_id:
			return Dictionary(container_value).duplicate(true)
	return {}


func _non_empty_count(values: Array) -> int:
	var count := 0
	for value in values:
		if not String(value).is_empty():
			count += 1
	return count


func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
