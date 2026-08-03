extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const DeltaScript = preload("res://scripts/simulation/matter/network/matter_replication_delta.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/network/matter_replication_snapshot.gd")

const SCHEMA: String = "planet_simulator.matter_replication_frame.v1"
const KINDS: Array[String] = ["MUTATION_DELTA", "STATE_SNAPSHOT"]
const FIELDS: Array[String] = [
	"schema", "frame_id", "frame_kind", "body_id", "authority_owner_id",
	"authority_epoch", "session_id", "stream_sequence", "payload_schema",
	"payload_transport", "checksum",
]


static func create(data: Dictionary) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"frame_id": String(data.get("frame_id", "")).strip_edges().to_lower(),
		"frame_kind": String(data.get("frame_kind", "")).strip_edges().to_upper(),
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"authority_owner_id": String(data.get("authority_owner_id", "")).strip_edges().to_lower(),
		"authority_epoch": int(data.get("authority_epoch", 0)),
		"session_id": String(data.get("session_id", "")).strip_edges().to_lower(),
		"stream_sequence": int(data.get("stream_sequence", -1)),
		"payload_schema": String(data.get("payload_schema", "")).strip_edges().to_lower(),
		"payload_transport": String(data.get("payload_transport", "")),
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_REPLICATION_FRAME_SCHEMA")
	for field in ["frame_id", "body_id", "authority_owner_id", "session_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_FRAME_ID", {"field": field})
	if String(value.get("frame_kind", "")) not in KINDS:
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_FRAME_KIND")
	if not MatterUtilsScript.is_json_integer(value.get("authority_epoch")) \
			or int(value["authority_epoch"]) < 1 \
			or not MatterUtilsScript.is_json_integer(value.get("stream_sequence")) \
			or int(value["stream_sequence"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_FRAME_SEQUENCE")
	if typeof(value.get("payload_transport")) != TYPE_STRING \
			or String(value["payload_transport"]).is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_FRAME_TRANSPORT")
	var expected_schema: String = DeltaScript.SCHEMA \
		if String(value["frame_kind"]) == "MUTATION_DELTA" else SnapshotScript.SCHEMA
	if String(value.get("payload_schema", "")) != expected_schema:
		return MatterUtilsScript.failure("MATTER_REPLICATION_FRAME_PAYLOAD_SCHEMA_MISMATCH")
	var payload: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["payload_transport"])
	)
	var payload_validation: Dictionary = DeltaScript.validate(payload) \
		if expected_schema == DeltaScript.SCHEMA else SnapshotScript.validate(payload)
	if not bool(payload_validation.get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_REPLICATION_FRAME_PAYLOAD", {
			"cause": payload_validation,
		})
	if String(payload["body_id"]) != String(value["body_id"]) \
			or String(payload["authority_owner_id"]) != String(value["authority_owner_id"]) \
			or int(payload["authority_epoch"]) != int(value["authority_epoch"]) \
			or int(payload["stream_sequence"]) != int(value["stream_sequence"]):
		return MatterUtilsScript.failure("MATTER_REPLICATION_FRAME_IDENTITY_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_replication_frame")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func decode_payload(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return PersistenceCodecScript.decode_persistence_json(String(value["payload_transport"]))
