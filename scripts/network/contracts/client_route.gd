extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const EndpointScript = preload("res://scripts/network/contracts/network_endpoint.gd")

const SCHEMA: String = "planet_simulator.client_route.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "route_id", "client_id", "entity_id",
	"primary_node_id", "secondary_node_id", "authority_epoch", "valid_from_tick",
	"expires_at_tick", "reason", "route_revision", "primary_endpoint", "secondary_endpoint",
]


static func create(
	route_id: String,
	client_id: String,
	entity_id: String,
	primary_node_id: String,
	secondary_node_id: String,
	authority_epoch: int,
	valid_from_tick: int,
	expires_at_tick: int,
	reason: String,
	route_revision: int,
	primary_endpoint: Dictionary,
	secondary_endpoint: Dictionary
) -> Dictionary:
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"route_id": route_id, "client_id": client_id, "entity_id": entity_id,
		"primary_node_id": primary_node_id, "secondary_node_id": secondary_node_id,
		"authority_epoch": authority_epoch, "valid_from_tick": valid_from_tick,
		"expires_at_tick": expires_at_tick, "reason": reason,
		"route_revision": route_revision, "primary_endpoint": primary_endpoint.duplicate(true),
		"secondary_endpoint": secondary_endpoint.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "route_id", "client_id", "entity_id", "primary_node_id", "reason"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	check = UtilsScript.require_string(value, "secondary_node_id", true)
	if not bool(check.get("success", false)):
		return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected client route schema")
	for field in ["protocol_version", "authority_epoch", "valid_from_tick", "expires_at_tick", "route_revision"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if int(value["authority_epoch"]) < 1 or int(value["valid_from_tick"]) < 0 or int(value["expires_at_tick"]) <= int(value["valid_from_tick"]) or int(value["route_revision"]) < 0:
		return UtilsScript.validation_failure("INVALID_ROUTE_WINDOW", "Invalid client route counters or window")
	if String(value["primary_node_id"]) == String(value["secondary_node_id"]) and not String(value["secondary_node_id"]).is_empty():
		return UtilsScript.validation_failure("DUPLICATE_ROUTE_NODE", "Primary and secondary nodes must differ")
	for field in ["primary_endpoint", "secondary_endpoint"]:
		if typeof(value.get(field)) != TYPE_DICTIONARY:
			return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be a Dictionary" % field)
	if not bool(EndpointScript.validate(value["primary_endpoint"]).get("success", false)):
		return UtilsScript.validation_failure("INVALID_ENDPOINT", "primary_endpoint is invalid")
	if String(value["secondary_node_id"]).is_empty():
		if not value["secondary_endpoint"].is_empty():
			return UtilsScript.validation_failure("INVALID_SECONDARY_ROUTE", "secondary_endpoint must be empty without secondary_node_id")
	elif not bool(EndpointScript.validate(value["secondary_endpoint"]).get("success", false)):
		return UtilsScript.validation_failure("INVALID_ENDPOINT", "secondary_endpoint is invalid")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var canonical: Dictionary = value.duplicate(true)
	canonical["primary_endpoint"] = EndpointScript.normalize(value["primary_endpoint"])
	if not value["secondary_endpoint"].is_empty():
		canonical["secondary_endpoint"] = EndpointScript.normalize(value["secondary_endpoint"])
	var round_trip: Dictionary = UtilsScript.json_round_trip(canonical)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}
