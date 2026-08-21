extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")

const SCHEMA := "planet_simulator.gateway_ingress_envelope.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"envelope_id",
	"gateway_instance_id",
	"backend_link_id",
	"gateway_session_id",
	"session_slot",
	"route_revision",
	"observed_authority_epoch",
	"target_authority_id",
	"target_server_instance_id",
	"route_role",
	"frame",
]


static func create(
		envelope_id: String,
		gateway_instance_id: String,
		backend_link_id: String,
		gateway_session_id: String,
		session_slot: int,
		route_revision: int,
		observed_authority_epoch: int,
		target_authority_id: String,
		target_server_instance_id: String,
		route_role: String,
		frame: Dictionary,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"envelope_id": envelope_id,
		"gateway_instance_id": gateway_instance_id,
		"backend_link_id": backend_link_id,
		"gateway_session_id": gateway_session_id,
		"session_slot": session_slot,
		"route_revision": route_revision,
		"observed_authority_epoch": observed_authority_epoch,
		"target_authority_id": target_authority_id,
		"target_server_instance_id": target_server_instance_id,
		"route_role": route_role,
		"frame": frame.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	var id_checks: Array = [
		["envelope_id", "gateway-envelope"],
		["gateway_instance_id", "gateway"],
		["backend_link_id", "backend-link"],
		["gateway_session_id", "gateway-session"],
		["target_authority_id", "authority"],
		["target_server_instance_id", "server-instance"],
	]
	for pair in id_checks:
		var id_check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(id_check.get("success", false)):
			return id_check
	for integer_field in ["session_slot", "route_revision", "observed_authority_epoch"]:
		var integer_check: Dictionary = GatewayUtilsScript.require_positive_integer(value, String(integer_field))
		if not bool(integer_check.get("success", false)):
			return integer_check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_enum(value, "route_role", GatewayUtilsScript.ROUTE_ROLES),
	]:
		if not bool(check.get("success", false)):
			return check
	if typeof(value.get("frame")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_FRAME", "frame must be a Dictionary")
	var frame: Dictionary = Dictionary(value.get("frame"))
	var frame_check: Dictionary = ClientWorldFrameScript.validate(frame)
	if not bool(frame_check.get("success", false)):
		return frame_check
	if String(frame.get("direction")) != "CLIENT_TO_WORLD":
		return NetworkUtilsScript.validation_failure("INVALID_FRAME_DIRECTION", "Ingress frame must be CLIENT_TO_WORLD")
	if String(frame.get("gateway_session_id")) != String(value.get("gateway_session_id")):
		return NetworkUtilsScript.validation_failure("SESSION_MISMATCH", "Inner and outer gateway_session_id differ")
	var channel: String = String(frame.get("channel"))
	if channel == "WORLD_PROJECTION":
		return NetworkUtilsScript.validation_failure("PROJECTION_INGRESS_FORBIDDEN", "Client cannot send WORLD_PROJECTION")
	if GatewayUtilsScript.is_mutating_client_channel(channel) and String(value.get("route_role")) != "ACTIVE":
		return NetworkUtilsScript.validation_failure(
			"NON_ACTIVE_MUTATION_ROUTE",
			"Mutating client frame may be routed only to ACTIVE authority",
		)
	return NetworkUtilsScript.validation_success()
