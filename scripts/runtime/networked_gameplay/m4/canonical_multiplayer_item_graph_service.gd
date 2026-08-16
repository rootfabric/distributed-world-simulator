extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p1.gd"

# V0-P2 canonical read/recovery adapter plus the bounded P3 trusted-output seam.
#
# The P1 slot/transfer implementation is preserved byte-for-byte in the
# compatibility parent. P2 keeps snapshots/exports pure and owns explicit
# restore migration. P3 adds a server-only output method here because this class
# remains the sole canonical Item Graph owner. The trusted method is deliberately
# absent from _execute(), so an ITEM_COMMAND cannot invoke it by command_type.

const NetworkUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BaseItemGraphValidator = preload(
	"res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd"
)
const CURRENT_SNAPSHOT_SCHEMA := "planet_simulator.canonical_multiplayer_item_graph_snapshot.v1"
const DURABLE_VALIDATION_AUTHORITY_ID := "authority/v0-p2/durable-validation"
const TRUSTED_SERVER_OUTPUT_COMMAND_TYPE := "server.output"


func create_snapshot() -> Dictionary:
	var body: Dictionary = {
		"schema": CURRENT_SNAPSHOT_SCHEMA,
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"revision": _revision,
		"tick": _tick,
		"items": _sorted_values(_items),
		"inventories": _sorted_map(_inventories),
		"containers": _sorted_values(_containers),
		"mounts": _sorted_values(_mounts),
		"open_containers": _sorted_map(_open_containers),
	}
	if _sandbox_mode:
		body["playable_sandbox"] = true
	body["checksum"] = NetworkUtils.payload_hash(body)
	return body


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
	var fingerprint := NetworkUtils.payload_hash({
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


func validate_durable_state(value: Dictionary) -> Dictionary:
	var snapshot_value = value.get("snapshot", null)
	if not snapshot_value is Dictionary:
		return super.validate_durable_state(value)
	var snapshot: Dictionary = snapshot_value
	var validator = BaseItemGraphValidator.new()
	var setup_result: Dictionary = validator.setup(
		DURABLE_VALIDATION_AUTHORITY_ID,
		1,
		{"playable_sandbox": bool(snapshot.get("playable_sandbox", false))}
	)
	if not bool(setup_result.get("success", false)):
		return _failure("ITEM_GRAPH_DURABLE_VALIDATION_CONTEXT_FAILED")
	return validator.validate_durable_state(value)


func restore_durable_state(value: Dictionary) -> Dictionary:
	var restored: Dictionary = super.restore_durable_state(value)
	if not bool(restored.get("success", false)):
		return restored

	var before_revision := _revision
	var before_tick := _tick
	var before_snapshot: Dictionary = create_snapshot()

	# This is the one explicit compatibility migration boundary. Canonical read
	# APIs must never call normalization after this point.
	_normalize_slot_locations()
	var normalized_snapshot: Dictionary = create_snapshot()
	var migrated := (
		String(before_snapshot.get("checksum", ""))
		!= String(normalized_snapshot.get("checksum", ""))
	)
	var migration_summary := _build_slot_migration_summary(
		before_snapshot,
		normalized_snapshot
	)

	if migrated:
		_revision += 1
		_tick += 1

	var final_snapshot: Dictionary = create_snapshot()
	var restored_details: Dictionary = Dictionary(restored.get("details", {})).duplicate(true)
	restored_details["revision"] = _revision
	restored_details["tick"] = _tick
	restored_details["snapshot_checksum"] = String(final_snapshot.get("checksum", ""))
	restored_details["slot_migration"] = {
		"migrated": migrated,
		"before_revision": before_revision,
		"before_tick": before_tick,
		"after_revision": _revision,
		"after_tick": _tick,
		"before_checksum": String(before_snapshot.get("checksum", "")),
		"normalized_checksum": String(normalized_snapshot.get("checksum", "")),
		"final_checksum": String(final_snapshot.get("checksum", "")),
		"changed_item_count": int(migration_summary.get("changed_item_count", 0)),
		"changed_owner_count": int(migration_summary.get("changed_owner_count", 0)),
	}
	restored["details"] = restored_details
	return restored


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
	var identity := NetworkUtils.payload_hash({
		"operation_id": operation_id,
		"player_id": player_id,
		"definition_id": definition_id,
		"source_id": source_id,
	})
	return "item/server-output/%s" % identity.left(32)


func _build_slot_migration_summary(
	before_snapshot: Dictionary,
	after_snapshot: Dictionary
) -> Dictionary:
	var before_items := _snapshot_items_by_id(before_snapshot)
	var after_items := _snapshot_items_by_id(after_snapshot)
	var changed_items := 0
	var changed_owners: Dictionary = {}
	for item_id_value in after_items.keys():
		var item_id := String(item_id_value)
		if not before_items.has(item_id):
			continue
		var before_location: Dictionary = Dictionary(
			Dictionary(before_items[item_id]).get("location", {})
		)
		var after_location: Dictionary = Dictionary(
			Dictionary(after_items[item_id]).get("location", {})
		)
		if before_location == after_location:
			continue
		changed_items += 1
		var owner_key := _slot_owner_key(after_location)
		if owner_key.is_empty():
			owner_key = _slot_owner_key(before_location)
		if not owner_key.is_empty():
			changed_owners[owner_key] = true
	return {
		"changed_item_count": changed_items,
		"changed_owner_count": changed_owners.size(),
	}


func _snapshot_items_by_id(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item_value in snapshot.get("items", []):
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		var item_id := String(item.get("item_id", ""))
		if not item_id.is_empty():
			result[item_id] = item.duplicate(true)
	return result


func _slot_owner_key(location: Dictionary) -> String:
	match String(location.get("kind", "")):
		"INVENTORY":
			var player_id := String(location.get("player_id", ""))
			return "inventory/%s" % player_id if not player_id.is_empty() else ""
		"CONTAINER":
			return String(location.get("container_id", ""))
	return ""
