extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const StoreScript = preload("res://scripts/simulation/matter/storage/matter_sparse_brick_store.gd")
const JournalScript = preload("res://scripts/simulation/matter/mutation/matter_mutation_journal.gd")

const SCHEMA: String = "planet_simulator.matter_replication_snapshot.v1"
const FIELDS: Array[String] = [
	"schema", "body_id", "body_definition_hash", "grid_profile_hash",
	"authority_owner_id", "authority_epoch", "stream_sequence",
	"store_state_transport", "journal_state_transport",
	"persistent_snapshot_count", "operation_count", "state_hash", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_definition_hash": String(data.get("body_definition_hash", "")),
		"grid_profile_hash": String(data.get("grid_profile_hash", "")),
		"authority_owner_id": String(data.get("authority_owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"stream_sequence": int(data.get("stream_sequence", -1)),
		"store_state_transport": String(data.get("store_state_transport", "")),
		"journal_state_transport": String(data.get("journal_state_transport", "")),
		"persistent_snapshot_count": int(data.get("persistent_snapshot_count", -1)),
		"operation_count": int(data.get("operation_count", -1)),
		"state_hash": String(data.get("state_hash", "")),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_REPLICATION_SNAPSHOT_SCHEMA")
	for field in ["body_id", "authority_owner_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT_ID", {"field": field})
	for field in ["body_definition_hash", "grid_profile_hash", "state_hash"]:
		if not MatterUtilsScript.is_lower_hex_64(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT_HASH", {"field": field})
	for field in ["authority_epoch", "stream_sequence", "persistent_snapshot_count", "operation_count"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["stream_sequence"]) < 0 \
			or int(value["persistent_snapshot_count"]) < 0 or int(value["operation_count"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT_INTEGER")
	for field in ["store_state_transport", "journal_state_transport"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).is_empty():
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_SNAPSHOT_TRANSPORT", {"field": field})
	var store_state: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["store_state_transport"])
	)
	var journal_state: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["journal_state_transport"])
	)
	if not bool(StoreScript.validate_persistence_state(store_state).get("success", false)):
		return MatterUtilsScript.failure("INVALID_REPLICATED_MATTER_STORE_STATE")
	if not bool(JournalScript.validate_persistence_state(journal_state).get("success", false)):
		return MatterUtilsScript.failure("INVALID_REPLICATED_MATTER_JOURNAL_STATE")
	if String(store_state["body_definition_hash"]) != String(value["body_definition_hash"]) \
			or String(store_state["grid_profile_hash"]) != String(value["grid_profile_hash"]):
		return MatterUtilsScript.failure("MATTER_REPLICATION_SNAPSHOT_IDENTITY_MISMATCH")
	if store_state["snapshots"].size() != int(value["persistent_snapshot_count"]) \
			or journal_state["records"].size() != int(value["operation_count"]):
		return MatterUtilsScript.failure("MATTER_REPLICATION_SNAPSHOT_COUNT_MISMATCH")
	if int(value["operation_count"]) != int(value["stream_sequence"]):
		return MatterUtilsScript.failure("MATTER_REPLICATION_SNAPSHOT_STREAM_JOURNAL_MISMATCH")
	for raw_snapshot in store_state["snapshots"]:
		if int(Dictionary(raw_snapshot).get("state_revision", 0)) < 1:
			return MatterUtilsScript.failure("PROCEDURAL_BRICK_REPLICATED")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_replication_snapshot")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)
