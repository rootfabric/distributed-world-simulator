extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")
const AuthorityAddressScript = preload("res://scripts/simulation/spatial/aggregate_authority_address.gd")

const SCHEMA: String = "planet_simulator.aggregate_shard_descriptor.v1"
const FIELDS: Array[String] = [
	"schema",
	"shard_id",
	"logical_aggregate_id",
	"aggregate_kind",
	"state_schema",
	"descriptor_revision",
	"cell_ids",
	"authority_address",
	"neighbour_shard_ids",
]


static func create(
	shard_id: String,
	logical_aggregate_id: String,
	aggregate_kind: String,
	state_schema: String,
	descriptor_revision: int,
	cell_ids: Array,
	authority_address: Dictionary,
	neighbour_shard_ids: Array = []
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"shard_id": shard_id.strip_edges().to_lower(),
		"logical_aggregate_id": logical_aggregate_id.strip_edges().to_lower(),
		"aggregate_kind": aggregate_kind.strip_edges().to_upper(),
		"state_schema": state_schema.strip_edges().to_lower(),
		"descriptor_revision": descriptor_revision,
		"cell_ids": SpatialUtilsScript.sorted_unique_ids(cell_ids),
		"authority_address": authority_address.duplicate(true),
		"neighbour_shard_ids": SpatialUtilsScript.sorted_unique_ids(neighbour_shard_ids),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AGGREGATE_SHARD_DESCRIPTOR_SCHEMA")
	if not SpatialUtilsScript.is_canonical_id(value.get("shard_id"), 2):
		return _failure("INVALID_AGGREGATE_SHARD_ID")
	if not SpatialUtilsScript.is_canonical_id(value.get("logical_aggregate_id"), 2):
		return _failure("INVALID_LOGICAL_AGGREGATE_ID")
	if not SpatialUtilsScript.is_kind(value.get("aggregate_kind")):
		return _failure("INVALID_AGGREGATE_SHARD_KIND")
	if not SpatialUtilsScript.is_schema_id(value.get("state_schema")):
		return _failure("INVALID_AGGREGATE_SHARD_STATE_SCHEMA")
	if not NetworkUtilsScript.is_json_integer(value.get("descriptor_revision")) or int(value["descriptor_revision"]) < 1:
		return _failure("INVALID_AGGREGATE_SHARD_DESCRIPTOR_REVISION")
	var cell_validation: Dictionary = SpatialUtilsScript.validate_sorted_unique_ids(value.get("cell_ids"), false)
	if not bool(cell_validation.get("success", false)):
		return _failure("INVALID_AGGREGATE_SHARD_CELLS", cell_validation)
	if typeof(value.get("authority_address")) != TYPE_DICTIONARY or not bool(AuthorityAddressScript.validate(value["authority_address"]).get("success", false)):
		return _failure("INVALID_AGGREGATE_SHARD_AUTHORITY")
	var neighbour_validation: Dictionary = SpatialUtilsScript.validate_sorted_unique_ids(value.get("neighbour_shard_ids"), true)
	if not bool(neighbour_validation.get("success", false)):
		return _failure("INVALID_AGGREGATE_SHARD_NEIGHBOURS", neighbour_validation)
	if Array(value["neighbour_shard_ids"]).has(String(value["shard_id"])):
		return _failure("AGGREGATE_SHARD_SELF_NEIGHBOUR")
	return NetworkUtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = NetworkUtilsScript.json_round_trip(value)
	return Dictionary(round_trip.get("value", {})) if bool(round_trip.get("success", false)) else {}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
