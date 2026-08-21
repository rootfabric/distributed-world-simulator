extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.gateway_session_binding.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"gateway_session_id",
	"client_session_id",
	"logical_player_id",
	"player_entity_id",
	"world_id",
	"binding_revision",
	"state",
]


static func create(
		gateway_session_id: String,
		client_session_id: String,
		logical_player_id: String,
		player_entity_id: String,
		world_id: String,
		binding_revision: int,
		state: String,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"gateway_session_id": gateway_session_id,
		"client_session_id": client_session_id,
		"logical_player_id": logical_player_id,
		"player_entity_id": player_entity_id,
		"world_id": world_id,
		"binding_revision": binding_revision,
		"state": state,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["gateway_session_id", "gateway-session"],
		["client_session_id", "client-session"],
		["logical_player_id", "player"],
		["player_entity_id", "entity"],
		["world_id", "world"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_positive_integer(value, "binding_revision"),
		GatewayUtilsScript.require_enum(value, "state", GatewayUtilsScript.SESSION_STATES),
	]:
		if not bool(check.get("success", false)):
			return check
	return NetworkUtilsScript.validation_success()
