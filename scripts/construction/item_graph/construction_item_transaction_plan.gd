extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")

const SCHEMA: String = "planet_simulator.construction_item_transaction_plan.v1"
const COMMAND_ASSEMBLE: String = "ASSEMBLE_CONSTRUCT"
const COMMAND_DECONSTRUCT: String = "DECONSTRUCT_CONSTRUCT"
const COMMAND_ADVANCE_STAGE: String = "ADVANCE_CONSTRUCTION_STAGE"
const COMMAND_FABRICATION_RESERVE: String = "FABRICATION_RESERVE"
const COMMAND_FABRICATION_COMPLETE: String = "FABRICATION_COMPLETE"
const COMMAND_FABRICATION_RELEASE: String = "FABRICATION_RELEASE"
const COMMAND_EDIT_PARAMETRIC_MEMBER: String = "EDIT_PARAMETRIC_MEMBER"
const COMMAND_TYPES: Array[String] = [COMMAND_ASSEMBLE, COMMAND_DECONSTRUCT, COMMAND_ADVANCE_STAGE, COMMAND_FABRICATION_RESERVE, COMMAND_FABRICATION_COMPLETE, COMMAND_FABRICATION_RELEASE, COMMAND_EDIT_PARAMETRIC_MEMBER]
const INVARIANT_ITEM_IDENTITY: String = "ITEM_IDENTITY_CONSERVATION"
const INVARIANT_PART_BINDINGS: String = "PART_BINDING_CONSISTENCY"
const INVARIANT_ROOT: String = "CONSTRUCT_ROOT_CONSISTENCY"
const REQUIRED_INVARIANTS: Array[String] = [INVARIANT_ROOT, INVARIANT_ITEM_IDENTITY, INVARIANT_PART_BINDINGS]
const FIELDS: Array[String] = [
	"schema",
	"plan_id",
	"operation_id",
	"command_type",
	"construct_mutation",
	"item_mutations",
	"invariants",
	"checksum",
]

static func create(
	plan_id: String,
	operation_id: String,
	command_type: String,
	construct_mutation: Dictionary,
	item_mutations: Array,
	invariants: Array = REQUIRED_INVARIANTS
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"plan_id": plan_id,
		"operation_id": operation_id,
		"command_type": command_type,
		"construct_mutation": construct_mutation.duplicate(true),
		"item_mutations": _sorted_item_mutations(item_mutations),
		"invariants": _sorted_strings(invariants),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if value.get("schema") != SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_TRANSACTION_PLAN_SCHEMA")
	if not _is_identifier(String(value.get("plan_id", "")), "plan/"):
		return _failure("INVALID_CONSTRUCTION_TRANSACTION_PLAN_ID")
	if not _is_identifier(String(value.get("operation_id", "")), "operation/"):
		return _failure("INVALID_CONSTRUCTION_TRANSACTION_OPERATION_ID")
	if not COMMAND_TYPES.has(String(value.get("command_type", ""))):
		return _failure("INVALID_CONSTRUCTION_TRANSACTION_COMMAND")
	if typeof(value.get("construct_mutation")) != TYPE_DICTIONARY:
		return _failure("INVALID_CONSTRUCTION_TRANSACTION_CONSTRUCT_MUTATION")
	var construct_validation: Dictionary = ConstructMutationScript.validate(value["construct_mutation"])
	if not bool(construct_validation.get("success", false)):
		return construct_validation
	if typeof(value.get("item_mutations")) != TYPE_ARRAY or value["item_mutations"].is_empty():
		return _failure("INVALID_CONSTRUCTION_TRANSACTION_ITEM_MUTATIONS")
	var previous_item_id: String = ""
	var seen_items: Dictionary = {}
	for mutation in value["item_mutations"]:
		if typeof(mutation) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_TRANSACTION_ITEM_MUTATION")
		var validation: Dictionary = ItemMutationScript.validate(mutation)
		if not bool(validation.get("success", false)):
			return validation
		var item_id: String = String(mutation["item_instance_id"])
		if seen_items.has(item_id):
			return _failure("DUPLICATE_CONSTRUCTION_TRANSACTION_ITEM_MUTATION")
		if not previous_item_id.is_empty() and item_id < previous_item_id:
			return _failure("CONSTRUCTION_TRANSACTION_ITEM_MUTATIONS_NOT_SORTED")
		seen_items[item_id] = true
		previous_item_id = item_id
	if typeof(value.get("invariants")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_TRANSACTION_INVARIANTS")
	var invariants: Array = value["invariants"]
	for invariant in invariants:
		if typeof(invariant) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_TRANSACTION_INVARIANT")
	if invariants != _sorted_strings(invariants) or invariants != REQUIRED_INVARIANTS:
		return _failure("INVALID_CONSTRUCTION_TRANSACTION_INVARIANT_SET")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value):
		return _failure("CONSTRUCTION_TRANSACTION_PLAN_CHECKSUM_MISMATCH")
	if not bool(UtilsScript.canonicalize(value).get("success", false)):
		return _failure("CONSTRUCTION_TRANSACTION_PLAN_NOT_JSON_SAFE")
	return _success()

static func compute_checksum(value: Dictionary) -> String:
	var payload: Dictionary = value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _sorted_item_mutations(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort_custom(func(a, b): return String(a.get("item_instance_id", "")) < String(b.get("item_instance_id", "")))
	return result

static func _sorted_strings(values: Array) -> Array:
	var result: Array = values.duplicate(true)
	result.sort()
	return result

static func _is_identifier(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.strip_edges()

static func _success() -> Dictionary:
	return {"success": true, "error_code": "", "message": ""}

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
