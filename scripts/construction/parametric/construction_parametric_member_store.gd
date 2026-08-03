extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const InstanceScript = preload("res://scripts/construction/parametric/construction_parametric_member_instance.gd")

const STATE_SCHEMA := "planet_simulator.construction_parametric_member_store_state.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "instances", "checksum"]

var _instances: Dictionary = {}
var _generation := 0

func publish(instance: Dictionary) -> Dictionary:
	var checked := InstanceScript.validate(instance)
	if not bool(checked.get("success", false)): return checked
	var id := String(instance["member_instance_id"])
	if _instances.has(id):
		if String(_instances[id]["checksum"]) == String(instance["checksum"]): return ParametricUtils.success({"replay": true, "generation": _generation})
		return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_CONFLICT")
	_instances[id] = instance.duplicate(true); _generation += 1
	return ParametricUtils.success({"replay": false, "generation": _generation})

func remove(member_instance_id: String, expected_checksum: String) -> Dictionary:
	if not _instances.has(member_instance_id): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_INSTANCE_NOT_FOUND")
	if String(_instances[member_instance_id]["checksum"]) != expected_checksum: return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_REMOVE_PRECONDITION_MISMATCH")
	_instances.erase(member_instance_id); _generation += 1; return ParametricUtils.success({"generation": _generation})

func get_instance(member_instance_id: String) -> Dictionary:
	return Dictionary(_instances.get(member_instance_id, {})).duplicate(true)

func get_generation() -> int:
	return _generation

func export_state() -> Dictionary:
	var values: Array = []; var ids: Array = _instances.keys(); ids.sort()
	for id in ids: values.append(Dictionary(_instances[id]).duplicate(true))
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "instances": values, "checksum": ""}; state["checksum"] = compute_state_checksum(state); return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state)
	if not bool(checked.get("success", false)): return checked
	var candidate := {}; var previous := ""
	for instance in state["instances"]:
		var id := String(instance["member_instance_id"])
		if candidate.has(id) or (not previous.is_empty() and id < previous): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_STORE_ORDER")
		candidate[id] = Dictionary(instance).duplicate(true); previous = id
	_instances = candidate; _generation = int(state["generation"]); return ParametricUtils.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS)
	if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_PARAMETRIC_MEMBER_STORE_STATE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_STORE_GENERATION")
	if typeof(state.get("instances")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_STORE_INSTANCES")
	var previous := ""; var seen := {}
	for instance in state["instances"]:
		if typeof(instance) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_STORE_INSTANCE")
		var checked := InstanceScript.validate(instance); if not bool(checked.get("success", false)): return checked
		var id := String(instance["member_instance_id"])
		if seen.has(id) or (not previous.is_empty() and id < previous): return ParametricUtils.failure("INVALID_CONSTRUCTION_PARAMETRIC_MEMBER_STORE_ORDER")
		seen[id] = true; previous = id
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ParametricUtils.failure("CONSTRUCTION_PARAMETRIC_MEMBER_STORE_STATE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()

static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
