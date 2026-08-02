extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const BrickSnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")

const SCHEMA: String = "planet_simulator.matter_interest_delta.v1"
const FIELDS: Array[String] = [
	"schema", "body_id", "authority_owner_id", "authority_epoch",
	"subscription_id", "interest_revision", "previous_region_sequence",
	"region_sequence", "source_global_stream_sequence", "operation_id",
	"result_transport", "snapshot_transports", "base_projection_hash",
	"target_projection_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"authority_owner_id": String(data.get("authority_owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"subscription_id": String(data.get("subscription_id", "")).strip_edges().to_lower(),
		"interest_revision": int(data.get("interest_revision", 0)),
		"previous_region_sequence": int(data.get("previous_region_sequence", -1)),
		"region_sequence": int(data.get("region_sequence", -1)),
		"source_global_stream_sequence": int(data.get("source_global_stream_sequence", -1)),
		"operation_id": String(data.get("operation_id", "")).strip_edges().to_lower(),
		"result_transport": String(data.get("result_transport", "")),
		"snapshot_transports": Array(data.get("snapshot_transports", [])).duplicate(),
		"base_projection_hash": String(data.get("base_projection_hash", "")),
		"target_projection_hash": String(data.get("target_projection_hash", "")),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_INTEREST_DELTA_SCHEMA")
	for field in ["body_id", "authority_owner_id", "subscription_id", "operation_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_ID", {"field": field})
	for field in ["authority_epoch", "interest_revision", "previous_region_sequence", "region_sequence", "source_global_stream_sequence"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["interest_revision"]) < 1 \
			or int(value["previous_region_sequence"]) < 0 \
			or int(value["region_sequence"]) != int(value["previous_region_sequence"]) + 1 \
			or int(value["source_global_stream_sequence"]) < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_SEQUENCE")
	if not MatterUtilsScript.is_lower_hex_64(value.get("base_projection_hash")) \
			or not MatterUtilsScript.is_lower_hex_64(value.get("target_projection_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_HASH")
	if typeof(value.get("result_transport")) != TYPE_STRING \
			or String(value["result_transport"]).is_empty() \
			or typeof(value.get("snapshot_transports")) != TYPE_ARRAY \
			or value["snapshot_transports"].is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_TRANSPORT")
	var raw_result: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["result_transport"])
	)
	var result: Dictionary = PersistenceCodecScript.rehydrate_result(raw_result)
	if result.is_empty() or not bool(ResultScript.validate(result).get("success", false)) \
			or String(result["status"]) != "COMMITTED" \
			or String(result["operation_id"]) != String(value["operation_id"]):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_RESULT")
	var changed_by_address_id: Dictionary = {}
	for changed_value in result["changed_bricks"]:
		var changed: Dictionary = changed_value
		changed_by_address_id[String(changed["address"]["address_id"])] = changed
	var previous_address_id: String = ""
	for index in range(value["snapshot_transports"].size()):
		var raw_transport = value["snapshot_transports"][index]
		if typeof(raw_transport) != TYPE_STRING or String(raw_transport).is_empty():
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_BRICK_TRANSPORT", {"index": index})
		var raw_snapshot: Dictionary = PersistenceCodecScript.decode_persistence_json(String(raw_transport))
		var snapshot: Dictionary = PersistenceCodecScript.rehydrate_snapshot(raw_snapshot)
		if snapshot.is_empty() or not bool(BrickSnapshotScript.validate(snapshot).get("success", false)) \
				or int(snapshot["state_revision"]) < 1:
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_DELTA_BRICK", {"index": index})
		var address_id: String = String(snapshot["address"]["address_id"])
		if not changed_by_address_id.has(address_id):
			return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_BRICK_NOT_CHANGED")
		if not previous_address_id.is_empty() and address_id <= previous_address_id:
			return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_BRICKS_NOT_SORTED")
		var changed: Dictionary = changed_by_address_id[address_id]
		if int(snapshot["state_revision"]) != int(changed["new_revision"]) \
				or String(snapshot["checksum"]) != String(changed["snapshot_checksum"]):
			return MatterUtilsScript.failure("MATTER_INTEREST_DELTA_BRICK_REVISION_MISMATCH")
		previous_address_id = address_id
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_interest_delta")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)
