extends RefCounted

const NetworkUtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const GatewayUtilsScript = preload("res://scripts/network/gateway/gateway_contract_utils.gd")

const SCHEMA := "planet_simulator.projection_subscription.v1"
const PROTOCOL_VERSION := 1
const FIELDS: Array[String] = [
	"schema",
	"protocol_version",
	"subscription_id",
	"gateway_session_id",
	"source_authority_id",
	"source_server_instance_id",
	"stream_id",
	"manifest_revision",
	"source_revision",
	"grant_id",
	"interest_key",
	"read_only",
]


static func create(
		subscription_id: String,
		gateway_session_id: String,
		source_authority_id: String,
		source_server_instance_id: String,
		stream_id: String,
		manifest_revision: int,
		source_revision: int,
		grant_id: String,
		interest_key: String,
		read_only: bool = true,
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"protocol_version": PROTOCOL_VERSION,
		"subscription_id": subscription_id,
		"gateway_session_id": gateway_session_id,
		"source_authority_id": source_authority_id,
		"source_server_instance_id": source_server_instance_id,
		"stream_id": stream_id,
		"manifest_revision": manifest_revision,
		"source_revision": source_revision,
		"grant_id": grant_id,
		"interest_key": interest_key,
		"read_only": read_only,
	}


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = NetworkUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	for pair in [
		["subscription_id", "projection-subscription"],
		["gateway_session_id", "gateway-session"],
		["source_authority_id", "authority"],
		["source_server_instance_id", "server-instance"],
		["stream_id", "projection-stream"],
		["grant_id", "projection-grant"],
		["interest_key", "interest"],
	]:
		var check: Dictionary = GatewayUtilsScript.require_id(value, String(pair[0]), String(pair[1]))
		if not bool(check.get("success", false)):
			return check
	for integer_field in ["manifest_revision", "source_revision"]:
		var integer_check: Dictionary = GatewayUtilsScript.require_nonnegative_integer(value, String(integer_field))
		if not bool(integer_check.get("success", false)):
			return integer_check
	var schema_check: Dictionary = GatewayUtilsScript.validate_schema(value, SCHEMA)
	if not bool(schema_check.get("success", false)):
		return schema_check
	if typeof(value.get("read_only")) != TYPE_BOOL or not bool(value.get("read_only")):
		return NetworkUtilsScript.validation_failure(
			"PROJECTION_NOT_READ_ONLY",
			"Projection subscription must be read_only=true",
		)
	return NetworkUtilsScript.validation_success()
