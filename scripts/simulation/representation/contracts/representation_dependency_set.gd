extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")

const SCHEMA := "planet_simulator.representation_dependency_set.v1"
const CHILD_FIELDS: Array[String] = [
	"source_domain",
	"source_id",
	"authority_epoch",
	"source_revision",
	"source_hash",
]
const FIELDS: Array[String] = [
	"schema",
	"source_domain",
	"source_id",
	"scope_id",
	"child_revisions",
	"dependency_hash",
	"checksum",
]


static func create(
	source_domain: String,
	source_id: String,
	scope_id: String,
	child_revisions: Array
) -> Dictionary:
	var children: Array = _sorted_children(child_revisions)
	var value: Dictionary = {
		"schema": SCHEMA,
		"source_domain": source_domain,
		"source_id": source_id,
		"scope_id": scope_id,
		"child_revisions": children,
		"dependency_hash": Utils.payload_hash(children),
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}


static func validate(value: Dictionary) -> Dictionary:
	var checked: Dictionary = Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_REPRESENTATION_DEPENDENCY_SET_SCHEMA")
	if not Utils.is_source_domain(value.get("source_domain")):
		return Utils.failure("INVALID_REPRESENTATION_SOURCE_DOMAIN")
	if not Utils.is_canonical_id(value.get("source_id"), 2) or not Utils.is_canonical_id(value.get("scope_id"), 2):
		return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_ID")
	if typeof(value.get("child_revisions")) != TYPE_ARRAY or value["child_revisions"].is_empty():
		return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_CHILDREN")
	var previous_key: String = ""
	for index in range(value["child_revisions"].size()):
		var raw_child = value["child_revisions"][index]
		if typeof(raw_child) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_CHILD", {"index": index})
		var child: Dictionary = raw_child
		checked = Utils.validate_exact_fields(child, CHILD_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if not Utils.is_source_domain(child.get("source_domain")) or not Utils.is_canonical_id(child.get("source_id"), 2):
			return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_CHILD", {"index": index})
		if not Utils.is_json_integer(child.get("authority_epoch")) or int(child["authority_epoch"]) < 1:
			return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_CHILD", {"index": index})
		if not Utils.is_json_integer(child.get("source_revision")) or int(child["source_revision"]) < 0:
			return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_CHILD", {"index": index})
		if not Utils.is_lower_hex_64(child.get("source_hash")):
			return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_CHILD", {"index": index})
		var current_key: String = "%s|%s" % [child["source_domain"], child["source_id"]]
		if index > 0 and current_key <= previous_key:
			return Utils.failure("REPRESENTATION_DEPENDENCIES_NOT_SORTED_UNIQUE", {"index": index})
		previous_key = current_key
	if not Utils.is_lower_hex_64(value.get("dependency_hash")):
		return Utils.failure("INVALID_REPRESENTATION_DEPENDENCY_HASH")
	if String(value["dependency_hash"]) != Utils.payload_hash(value["child_revisions"]):
		return Utils.failure("REPRESENTATION_DEPENDENCY_HASH_MISMATCH")
	return Utils.validate_checksum(value)


static func _sorted_children(values: Array) -> Array:
	var output: Array = []
	for raw_value in values:
		var insert_at: int = output.size()
		var key: String = _child_key(raw_value)
		for index in range(output.size()):
			if key < _child_key(output[index]):
				insert_at = index
				break
		output.insert(insert_at, raw_value.duplicate(true) if typeof(raw_value) == TYPE_DICTIONARY else raw_value)
	return output


static func _child_key(value) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return str(value)
	return "%s|%s" % [value.get("source_domain", ""), value.get("source_id", "")]
