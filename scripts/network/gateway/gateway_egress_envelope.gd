extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")
const ClientWorldFrameScript = preload("res://scripts/network/gateway/client_world_frame.gd")

const SCHEMA := "planet_simulator.gateway_egress_envelope.v1"
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
	"source_authority_id",
	"source_server_instance_id",
	"source_role",
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
		source_authority_id: String,
		source_server_instance_id: String,
		source_role: String,
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
		"source_authority_id": source_authority_id,
		"source_server_instance_id": source_server_instance_id,
		"source_role": source_role,
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
		["source_authority_id", "authority"],
		["source_server_instance_id", "server-instance"],
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
		GatewayUtilsScript.require_enum(value, "source_role", GatewayUtilsScript.ROUTE_ROLES),
	]:
		if not bool(check.get("success", false)):
			return check
	if typeof(value.get("frame")) != TYPE_DICTIONARY:
		return NetworkUtilsScript.validation_failure("INVALID_FRAME", "frame must be a Dictionary")
	var frame: Dictionary = Dictionary(value.get("frame"))
	var frame_check: Dictionary = ClientWorldFrameScript.validate(frame)
	if not bool(frame_check.get("success", false)):
		return frame_check
	if String(frame.get("direction")) != "WORLD_TO_CLIENT":
		return NetworkUtilsScript.validation_failure("INVALID_FRAME_DIRECTION", "Egress frame must be WORLD_TO_CLIENT")
	if String(frame.get("gateway_session_id")) != String(value.get("gateway_session_id")):
		return NetworkUtilsScript.validation_failure("SESSION_MISMATCH", "Inner and outer gateway_session_id differ")
	var role: String = String(value.get("source_role"))
	var channel: String = String(frame.get("channel"))
	if role == "PROJECTION" and channel != "WORLD_PROJECTION":
		return NetworkUtilsScript.validation_failure(
			"PROJECTION_CHANNEL_REQUIRED",
			"PROJECTION source may emit only WORLD_PROJECTION frames",
		)
	if channel == "WORLD_PROJECTION" and role != "PROJECTION":
		return NetworkUtilsScript.validation_failure(
			"PROJECTION_SOURCE_REQUIRED",
			"WORLD_PROJECTION requires source_role=PROJECTION",
		)
	if role in ["WARM", "DRAIN"] and channel in ["AUTHORITATIVE_SNAPSHOT", "WORLD_OPERATION"]:
		return NetworkUtilsScript.validation_failure(
			"NON_ACTIVE_AUTHORITATIVE_EGRESS",
			"WARM/DRAIN source cannot emit authoritative gameplay result channels",
		)
	return NetworkUtilsScript.validation_success()
