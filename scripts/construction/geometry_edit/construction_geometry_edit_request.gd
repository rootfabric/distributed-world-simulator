extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const OperationScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_operation.gd")
const ConstraintScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_constraint.gd")

const SCHEMA := "planet_simulator.construction_geometry_edit_request.v1"
const FIELDS: Array[String] = ["schema", "edit_id", "operation_id", "member_instance_id", "item_instance_id", "construct_id", "part_id", "expected_member_checksum", "expected_item_revision", "expected_construct_checksum", "expected_edit_revision", "operations", "constraints", "metadata", "checksum"]

static func create(edit_id: String, operation_id: String, member_instance_id: String, item_instance_id: String, construct_id: String, part_id: String, expected_member_checksum: String, expected_item_revision: int, expected_construct_checksum: String, expected_edit_revision: int, operations: Array, constraints: Array = [], metadata: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"edit_id": edit_id,
		"operation_id": operation_id,
		"member_instance_id": member_instance_id,
		"item_instance_id": item_instance_id,
		"construct_id": construct_id,
		"part_id": part_id,
		"expected_member_checksum": expected_member_checksum,
		"expected_item_revision": expected_item_revision,
		"expected_construct_checksum": expected_construct_checksum,
		"expected_edit_revision": expected_edit_revision,
		"operations": _sorted_operations(operations),
		"constraints": _sorted_constraints(constraints),
		"metadata": metadata.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_GEOMETRY_EDIT_REQUEST_SCHEMA")
	if not ParametricUtils.path_id(String(value.get("edit_id", "")), "geometry-edit/") or not ParametricUtils.path_id(String(value.get("operation_id", "")), "operation/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_REQUEST_ID")
	if not ParametricUtils.path_id(String(value.get("member_instance_id", "")), "parametric-member/") or not ParametricUtils.path_id(String(value.get("item_instance_id", "")), "item/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_MEMBER_IDENTITY")
	if not ParametricUtils.path_id(String(value.get("construct_id", "")), "construct/") or not ParametricUtils.path_id(String(value.get("part_id", "")), "part/"): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_TARGET")
	for field in ["expected_member_checksum", "expected_construct_checksum"]:
		if typeof(value.get(field)) != TYPE_STRING or String(value[field]).length() != 64: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_PRECONDITION_CHECKSUM")
	for field in ["expected_item_revision", "expected_edit_revision"]:
		if not UtilsScript.is_json_integer(value.get(field)) or int(value[field]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_PRECONDITION_REVISION")
	if typeof(value.get("operations")) != TYPE_ARRAY or Array(value["operations"]).is_empty() or value["operations"] != _sorted_operations(value["operations"]): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_GEOMETRY_EDIT_OPERATIONS")
	var operation_ids := {}; var expected_sequence := 0
	for operation in value["operations"]:
		if typeof(operation) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_OPERATION")
		var checked := OperationScript.validate(operation); if not bool(checked.get("success", false)): return checked
		if int(operation["sequence"]) != expected_sequence: return ParametricUtils.failure("NON_CONTIGUOUS_CONSTRUCTION_GEOMETRY_EDIT_OPERATION_SEQUENCE")
		var oid := String(operation["operation_id"]); if operation_ids.has(oid): return ParametricUtils.failure("DUPLICATE_CONSTRUCTION_GEOMETRY_EDIT_OPERATION")
		operation_ids[oid] = true; expected_sequence += 1
	if typeof(value.get("constraints")) != TYPE_ARRAY or value["constraints"] != _sorted_constraints(value["constraints"]): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINTS")
	var constraint_ids := {}
	for constraint in value["constraints"]:
		if typeof(constraint) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT")
		var checked := ConstraintScript.validate(constraint); if not bool(checked.get("success", false)): return checked
		var cid := String(constraint["constraint_id"]); if constraint_ids.has(cid): return ParametricUtils.failure("DUPLICATE_CONSTRUCTION_GEOMETRY_EDIT_CONSTRAINT")
		constraint_ids[cid] = true
	if typeof(value.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(value["metadata"]).get("success", false)): return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_METADATA")
	if String(value.get("checksum", "")) != compute_checksum(value): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_REQUEST_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted_operations(values: Array) -> Array:
	var output := values.duplicate(true); output.sort_custom(func(a,b): return int(a.get("sequence", -1)) < int(b.get("sequence", -1))); return output
static func _sorted_constraints(values: Array) -> Array:
	var output := values.duplicate(true); output.sort_custom(func(a,b): return String(a.get("constraint_id", "")) < String(b.get("constraint_id", ""))); return output
