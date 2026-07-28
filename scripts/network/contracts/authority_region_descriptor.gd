extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.authority_region_descriptor.v1"
const PROTOCOL_VERSION: int = 1
const LIFECYCLE_STATES: Array[String] = ["DORMANT", "WARM", "ACTIVE", "UNLOADING"]
const SELECTOR_FIELDS: Array[String] = ["kind", "partition_prefix", "chunk_ids"]
const SELECTOR_KINDS: Array[String] = ["GLOBAL_SPACE", "PARTITION_PREFIX", "CHUNK_SET"]
const FIELDS: Array[String] = [
	"schema", "protocol_version", "region_id", "universe_id", "instance_id", "space_id",
	"partition_scheme", "partition_revision", "selector", "owner_node_id",
	"authority_epoch", "lifecycle_state", "descriptor_revision",
]


static func create(
	region_id: String,
	universe_id: String,
	instance_id: String,
	space_id: String,
	partition_scheme: String,
	partition_revision: int,
	selector: Dictionary,
	owner_node_id: String,
	authority_epoch: int,
	lifecycle_state: String,
	descriptor_revision: int = 0
) -> Dictionary:
	return {
		"schema": SCHEMA, "protocol_version": PROTOCOL_VERSION,
		"region_id": region_id, "universe_id": universe_id, "instance_id": instance_id,
		"space_id": space_id, "partition_scheme": partition_scheme,
		"partition_revision": partition_revision, "selector": selector.duplicate(true),
		"owner_node_id": owner_node_id, "authority_epoch": authority_epoch,
		"lifecycle_state": lifecycle_state, "descriptor_revision": descriptor_revision,
	}


static func validate(value: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(check.get("success", false)):
		return check
	for field in ["schema", "region_id", "universe_id", "instance_id", "space_id", "partition_scheme", "owner_node_id", "lifecycle_state"]:
		check = UtilsScript.require_string(value, field)
		if not bool(check.get("success", false)):
			return check
	if String(value["schema"]) != SCHEMA:
		return UtilsScript.validation_failure("UNSUPPORTED_SCHEMA", "Unexpected authority region schema")
	for field in ["protocol_version", "partition_revision", "authority_epoch", "descriptor_revision"]:
		check = UtilsScript.require_json_integer(value, field)
		if not bool(check.get("success", false)):
			return check
	if int(value["protocol_version"]) != PROTOCOL_VERSION:
		return UtilsScript.validation_failure("UNSUPPORTED_PROTOCOL", "Unsupported protocol version")
	if int(value["partition_revision"]) < 0 or int(value["authority_epoch"]) < 1 or int(value["descriptor_revision"]) < 0:
		return UtilsScript.validation_failure("INVALID_REVISION", "Invalid region revisions")
	if not LIFECYCLE_STATES.has(String(value["lifecycle_state"])):
		return UtilsScript.validation_failure("INVALID_LIFECYCLE_STATE", "Invalid region lifecycle state")
	if typeof(value.get("selector")) != TYPE_DICTIONARY:
		return UtilsScript.validation_failure("INVALID_SELECTOR", "selector must be a Dictionary")
	check = _validate_selector(value["selector"])
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
	canonical["selector"] = value["selector"].duplicate(true)
	canonical["selector"]["chunk_ids"] = Array(canonical["selector"]["chunk_ids"]).duplicate()
	canonical["selector"]["chunk_ids"].sort()
	var round_trip: Dictionary = UtilsScript.json_round_trip(canonical)
	return round_trip.get("value", {}) if bool(round_trip.get("success", false)) else {}


static func _validate_selector(selector: Dictionary) -> Dictionary:
	var check: Dictionary = UtilsScript.validate_exact_fields(selector, SELECTOR_FIELDS)
	if not bool(check.get("success", false)):
		return check
	check = UtilsScript.require_string(selector, "kind")
	if not bool(check.get("success", false)):
		return check
	check = UtilsScript.require_string(selector, "partition_prefix", true)
	if not bool(check.get("success", false)):
		return check
	if not SELECTOR_KINDS.has(String(selector["kind"])):
		return UtilsScript.validation_failure("INVALID_SELECTOR_KIND", "Unknown selector kind")
	if typeof(selector.get("chunk_ids")) != TYPE_ARRAY:
		return UtilsScript.validation_failure("INVALID_FIELD_TYPE", "chunk_ids must be an Array")
	var seen: Dictionary = {}
	for chunk_id in selector["chunk_ids"]:
		if typeof(chunk_id) != TYPE_STRING or String(chunk_id).is_empty() or seen.has(chunk_id):
			return UtilsScript.validation_failure("INVALID_CHUNK_SET", "chunk_ids must be unique non-empty Strings")
		seen[chunk_id] = true
	match String(selector["kind"]):
		"GLOBAL_SPACE":
			if not String(selector["partition_prefix"]).is_empty() or not selector["chunk_ids"].is_empty():
				return UtilsScript.validation_failure("INVALID_SELECTOR", "GLOBAL_SPACE selector cannot contain partition data")
		"PARTITION_PREFIX":
			if String(selector["partition_prefix"]).is_empty() or not selector["chunk_ids"].is_empty():
				return UtilsScript.validation_failure("INVALID_SELECTOR", "PARTITION_PREFIX requires only partition_prefix")
		"CHUNK_SET":
			if not String(selector["partition_prefix"]).is_empty() or selector["chunk_ids"].is_empty():
				return UtilsScript.validation_failure("INVALID_SELECTOR", "CHUNK_SET requires only chunk_ids")
	return UtilsScript.validation_success()
