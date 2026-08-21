extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.gateway_connect_gate.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"connect_attempt_id",
	"transport_connection_id",
	"gateway_instance_id",
	"gateway_session_id",
	"client_session_id",
	"session_binding_id",
	"logical_player_id",
	"player_entity_id",
	"world_id",
	"authority_id",
	"server_instance_id",
	"protocol_admission_revision",
	"identity_verification_revision",
	"session_revision",
	"placement_revision",
	"directory_generation",
	"authority_epoch",
	"route_revision",
	"ready_snapshot_revision",
	"protocol_admitted",
	"identity_verified",
	"session_resolved",
	"placement_resolved",
	"authority_resolved",
	"backend_route_attached",
	"player_domain_ready",
	"world_ready",
	"gate_revision",
]


static func create(
		connect_attempt_id: String,
		transport_connection_id: String,
		gateway_instance_id: String,
		gateway_session_id: String,
		client_session_id: String,
		session_binding_id: String,
		logical_player_id: String,
		player_entity_id: String,
		world_id: String,
		authority_id: String,
		server_instance_id: String,
		protocol_admission_revision: int,
		identity_verification_revision: int,
		session_revision: int,
		placement_revision: int,
		directory_generation: int,
		authority_epoch: int,
		route_revision: int,
		ready_snapshot_revision: int,
		protocol_admitted: bool,
		identity_verified: bool,
		session_resolved: bool,
		placement_resolved: bool,
		authority_resolved: bool,
		backend_route_attached: bool,
		player_domain_ready: bool,
		world_ready: bool,
		gate_revision: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"connect_attempt_id": connect_attempt_id,
		"transport_connection_id": transport_connection_id,
		"gateway_instance_id": gateway_instance_id,
		"gateway_session_id": gateway_session_id,
		"client_session_id": client_session_id,
		"session_binding_id": session_binding_id,
		"logical_player_id": logical_player_id,
		"player_entity_id": player_entity_id,
		"world_id": world_id,
		"authority_id": authority_id,
		"server_instance_id": server_instance_id,
		"protocol_admission_revision": protocol_admission_revision,
		"identity_verification_revision": identity_verification_revision,
		"session_revision": session_revision,
		"placement_revision": placement_revision,
		"directory_generation": directory_generation,
		"authority_epoch": authority_epoch,
		"route_revision": route_revision,
		"ready_snapshot_revision": ready_snapshot_revision,
		"protocol_admitted": protocol_admitted,
		"identity_verified": identity_verified,
		"session_resolved": session_resolved,
		"placement_resolved": placement_resolved,
		"authority_resolved": authority_resolved,
		"backend_route_attached": backend_route_attached,
		"player_domain_ready": player_domain_ready,
		"world_ready": world_ready,
		"gate_revision": gate_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["connect_attempt_id", "connect-attempt"],
		["transport_connection_id", "transport-connection"],
		["gateway_instance_id", "gateway"],
		["gateway_session_id", "gateway-session"],
		["client_session_id", "client-session"],
		["session_binding_id", "session-binding"],
		["logical_player_id", "player"],
		["player_entity_id", "entity"],
		["world_id", "world"],
		["authority_id", "authority"],
		["server_instance_id", "server-instance"],
	]:
		var id_check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for field in [
		"protocol_admission_revision",
		"identity_verification_revision",
		"session_revision",
		"placement_revision",
		"directory_generation",
		"authority_epoch",
		"route_revision",
		"ready_snapshot_revision",
		"gate_revision",
	]:
		var integer_check: Dictionary = GatewayUtilsScript.require_positive_integer(value, String(field))
		if not bool(integer_check.get("success", false)):
			return integer_check
	var schema_check: Dictionary = GatewayUtilsScript.validate_schema(value, SCHEMA)
	if not bool(schema_check.get("success", false)):
		return schema_check
	var gates := [
		["protocol_admitted", "PROTOCOL_NOT_ADMITTED"],
		["identity_verified", "IDENTITY_NOT_VERIFIED"],
		["session_resolved", "SESSION_NOT_RESOLVED"],
		["placement_resolved", "PLACEMENT_NOT_RESOLVED"],
		["authority_resolved", "AUTHORITY_NOT_RESOLVED"],
		["backend_route_attached", "BACKEND_ROUTE_NOT_ATTACHED"],
		["player_domain_ready", "PLAYER_DOMAIN_NOT_READY"],
		["world_ready", "WORLD_NOT_READY"],
	]
	for gate in gates:
		var field := String(gate[0])
		if typeof(value.get(field)) != TYPE_BOOL:
			return NetworkUtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be Boolean" % field)
		if not bool(value.get(field)):
			return NetworkUtilsScript.validation_failure(String(gate[1]), "%s must be true before WorldReady" % field)
	return NetworkUtilsScript.validation_success()
