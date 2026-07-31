extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")

const STATE_SCHEMA: String = "planet_simulator.c2a_construction_item_graph_state.v1"
const STATUS_SUCCEEDED: String = "SUCCEEDED"
const STATUS_REJECTED: String = "REJECTED"
const STATUS_RETRYABLE: String = "RETRYABLE"
const STATE_FIELDS: Array[String] = ["schema", "generation", "items", "constructs", "terminal_operations", "checksum"]
const TERMINAL_RESULT_FIELDS: Array[String] = [
	"success", "error_code", "message", "status", "operation_id", "plan_id",
	"plan_checksum", "generation", "construct_id", "construct_revision", "affected_item_ids",
]

var _items: Dictionary = {}
var _constructs: Dictionary = {}
var _terminal_operations: Dictionary = {}
var _generation: int = 0

func setup(initial_items: Array = [], initial_constructs: Array = []) -> Dictionary:
	var candidate_items: Dictionary = {}
	for value in initial_items:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("INVALID_INITIAL_CONSTRUCTION_ITEM")
		var validation: Dictionary = ProjectionScript.validate(value)
		if not bool(validation.get("success", false)):
			return validation
		var item_id: String = String(value["item_instance_id"])
		if candidate_items.has(item_id):
			return _failure("DUPLICATE_INITIAL_CONSTRUCTION_ITEM")
		candidate_items[item_id] = _canonical_dictionary(value)
	var candidate_constructs: Dictionary = {}
	for value in initial_constructs:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("INVALID_INITIAL_CONSTRUCT")
		var validation: Dictionary = SnapshotScript.validate(value)
		if not bool(validation.get("success", false)):
			return validation
		var construct_id: String = String(value["construct_id"])
		if candidate_constructs.has(construct_id):
			return _failure("DUPLICATE_INITIAL_CONSTRUCT")
		candidate_constructs[construct_id] = _canonical_dictionary(value)
	var invariant_validation: Dictionary = _validate_state_invariants(candidate_items, candidate_constructs)
	if not bool(invariant_validation.get("success", false)):
		return invariant_validation
	_items = candidate_items
	_constructs = candidate_constructs
	_terminal_operations.clear()
	_generation = 0
	return _success()

func apply_plan(plan: Dictionary, failure_mode: String = "") -> Dictionary:
	var validation: Dictionary = PlanScript.validate(plan)
	if not bool(validation.get("success", false)):
		return _with_status(validation, STATUS_REJECTED)
	var operation_id: String = String(plan["operation_id"])
	var plan_checksum: String = String(plan["checksum"])
	if _terminal_operations.has(operation_id):
		var record: Dictionary = _terminal_operations[operation_id]
		if String(record["plan_checksum"]) == plan_checksum:
			return Dictionary(record["result"]).duplicate(true)
		return _failure("CONSTRUCTION_OPERATION_ID_CONFLICT", {}, STATUS_REJECTED)
	var precondition_validation: Dictionary = _validate_preconditions(plan)
	if not bool(precondition_validation.get("success", false)):
		return _remember_terminal_rejection(plan, precondition_validation)
	var candidate_items: Dictionary = _items.duplicate(true)
	var candidate_constructs: Dictionary = _constructs.duplicate(true)
	var construct_apply: Dictionary = _apply_construct_mutation(candidate_constructs, plan["construct_mutation"])
	if not bool(construct_apply.get("success", false)):
		return _remember_terminal_rejection(plan, construct_apply)
	for mutation in plan["item_mutations"]:
		var item_apply: Dictionary = _apply_item_mutation(candidate_items, mutation)
		if not bool(item_apply.get("success", false)):
			return _remember_terminal_rejection(plan, item_apply)
	var invariant_validation: Dictionary = _validate_state_invariants(candidate_items, candidate_constructs)
	if not bool(invariant_validation.get("success", false)):
		return _remember_terminal_rejection(plan, invariant_validation)
	if failure_mode == "BEFORE_COMMIT":
		return _failure("INJECTED_CONSTRUCTION_COMMIT_FAILURE", {}, STATUS_RETRYABLE)
	if not failure_mode.is_empty():
		return _failure("UNKNOWN_CONSTRUCTION_FAILURE_MODE", {}, STATUS_REJECTED)
	_items = candidate_items
	_constructs = candidate_constructs
	_generation += 1
	var affected_item_ids: Array = []
	for mutation in plan["item_mutations"]:
		affected_item_ids.append(String(mutation["item_instance_id"]))
	var construct_mutation: Dictionary = plan["construct_mutation"]
	var construct_revision: int = -1
	if not Dictionary(construct_mutation["after_snapshot"]).is_empty():
		construct_revision = int(construct_mutation["after_snapshot"]["state_revision"])
	var result: Dictionary = {
		"success": true,
		"error_code": "",
		"message": "",
		"status": STATUS_SUCCEEDED,
		"operation_id": operation_id,
		"plan_id": String(plan["plan_id"]),
		"plan_checksum": plan_checksum,
		"generation": _generation,
		"construct_id": String(construct_mutation["construct_id"]),
		"construct_revision": construct_revision,
		"affected_item_ids": affected_item_ids,
	}
	_terminal_operations[operation_id] = {"plan_checksum": plan_checksum, "result": result.duplicate(true)}
	return result

func get_item_projection(item_instance_id: String) -> Dictionary:
	if not _items.has(item_instance_id):
		return {}
	return Dictionary(_items[item_instance_id]).duplicate(true)

func get_construct_snapshot(construct_id: String) -> Dictionary:
	if not _constructs.has(construct_id):
		return {}
	return Dictionary(_constructs[construct_id]).duplicate(true)

func get_generation() -> int:
	return _generation

func has_terminal_operation(operation_id: String) -> bool:
	return _terminal_operations.has(operation_id)


func get_operation_result(operation_id: String) -> Dictionary:
	if not _terminal_operations.has(operation_id):
		return {}
	return Dictionary(_terminal_operations[operation_id].get("result", {})).duplicate(true)

func export_state() -> Dictionary:
	var operations: Array = []
	var operation_ids: Array = _terminal_operations.keys()
	operation_ids.sort()
	for operation_id in operation_ids:
		operations.append({
			"operation_id": String(operation_id),
			"plan_checksum": String(_terminal_operations[operation_id]["plan_checksum"]),
			"result": Dictionary(_terminal_operations[operation_id]["result"]).duplicate(true),
		})
	var state: Dictionary = {
		"schema": STATE_SCHEMA,
		"generation": _generation,
		"items": _sorted_values(_items, "item_instance_id"),
		"constructs": _sorted_values(_constructs, "construct_id"),
		"terminal_operations": operations,
		"checksum": "",
	}
	state["checksum"] = compute_state_checksum(state)
	return state

func compute_state_checksum(state: Dictionary) -> String:
	var payload: Dictionary = state.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

func load_state(state: Dictionary) -> Dictionary:
	var validation: Dictionary = _validate_exported_state(state)
	if not bool(validation.get("success", false)):
		return validation
	var canonical_result: Dictionary = UtilsScript.canonicalize(state)
	if not bool(canonical_result.get("success", false)) or not canonical_result.get("value") is Dictionary:
		return _failure("CONSTRUCTION_ITEM_GRAPH_STATE_CANONICALIZATION_FAILED")
	var canonical_state: Dictionary = canonical_result["value"]
	var candidate_items: Dictionary = {}
	for item in canonical_state["items"]:
		candidate_items[String(item["item_instance_id"])] = item.duplicate(true)
	var candidate_constructs: Dictionary = {}
	for construct in canonical_state["constructs"]:
		candidate_constructs[String(construct["construct_id"])] = construct.duplicate(true)
	var candidate_operations: Dictionary = {}
	for record in canonical_state["terminal_operations"]:
		candidate_operations[String(record["operation_id"])] = {
			"plan_checksum": String(record["plan_checksum"]),
			"result": Dictionary(record["result"]).duplicate(true),
		}
	_items = candidate_items
	_constructs = candidate_constructs
	_terminal_operations = candidate_operations
	_generation = int(canonical_state["generation"])
	return _success()

func _validate_preconditions(plan: Dictionary) -> Dictionary:
	var construct_mutation: Dictionary = plan["construct_mutation"]
	var construct_id: String = String(construct_mutation["construct_id"])
	var before_construct: Dictionary = construct_mutation["before_snapshot"]
	if before_construct.is_empty():
		if _constructs.has(construct_id):
			return _failure("CONSTRUCT_PRECONDITION_EXPECTED_ABSENT")
	elif (
		not _constructs.has(construct_id)
		or not _canonical_equal(Dictionary(_constructs[construct_id]), before_construct)
	):
		return _failure("CONSTRUCT_PRECONDITION_MISMATCH")
	for mutation in plan["item_mutations"]:
		var item_id: String = String(mutation["item_instance_id"])
		var before: Dictionary = mutation["before_projection"]
		if before.is_empty():
			if _items.has(item_id):
				return _failure("ITEM_PRECONDITION_EXPECTED_ABSENT", {"item_instance_id": item_id})
		elif (
			not _items.has(item_id)
			or not _canonical_equal(Dictionary(_items[item_id]), before)
		):
			return _failure("ITEM_PRECONDITION_MISMATCH", {"item_instance_id": item_id})
	return _success()

func _apply_construct_mutation(target: Dictionary, mutation: Dictionary) -> Dictionary:
	var construct_id: String = String(mutation["construct_id"])
	match String(mutation["operation_kind"]):
		ConstructMutationScript.OP_CREATE, ConstructMutationScript.OP_UPDATE:
			target[construct_id] = _canonical_dictionary(mutation["after_snapshot"])
		ConstructMutationScript.OP_DELETE:
			target.erase(construct_id)
		_:
			return _failure("UNSUPPORTED_CONSTRUCT_MUTATION")
	return _success()

func _apply_item_mutation(target: Dictionary, mutation: Dictionary) -> Dictionary:
	var item_id: String = String(mutation["item_instance_id"])
	match String(mutation["operation_kind"]):
		ItemMutationScript.OP_CREATE, ItemMutationScript.OP_UPDATE:
			target[item_id] = _canonical_dictionary(mutation["after_projection"])
		ItemMutationScript.OP_DELETE:
			target.erase(item_id)
		_:
			return _failure("UNSUPPORTED_ITEM_MUTATION")
	return _success()

func _validate_state_invariants(items: Dictionary, constructs: Dictionary) -> Dictionary:
	var attached_items_by_construct: Dictionary = {}
	for item_id in items:
		var projection: Dictionary = items[item_id]
		var projection_validation: Dictionary = ProjectionScript.validate(projection)
		if not bool(projection_validation.get("success", false)):
			return projection_validation
		var relation: Dictionary = projection["relation"]
		if String(relation.get("kind", "")) == ProjectionScript.ATTACHMENT:
			var construct_id: String = String(relation.get("assembly_id", ""))
			if not attached_items_by_construct.has(construct_id):
				attached_items_by_construct[construct_id] = []
			attached_items_by_construct[construct_id].append(String(item_id))
	for construct_id in constructs:
		var snapshot: Dictionary = constructs[construct_id]
		var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot)
		if not bool(snapshot_validation.get("success", false)):
			return snapshot_validation
		var root_item_id: String = String(snapshot["root_item_instance_id"])
		if not items.has(root_item_id):
			return _failure("CONSTRUCT_ROOT_ITEM_MISSING", {"construct_id": construct_id})
		var root: Dictionary = items[root_item_id]
		var root_component = root["components"].get("construction_root", {})
		if not root_component is Dictionary or String(Dictionary(root_component).get("construct_id", "")) != String(construct_id):
			return _failure("CONSTRUCT_ROOT_COMPONENT_MISMATCH", {"construct_id": construct_id})
		var expected_item_ids: Dictionary = {}
		for part in snapshot["parts"]:
			var item_id: String = String(part["item_instance_id"])
			if expected_item_ids.has(item_id):
				return _failure("CONSTRUCT_REUSES_ITEM_ID", {"item_instance_id": item_id})
			expected_item_ids[item_id] = true
			if not items.has(item_id):
				return _failure("CONSTRUCT_PART_ITEM_MISSING", {"item_instance_id": item_id})
			var relation: Dictionary = items[item_id]["relation"]
			if (
				String(relation.get("kind", "")) != ProjectionScript.ATTACHMENT
				or String(relation.get("assembly_id", "")) != String(construct_id)
				or String(relation.get("parent_item_id", "")) != root_item_id
				or String(relation.get("socket_id", "")) != String(part["part_id"])
			):
				return _failure("CONSTRUCT_PART_BINDING_MISMATCH", {"item_instance_id": item_id})
		for attached_item_id in attached_items_by_construct.get(construct_id, []):
			if not expected_item_ids.has(attached_item_id):
				return _failure("ATTACHED_ITEM_NOT_DECLARED_AS_CONSTRUCT_PART", {"item_instance_id": attached_item_id})
	for construct_id in attached_items_by_construct:
		if not constructs.has(construct_id):
			return _failure("ITEM_ATTACHED_TO_MISSING_CONSTRUCT", {"construct_id": construct_id})
	return _success()

func _validate_exported_state(state: Dictionary) -> Dictionary:
	var exact: Dictionary = UtilsScript.validate_exact_fields(state, STATE_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if state.get("schema") != STATE_SCHEMA:
		return _failure("UNSUPPORTED_CONSTRUCTION_ITEM_GRAPH_STATE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0:
		return _failure("INVALID_CONSTRUCTION_ITEM_GRAPH_GENERATION")
	if typeof(state.get("items")) != TYPE_ARRAY or typeof(state.get("constructs")) != TYPE_ARRAY or typeof(state.get("terminal_operations")) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_ITEM_GRAPH_STATE_COLLECTIONS")
	if typeof(state.get("checksum")) != TYPE_STRING or String(state["checksum"]) != compute_state_checksum(state):
		return _failure("CONSTRUCTION_ITEM_GRAPH_STATE_CHECKSUM_MISMATCH")
	var item_ids: Dictionary = {}
	var previous_item_id: String = ""
	for item in state["items"]:
		if typeof(item) != TYPE_DICTIONARY:
			return _failure("INVALID_PERSISTED_CONSTRUCTION_ITEM")
		var validation: Dictionary = ProjectionScript.validate(item)
		if not bool(validation.get("success", false)):
			return validation
		var item_id: String = String(item["item_instance_id"])
		if item_ids.has(item_id) or (not previous_item_id.is_empty() and item_id < previous_item_id):
			return _failure("NON_CANONICAL_PERSISTED_CONSTRUCTION_ITEMS")
		item_ids[item_id] = item.duplicate(true)
		previous_item_id = item_id
	var constructs: Dictionary = {}
	var previous_construct_id: String = ""
	for construct in state["constructs"]:
		if typeof(construct) != TYPE_DICTIONARY:
			return _failure("INVALID_PERSISTED_CONSTRUCT")
		var validation: Dictionary = SnapshotScript.validate(construct)
		if not bool(validation.get("success", false)):
			return validation
		var construct_id: String = String(construct["construct_id"])
		if constructs.has(construct_id) or (not previous_construct_id.is_empty() and construct_id < previous_construct_id):
			return _failure("NON_CANONICAL_PERSISTED_CONSTRUCTS")
		constructs[construct_id] = construct.duplicate(true)
		previous_construct_id = construct_id
	var operation_ids: Dictionary = {}
	var previous_operation_id: String = ""
	for record in state["terminal_operations"]:
		if typeof(record) != TYPE_DICTIONARY:
			return _failure("INVALID_PERSISTED_CONSTRUCTION_OPERATION")
		var record_fields: Array[String] = ["operation_id", "plan_checksum", "result"]
		var record_exact: Dictionary = UtilsScript.validate_exact_fields(record, record_fields)
		if not bool(record_exact.get("success", false)):
			return record_exact
		var operation_id: String = String(record["operation_id"])
		if operation_ids.has(operation_id) or (not previous_operation_id.is_empty() and operation_id < previous_operation_id):
			return _failure("NON_CANONICAL_PERSISTED_CONSTRUCTION_OPERATIONS")
		if String(record["plan_checksum"]).length() != 64 or typeof(record["result"]) != TYPE_DICTIONARY:
			return _failure("INVALID_PERSISTED_CONSTRUCTION_OPERATION_PAYLOAD")
		var result_validation: Dictionary = _validate_terminal_result(record)
		if not bool(result_validation.get("success", false)):
			return result_validation
		operation_ids[operation_id] = true
		previous_operation_id = operation_id
	var invariant_validation: Dictionary = _validate_state_invariants(item_ids, constructs)
	if not bool(invariant_validation.get("success", false)):
		return invariant_validation
	if not bool(UtilsScript.canonicalize(state).get("success", false)):
		return _failure("CONSTRUCTION_ITEM_GRAPH_STATE_NOT_JSON_SAFE")
	return _success()

func _sorted_values(source: Dictionary, id_field: String) -> Array:
	var ids: Array = source.keys()
	ids.sort()
	var values: Array = []
	for id in ids:
		var value: Dictionary = source[id]
		if String(value.get(id_field, "")) != String(id):
			return []
		values.append(value.duplicate(true))
	return values

func _remember_terminal_rejection(plan: Dictionary, failure: Dictionary) -> Dictionary:
	var construct_mutation: Dictionary = plan["construct_mutation"]
	var construct_id: String = String(construct_mutation["construct_id"])
	var construct_revision: int = -1
	if _constructs.has(construct_id):
		construct_revision = int(_constructs[construct_id]["state_revision"])
	var result: Dictionary = {
		"success": false,
		"error_code": String(failure.get("error_code", "CONSTRUCTION_TRANSACTION_REJECTED")),
		"message": String(failure.get("message", failure.get("error_code", "CONSTRUCTION_TRANSACTION_REJECTED"))),
		"status": STATUS_REJECTED,
		"operation_id": String(plan["operation_id"]),
		"plan_id": String(plan["plan_id"]),
		"plan_checksum": String(plan["checksum"]),
		"generation": _generation,
		"construct_id": construct_id,
		"construct_revision": construct_revision,
		"affected_item_ids": [],
	}
	_terminal_operations[String(plan["operation_id"])] = {
		"plan_checksum": String(plan["checksum"]),
		"result": result.duplicate(true),
	}
	return result

func _validate_terminal_result(record: Dictionary) -> Dictionary:
	var result: Dictionary = record["result"]
	var exact: Dictionary = UtilsScript.validate_exact_fields(result, TERMINAL_RESULT_FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(result.get("success")) != TYPE_BOOL:
		return _failure("INVALID_PERSISTED_CONSTRUCTION_RESULT_SUCCESS")
	var status: String = String(result.get("status", ""))
	if not [STATUS_SUCCEEDED, STATUS_REJECTED].has(status):
		return _failure("INVALID_PERSISTED_CONSTRUCTION_RESULT_STATUS")
	if bool(result["success"]) != (status == STATUS_SUCCEEDED):
		return _failure("PERSISTED_CONSTRUCTION_RESULT_STATUS_MISMATCH")
	if String(result.get("operation_id", "")) != String(record["operation_id"]) or String(result.get("plan_checksum", "")) != String(record["plan_checksum"]):
		return _failure("PERSISTED_CONSTRUCTION_RESULT_IDENTITY_MISMATCH")
	for field in ["generation", "construct_revision"]:
		if not UtilsScript.is_json_integer(result.get(field)):
			return _failure("INVALID_PERSISTED_CONSTRUCTION_RESULT_INTEGER", {"field": field})
	if int(result["generation"]) < 0 or int(result["construct_revision"]) < -1:
		return _failure("INVALID_PERSISTED_CONSTRUCTION_RESULT_REVISION")
	if typeof(result.get("affected_item_ids")) != TYPE_ARRAY:
		return _failure("INVALID_PERSISTED_CONSTRUCTION_RESULT_ITEMS")
	var previous_item_id: String = ""
	var seen_items: Dictionary = {}
	for item_id_value in result["affected_item_ids"]:
		if typeof(item_id_value) != TYPE_STRING:
			return _failure("INVALID_PERSISTED_CONSTRUCTION_RESULT_ITEM_ID")
		var item_id: String = String(item_id_value)
		if not item_id.begins_with("item/") or seen_items.has(item_id) or (not previous_item_id.is_empty() and item_id < previous_item_id):
			return _failure("NON_CANONICAL_PERSISTED_CONSTRUCTION_RESULT_ITEMS")
		seen_items[item_id] = true
		previous_item_id = item_id
	if not bool(UtilsScript.canonicalize(result).get("success", false)):
		return _failure("PERSISTED_CONSTRUCTION_RESULT_NOT_JSON_SAFE")
	return _success()

func _canonical_equal(left: Dictionary, right: Dictionary) -> bool:
	var left_json: String = UtilsScript.canonical_json(left)
	if left_json.is_empty():
		return false
	var right_json: String = UtilsScript.canonical_json(right)
	return not right_json.is_empty() and left_json == right_json


func _canonical_dictionary(value: Dictionary) -> Dictionary:
	var result: Dictionary = UtilsScript.canonicalize(value)
	if bool(result.get("success", false)) and result.get("value") is Dictionary:
		return Dictionary(result["value"])
	return value.duplicate(true)

func _with_status(result: Dictionary, status: String) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	output["status"] = status
	return output

func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

func _failure(code: String, details: Dictionary = {}, status: String = "") -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	if not status.is_empty():
		result["status"] = status
	for key in details:
		result[key] = details[key]
	return result
