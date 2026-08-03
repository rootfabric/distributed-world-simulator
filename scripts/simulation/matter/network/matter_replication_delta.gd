extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")

const SCHEMA: String = "planet_simulator.matter_replication_delta.v1"
const FIELDS: Array[String] = [
	"schema", "body_id", "authority_owner_id", "authority_epoch",
	"previous_stream_sequence", "stream_sequence", "operation_id",
	"request_transport", "result_transport", "snapshot_transports",
	"base_state_hash", "target_state_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var snapshot_transports: Array = Array(data.get("snapshot_transports", [])).duplicate()
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"authority_owner_id": String(data.get("authority_owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"previous_stream_sequence": int(data.get("previous_stream_sequence", -1)),
		"stream_sequence": int(data.get("stream_sequence", 0)),
		"operation_id": String(data.get("operation_id", "")).strip_edges().to_lower(),
		"request_transport": String(data.get("request_transport", "")),
		"result_transport": String(data.get("result_transport", "")),
		"snapshot_transports": snapshot_transports,
		"base_state_hash": String(data.get("base_state_hash", "")),
		"target_state_hash": String(data.get("target_state_hash", "")),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_REPLICATION_DELTA_SCHEMA")
	for field in ["body_id", "authority_owner_id", "operation_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_DELTA_ID", {"field": field})
	if not MatterUtilsScript.is_json_integer(value.get("authority_epoch")) \
			or int(value["authority_epoch"]) < 1:
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_AUTHORITY_EPOCH")
	if not MatterUtilsScript.is_json_integer(value.get("previous_stream_sequence")) \
			or not MatterUtilsScript.is_json_integer(value.get("stream_sequence")):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SEQUENCE")
	var previous_sequence: int = int(value["previous_stream_sequence"])
	var sequence: int = int(value["stream_sequence"])
	if previous_sequence < 0 or sequence < 1 or sequence != previous_sequence + 1:
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SEQUENCE")
	if typeof(value.get("request_transport")) != TYPE_STRING \
			or String(value["request_transport"]).is_empty() \
			or typeof(value.get("result_transport")) != TYPE_STRING \
			or String(value["result_transport"]).is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_DELTA_TRANSPORT")
	if typeof(value.get("snapshot_transports")) != TYPE_ARRAY:
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT_TRANSPORTS")
	if not MatterUtilsScript.is_lower_hex_64(value.get("base_state_hash")) \
			or not MatterUtilsScript.is_lower_hex_64(value.get("target_state_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_STATE_HASH")
	var request_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["request_transport"])
	)
	var result_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["result_transport"])
	)
	var request: Dictionary = PersistenceCodecScript.rehydrate_request(request_raw)
	var result: Dictionary = PersistenceCodecScript.rehydrate_result(result_raw)
	if request.is_empty() or result.is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_OPERATION_TRANSPORT")
	if String(request["operation_id"]) != String(value["operation_id"]) \
			or String(result["operation_id"]) != String(value["operation_id"]) \
			or String(request["body_id"]) != String(value["body_id"]):
		return MatterUtilsScript.failure("MATTER_REPLICATION_OPERATION_IDENTITY_MISMATCH")
	var snapshots_by_address_id: Dictionary = {}
	var previous_snapshot_address_id: String = ""
	for index in range(value["snapshot_transports"].size()):
		var raw_transport = value["snapshot_transports"][index]
		if typeof(raw_transport) != TYPE_STRING or String(raw_transport).is_empty():
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT_TRANSPORT", {"index": index})
		var snapshot_raw: Dictionary = PersistenceCodecScript.decode_persistence_json(String(raw_transport))
		var snapshot: Dictionary = PersistenceCodecScript.rehydrate_snapshot(snapshot_raw)
		if snapshot.is_empty() or int(snapshot["state_revision"]) < 1:
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT", {"index": index})
		var address_id: String = String(snapshot["address"]["address_id"])
		if snapshots_by_address_id.has(address_id):
			return MatterUtilsScript.failure("DUPLICATE_MATTER_REPLICATION_SNAPSHOT")
		if not previous_snapshot_address_id.is_empty() and address_id <= previous_snapshot_address_id:
			return MatterUtilsScript.failure("MATTER_REPLICATION_SNAPSHOTS_NOT_SORTED")
		snapshots_by_address_id[address_id] = snapshot
		previous_snapshot_address_id = address_id
	if String(result["status"]) == "REJECTED":
		if not snapshots_by_address_id.is_empty() or not result["changed_bricks"].is_empty():
			return MatterUtilsScript.failure("REJECTED_MATTER_REPLICATION_CHANGED_STATE")
	else:
		if result["changed_bricks"].size() != snapshots_by_address_id.size():
			return MatterUtilsScript.failure("MATTER_REPLICATION_CHANGED_BRICK_COUNT_MISMATCH")
		for changed_value in result["changed_bricks"]:
			var changed: Dictionary = changed_value
			var address_id: String = String(changed["address"]["address_id"])
			if not snapshots_by_address_id.has(address_id):
				return MatterUtilsScript.failure("MATTER_REPLICATION_CHANGED_BRICK_MISSING")
			var snapshot: Dictionary = snapshots_by_address_id[address_id]
			if int(changed["new_revision"]) != int(changed["previous_revision"]) + 1 \
					or int(snapshot["state_revision"]) != int(changed["new_revision"]) \
					or String(snapshot["checksum"]) != String(changed["snapshot_checksum"]):
				return MatterUtilsScript.failure("MATTER_REPLICATION_CHANGED_BRICK_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_replication_delta")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)
