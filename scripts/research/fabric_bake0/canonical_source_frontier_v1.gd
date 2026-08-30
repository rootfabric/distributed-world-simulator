extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_canonical_source_frontier.v1"
const FIELDS: Array[String] = ["schema", "sources", "frontier_hash", "checksum"]

static func create(sources: Array) -> Dictionary:
	var ordered: Array = []
	for raw in sources:
		ordered.append(raw.duplicate(true) if typeof(raw) == TYPE_DICTIONARY else raw)
	ordered.sort_custom(func(a, b): return _key(a) < _key(b))
	var value: Dictionary = {
		"schema": SCHEMA,
		"sources": ordered,
		"frontier_hash": Utils.canonical_hash(ordered),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_CANONICAL_SOURCE_FRONTIER_SCHEMA")
	if typeof(value.get("sources")) != TYPE_ARRAY or value["sources"].is_empty():
		return Utils.failure("INVALID_CANONICAL_SOURCE_FRONTIER")
	var previous := ""
	for index in range(value["sources"].size()):
		if typeof(value["sources"][index]) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_CANONICAL_SOURCE_REVISION", {"index": index})
		var source: Dictionary = value["sources"][index]
		checked = Utils.validate_source_revision(source)
		if not bool(checked.get("success", false)):
			return checked
		var current := _key(source)
		if index > 0 and current <= previous:
			return Utils.failure("CANONICAL_SOURCE_FRONTIER_NOT_SORTED_UNIQUE", {"index": index})
		previous = current
	if not Utils.is_lower_hex_64(value.get("frontier_hash")):
		return Utils.failure("INVALID_CANONICAL_SOURCE_FRONTIER_HASH")
	if String(value["frontier_hash"]) != Utils.canonical_hash(value["sources"]):
		return Utils.failure("CANONICAL_SOURCE_FRONTIER_HASH_MISMATCH")
	return Utils.validate_checksum(value)

static func source_keys(value: Dictionary) -> Array:
	var keys: Array = []
	for source in value.get("sources", []):
		keys.append(Utils.source_key(String(source["source_domain"]), String(source["source_id"])))
	return keys

static func _key(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return str(value)
	return "%s|%s" % [String(value.get("source_domain", "")), String(value.get("source_id", ""))]
