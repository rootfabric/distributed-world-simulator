extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_replication_sync_request.v1"
const FIELDS: Array[String] = [
	"schema", "client_id", "session_id", "authority_epoch",
	"known_stream_sequence", "known_state_hash", "checksum",
]


static func create(
	client_id: String,
	session_id: String,
	authority_epoch: int,
	known_stream_sequence: int,
	known_state_hash: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"client_id": client_id.strip_edges().to_lower(),
		"session_id": session_id.strip_edges().to_lower(),
		"authority_epoch": authority_epoch,
		"known_stream_sequence": known_stream_sequence,
		"known_state_hash": known_state_hash,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_SYNC_REQUEST_SCHEMA")
	for field in ["client_id", "session_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_SYNC_REQUEST_ID", {"field": field})
	if not MatterUtilsScript.is_json_integer(value.get("authority_epoch")) \
			or int(value["authority_epoch"]) < 1 \
			or not MatterUtilsScript.is_json_integer(value.get("known_stream_sequence")) \
			or int(value["known_stream_sequence"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_SYNC_REQUEST_SEQUENCE")
	if not MatterUtilsScript.is_lower_hex_64(value.get("known_state_hash")):
		return MatterUtilsScript.failure("INVALID_MATTER_SYNC_REQUEST_STATE_HASH")
	return MatterUtilsScript.validate_checksum(value)
