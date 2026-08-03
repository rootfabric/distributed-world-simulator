extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")

const SCHEMA := "planet_simulator.representation_stream_ack.v1"
const STATUSES: Array[String] = ["CANCELLED", "FAILED", "RECEIVING", "STAGE_READY", "STALE", "STREAM_READY"]
const FIELDS: Array[String] = [
	"schema",
	"stream_id",
	"stream_request_id",
	"request_revision",
	"stage_index",
	"artifact_hash",
	"received_contiguous_bytes",
	"received_chunks",
	"status",
	"client_cache_generation",
	"error_code",
	"checksum",
]


static func create(
	stream_id: String,
	stream_request_id: String,
	request_revision: int,
	stage_index: int,
	artifact_hash: String,
	received_contiguous_bytes: int,
	received_chunks: int,
	status: String,
	client_cache_generation: int,
	error_code: String = ""
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"stream_id": stream_id,
		"stream_request_id": stream_request_id,
		"request_revision": request_revision,
		"stage_index": stage_index,
		"artifact_hash": artifact_hash,
		"received_contiguous_bytes": received_contiguous_bytes,
		"received_chunks": received_chunks,
		"status": status,
		"client_cache_generation": client_cache_generation,
		"error_code": error_code,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_STREAM_ACK_SCHEMA")
	if not Utils.is_canonical_id(value.get("stream_id"), 2) or not Utils.is_canonical_id(value.get("stream_request_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_ACK_ID")
	if not Utils.is_json_integer(value.get("request_revision")) or int(value["request_revision"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_ACK_REVISION")
	for field in ["stage_index", "received_contiguous_bytes", "received_chunks", "client_cache_generation"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return Utils.failure("INVALID_REPRESENTATION_STREAM_ACK_PROGRESS")
	if not Utils.is_lower_hex_64(value.get("artifact_hash")):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_ACK_HASH")
	if typeof(value.get("status")) != TYPE_STRING or not STATUSES.has(String(value["status"])):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_ACK_STATUS")
	if typeof(value.get("error_code")) != TYPE_STRING:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_ACK_ERROR")
	var failed: bool = String(value["status"]) == "FAILED"
	if failed != (not String(value["error_code"]).is_empty()):
		return Utils.failure("INCONSISTENT_REPRESENTATION_STREAM_ACK_ERROR")
	return Utils.validate_checksum(value)
