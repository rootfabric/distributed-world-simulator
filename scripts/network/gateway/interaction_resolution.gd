extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const CwipUtilsScript = preload("res://scripts/network/gateway/cwip_contract_utils.gd")

const SCHEMA := "planet_simulator.interaction_resolution.v1"
const PROTOCOL_VERSION := 1
const RESULTS: Array[String] = ["NO_COLLISION", "COLLISION", "REJECTED"]
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"interaction_id",
	"result",
	"winning_world_id",
	"winning_entity_id",
	"winning_collision_t",
	"proof_set_digest",
	"resolution_revision",
]


static func create(
		interaction_id: String,
		result: String,
		winning_world_id,
		winning_entity_id,
		winning_collision_t,
		proof_set_digest: String,
		resolution_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"interaction_id": interaction_id,
		"result": result,
		"winning_world_id": winning_world_id,
		"winning_entity_id": winning_entity_id,
		"winning_collision_t": winning_collision_t,
		"proof_set_digest": proof_set_digest,
		"resolution_revision": resolution_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		CwipUtilsScript.require_id(value, "interaction_id", "interaction"),
		GatewayUtilsScript.require_enum(value, "result", RESULTS),
		CwipUtilsScript.require_sha256(value, "proof_set_digest"),
		CwipUtilsScript.require_positive_integer(value, "resolution_revision"),
	]:
		if not bool(check.get("success", false)):
			return check
	var result := String(value.get("result"))
	if result == "COLLISION":
		var world_check: Dictionary = CwipUtilsScript.require_optional_id(value, "winning_world_id", "world")
		if not bool(world_check.get("success", false)) or value.get("winning_world_id") == null:
			return NetworkUtilsScript.validation_failure("MISSING_WINNING_WORLD", "COLLISION resolution requires winning_world_id")
		var entity_check: Dictionary = CwipUtilsScript.require_optional_id(value, "winning_entity_id", "entity")
		if not bool(entity_check.get("success", false)):
			return entity_check
		var collision_check: Dictionary = CwipUtilsScript.require_nonnegative_number(value, "winning_collision_t")
		if not bool(collision_check.get("success", false)):
			return collision_check
	else:
		if value.get("winning_world_id") != null or value.get("winning_entity_id") != null or value.get("winning_collision_t") != null:
			return NetworkUtilsScript.validation_failure("UNEXPECTED_WINNING_COLLISION", "Non-collision resolution cannot carry winning collision fields")
	return NetworkUtilsScript.validation_success()
