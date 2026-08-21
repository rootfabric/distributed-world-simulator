extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.gateway_route_binding.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"route_binding_id",
	"gateway_session_id",
	"player_entity_id",
	"authority_id",
	"server_instance_id",
	"observed_authority_epoch",
	"route_revision",
	"route_role",
]


static func create(
		route_binding_id: String,
		gateway_session_id: String,
		player_entity_id: String,
		authority_id: String,
		server_instance_id: String,
		observed_authority_epoch: int,
		route_revision: int,
		route_role: String,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"route_binding_id": route_binding_id,
		"gateway_session_id": gateway_session_id,
		"player_entity_id": player_entity_id,
		"authority_id": authority_id,
		"server_instance_id": server_instance_id,
		"observed_authority_epoch": observed_authority_epoch,
		"route_revision": route_revision,
		"route_role": route_role,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["route_binding_id", "gateway-route"],
		["gateway_session_id", "gateway-session"],
		["player_entity_id", "entity"],
		["authority_id", "authority"],
		["server_instance_id", "server-instance"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for integer_field in ["observed_authority_epoch", "route_revision"]:
		var integer_check: Dictionary = GatewayUtilsScript.require_positive_integer(value, String(integer_field))
		if not bool(integer_check.get("success", false)):
			return integer_check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_enum(value, "route_role", GatewayUtilsScript.ROUTE_ROLES),
	]:
		if not bool(check.get("success", false)):
			return check
	# RouteRevision and AuthorityEpoch are different namespaces. Numeric equality is legal.
	return NetworkUtilsScript.validation_success()
