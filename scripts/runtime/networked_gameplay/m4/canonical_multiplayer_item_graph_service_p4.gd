extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p3.gd"

# V0-P4 server-only material consumption seam.
#
# This remains the same canonical M4 Item Graph owner used by P3 mining. The
# methods below are intentionally not exposed through _execute(); only trusted
# server composition may call them. They bind a material debit to the exact
# allocator snapshot and Construction transaction checksum.

const NetworkUtilsP4 = preload("res://scripts/network/contracts/network_contract_utils.gd")

const TRUSTED_CONSTRUCTION_CONSUME_COMMAND_TYPE := "server.construction.consume"
const R1_DEFINITION_ID := "item/ore"
const ALLOCATION_FIELDS: Array[String] = [
	"item_id",
	"definition_id",
	"quantity",
	"slot_index",
	"available_quantity",
]


func preflight_server_construction_consume(
	operation_id: String,
	logical_player_id: String,
	allocations: Array,
	expected_revision: int,
	expected_tick: int,
	expected_snapshot_checksum: String,
	transaction_plan_checksum: String
) -> Dictionary:
	if not _configured:
		return _failure("ITEM_GRAPH_NOT_CONFIGURED")
	var normalized := _normalize_construction_consume_request(
		operation_id,
		logical_player_id,
		allocations,
		expected_revision,
		expected_tick,
		expected_snapshot_checksum,
		transaction_plan_checksum
	)
	if not bool(normalized.get("success", false)):
		return normalized
	var details: Dictionary = Dictionary(normalized.get("details", {}))
	var player_id := String(details.get("logical_player_id", ""))
	var op := String(details.get("operation_id", ""))
	var payload: Dictionary = Dictionary(details.get("payload", {}))
	var replay_lookup := lookup_replay(
		player_id,
		_authority_epoch,
		op,
		TRUSTED_CONSTRUCTION_CONSUME_COMMAND_TYPE,
		payload
	)
	if bool(replay_lookup.get("found", false)):
		return Dictionary(replay_lookup.get("result", {})).duplicate(true)

	var snapshot: Dictionary = create_snapshot()
	if (
		int(snapshot.get("revision", -1)) != expected_revision
		or int(snapshot.get("tick", -1)) != expected_tick
		or String(snapshot.get("checksum", "")) != expected_snapshot_checksum
	):
		return _failure("CONSTRUCTION_MATERIAL_SNAPSHOT_STALE")
	if not _inventories.has(player_id):
		return _failure("CONSTRUCTION_MATERIAL_PLAYER_INVENTORY_NOT_FOUND")
	var inventory: Dictionary = _inventories[player_id]
	var membership: Array = Array(inventory.get("inventory", []))
	var total_quantity := 0
	for allocation_value in details.get("allocations", []):
		var allocation: Dictionary = allocation_value
		var item_id := String(allocation.get("item_id", ""))
		if not _items.has(item_id) or item_id not in membership:
			return _failure("CONSTRUCTION_MATERIAL_ITEM_NOT_OWNED")
		var item: Dictionary = _items[item_id]
		var location_value = item.get("location", {})
		if not location_value is Dictionary:
			return _failure("CONSTRUCTION_MATERIAL_ITEM_NOT_OWNED")
		var location: Dictionary = location_value
		if (
			String(item.get("definition_id", "")).strip_edges().to_lower() != R1_DEFINITION_ID
			or String(location.get("kind", "")) != "INVENTORY"
			or String(location.get("player_id", "")).strip_edges().to_lower() != player_id
			or int(location.get("slot_index", -1)) != int(allocation.get("slot_index", -2))
			or int(item.get("quantity", 0)) != int(allocation.get("available_quantity", -1))
			or int(allocation.get("quantity", 0)) > int(item.get("quantity", 0))
		):
			return _failure("CONSTRUCTION_MATERIAL_PRECONDITION_MISMATCH")
		total_quantity += int(allocation.get("quantity", 0))
	return _success({
		"logical_player_id": player_id,
		"consumed_quantity": total_quantity,
		"transaction_plan_checksum": transaction_plan_checksum,
		"snapshot_revision": expected_revision,
		"snapshot_tick": expected_tick,
		"snapshot_checksum": expected_snapshot_checksum,
		"replay": false,
	})


func apply_server_construction_consume(
	operation_id: String,
	logical_player_id: String,
	allocations: Array,
	expected_revision: int,
	expected_tick: int,
	expected_snapshot_checksum: String,
	transaction_plan_checksum: String
) -> Dictionary:
	if not _configured:
		return _failure("ITEM_GRAPH_NOT_CONFIGURED")
	var normalized := _normalize_construction_consume_request(
		operation_id,
		logical_player_id,
		allocations,
		expected_revision,
		expected_tick,
		expected_snapshot_checksum,
		transaction_plan_checksum
	)
	if not bool(normalized.get("success", false)):
		return normalized
	var normalized_details: Dictionary = Dictionary(normalized.get("details", {}))
	var player_id := String(normalized_details.get("logical_player_id", ""))
	var op := String(normalized_details.get("operation_id", ""))
	var payload: Dictionary = Dictionary(normalized_details.get("payload", {}))
	var replay_lookup := lookup_replay(
		player_id,
		_authority_epoch,
		op,
		TRUSTED_CONSTRUCTION_CONSUME_COMMAND_TYPE,
		payload
	)
	if bool(replay_lookup.get("found", false)):
		return Dictionary(replay_lookup.get("result", {})).duplicate(true)

	var preflight := preflight_server_construction_consume(
		op,
		player_id,
		Array(normalized_details.get("allocations", [])),
		expected_revision,
		expected_tick,
		expected_snapshot_checksum,
		transaction_plan_checksum
	)
	if not bool(preflight.get("success", false)):
		return preflight

	var deleted_item_ids: Array[String] = []
	var updated_items: Array = []
	var consumed_quantity := 0
	for allocation_value in normalized_details.get("allocations", []):
		var allocation: Dictionary = allocation_value
		var item_id := String(allocation.get("item_id", ""))
		var amount := int(allocation.get("quantity", 0))
		var item: Dictionary = _items[item_id]
		var before_quantity := int(item.get("quantity", 0))
		var remaining := before_quantity - amount
		consumed_quantity += amount
		if remaining == 0:
			_remove_from_inventory(player_id, item_id)
			_items.erase(item_id)
			deleted_item_ids.append(item_id)
		else:
			item["quantity"] = remaining
			_items[item_id] = item
			updated_items.append({
				"item_id": item_id,
				"before_quantity": before_quantity,
				"after_quantity": remaining,
			})
	_revision += 1
	_tick += 1
	deleted_item_ids.sort()
	updated_items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("item_id", "")) < String(right.get("item_id", ""))
	)
	var result := _success({
		"logical_player_id": player_id,
		"consumed_quantity": consumed_quantity,
		"deleted_item_ids": deleted_item_ids,
		"updated_items": updated_items,
		"transaction_plan_checksum": transaction_plan_checksum,
	})
	result["snapshot"] = create_snapshot()
	result["revision"] = _revision
	result["tick"] = _tick
	result["replay"] = false
	var fingerprint := NetworkUtilsP4.payload_hash({
		"player": player_id,
		"epoch": _authority_epoch,
		"type": TRUSTED_CONSTRUCTION_CONSUME_COMMAND_TYPE,
		"payload": payload,
	})
	_ledger[op] = {
		"fingerprint": fingerprint,
		"result": result.duplicate(true),
	}
	return result


func _normalize_construction_consume_request(
	operation_id: String,
	logical_player_id: String,
	allocations: Array,
	expected_revision: int,
	expected_tick: int,
	expected_snapshot_checksum: String,
	transaction_plan_checksum: String
) -> Dictionary:
	var op := operation_id.strip_edges()
	var player_id := logical_player_id.strip_edges().to_lower()
	var snapshot_checksum := expected_snapshot_checksum.strip_edges().to_lower()
	var plan_checksum := transaction_plan_checksum.strip_edges().to_lower()
	if (
		not op.begins_with("operation/")
		or op.length() <= 10
		or player_id.is_empty()
		or expected_revision < 0
		or expected_tick < 0
		or snapshot_checksum.length() != 64
		or plan_checksum.length() != 64
		or allocations.is_empty()
	):
		return _failure("INVALID_SERVER_CONSTRUCTION_CONSUME")
	var canonical_allocations: Array = []
	var seen: Dictionary = {}
	var previous_slot := -1
	var previous_item_id := ""
	for allocation_value in allocations:
		if not allocation_value is Dictionary:
			return _failure("INVALID_SERVER_CONSTRUCTION_ALLOCATION")
		var allocation: Dictionary = allocation_value
		if allocation.keys().size() != ALLOCATION_FIELDS.size():
			return _failure("INVALID_SERVER_CONSTRUCTION_ALLOCATION")
		for field in ALLOCATION_FIELDS:
			if not allocation.has(field):
				return _failure("INVALID_SERVER_CONSTRUCTION_ALLOCATION")
		var item_id := String(allocation.get("item_id", "")).strip_edges().to_lower()
		var definition_id := String(allocation.get("definition_id", "")).strip_edges().to_lower()
		var quantity := int(allocation.get("quantity", 0))
		var slot_index := int(allocation.get("slot_index", -1))
		var available_quantity := int(allocation.get("available_quantity", 0))
		if (
			not item_id.begins_with("item/")
			or item_id.length() <= 5
			or definition_id != R1_DEFINITION_ID
			or quantity < 1
			or available_quantity < quantity
			or slot_index < 0
			or seen.has(item_id)
		):
			return _failure("INVALID_SERVER_CONSTRUCTION_ALLOCATION")
		if previous_slot > slot_index or (previous_slot == slot_index and not previous_item_id.is_empty() and previous_item_id > item_id):
			return _failure("SERVER_CONSTRUCTION_ALLOCATIONS_NOT_CANONICAL")
		seen[item_id] = true
		previous_slot = slot_index
		previous_item_id = item_id
		canonical_allocations.append({
			"item_id": item_id,
			"definition_id": definition_id,
			"quantity": quantity,
			"slot_index": slot_index,
			"available_quantity": available_quantity,
		})
	var payload := {
		"allocations": canonical_allocations,
		"expected_revision": expected_revision,
		"expected_tick": expected_tick,
		"expected_snapshot_checksum": snapshot_checksum,
		"transaction_plan_checksum": plan_checksum,
	}
	return _success({
		"operation_id": op,
		"logical_player_id": player_id,
		"allocations": canonical_allocations,
		"payload": payload,
	})
