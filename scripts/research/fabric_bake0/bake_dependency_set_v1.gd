extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_dependency_set.v1"
const DEPENDENCY_FIELDS: Array[String] = ["dependency_id", "dependency_hash"]
const FIELDS: Array[String] = ["schema", "dependencies", "dependency_hash", "checksum"]

static func create(dependencies: Array) -> Dictionary:
	var ordered := Utils.sorted_dicts(dependencies, "dependency_id")
	var value: Dictionary = {
		"schema": SCHEMA,
		"dependencies": ordered,
		"dependency_hash": Utils.canonical_hash(ordered),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_BAKE_DEPENDENCY_SET_SCHEMA")
	if typeof(value.get("dependencies")) != TYPE_ARRAY:
		return Utils.failure("INVALID_BAKE_DEPENDENCIES")
	var previous := ""
	for index in range(value["dependencies"].size()):
		var raw = value["dependencies"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_BAKE_DEPENDENCY", {"index": index})
		var dependency: Dictionary = raw
		checked = Utils.validate_exact_fields(dependency, DEPENDENCY_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_canonical_id(dependency.get("dependency_id"), 2):
			return Utils.failure("INVALID_BAKE_DEPENDENCY_ID", {"index": index})
		if not Utils.is_lower_hex_64(dependency.get("dependency_hash")):
			return Utils.failure("INVALID_BAKE_DEPENDENCY_HASH", {"index": index})
		var current := String(dependency["dependency_id"])
		if index > 0 and current <= previous:
			return Utils.failure("BAKE_DEPENDENCIES_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	if not Utils.is_lower_hex_64(value.get("dependency_hash")):
		return Utils.failure("INVALID_BAKE_DEPENDENCY_SET_HASH")
	if String(value["dependency_hash"]) != Utils.canonical_hash(value["dependencies"]):
		return Utils.failure("BAKE_DEPENDENCY_SET_HASH_MISMATCH")
	return Utils.validate_checksum(value)
