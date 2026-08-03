extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const PersistenceCodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const DeltaScript = preload("res://scripts/simulation/matter/interest/matter_interest_delta.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/interest/matter_interest_snapshot.gd")

const SCHEMA: String = "planet_simulator.matter_interest_frame.v1"
const KINDS: Array[String] = ["REGION_DELTA", "REGION_SNAPSHOT"]
const FIELDS: Array[String] = [
	"schema", "frame_id", "frame_kind", "body_id", "authority_owner_id",
	"authority_epoch", "session_id", "subscription_id", "interest_revision",
	"region_sequence", "source_global_stream_sequence", "payload_schema",
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
		"subscription_id": String(data.get("subscription_id", "")).strip_edges().to_lower(),
		"interest_revision": int(data.get("interest_revision", 0)),
		"region_sequence": int(data.get("region_sequence", -1)),
		"source_global_stream_sequence": int(data.get("source_global_stream_sequence", -1)),
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
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_INTEREST_FRAME_SCHEMA")
	for field in ["frame_id", "body_id", "authority_owner_id", "session_id", "subscription_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_FRAME_ID", {"field": field})
	if String(value.get("frame_kind", "")) not in KINDS:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_FRAME_KIND")
	for field in ["authority_epoch", "interest_revision", "region_sequence", "source_global_stream_sequence"]:
		if not MatterUtilsScript.is_json_integer(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_FRAME_INTEGER", {"field": field})
	if int(value["authority_epoch"]) < 1 or int(value["interest_revision"]) < 1 \
			or int(value["region_sequence"]) < 0 or int(value["source_global_stream_sequence"]) < 0:
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_FRAME_SEQUENCE")
	if typeof(value.get("payload_transport")) != TYPE_STRING \
			or String(value["payload_transport"]).is_empty():
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_FRAME_TRANSPORT")
	var expected_schema: String = DeltaScript.SCHEMA \
		if String(value["frame_kind"]) == "REGION_DELTA" else SnapshotScript.SCHEMA
	if String(value.get("payload_schema", "")) != expected_schema:
		return MatterUtilsScript.failure("MATTER_INTEREST_FRAME_PAYLOAD_SCHEMA_MISMATCH")
	var payload: Dictionary = PersistenceCodecScript.decode_persistence_json(
		String(value["payload_transport"])
	)
	var payload_validation: Dictionary = DeltaScript.validate(payload) \
		if expected_schema == DeltaScript.SCHEMA else SnapshotScript.validate(payload)
	if not bool(payload_validation.get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_INTEREST_FRAME_PAYLOAD", {"cause": payload_validation})
	if String(payload["body_id"]) != String(value["body_id"]) \
			or String(payload["authority_owner_id"]) != String(value["authority_owner_id"]) \
			or int(payload["authority_epoch"]) != int(value["authority_epoch"]) \
			or int(payload["interest_revision"]) != int(value["interest_revision"]) \
			or int(payload["region_sequence"]) != int(value["region_sequence"]) \
			or int(payload["source_global_stream_sequence"]) != int(value["source_global_stream_sequence"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_FRAME_IDENTITY_MISMATCH")
	var payload_subscription_id: String = String(payload.get("subscription_id", ""))
	if expected_schema == SnapshotScript.SCHEMA:
		var subscription: Dictionary = SnapshotScript.decode_subscription(payload)
		payload_subscription_id = String(subscription.get("subscription_id", ""))
	if payload_subscription_id != String(value["subscription_id"]):
		return MatterUtilsScript.failure("MATTER_INTEREST_FRAME_SUBSCRIPTION_MISMATCH")
	return MatterUtilsScript.validate_checksum(value)


static func decode_payload(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	return PersistenceCodecScript.decode_persistence_json(String(value["payload_transport"]))
