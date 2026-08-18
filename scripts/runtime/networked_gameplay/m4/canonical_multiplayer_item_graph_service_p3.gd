extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p2.gd"

# V0-P3 trusted-output adapter.
# The exact P2 R8 recovery/read implementation remains byte-identical in the
# compatibility parent. This current canonical path adds only a server-only
# output seam used by ResourceMining; it is deliberately absent from _execute().

const NetworkUtilsP3 = preload("res://scripts/network/contracts/network_contract_utils.gd")
const TRUSTED_SERVER_OUTPUT_COMMAND_TYPE := "server.output"


func preflight_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("ITEM_GRAPH_NOT_CONFIGURED")
	var op := operation_id.strip_edges()
	var player_id := logical_player_id.strip_edges().to_lower()
	var definition := definition_id.strip_edges().to_lower()
	var source := source_id.strip_edges().to_lower()
	if op.is_empty() or player_id.is_empty() or definition.is_empty() or quantity < 1:
		return _failure("INVALID_SERVER_OUTPUT")
	if not _inventories.has(player_id):
		return _failure("SERVER_OUTPUT_TARGET_NOT_FOUND")
	var payload := _trusted_server_output_payload(definition, quantity, source)
	var replay_lookup := lookup_replay(
		player_id,
		_authority_epoch,
		op,
		TRUSTED_SERVER_OUTPUT_COMMAND_TYPE,
		payload
	)
	if bool(replay_lookup.get("found", false)):
		var replay_result: Dictionary = Dictionary(replay_lookup.get("result", {})).duplicate(true)
		if not bool(replay_result.get("success", false)):
			return replay_result
		var replay_details: Dictionary = Dictionary(replay_result.get("details", {}))
		return _success({
			"replay": true,
			"output_item_id": String(replay_details.get("output_item_id", replay_details.get("item_id", ""))),
			"target_slot_index": int(replay_details.get("target_slot_index", -1)),
		})
	var output_item_id := _trusted_server_output_item_id(op, player_id, definition, source)
	if _items.has(output_item_id):
		return _failure("SERVER_OUTPUT_ITEM_ID_COLLISION")
	var target_slot_index := _first_free_inventory_slot(player_id)
	if target_slot_index < 0:
		return _failure("CONTAINER_FULL")
	return _success({
		"replay": false,
		"output_item_id": output_item_id,
		"target_slot_index": target_slot_index,
	})


func apply_server_output(
	operation_id: String,
	logical_player_id: String,
	definition_id: String,
	quantity: int,
	source_id: String = ""
) -> Dictionary:
	if not _configured:
		return _failure("ITEM_GRAPH_NOT_CONFIGURED")
	var op := operation_id.strip_edges()
	var player_id := logical_player_id.strip_edges().to_lower()
	var definition := definition_id.strip_edges().to_lower()
	var source := source_id.strip_edges().to_lower()
	if op.is_empty() or player_id.is_empty() or definition.is_empty() or quantity < 1:
		return _failure("INVALID_SERVER_OUTPUT")
	var payload := _trusted_server_output_payload(definition, quantity, source)
	var replay_lookup := lookup_replay(
		player_id,
		_authority_epoch,
		op,
		TRUSTED_SERVER_OUTPUT_COMMAND_TYPE,
		payload
	)
	if bool(replay_lookup.get("found", false)):
		return Dictionary(replay_lookup.get("result", {})).duplicate(true)
	var preflight := preflight_server_output(op, player_id, definition, quantity, source)
	if not bool(preflight.get("success", false)):
		return preflight
	var details: Dictionary = Dictionary(preflight.get("details", {}))
	var output_item_id := String(details.get("output_item_id", ""))
	var target_slot_index := int(details.get("target_slot_index", -1))
	_items[output_item_id] = {
		"item_id": output_item_id,
		"definition_id": definition,
		"quantity": quantity,
		"location": {
			"kind": "INVENTORY",
			"player_id": player_id,
			"slot_index": target_slot_index,
		},
		"mounted": false,
	}
	_add_to_inventory(player_id, output_item_id)
	_revision += 1
	_tick += 1
	var result := _success({
		"item_id": output_item_id,
		"output_item_id": output_item_id,
		"definition_id": definition,
		"quantity": quantity,
		"target_slot_index": target_slot_index,
		"source_id": source,
	})
	result["snapshot"] = create_snapshot()
	result["revision"] = _revision
	result["tick"] = _tick
	result["replay"] = false
	var fingerprint := NetworkUtilsP3.payload_hash({
		"player": player_id,
		"epoch": _authority_epoch,
		"type": TRUSTED_SERVER_OUTPUT_COMMAND_TYPE,
		"payload": payload,
	})
	_ledger[op] = {
		"fingerprint": fingerprint,
		"result": result.duplicate(true),
	}
	return result


func _trusted_server_output_payload(
	definition_id: String,
	quantity: int,
	source_id: String
) -> Dictionary:
	return {
		"definition_id": definition_id,
		"quantity": quantity,
		"source_id": source_id,
	}


func _trusted_server_output_item_id(
	operation_id: String,
	player_id: String,
	definition_id: String,
	source_id: String
) -> String:
	var identity := NetworkUtilsP3.payload_hash({
		"operation_id": operation_id,
		"player_id": player_id,
		"definition_id": definition_id,
		"source_id": source_id,
	})
	return "item/server-output/%s" % identity.left(32)
