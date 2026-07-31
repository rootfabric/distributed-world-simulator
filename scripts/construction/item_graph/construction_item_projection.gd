extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.construction_item_projection.v1"
const ITEM_INSTANCE_SCHEMA: String = "planet_simulator.item_instance.v2"
const ITEM_INSTANCE_SCHEMA_VERSION: int = 2
const FIELDS: Array[String] = [
	"schema",
	"item_instance_id",
	"definition_id",
	"display_name",
	"quantity",
	"relation",
	"components",
	"revision",
]
const ITEM_INSTANCE_FIELDS: Array[String] = [
	"schema",
	"schema_version",
	"instance_id",
	"definition_id",
	"display_name",
	"quantity",
	"relation",
	"components",
	"revision",
]
const WORLD: String = "WORLD"
const CONTAINER: String = "CONTAINER"
const ATTACHMENT: String = "ATTACHMENT"
const DESTROYED: String = "DESTROYED"
const RELATION_KINDS: Array[String] = [WORLD, CONTAINER, ATTACHMENT, DESTROYED]

static func create(
	item_instance_id: String,
	definition_id: String,
	display_name: String,
	quantity: int,
	relation: Dictionary,
	components: Dictionary = {},
	revision: int = 0
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"item_instance_id": item_instance_id,
		"definition_id": definition_id,
		"display_name": display_name,
		"quantity": quantity,
		"relation": _canonical_dictionary(relation),
		"components": _canonical_dictionary(components),
		"revision": revision,
	}

static func from_item_instance_dict(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, ITEM_INSTANCE_FIELDS)
	if not bool(exact.get("success", false)):
		return _failure("INVALID_ITEM_INSTANCE_PROJECTION_SOURCE", {"cause": exact})
	if value.get("schema") != ITEM_INSTANCE_SCHEMA or int(value.get("schema_version", -1)) != ITEM_INSTANCE_SCHEMA_VERSION:
		return _failure("UNSUPPORTED_ITEM_INSTANCE_PROJECTION_SOURCE")
	var projection: Dictionary = create(
		String(value.get("instance_id", "")),
		String(value.get("definition_id", "")),
		String(value.get("display_name", "")),
		int(value.get("quantity", 0)),
		Dictionary(value.get("relation", {})),
		Dictionary(value.get("components", {})),
		int(value.get("revision", -1))
	)
	var validation: Dictionary = validate(projection)
	if not bool(validation.get("success", false)):
		return validation
	return _success({"projection": projection})

static func to_item_instance_dict(value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	return _success({
		"item": {
			"schema": ITEM_INSTANCE_SCHEMA,
			"schema_version": ITEM_INSTANCE_SCHEMA_VERSION,
			"instance_id": String(value["item_instance_id"]),
			"definition_id": String(value["definition_id"]),
			"display_name": String(value["display_name"]),
			"quantity": int(value["quantity"]),
			"relation": _canonical_dictionary(value["relation"]),
			"components": _canonical_dictionary(value["components"]),
			"revision": int(value["revision"]),
		}
	})

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_ITEM_PROJECTION_SCHEMA")
	if not _is_identifier(String(value.get("item_instance_id", "")), "item/"):
		return _failure("INVALID_CONSTRUCTION_ITEM_ID")
	if not _is_token(String(value.get("definition_id", ""))):
		return _failure("INVALID_CONSTRUCTION_ITEM_DEFINITION_ID")
	if typeof(value.get("display_name")) != TYPE_STRING:
		return _failure("INVALID_CONSTRUCTION_ITEM_DISPLAY_NAME")
	if not UtilsScript.is_json_integer(value.get("quantity")) or int(value["quantity"]) < 1:
		return _failure("INVALID_CONSTRUCTION_ITEM_QUANTITY")
	if not UtilsScript.is_json_integer(value.get("revision")) or int(value["revision"]) < 0:
		return _failure("INVALID_CONSTRUCTION_ITEM_REVISION")
	if typeof(value.get("relation")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_ITEM_RELATION")
	var relation_validation: Dictionary = validate_relation(value["relation"])
	if not bool(relation_validation.get("success", false)):
		return relation_validation
	if typeof(value.get("components")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_ITEM_COMPONENTS")
	if not bool(UtilsScript.canonicalize(value.get("components"), "$.components").get("success", false)):
		return _failure("CONSTRUCTION_ITEM_COMPONENTS_NOT_JSON_SAFE")
	if not bool(UtilsScript.canonicalize(value, "$").get("success", false)):
		return _failure("CONSTRUCTION_ITEM_PROJECTION_NOT_JSON_SAFE")
	return _success()

static func validate_relation(relation: Dictionary) -> Dictionary:
	if not bool(UtilsScript.canonicalize(relation, "$.relation").get("success", false)):
		return _failure("CONSTRUCTION_ITEM_RELATION_NOT_JSON_SAFE")
	var kind: String = String(relation.get("kind", ""))
	if not RELATION_KINDS.has(kind):
		return _failure("INVALID_CONSTRUCTION_ITEM_RELATION_KIND")
	match kind:
		CONTAINER:
			if not _is_token(String(relation.get("container_id", ""))):
				return _failure("INVALID_CONSTRUCTION_CONTAINER_ID")
			if not UtilsScript.is_json_integer(relation.get("slot_index", -2)) or int(relation.get("slot_index", -2)) < -1:
				return _failure("INVALID_CONSTRUCTION_CONTAINER_SLOT")
		ATTACHMENT:
			if not _is_identifier(String(relation.get("assembly_id", "")), "construct/"):
				return _failure("INVALID_CONSTRUCTION_ATTACHMENT_ASSEMBLY")
			if not _is_identifier(String(relation.get("parent_item_id", "")), "item/"):
				return _failure("INVALID_CONSTRUCTION_ATTACHMENT_PARENT")
			if not _is_identifier(String(relation.get("socket_id", "")), "part/"):
				return _failure("INVALID_CONSTRUCTION_ATTACHMENT_SOCKET")
		WORLD:
			if relation.has("entity_id") and not _is_token(String(relation.get("entity_id", ""))):
				return _failure("INVALID_CONSTRUCTION_WORLD_ENTITY_ID")
		DESTROYED:
			pass
	return _success()

static func attachment_relation(construct_id: String, root_item_instance_id: String, part_id: String) -> Dictionary:
	return {
		"kind": ATTACHMENT,
		"assembly_id": construct_id,
		"parent_item_id": root_item_instance_id,
		"socket_id": part_id,
	}

static func container_relation(container_id: String, slot_index: int = -1) -> Dictionary:
	return {"kind": CONTAINER, "container_id": container_id, "slot_index": slot_index}

static func world_relation() -> Dictionary:
	return {"kind": WORLD}

static func fingerprint(value: Dictionary) -> String:
	return UtilsScript.payload_hash(value)

static func _canonical_dictionary(value: Dictionary) -> Dictionary:
	var result: Dictionary = UtilsScript.canonicalize(value)
	if bool(result.get("success", false)) and result.get("value") is Dictionary:
		return Dictionary(result["value"])
	return value.duplicate(true)

static func _is_identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and _is_token(value)

static func _is_token(value: String) -> bool:
	if value.strip_edges().is_empty() or value != value.strip_edges():
		return false
	for index in range(value.length()):
		var code: int = value.unicode_at(index)
		var allowed: bool = (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
			or code in [45, 46, 47, 58, 95]
		)
		if not allowed:
			return false
	return true

static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result
