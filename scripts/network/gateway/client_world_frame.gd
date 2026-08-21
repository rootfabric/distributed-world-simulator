extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.client_world_frame.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"frame_id",
	"gateway_session_id",
	"direction",
	"channel",
	"sequence",
	"payload_schema",
	"payload",
]


static func create(
		frame_id: String,
		gateway_session_id: String,
		direction: String,
		channel: String,
		sequence: int,
		payload_schema: String,
		payload: Dictionary,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"frame_id": frame_id,
		"gateway_session_id": gateway_session_id,
		"direction": direction,
		"channel": channel,
		"sequence": sequence,
		"payload_schema": payload_schema,
		"payload": payload.duplicate(true),
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_id(value, "frame_id", "frame"),
		GatewayUtilsScript.require_id(value, "gateway_session_id", "gateway-session"),
		GatewayUtilsScript.require_enum(value, "direction", GatewayUtilsScript.DIRECTIONS),
		GatewayUtilsScript.require_enum(value, "channel", GatewayUtilsScript.CHANNELS),
		GatewayUtilsScript.require_positive_integer(value, "sequence"),
		GatewayUtilsScript.require_payload_schema(value),
		GatewayUtilsScript.validate_client_surface_payload(value.get("payload")),
	]:
		if not bool(check.get("success", false)):
			return check
	return GatewayUtilsScript.validate_client_frame_semantics(value)
