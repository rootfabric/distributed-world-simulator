extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const IdentityScript = preload("res://scripts/simulation/aggregates/aggregate_identity.gd")
const AuthorityScript = preload("res://scripts/simulation/aggregates/aggregate_authority_state.gd")
const SpatialScopeScript = preload("res://scripts/simulation/aggregates/aggregate_spatial_scope.gd")
const PartitionAddressScript = preload("res://scripts/simulation/partition/partition_address.gd")

const SCHEMA: String = "planet_simulator.aggregate_descriptor.v1"
const FIELDS: Array[String] = [
	"schema",
	"identity",
	"authority",
	"spatial_scope",
	"partition_address",
]


static func create(
	identity: Dictionary,
	authority: Dictionary,
	spatial_scope: Dictionary,
	partition_address: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"identity": identity.duplicate(true),
		"authority": authority.duplicate(true),
		"spatial_scope": spatial_scope.duplicate(true),
		"partition_address": partition_address.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return _failure("UNSUPPORTED_AGGREGATE_DESCRIPTOR_SCHEMA")
	for field in ["identity", "authority", "spatial_scope", "partition_address"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return _failure("INVALID_AGGREGATE_DESCRIPTOR_SECTION")
	if not bool(IdentityScript.validate(value["identity"]).get("success", false)):
		return _failure("INVALID_AGGREGATE_IDENTITY")
	if not bool(AuthorityScript.validate(value["authority"]).get("success", false)):
		return _failure("INVALID_AGGREGATE_AUTHORITY")
	if not bool(SpatialScopeScript.validate(value["spatial_scope"]).get("success", false)):
		return _failure("INVALID_AGGREGATE_SPATIAL_SCOPE")
	var partition: Dictionary = value["partition_address"]
	if not partition.is_empty() and not PartitionAddressScript.is_valid(partition):
		return _failure("INVALID_AGGREGATE_PARTITION_ADDRESS")
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return Dictionary(round_trip.get("value", {})) if bool(round_trip.get("success", false)) else {}


static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
