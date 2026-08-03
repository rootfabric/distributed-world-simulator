extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.network_condition_profile.v1"
const DOCUMENT_SCHEMA: String = "planet_simulator.network_condition_presets.v1"
const FIELDS: Array[String] = [
	"schema", "profile_id",
	"outgoing_latency_min_ms", "outgoing_latency_max_ms",
	"incoming_latency_min_ms", "incoming_latency_max_ms",
	"jitter_ms", "packet_loss_percent", "burst_loss_probability_percent",
	"burst_loss_duration_ms", "duplicate_percent", "reorder_percent",
	"bandwidth_limit_kbps", "queue_limit_bytes", "lag_spike_ms",
	"disconnect_duration_ms", "random_seed", "checksum",
]


static func create(profile_id: String, values: Dictionary) -> Dictionary:
	var profile: Dictionary = {
		"schema": SCHEMA,
		"profile_id": profile_id,
		"outgoing_latency_min_ms": int(values.get("outgoing_latency_min_ms", 0)),
		"outgoing_latency_max_ms": int(values.get("outgoing_latency_max_ms", 0)),
		"incoming_latency_min_ms": int(values.get("incoming_latency_min_ms", 0)),
		"incoming_latency_max_ms": int(values.get("incoming_latency_max_ms", 0)),
		"jitter_ms": int(values.get("jitter_ms", 0)),
		"packet_loss_percent": float(values.get("packet_loss_percent", 0.0)),
		"burst_loss_probability_percent": float(values.get("burst_loss_probability_percent", 0.0)),
		"burst_loss_duration_ms": int(values.get("burst_loss_duration_ms", 0)),
		"duplicate_percent": float(values.get("duplicate_percent", 0.0)),
		"reorder_percent": float(values.get("reorder_percent", 0.0)),
		"bandwidth_limit_kbps": int(values.get("bandwidth_limit_kbps", 0)),
		"queue_limit_bytes": int(values.get("queue_limit_bytes", 0)),
		"lag_spike_ms": int(values.get("lag_spike_ms", 0)),
		"disconnect_duration_ms": int(values.get("disconnect_duration_ms", 0)),
		"random_seed": int(values.get("random_seed", 1)),
		"checksum": "",
	}
	profile["checksum"] = compute_checksum(profile)
	return profile


static func validate(profile: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(profile, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "profile_id", "checksum"]:
		check = UtilsScript.require_string(profile, field)
		if not bool(check.get("success", false)):
			return check
	if String(profile["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected network condition profile schema")
	if not is_profile_id(String(profile["profile_id"])):
		return UtilsScript.validation_failure("INVALID_PROFILE_ID", "profile_id must be canonical uppercase")
	for field in [
		"outgoing_latency_min_ms", "outgoing_latency_max_ms",
		"incoming_latency_min_ms", "incoming_latency_max_ms", "jitter_ms",
		"burst_loss_duration_ms", "bandwidth_limit_kbps", "queue_limit_bytes",
		"lag_spike_ms", "disconnect_duration_ms", "random_seed",
	]:
		if not UtilsScript.is_json_integer(profile[field]):
			return UtilsScript.validation_failure("INVALID_INTEGER_FIELD", "%s must be an integer" % field)
		if field != "random_seed" and int(profile[field]) < 0:
			return UtilsScript.validation_failure("NEGATIVE_PROFILE_VALUE", "%s cannot be negative" % field)
	if int(profile["random_seed"]) < 1:
		return UtilsScript.validation_failure("INVALID_RANDOM_SEED", "random_seed must be positive")
	if int(profile["outgoing_latency_min_ms"]) > int(profile["outgoing_latency_max_ms"]):
		return UtilsScript.validation_failure("INVALID_OUTGOING_LATENCY_RANGE", "Outgoing latency minimum exceeds maximum")
	if int(profile["incoming_latency_min_ms"]) > int(profile["incoming_latency_max_ms"]):
		return UtilsScript.validation_failure("INVALID_INCOMING_LATENCY_RANGE", "Incoming latency minimum exceeds maximum")
	for field in ["packet_loss_percent", "burst_loss_probability_percent", "duplicate_percent", "reorder_percent"]:
		if not _is_percentage(profile[field]):
			return UtilsScript.validation_failure("INVALID_PERCENTAGE", "%s must be in range 0..100" % field)
	if String(profile["checksum"]) != compute_checksum(profile):
		return UtilsScript.validation_failure("CHECKSUM_MISMATCH", "Network condition profile checksum mismatch")
	return UtilsScript.validation_success()


static func validate_document(document: Dictionary) -> Dictionary:
	var required_fields: Array[String] = ["schema", "document_revision", "profiles"]
	var check: Dictionary = UtilsScript.validate_exact_fields(document, required_fields)
	if not bool(check.get("success", false)):
		return check
	if String(document.get("schema", "")) != DOCUMENT_SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_DOCUMENT_SCHEMA", "Unexpected network condition preset document schema")
	if not UtilsScript.is_json_integer(document.get("document_revision")) or int(document["document_revision"]) < 1:
		return UtilsScript.validation_failure("INVALID_DOCUMENT_REVISION", "document_revision must be positive")
	if not document.get("profiles") is Array or document["profiles"].is_empty():
		return UtilsScript.validation_failure("INVALID_PROFILES", "profiles must be a non-empty Array")
	var profile_ids: Dictionary = {}
	for profile_value in document["profiles"]:
		if not profile_value is Dictionary:
			return UtilsScript.validation_failure("INVALID_PROFILE", "Every profile must be a Dictionary")
		check = validate(Dictionary(profile_value))
		if not bool(check.get("success", false)):
			return check
		var profile_id: String = String(profile_value["profile_id"])
		if profile_ids.has(profile_id):
			return UtilsScript.validation_failure("DUPLICATE_PROFILE_ID", "Duplicate profile_id: %s" % profile_id)
		profile_ids[profile_id] = true
	return UtilsScript.validation_success()


static func compute_checksum(profile: Dictionary) -> String:
	var payload: Dictionary = profile.duplicate(true)
	payload.erase("checksum")
	return UtilsScript.payload_hash(payload)


static func _is_percentage(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number: float = float(value)
	return not is_nan(number) and not is_inf(number) and number >= 0.0 and number <= 100.0


static func is_passthrough(profile: Dictionary) -> bool:
	var check: Dictionary = validate(profile)
	if not bool(check.get("success", false)):
		return false
	for field in [
		"outgoing_latency_min_ms", "outgoing_latency_max_ms",
		"incoming_latency_min_ms", "incoming_latency_max_ms", "jitter_ms",
		"burst_loss_duration_ms", "bandwidth_limit_kbps", "queue_limit_bytes",
		"lag_spike_ms", "disconnect_duration_ms",
	]:
		if int(profile.get(field, 0)) != 0:
			return false
	for field in [
		"packet_loss_percent", "burst_loss_probability_percent",
		"duplicate_percent", "reorder_percent",
	]:
		if not is_equal_approx(float(profile.get(field, 0.0)), 0.0):
			return false
	return true


static func is_profile_id(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges() or value != value.to_upper() or value.length() > 64:
		return false
	for character in value:
		if not ((character >= "A" and character <= "Z") or (character >= "0" and character <= "9") or character == "_"):
			return false
	return true
