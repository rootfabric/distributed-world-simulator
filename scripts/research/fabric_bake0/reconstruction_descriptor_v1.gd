extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_reconstruction_descriptor.v1"
const REGION_FIELDS: Array[String] = ["region_id", "source_keys"]
const FIELDS: Array[String] = [
	"schema", "descriptor_id", "source_frontier_hash", "mapping_hash",
	"hidden_state_policy", "region_mappings", "conservation_reconciliation",
	"event_frontier_hash", "reconstruction_version", "checksum",
]
const HIDDEN_STATE_POLICIES: Array[String] = [
	"CANONICAL_ONLY", "CANONICAL_PLUS_REDUCED", "CONSERVATIVE_INITIALIZATION",
]
const RECONCILIATIONS: Array[String] = ["BOUNDED", "STRICT"]

static func create(
	descriptor_id: String, source_frontier_hash: String, mapping_hash: String,
	hidden_state_policy: String, region_mappings: Array,
	conservation_reconciliation: String, event_frontier_hash: String,
	reconstruction_version: String
) -> Dictionary:
	var mappings := Utils.sorted_dicts(region_mappings, "region_id")
	for index in range(mappings.size()):
		if typeof(mappings[index]) == TYPE_DICTIONARY:
			var mapping: Dictionary = mappings[index]
			if typeof(mapping.get("source_keys")) == TYPE_ARRAY:
				mapping["source_keys"] = Utils.sorted_strings(mapping["source_keys"])
	var value: Dictionary = {
		"schema": SCHEMA,
		"descriptor_id": descriptor_id,
		"source_frontier_hash": source_frontier_hash,
		"mapping_hash": mapping_hash,
		"hidden_state_policy": hidden_state_policy,
		"region_mappings": mappings,
		"conservation_reconciliation": conservation_reconciliation,
		"event_frontier_hash": event_frontier_hash,
		"reconstruction_version": reconstruction_version,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_RECONSTRUCTION_DESCRIPTOR_SCHEMA")
	if not Utils.is_canonical_id(value.get("descriptor_id"), 2):
		return Utils.failure("INVALID_RECONSTRUCTION_DESCRIPTOR_ID")
	for field in ["source_frontier_hash", "mapping_hash", "event_frontier_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_RECONSTRUCTION_HASH", {"field": field})
	if not HIDDEN_STATE_POLICIES.has(String(value.get("hidden_state_policy", ""))):
		return Utils.failure("INVALID_HIDDEN_STATE_POLICY")
	if not RECONCILIATIONS.has(String(value.get("conservation_reconciliation", ""))):
		return Utils.failure("INVALID_RECONSTRUCTION_RECONCILIATION")
	if typeof(value.get("reconstruction_version")) != TYPE_STRING or String(value["reconstruction_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_RECONSTRUCTION_VERSION")
	if typeof(value.get("region_mappings")) != TYPE_ARRAY or value["region_mappings"].is_empty():
		return Utils.failure("INVALID_RECONSTRUCTION_REGION_MAPPINGS")
	var previous := ""
	for index in range(value["region_mappings"].size()):
		var raw = value["region_mappings"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_RECONSTRUCTION_REGION_MAPPING", {"index": index})
		var mapping: Dictionary = raw
		checked = Utils.validate_exact_fields(mapping, REGION_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(mapping.get("region_id"), 2):
			return Utils.failure("INVALID_RECONSTRUCTION_REGION_ID", {"index": index})
		checked = Utils.validate_sorted_unique_strings(mapping.get("source_keys"), false)
		if not bool(checked.get("success", false)):
			return checked
		for source_key in mapping["source_keys"]:
			if not Utils.is_canonical_id(source_key, 3):
				return Utils.failure("INVALID_RECONSTRUCTION_SOURCE_KEY", {"index": index})
		var current := String(mapping["region_id"])
		if index > 0 and current <= previous:
			return Utils.failure("RECONSTRUCTION_REGIONS_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	return Utils.validate_checksum(value)

static func validate_source_coverage(value: Dictionary, allowed_source_keys: Array) -> Dictionary:
	var checked := validate(value)
	if not bool(checked.get("success", false)):
		return checked
	var covered: Dictionary = {}
	for mapping in value["region_mappings"]:
		for source_key in mapping["source_keys"]:
			if not allowed_source_keys.has(source_key):
				return Utils.failure("RECONSTRUCTION_SOURCE_OUTSIDE_FRONTIER", {"source_key": source_key})
			covered[String(source_key)] = true
	for source_key in allowed_source_keys:
		if not covered.has(String(source_key)):
			return Utils.failure("RECONSTRUCTION_SOURCE_NOT_COVERED", {"source_key": source_key})
	return Utils.success()
