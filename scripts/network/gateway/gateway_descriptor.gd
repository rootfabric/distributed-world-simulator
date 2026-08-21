extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const BusUtilsScript = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.gateway_descriptor.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"descriptor_id",
	"gateway_instance_id",
	"pop_id",
	"region_hint",
	"endpoint_id",
	"locator_revision",
	"health_state",
	"capacity_hint",
]


static func create(
		descriptor_id: String,
		gateway_instance_id: String,
		pop_id: String,
		region_hint: String,
		endpoint_id: String,
		locator_revision: int,
		health_state: String,
		capacity_hint: int,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"descriptor_id": descriptor_id,
		"gateway_instance_id": gateway_instance_id,
		"pop_id": pop_id,
		"region_hint": region_hint,
		"endpoint_id": endpoint_id,
		"locator_revision": locator_revision,
		"health_state": health_state,
		"capacity_hint": capacity_hint,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["descriptor_id", "gateway-descriptor"],
		["gateway_instance_id", "gateway"],
		["pop_id", "gateway-pop"],
		["endpoint_id", "endpoint"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for check in [
		GatewayUtilsScript.validate_schema(value, SCHEMA),
		GatewayUtilsScript.require_positive_integer(value, "locator_revision"),
		GatewayUtilsScript.require_enum(value, "health_state", GatewayUtilsScript.GATEWAY_HEALTH_STATES),
	]:
		if not bool(check.get("success", false)):
			return check
	if not BusUtilsScript.is_semantic_name(value.get("region_hint"), true):
		return NetworkUtilsScript.validation_failure("INVALID_REGION_HINT", "region_hint is not canonical")
	if not NetworkUtilsScript.is_json_integer(value.get("capacity_hint")) \
			or int(value.get("capacity_hint")) < 0 \
			or int(value.get("capacity_hint")) > 100:
		return NetworkUtilsScript.validation_failure("INVALID_CAPACITY_HINT", "capacity_hint must be within 0..100")
	return NetworkUtilsScript.validation_success()
