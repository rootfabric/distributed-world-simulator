extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const FingerprintScript = preload("res://scripts/network/observability/network_build_fingerprint.gd")

const SCHEMA: String = "planet_simulator.network_observability_sample.v1"
const FIELDS: Array[String] = [
	"schema", "sample_id", "runtime_role", "captured_at_ms", "fingerprint",
	"counters", "gauges", "distributions", "channels", "checksum",
]
const DISTRIBUTION_FIELDS: Array[String] = ["count", "min", "max", "mean", "p50", "p95", "p99"]
const CHANNEL_FIELDS: Array[String] = ["packets_sent", "packets_received", "bytes_sent", "bytes_received"]


static func create(
	sample_id: String,
	runtime_role: String,
	captured_at_ms: int,
	fingerprint: Dictionary,
	counters: Dictionary,
	gauges: Dictionary,
	distributions: Dictionary,
	channels: Dictionary
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"sample_id": sample_id,
		"runtime_role": runtime_role,
		"captured_at_ms": captured_at_ms,
		"fingerprint": fingerprint.duplicate(true),
		"counters": counters.duplicate(true),
		"gauges": gauges.duplicate(true),
		"distributions": distributions.duplicate(true),
		"channels": channels.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "sample_id", "runtime_role", "checksum"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected observability sample schema")
	if not _is_identifier(String(value["sample_id"]), true):
		return UtilsScript.validation_failure("INVALID_SAMPLE_ID", "sample_id must be canonical")
	if String(value["runtime_role"]) not in ["server", "client", "listen-host", "test"]:
		return UtilsScript.validation_failure("INVALID_RUNTIME_ROLE", "Unsupported runtime_role")
	check = UtilsScript.require_json_integer(value, "captured_at_ms")
	if not bool(check.get("success", false)) or int(value["captured_at_ms"]) < 0:
		return UtilsScript.validation_failure("INVALID_CAPTURE_TIME", "captured_at_ms must be a non-negative integer")
	if not value.get("fingerprint") is Dictionary:
		return UtilsScript.validation_failure("INVALID_FINGERPRINT", "fingerprint must be a Dictionary")
	check = FingerprintScript.validate(Dictionary(value["fingerprint"]))
	if not bool(check.get("success", false)):
		return UtilsScript.validation_failure("INVALID_FINGERPRINT", String(check.get("error_code", "INVALID_FINGERPRINT")))
	check = _validate_metric_map(value.get("counters"), true)
	if not bool(check.get("success", false)):
		return check
	check = _validate_metric_map(value.get("gauges"), false)
	if not bool(check.get("success", false)):
		return check
	check = _validate_distributions(value.get("distributions"))
	if not bool(check.get("success", false)):
		return check
	check = _validate_channels(value.get("channels"))
	if not bool(check.get("success", false)):
		return check
	if String(value["checksum"]) != compute_checksum(value):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Observability sample checksum mismatch")
	return UtilsScript.validation_success()


static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func _validate_metric_map(raw_value, require_integer: bool) -> Dictionary:
	if not raw_value is Dictionary:
		return UtilsScript.validation_failure("INVALID_METRIC_MAP", "Metric map must be a Dictionary")
	for key_value in raw_value.keys():
		var key: String = String(key_value)
		if typeof(key_value) != TYPE_STRING or not _is_identifier(key, false):
			return UtilsScript.validation_failure("INVALID_METRIC_NAME", "Metric names must be canonical")
		var number_value = raw_value[key_value]
		if require_integer:
			if not UtilsScript.is_json_integer(number_value) or int(number_value) < 0:
				return UtilsScript.validation_failure("INVALID_COUNTER_VALUE", "Counter values must be non-negative integers")
		elif not _is_finite_number(number_value):
			return UtilsScript.validation_failure("INVALID_GAUGE_VALUE", "Gauge values must be finite numbers")
	return UtilsScript.validation_success()


static func _validate_distributions(raw_value) -> Dictionary:
	if not raw_value is Dictionary:
		return UtilsScript.validation_failure("INVALID_DISTRIBUTIONS", "distributions must be a Dictionary")
	for key_value in raw_value.keys():
		if typeof(key_value) != TYPE_STRING or not _is_identifier(String(key_value), false):
			return UtilsScript.validation_failure("INVALID_METRIC_NAME", "Distribution names must be canonical")
		if not raw_value[key_value] is Dictionary:
			return UtilsScript.validation_failure("INVALID_DISTRIBUTION", "Distribution must be a Dictionary")
		var distribution: Dictionary = raw_value[key_value]
		var check: Dictionary = UtilsScript.validate_exact_fields(distribution, DISTRIBUTION_FIELDS)
		if not bool(check.get("success", false)):
			return check
		if not UtilsScript.is_json_integer(distribution["count"]) or int(distribution["count"]) < 0:
			return UtilsScript.validation_failure("INVALID_DISTRIBUTION_COUNT", "Distribution count must be non-negative")
		for field in ["min", "max", "mean", "p50", "p95", "p99"]:
			if not _is_finite_number(distribution[field]):
				return UtilsScript.validation_failure("INVALID_DISTRIBUTION_VALUE", "Distribution values must be finite")
	return UtilsScript.validation_success()


static func _validate_channels(raw_value) -> Dictionary:
	if not raw_value is Dictionary:
		return UtilsScript.validation_failure("INVALID_CHANNELS", "channels must be a Dictionary")
	for key_value in raw_value.keys():
		if typeof(key_value) != TYPE_STRING or not _is_identifier(String(key_value), false):
			return UtilsScript.validation_failure("INVALID_CHANNEL_NAME", "Channel names must be canonical")
		if not raw_value[key_value] is Dictionary:
			return UtilsScript.validation_failure("INVALID_CHANNEL_METRICS", "Channel metrics must be a Dictionary")
		var metrics: Dictionary = raw_value[key_value]
		var check: Dictionary = UtilsScript.validate_exact_fields(metrics, CHANNEL_FIELDS)
		if not bool(check.get("success", false)):
			return check
		for field in CHANNEL_FIELDS:
			if not UtilsScript.is_json_integer(metrics[field]) or int(metrics[field]) < 0:
				return UtilsScript.validation_failure("INVALID_CHANNEL_METRIC", "Channel metrics must be non-negative integers")
	return UtilsScript.validation_success()


static func _is_finite_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number: float = float(value)
	return not is_nan(number) and not is_inf(number)


static func _is_identifier(value: String, allow_slash: bool) -> bool:
	if value.is_empty() or value != value.strip_edges() or value != value.to_lower() or value.length() > 192:
		return false
	for character in value:
		if not ((character >= "a" and character <= "z") or (character >= "0" and character <= "9") or character in ["-", "_", "."] or (allow_slash and character == "/")):
			return false
	return not value.contains("//") and not value.begins_with("/") and not value.ends_with("/")
