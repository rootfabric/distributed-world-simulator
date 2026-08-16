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
const PURPOSE_TRANSFER_FABRICATION_INPUT: String = "TRANSFER_FABRICATION_INPUT"
const PURPOSE_CREATE_FABRICATED_ITEM: String = "CREATE_FABRICATED_ITEM"
const PURPOSE_CONSUME_FABRICATION_INPUT: String = "CONSUME_FABRICATION_INPUT"
const PURPOSE_APPLY_DAMAGE: String = "APPLY_CONSTRUCTION_DAMAGE"
const PURPOSE_REBIND_SPLIT_PART: String = "REBIND_SPLIT_PART"
const PURPOSE_SALVAGE_PART: String = "SALVAGE_CONSTRUCTION_PART"
const PURPOSE_REPAIR_PART: String = "REPAIR_CONSTRUCTION_PART"
const PURPOSE_EDIT_PARAMETRIC_MEMBER: String = "EDIT_PARAMETRIC_MEMBER"
const PURPOSES: Array[String] = [
	PURPOSE_CREATE_ROOT,
	PURPOSE_ATTACH_PART,
	PURPOSE_DETACH_PART,
	PURPOSE_CONSUME_MATERIAL,
	PURPOSE_DESTROY_ROOT,
	PURPOSE_TRANSFER_FABRICATION_INPUT,
	PURPOSE_CREATE_FABRICATED_ITEM,
	PURPOSE_CONSUME_FABRICATION_INPUT,
	PURPOSE_APPLY_DAMAGE,
	PURPOSE_REBIND_SPLIT_PART,
	PURPOSE_SALVAGE_PART,
	PURPOSE_REPAIR_PART,
	PURPOSE_EDIT_PARAMETRIC_MEMBER,
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
			if purpose == PURPOSE_CREATE_ROOT:
				if not _is_construction_root(after):
					return _failure("CREATED_ROOT_ITEM_LACKS_CONSTRUCTION_COMPONENT")
			elif purpose == PURPOSE_CREATE_FABRICATED_ITEM:
				if String(after["relation"].get("kind", "")) != ProjectionScript.CONTAINER:
					return _failure("FABRICATED_ITEM_TARGET_MUST_BE_CONTAINER")
				var origin = after["components"].get("fabrication_origin", {})
				if not origin is Dictionary or String(Dictionary(origin).get("job_id", "")).is_empty():
					return _failure("FABRICATED_ITEM_ORIGIN_REQUIRED")
			else:
				return _failure("INVALID_CREATE_ITEM_MUTATION_PURPOSE")
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
			if purpose == PURPOSE_DESTROY_ROOT:
				if not _is_construction_root(before):
					return _failure("INVALID_DELETE_ITEM_MUTATION_PURPOSE")
			elif purpose == PURPOSE_CONSUME_MATERIAL:
				if String(before["relation"].get("kind", "")) in [ProjectionScript.ATTACHMENT, ProjectionScript.DESTROYED]:
					return _failure("CONSUME_MATERIAL_SOURCE_NOT_TRANSFERABLE")
			elif purpose == PURPOSE_CONSUME_FABRICATION_INPUT:
				if String(before["relation"].get("kind", "")) != ProjectionScript.CONTAINER:
					return _failure("FABRICATION_INPUT_NOT_RESERVED")
			else:
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
		PURPOSE_CONSUME_MATERIAL, PURPOSE_CONSUME_FABRICATION_INPUT:
			if before_relation != after_relation or before["components"] != after["components"]:
				return _failure("CONSUME_MATERIAL_CHANGED_LOCATION_OR_COMPONENTS")
			if int(after["quantity"]) >= int(before["quantity"]):
				return _failure("CONSUME_MATERIAL_DID_NOT_DECREASE_QUANTITY")
		PURPOSE_TRANSFER_FABRICATION_INPUT:
			if String(before_relation.get("kind", "")) != ProjectionScript.CONTAINER or String(after_relation.get("kind", "")) != ProjectionScript.CONTAINER:
				return _failure("FABRICATION_TRANSFER_REQUIRES_CONTAINERS")
			if before_relation == after_relation:
				return _failure("FABRICATION_TRANSFER_DID_NOT_MOVE")
			if int(after["quantity"]) != int(before["quantity"]) or after["components"] != before["components"]:
				return _failure("FABRICATION_TRANSFER_MUTATED_PAYLOAD")
		PURPOSE_APPLY_DAMAGE:
			if before_relation != after_relation or int(after["quantity"]) != int(before["quantity"]):
				return _failure("DAMAGE_PART_CHANGED_IDENTITY_OR_LOCATION")
			if not _condition_only_change(before["components"], after["components"]):
				return _failure("DAMAGE_PART_CHANGED_UNRELATED_COMPONENTS")
		PURPOSE_REBIND_SPLIT_PART:
			if String(before_relation.get("kind", "")) != ProjectionScript.ATTACHMENT or String(after_relation.get("kind", "")) != ProjectionScript.ATTACHMENT:
				return _failure("SPLIT_REBIND_REQUIRES_ATTACHMENTS")
			if String(before_relation.get("assembly_id", "")) == String(after_relation.get("assembly_id", "")):
				return _failure("SPLIT_REBIND_DID_NOT_CHANGE_CONSTRUCT")
			if String(before_relation.get("socket_id", "")) != String(after_relation.get("socket_id", "")) or int(after["quantity"]) != int(before["quantity"]):
				return _failure("SPLIT_REBIND_CHANGED_PART_IDENTITY")
			if not _same_or_condition_only_change(before["components"], after["components"]):
				return _failure("SPLIT_REBIND_CHANGED_UNRELATED_COMPONENTS")
		PURPOSE_SALVAGE_PART:
			if String(before_relation.get("kind", "")) != ProjectionScript.ATTACHMENT or String(after_relation.get("kind", "")) not in [ProjectionScript.WORLD, ProjectionScript.CONTAINER]:
				return _failure("SALVAGE_PART_RELATION_INVALID")
			if int(after["quantity"]) != int(before["quantity"]) or not _same_or_condition_only_change(before["components"], after["components"]):
				return _failure("SALVAGE_PART_CHANGED_PAYLOAD")
		PURPOSE_REPAIR_PART:
			if String(after_relation.get("kind", "")) != ProjectionScript.ATTACHMENT or int(after["quantity"]) != int(before["quantity"]):
				return _failure("REPAIR_PART_TARGET_INVALID")
			if not _same_or_condition_only_change(before["components"], after["components"]):
				return _failure("REPAIR_PART_CHANGED_UNRELATED_COMPONENTS")
			if String(after["components"].get("condition", "INTACT")) != "INTACT":
				return _failure("REPAIR_PART_NOT_RESTORED")
		PURPOSE_EDIT_PARAMETRIC_MEMBER:
			if before_relation != after_relation or int(after["quantity"]) != int(before["quantity"]):
				return _failure("PARAMETRIC_EDIT_CHANGED_IDENTITY_OR_LOCATION")
			if not _parametric_member_only_change(before["components"], after["components"]):
				return _failure("PARAMETRIC_EDIT_CHANGED_UNRELATED_COMPONENTS")
		_:
			return _failure("INVALID_UPDATE_ITEM_MUTATION_PURPOSE")
	return _success()

static func _parametric_member_only_change(before: Dictionary, after: Dictionary) -> bool:
	var before_copy: Dictionary = before.duplicate(true)
	var after_copy: Dictionary = after.duplicate(true)
	var before_member = before_copy.get("parametric_member", {})
	var after_member = after_copy.get("parametric_member", {})
	if not before_member is Dictionary or not after_member is Dictionary:
		return false
	before_copy.erase("parametric_member")
	after_copy.erase("parametric_member")
	if UtilsScript.canonical_json(before_copy) != UtilsScript.canonical_json(after_copy):
		return false
	var immutable_fields: Array[String] = ["member_instance_id", "item_instance_id", "member_definition_id", "definition_version", "definition_checksum", "member_kind"]
	for field in immutable_fields:
		if Dictionary(before_member).get(field) != Dictionary(after_member).get(field):
			return false
	return String(Dictionary(before_member).get("checksum", "")) != String(Dictionary(after_member).get("checksum", ""))

static func _same_or_condition_only_change(before: Dictionary, after: Dictionary) -> bool:
	return before == after or _condition_only_change(before, after)

static func _condition_only_change(before: Dictionary, after: Dictionary) -> bool:
	var before_copy: Dictionary = before.duplicate(true)
	var after_copy: Dictionary = after.duplicate(true)
	before_copy.erase("condition")
	after_copy.erase("condition")
	if before_copy != after_copy:
		return false
	var next_condition: String = String(after.get("condition", ""))
	return next_condition in ["INTACT", "DEGRADED", "DESTROYED"] and next_condition != String(before.get("condition", ""))

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
