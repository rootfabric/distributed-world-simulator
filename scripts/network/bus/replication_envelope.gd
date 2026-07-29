extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")

const SCHEMA := "planet_simulator.replication_envelope.v1"
const PROTOCOL_VERSION := 1
const KINDS: Array[String] = ["DELTA", "GHOST", "INTEREST", "SNAPSHOT"]
const FIELDS: Array[String] = ["schema", "protocol_version", "replication_id", "source_id", "target_peer_id", "replication_kind", "sequence", "payload_schema", "payload"]


static func create(replication_id: String, source_id: String, target_peer_id: String, replication_kind: String, sequence: int, payload_schema: String, payload: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"replication_id": replication_id,
		"source_id": source_id,
		"target_peer_id": target_peer_id,
		"replication_kind": replication_kind,
		"sequence": sequence,
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA or not NetworkUtilsScript.is_json_integer(value.get("protocol_version")) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return NetworkUtilsScript.validation_failure("INVALID_SCHEMA", "Replication schema/version mismatch")
	if not BusUtilsScript.is_canonical_id(value.get("replication_id"), "replication") or not BusUtilsScript.is_canonical_id(value.get("source_id"), "source") or not BusUtilsScript.is_canonical_id(value.get("target_peer_id"), "peer"):
		return NetworkUtilsScript.validation_failure("INVALID_REPLICATION_IDENTITY", "replication identity is not canonical")
	if typeof(value.get("replication_kind")) != TYPE_STRING or not KINDS.has(String(value["replication_kind"])):
		return NetworkUtilsScript.validation_failure("INVALID_REPLICATION_KIND", "Unknown replication_kind")
	if not NetworkUtilsScript.is_json_integer(value.get("sequence")) or int(value["sequence"]) < 1:
		return NetworkUtilsScript.validation_failure("INVALID_SEQUENCE", "sequence must be positive")
	if not BusUtilsScript.is_payload_schema(value.get("payload_schema")):
		return NetworkUtilsScript.validation_failure("INVALID_PAYLOAD_SCHEMA", "payload_schema is not canonical")
	return BusUtilsScript.validate_payload(value.get("payload"))
