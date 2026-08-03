extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")

const SCHEMA := "planet_simulator.representation_stream_cancellation.v1"
const REASONS: Array[String] = ["CLIENT_SHUTDOWN", "OBSERVER_MOVED", "POLICY", "REPLACED", "STALE_SOURCE"]
const FIELDS: Array[String] = [
	"schema",
	"stream_request_id",
	"request_revision",
	"cancellation_generation",
	"reason",
	"created_tick",
	"checksum",
]


static func create(
	stream_request_id: String,
	request_revision: int,
	cancellation_generation: int,
	reason: String,
	created_tick: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"stream_request_id": stream_request_id,
		"request_revision": request_revision,
		"cancellation_generation": cancellation_generation,
		"reason": reason,
		"created_tick": created_tick,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_STREAM_CANCELLATION_SCHEMA")
	if not Utils.is_canonical_id(value.get("stream_request_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CANCELLATION_ID")
	if not Utils.is_json_integer(value.get("request_revision")) or int(value["request_revision"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CANCELLATION_REVISION")
	if not Utils.is_json_integer(value.get("cancellation_generation")) or int(value["cancellation_generation"]) < 1:
		return Utils.failure("INVALID_REPRESENTATION_CANCELLATION_GENERATION")
	if typeof(value.get("reason")) != TYPE_STRING or not REASONS.has(String(value["reason"])):
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CANCELLATION_REASON")
	if not Utils.is_json_integer(value.get("created_tick")) or int(value["created_tick"]) < 0:
		return Utils.failure("INVALID_REPRESENTATION_STREAM_CANCELLATION_TICK")
	return Utils.validate_checksum(value)
