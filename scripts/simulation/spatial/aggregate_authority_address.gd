extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SpatialUtilsScript = preload("res://scripts/simulation/spatial/spatial_contract_utils.gd")

const SCHEMA: String = "planet_simulator.aggregate_authority_address.v1"
const FIELDS: Array[String] = ["schema", "authority_owner_id", "authority_epoch", "route_id"]


static func create(owner_id: String, authority_epoch: int, route_id: String) -> Dictionary:
	return {
		"schema": SCHEMA,
		"authority_owner_id": owner_id.strip_edges().to_lower(),
		"authority_epoch": authority_epoch,
		"route_id": route_id.strip_edges().to_lower(),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AGGREGATE_AUTHORITY_ADDRESS_SCHEMA")
	if not SpatialUtilsScript.is_canonical_id(value.get("authority_owner_id"), 2):
		return _failure("INVALID_AGGREGATE_AUTHORITY_OWNER")
	if not NetworkUtilsScript.is_json_integer(value.get("authority_epoch")) or int(value["authority_epoch"]) < 1:
		return _failure("INVALID_AGGREGATE_AUTHORITY_EPOCH")
	if not SpatialUtilsScript.is_canonical_id(value.get("route_id"), 2):
		return _failure("INVALID_AGGREGATE_AUTHORITY_ROUTE")
	return NetworkUtilsScript.validation_success()


static func _failure(code: String) -> Dictionary:
	return NetworkUtilsScript.validation_failure(code, code)
