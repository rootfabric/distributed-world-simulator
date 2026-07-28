extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.simulation_space_descriptor.v1"
const PROTOCOL_VERSION: int = 1
const FIELDS: Array[String] = [
	"schema", "protocol_version", "space_id", "instance_id", "universe_id",
	"frame_id", "partition_scheme", "partition_revision", "authority_region_ids",
	"descriptor_revision",
]


static func create(
	space_id: String,
	instance_id: String,
	universe_id: String,
	frame_id: String,
	partition_scheme: String,
	partition_revision: int,
	authority_region_ids: Array[String],
	descriptor_revision: int = 0
) -> Dictionary:
	var regions: Array[String] = authority_region_ids.duplicate()
	regions.sort()
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"space_id": space_id, "instance_id": instance_id, "universe_id": universe_id,
		"frame_id": frame_id, "partition_scheme": partition_scheme,
		"partition_revision": partition_revision, "authority_region_ids": regions,
		"descriptor_revision": descriptor_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "space_id", "instance_id", "universe_id", "frame_id", "partition_scheme"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected space descriptor schema")
	for field in ["protocol_version", "partition_revision", "descriptor_revision"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if int(value["partition_revision"]) < 0 or int(value["descriptor_revision"]) < 0:
		return UtilsScript.validation_failure("INVALID_REVISION", "Descriptor revisions cannot be negative")
	check = _validate_unique_strings(value.get("authority_region_ids"), "authority_region_ids")
	if not bool(check.get("success", false)):
		return check
	var safe: Dictionary = UtilsScript.canonicalize(value)
	if not bool(safe.get("success", false)):
		return UtilsScript.validation_failure("NON_CANONICAL_PAYLOAD", String(safe.get("error", "")))
	return UtilsScript.validation_success()


static func normalize(value: Dictionary) -> Dictionary:
	if not bool(validate(value).get("success", false)):
		return {}
	var canonical: Dictionary = value.duplicate(true)
	canonical["authority_region_ids"] = Array(canonical["authority_region_ids"]).duplicate()
	canonical["authority_region_ids"].sort()
	var round_trip: Dictionary = UtilsScript.json_round_trip(canonical)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func _validate_unique_strings(value, field: String) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must be an Array" % field)
	var seen: Dictionary = {}
	for entry in value:
		if typeof(entry) != TYPE_STRING or String(entry).strip_edges().is_empty():
			return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "%s must contain non-empty Strings" % field)
		if seen.has(entry):
			return UtilsScript.validation_failure("DUPLICATE_VALUE", "%s must be unique" % field)
		seen[entry] = true
	return UtilsScript.validation_success()
