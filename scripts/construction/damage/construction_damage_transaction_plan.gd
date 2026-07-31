extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const RepairPlanScript = preload("res://scripts/construction/damage/construction_repair_plan.gd")

const SCHEMA := "planet_simulator.construction_damage_transaction_plan.v1"
const COMMAND_DAMAGE_SPLIT := "DAMAGE_SPLIT_CONSTRUCT"
const COMMAND_REPAIR_SPLIT := "REPAIR_SPLIT_CONSTRUCT"
const COMMAND_TYPES: Array[String] = [COMMAND_DAMAGE_SPLIT, COMMAND_REPAIR_SPLIT]
const REQUIRED_INVARIANTS: Array[String] = ["CONSTRUCT_ROOT_CONSISTENCY", "ITEM_IDENTITY_CONSERVATION", "PART_BINDING_CONSISTENCY", "SPLIT_COMPONENT_DISJOINTNESS"]
const FIELDS: Array[String] = ["schema", "plan_id", "operation_id", "command_type", "source_construct_id", "construct_mutations", "item_mutations", "repair_plan", "invariants", "checksum"]

static func create(plan_id: String, operation_id: String, command_type: String, source_construct_id: String, construct_mutations: Array, item_mutations: Array, repair_plan: Dictionary) -> Dictionary:
	var value := {
		"schema": SCHEMA, "plan_id": plan_id, "operation_id": operation_id, "command_type": command_type,
		"source_construct_id": source_construct_id, "construct_mutations": _sorted_mutations(construct_mutations, "construct_id"),
		"item_mutations": _sorted_mutations(item_mutations, "item_instance_id"), "repair_plan": repair_plan.duplicate(true),
		"invariants": REQUIRED_INVARIANTS.duplicate(), "checksum": "",
	}
	value["checksum"] = compute_checksum(value); return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS); if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_DAMAGE_TRANSACTION_SCHEMA")
	if not String(value.get("plan_id", "")).begins_with("plan/") or not String(value.get("operation_id", "")).begins_with("operation/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_TRANSACTION_ID")
	if not COMMAND_TYPES.has(String(value.get("command_type", ""))): return _failure("INVALID_CONSTRUCTION_DAMAGE_TRANSACTION_COMMAND")
	if not String(value.get("source_construct_id", "")).begins_with("construct/"): return _failure("INVALID_CONSTRUCTION_DAMAGE_TRANSACTION_SOURCE")
	if typeof(value.get("construct_mutations")) != TYPE_ARRAY or value["construct_mutations"].is_empty() or value["construct_mutations"] != _sorted_mutations(value["construct_mutations"], "construct_id"): return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_CONSTRUCT_MUTATIONS")
	var construct_ids := {}; var source_found := false
	for mutation in value["construct_mutations"]:
		if typeof(mutation) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_CONSTRUCT_MUTATION")
		var checked := ConstructMutationScript.validate(mutation); if not bool(checked.get("success", false)): return checked
		var cid := String(mutation["construct_id"]); if construct_ids.has(cid): return _failure("DUPLICATE_CONSTRUCTION_DAMAGE_CONSTRUCT_MUTATION")
		construct_ids[cid] = true; source_found = source_found or cid == String(value["source_construct_id"])
	if not source_found: return _failure("CONSTRUCTION_DAMAGE_SOURCE_MUTATION_REQUIRED")
	if typeof(value.get("item_mutations")) != TYPE_ARRAY or value["item_mutations"] != _sorted_mutations(value["item_mutations"], "item_instance_id"): return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_ITEM_MUTATIONS")
	var item_ids := {}
	for mutation in value["item_mutations"]:
		if typeof(mutation) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_ITEM_MUTATION")
		var checked := ItemMutationScript.validate(mutation); if not bool(checked.get("success", false)): return checked
		var iid := String(mutation["item_instance_id"]); if item_ids.has(iid): return _failure("DUPLICATE_CONSTRUCTION_DAMAGE_ITEM_MUTATION")
		item_ids[iid] = true
	if typeof(value.get("repair_plan")) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_REPAIR_PLAN")
	var repair_validation := RepairPlanScript.validate(value["repair_plan"]); if not bool(repair_validation.get("success", false)): return repair_validation
	if typeof(value.get("invariants")) != TYPE_ARRAY or value["invariants"] != REQUIRED_INVARIANTS: return _failure("INVALID_CONSTRUCTION_DAMAGE_TRANSACTION_INVARIANTS")
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value): return _failure("CONSTRUCTION_DAMAGE_TRANSACTION_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _sorted_mutations(values: Array, field: String) -> Array:
	var output := values.duplicate(true); output.sort_custom(func(a,b): return String(a.get(field, "")) < String(b.get(field, ""))); return output
static func _failure(code: String) -> Dictionary:
	return UtilsScript.validation_failure(code, code)
