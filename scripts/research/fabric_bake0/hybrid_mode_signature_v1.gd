extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_hybrid_mode_signature.v1"
const DEPENDENCY_FIELDS: Array[String] = ["dependency_id", "version_hash"]
const FIELDS: Array[String] = [
	"schema", "source_frontier_hash", "physical_topology_hash",
	"active_relation_ids", "complementarity_active_ids",
	"boundary_contract_hash", "dependency_versions", "compiler_version",
	"mode_hash", "checksum",
]
const FORBIDDEN_DEVICE_TOKENS: Array[String] = ["motor", "gearbox", "clutch", "valve"]

static func create(
	source_frontier_hash: String,
	physical_topology_hash: String,
	active_relation_ids: Array,
	complementarity_active_ids: Array,
	boundary_contract_hash: String,
	dependency_versions: Array,
	compiler_version: String
) -> Dictionary:
	var relations := Utils.sorted_strings(active_relation_ids)
	var active_set := Utils.sorted_strings(complementarity_active_ids)
	var dependencies := Utils.sorted_dicts(dependency_versions, "dependency_id")
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_frontier_hash": source_frontier_hash,
		"physical_topology_hash": physical_topology_hash,
		"active_relation_ids": relations,
		"complementarity_active_ids": active_set,
		"boundary_contract_hash": boundary_contract_hash,
		"dependency_versions": dependencies,
		"compiler_version": compiler_version,
		"mode_hash": "",
		"checksum": "",
	}
	value["mode_hash"] = identity_hash(value)
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_HYBRID_MODE_SIGNATURE_SCHEMA")
	for field in ["source_frontier_hash", "physical_topology_hash", "boundary_contract_hash", "mode_hash"]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_HYBRID_MODE_HASH", {"field": field})
	checked = Utils.validate_sorted_unique_strings(value.get("active_relation_ids"), true)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_sorted_unique_strings(value.get("complementarity_active_ids"), true)
	if not bool(checked.get("success", false)):
		return checked
	for relation_id in value["active_relation_ids"]:
		if not Utils.is_canonical_id(relation_id, 2):
			return Utils.failure("INVALID_HYBRID_ACTIVE_RELATION_ID")
		if _contains_device_token(String(relation_id)):
			return Utils.failure("DEVICE_SPECIFIC_HYBRID_MODE_FORBIDDEN", {"relation_id": relation_id})
	for active_id in value["complementarity_active_ids"]:
		if not Utils.is_canonical_id(active_id, 2):
			return Utils.failure("INVALID_HYBRID_COMPLEMENTARITY_ID")
		if _contains_device_token(String(active_id)):
			return Utils.failure("DEVICE_SPECIFIC_HYBRID_MODE_FORBIDDEN", {"active_id": active_id})
	if typeof(value.get("dependency_versions")) != TYPE_ARRAY:
		return Utils.failure("INVALID_HYBRID_MODE_DEPENDENCIES")
	var previous := ""
	for index in range(value["dependency_versions"].size()):
		var raw = value["dependency_versions"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_HYBRID_MODE_DEPENDENCY", {"index": index})
		var dependency: Dictionary = raw
		checked = Utils.validate_exact_fields(dependency, DEPENDENCY_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(dependency.get("dependency_id"), 2):
			return Utils.failure("INVALID_HYBRID_MODE_DEPENDENCY_ID", {"index": index})
		if not Utils.is_lower_hex_64(dependency.get("version_hash")):
			return Utils.failure("INVALID_HYBRID_MODE_DEPENDENCY_HASH", {"index": index})
		var current := String(dependency["dependency_id"])
		if index > 0 and current <= previous:
			return Utils.failure("HYBRID_MODE_DEPENDENCIES_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	if typeof(value.get("compiler_version")) != TYPE_STRING or String(value["compiler_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_HYBRID_MODE_COMPILER_VERSION")
	if String(value["mode_hash"]) != identity_hash(value):
		return Utils.failure("HYBRID_MODE_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func identity_hash(value: Dictionary) -> String:
	return Utils.canonical_hash({
		"source_frontier_hash": value.get("source_frontier_hash", ""),
		"physical_topology_hash": value.get("physical_topology_hash", ""),
		"active_relation_ids": value.get("active_relation_ids", []),
		"complementarity_active_ids": value.get("complementarity_active_ids", []),
		"boundary_contract_hash": value.get("boundary_contract_hash", ""),
		"dependency_versions": value.get("dependency_versions", []),
		"compiler_version": value.get("compiler_version", ""),
	})

static func dependency_fingerprint(value: Dictionary) -> String:
	return Utils.canonical_hash(value.get("dependency_versions", []))

static func _contains_device_token(value: String) -> bool:
	var lower := value.to_lower()
	for token in FORBIDDEN_DEVICE_TOKENS:
		if lower.find(token) >= 0:
			return true
	return false
