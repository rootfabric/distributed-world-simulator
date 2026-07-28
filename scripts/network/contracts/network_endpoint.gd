extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const FIELDS: Array[String] = ["transport", "host", "port", "channel", "secure"]
const TRANSPORTS: Array[String] = ["LOOPBACK", "ENET", "WEBSOCKET"]


static func create(
	transport: String,
	host: String,
	port: int,
	channel: String,
	secure: bool = false
) -> Dictionary:
	return {
		"transport": transport,
		"host": host,
		"port": port,
		"channel": channel,
		"secure": secure,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["transport", "host", "channel"]:
		check = UtilsScript.require_string(value, field, field == "host")
		if not bool(check.get("success", false)):
			return check
	if not TRANSPORTS.has(String(value["transport"])):
		return UtilsScript.validation_failure("INVALID_TRANSPORT", "Unsupported endpoint transport")
	check = UtilsScript.require_json_integer(value, "port")
	if not bool(check.get("success", false)):
		return check
	check = UtilsScript.require_boolean(value, "secure")
	if not bool(check.get("success", false)):
		return check
	var port: int = int(value["port"])
	if String(value["transport"]) == "LOOPBACK":
		if port != 0 or not String(value["host"]).is_empty():
			return UtilsScript.validation_failure("INVALID_ENDPOINT", "LOOPBACK endpoint requires empty host and port 0")
	elif String(value["host"]).strip_edges().is_empty() or port < 1 or port > 65535:
		return UtilsScript.validation_failure("INVALID_ENDPOINT", "Network endpoint requires host and port 1..65535")
	if String(value["channel"]).strip_edges().is_empty():
		return UtilsScript.validation_failure("EMPTY_FIELD", "channel cannot be empty")
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var round_trip: Dictionary = UtilsScript.json_round_trip(value)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}
