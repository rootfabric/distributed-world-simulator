extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")

const SCHEMA: String = "planet_simulator.construction_item_mutation.v1"
const OP_CREATE: String = "CREATE"
const OP_UPDATE: String = "UPDATE"
const OP_DELETE: String = "DELETE"
const OPERATION_KINDS: Array[String] = [OP_CREATE, OP_UPDATE, OP_DELETE]
const PURPOSE_CREATE_ROOT: String = "CREATE_CONSTRUCT_ROOT"
const PURPOSE_ATTACH_PART: String = "ATTACH_PART"
const PURPOSE_DETACH_PART: String = "DETACH_PART"
const PURPOSE_CONSUME_MATERIAL: String = "CONSUME_MATERIAL"
const PURPOSE_DESTROY_ROOT: String = "DESTROY_CONSTRUCT_ROOT"
const PURPOSES: Array[String] = [
	PURPOSE_CREATE_ROOT,
	PURPOSE_ATTACH_PART,
	PURPOSE_DETACH_PART,
	PURPOSE_CONSUME_MATERIAL,
	PURPOSE_DESTROY_ROOT,
]
const FIELDS: Array[String] = [
	"schema",
	"operation_kind",
	"purpose",
	"item_instance_id",
	"before_projection",
	"after_projection",
]

static func create(
	operation_kind: String,
	purpose: String,
	item_instance_id: String,
	before_projection: Dictionary = {},
	after_projection: Dictionary = {}
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"operation_kind": operation_kind,
		"purpose": purpose,
		"item_instance_id": item_instance_id,
		"before_projection": before_projection.duplicate(true),
		"after_projection": after_projection.duplicate(true),
	}

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_ITEM_MUTATION_SCHEMA")
	var operation_kind: String = String(value.get("operation_kind", ""))
	var purpose: String = String(value.get("purpose", ""))
	var item_id: String = String(value.get("item_instance_id", ""))
	if not OPERATION_KINDS.has(operation_kind):
		return _failure("INVALID_CONSTRUCTION_ITEM_OPERATION_KIND")
	if not PURPOSES.has(purpose):
		return _failure("INVALID_CONSTRUCTION_ITEM_MUTATION_PURPOSE")
	if not item_id.begins_with("item/") or item_id.length() <= 5:
		return _failure("INVALID_CONSTRUCTION_ITEM_MUTATION_ID")
	if typeof(value.get("before_projection")) != TYPE_DICTIONARY or typeof(value.get("after_projection")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_ITEM_MUTATION_PROJECTIONS")
	var before: Dictionary = value["before_projection"]
	var after: Dictionary = value["after_projection"]
	match operation_kind:
		OP_CREATE:
			if not before.is_empty():
				return _failure("CREATE_ITEM_MUTATION_HAS_BEFORE_STATE")
			var after_validation: Dictionary = ProjectionScript.validate(after)
			if not bool(after_validation.get("success", false)):
				return after_validation
			if String(after["item_instance_id"]) != item_id or int(after["revision"]) != 0:
				return _failure("INVALID_CREATED_ITEM_PROJECTION")
			if purpose != PURPOSE_CREATE_ROOT:
				return _failure("INVALID_CREATE_ITEM_MUTATION_PURPOSE")
			if not _is_construction_root(after):
				return _failure("CREATED_ROOT_ITEM_LACKS_CONSTRUCTION_COMPONENT")
		OP_UPDATE:
			var before_validation: Dictionary = ProjectionScript.validate(before)
			if not bool(before_validation.get("success", false)):
				return before_validation
			var after_validation: Dictionary = ProjectionScript.validate(after)
			if not bool(after_validation.get("success", false)):
				return after_validation
			if String(before["item_instance_id"]) != item_id or String(after["item_instance_id"]) != item_id:
				return _failure("ITEM_MUTATION_IDENTITY_MISMATCH")
			if int(after["revision"]) != int(before["revision"]) + 1:
				return _failure("ITEM_MUTATION_REVISION_CHAIN_MISMATCH")
			if String(after["definition_id"]) != String(before["definition_id"]) or String(after["display_name"]) != String(before["display_name"]):
				return _failure("ITEM_MUTATION_IMMUTABLE_IDENTITY_CHANGED")
			var purpose_validation: Dictionary = _validate_update_purpose(purpose, before, after)
			if not bool(purpose_validation.get("success", false)):
				return purpose_validation
		OP_DELETE:
			var before_validation: Dictionary = ProjectionScript.validate(before)
			if not bool(before_validation.get("success", false)):
				return before_validation
			if not after.is_empty():
				return _failure("DELETE_ITEM_MUTATION_HAS_AFTER_STATE")
			if String(before["item_instance_id"]) != item_id:
				return _failure("DELETED_ITEM_IDENTITY_MISMATCH")
			if purpose != PURPOSE_DESTROY_ROOT or not _is_construction_root(before):
				return _failure("INVALID_DELETE_ITEM_MUTATION_PURPOSE")
	return _success()

static func _validate_update_purpose(purpose: String, before: Dictionary, after: Dictionary) -> Dictionary:
	var before_relation: Dictionary = before["relation"]
	var after_relation: Dictionary = after["relation"]
	match purpose:
		PURPOSE_ATTACH_PART:
			if String(after_relation.get("kind", "")) != ProjectionScript.ATTACHMENT:
				return _failure("ATTACH_PART_MUTATION_LACKS_ATTACHMENT_RELATION")
			if String(before_relation.get("kind", "")) == ProjectionScript.ATTACHMENT:
				return _failure("ATTACH_PART_SOURCE_ALREADY_ATTACHED")
			if int(after["quantity"]) != int(before["quantity"]) or after["components"] != before["components"]:
				return _failure("ATTACH_PART_MUTATED_ITEM_PAYLOAD")
		PURPOSE_DETACH_PART:
			if String(before_relation.get("kind", "")) != ProjectionScript.ATTACHMENT:
				return _failure("DETACH_PART_SOURCE_NOT_ATTACHED")
			if not [ProjectionScript.CONTAINER, ProjectionScript.WORLD].has(String(after_relation.get("kind", ""))):
				return _failure("DETACH_PART_TARGET_NOT_TRANSFERABLE")
			if int(after["quantity"]) != int(before["quantity"]) or after["components"] != before["components"]:
				return _failure("DETACH_PART_MUTATED_ITEM_PAYLOAD")
		PURPOSE_CONSUME_MATERIAL:
			if before_relation != after_relation or before["components"] != after["components"]:
				return _failure("CONSUME_MATERIAL_CHANGED_LOCATION_OR_COMPONENTS")
			if int(after["quantity"]) >= int(before["quantity"]):
				return _failure("CONSUME_MATERIAL_DID_NOT_DECREASE_QUANTITY")
		_:
			return _failure("INVALID_UPDATE_ITEM_MUTATION_PURPOSE")
	return _success()

static func _is_construction_root(projection: Dictionary) -> bool:
	var components = projection.get("components", {})
	if not components is Dictionary:
		return false
	var root = Dictionary(components).get("construction_root", {})
	return root is Dictionary and String(Dictionary(root).get("schema", "")) == "planet_simulator.construction_root_component.v1" and String(Dictionary(root).get("construct_id", "")).begins_with("construct/")

static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
