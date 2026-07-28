extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")

const SCHEMA: String = "planet_simulator.authority_route.v1"
const PROTOCOL_VERSION: int = 1
const SUBJECT_TYPES: Array[String] = ["ENTITY", "REGION"]
const STATUSES: Array[String] = ["ACTIVE", "DRAINING", "STALE"]
const FIELDS: Array[String] = [
	"schema", "protocol_version", "route_id", "subject_type", "subject_id",
	"owner_node_id", "authority_epoch", "lease_id", "region_id", "endpoint",
	"route_revision", "valid_from_tick", "expires_at_tick", "status",
]


static func create(
	route_id: String,
	subject_type: String,
	subject_id: String,
	owner_node_id: String,
	authority_epoch: int,
	lease_id: String,
	region_id: String,
	endpoint: Dictionary,
	route_revision: int,
	valid_from_tick: int,
	expires_at_tick: int,
	status: String = "ACTIVE"
) -> Dictionary:
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"route_id": route_id, "subject_type": subject_type, "subject_id": subject_id,
		"owner_node_id": owner_node_id, "authority_epoch": authority_epoch,
		"lease_id": lease_id, "region_id": region_id, "endpoint": endpoint.duplicate(true),
		"route_revision": route_revision, "valid_from_tick": valid_from_tick,
		"expires_at_tick": expires_at_tick, "status": status,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "route_id", "subject_type", "subject_id", "owner_node_id", "lease_id", "region_id", "status"]:
		check = UtilsScript.require_string(value, field, field == "region_id")
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected authority route schema")
	check = UtilsScript.require_json_integer(value, "protocol_version")
	if not bool(check.get("success", false)) or int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if not SUBJECT_TYPES.has(String(value["subject_type"])) or not STATUSES.has(String(value["status"])):
		return UtilsScript.validation_failure("INVALID_ENUM", "Invalid route subject type or status")
	if String(value["subject_type"]) == "REGION" and String(value["region_id"]) != String(value["subject_id"]):
		return UtilsScript.validation_failure("REGION_ROUTE_MISMATCH", "REGION route subject_id must equal region_id")
	for field in ["authority_epoch", "route_revision", "valid_from_tick", "expires_at_tick"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["authority_epoch"]) < 1 or int(value["route_revision"]) < 0 or int(value["valid_from_tick"]) < 0 or int(value["expires_at_tick"]) <= int(value["valid_from_tick"]):
		return UtilsScript.validation_failure("INVALID_ROUTE_WINDOW", "Invalid route counters or validity window")
	if typeof(value.get("endpoint")) != TYPE_DICTIONARY:
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "endpoint must be a Dictionary")
	check = EndpointScript.validate(value["endpoint"])
	if not bool(check.get("success", false)):
		return UtilsScript.validation_failure("INVALID_ENDPOINT", String(check.get("message", "")))
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var canonical: Dictionary = value.duplicate(true)
	canonical["endpoint"] = EndpointScript.normalize(value["endpoint"])
	var round_trip: Dictionary = UtilsScript.json_round_trip(canonical)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}
