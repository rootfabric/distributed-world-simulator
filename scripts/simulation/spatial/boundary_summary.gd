extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")

const SCHEMA: String = "planet_simulator.boundary_summary.v1"
const FIELDS: Array[String] = [
	"schema",
	"summary_id",
	"source_shard_id",
	"target_shard_id",
	"boundary_id",
	"summary_schema",
	"source_revision",
	"from_tick",
	"to_tick",
	"values_by_key",
	"checksum",
]


static func create(
	summary_id: String,
	source_shard_id: String,
	target_shard_id: String,
	boundary_id: String,
	summary_schema: String,
	source_revision: int,
	from_tick: int,
	to_tick: int,
	values_by_key: Dictionary
) -> Dictionary:
	var result: Dictionary = {
		"schema": SCHEMA,
		"summary_id": summary_id.strip_edges().to_lower(),
		"source_shard_id": source_shard_id.strip_edges().to_lower(),
		"target_shard_id": target_shard_id.strip_edges().to_lower(),
		"boundary_id": boundary_id.strip_edges().to_lower(),
		"summary_schema": summary_schema.strip_edges().to_lower(),
		"source_revision": source_revision,
		"from_tick": from_tick,
		"to_tick": to_tick,
		"values_by_key": values_by_key.duplicate(true),
		"checksum": "",
	}
	result["checksum"] = compute_checksum(result)
	return result


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_BOUNDARY_SUMMARY_SCHEMA")
	for field in ["summary_id", "source_shard_id", "target_shard_id", "boundary_id"]:
		if not SpatialUtilsScript.is_canonical_id(value.get(field), 2):
			return _failure("INVALID_BOUNDARY_SUMMARY_IDENTIFIER", {"field": field})
	if String(value["source_shard_id"]) == String(value["target_shard_id"]):
		return _failure("BOUNDARY_SUMMARY_SELF_TARGET")
	if not SpatialUtilsScript.is_schema_id(value.get("summary_schema")):
		return _failure("INVALID_BOUNDARY_SUMMARY_STATE_SCHEMA")
	for field in ["source_revision", "from_tick", "to_tick"]:
		if not NetworkUtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0:
			return _failure("INVALID_BOUNDARY_SUMMARY_INTEGER", {"field": field})
	if int(value["to_tick"]) < int(value["from_tick"]):
		return _failure("BOUNDARY_SUMMARY_TICK_RANGE_INVALID")
	if typeof(value.get("values_by_key")) != TYPE_DICTIONARY or value["values_by_key"].is_empty():
		return _failure("INVALID_BOUNDARY_SUMMARY_VALUES")
	var canonical: Dictionary = NetworkUtilsScript.canonicalize(value["values_by_key"], "$.values_by_key")
	if not bool(canonical.get("success", false)):
		return _failure("NON_CANONICAL_BOUNDARY_SUMMARY_VALUES")
	for raw_key in value["values_by_key"].keys():
		if not SpatialUtilsScript.is_lower_segment(String(raw_key), false):
			return _failure("INVALID_BOUNDARY_SUMMARY_VALUE_KEY")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("BOUNDARY_SUMMARY_CHECKSUM_MISMATCH")
	return NetworkUtilsScript.validation_success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return NetworkUtilsScript.payload_hash(payload)


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
