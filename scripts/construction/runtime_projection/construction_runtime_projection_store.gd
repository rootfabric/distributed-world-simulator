extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const DescriptorScript = preload("res://scripts/construction/runtime_projection/construction_runtime_construct_descriptor.gd")
const STATE_SCHEMA := "planet_simulator.construction_runtime_projection_store.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "descriptors", "checksum"]

var _descriptors: Dictionary = {}
var _generation := 0

func publish(descriptor: Dictionary) -> Dictionary:
	var checked := DescriptorScript.validate(descriptor); if not bool(checked.get("success", false)): return checked
	var construct_id := String(descriptor["construct_id"])
	if _descriptors.has(construct_id):
		var current: Dictionary = _descriptors[construct_id]
		if String(current["checksum"]) == String(descriptor["checksum"]): return _success({"replay": true, "generation": _generation})
		if int(descriptor["construct_revision"]) < int(current["construct_revision"]): return _failure("STALE_CONSTRUCTION_RUNTIME_PROJECTION")
		if int(descriptor["construct_revision"]) == int(current["construct_revision"]) and String(descriptor["construct_checksum"]) != String(current["construct_checksum"]): return _failure("CONSTRUCTION_RUNTIME_SAME_REVISION_MUTATION")
	_descriptors[construct_id] = descriptor.duplicate(true); _generation += 1
	return _success({"replay": false, "generation": _generation})

func remove(construct_id: String, expected_checksum: String = "") -> Dictionary:
	if not _descriptors.has(construct_id): return _success({"replay": true, "generation": _generation})
	if not expected_checksum.is_empty() and String(_descriptors[construct_id]["checksum"]) != expected_checksum: return _failure("CONSTRUCTION_RUNTIME_REMOVE_PRECONDITION_MISMATCH")
	_descriptors.erase(construct_id); _generation += 1; return _success({"replay": false, "generation": _generation})

func get_descriptor(construct_id: String) -> Dictionary: return Dictionary(_descriptors.get(construct_id, {})).duplicate(true)
func get_all() -> Array:
	var result: Array = []
	for value in _descriptors.values(): result.append(Dictionary(value).duplicate(true))
	result.sort_custom(func(a, b): return String(a["construct_id"]) < String(b["construct_id"]))
	return result
func get_generation() -> int: return _generation
func clear() -> void: _descriptors.clear(); _generation = 0

func export_state() -> Dictionary:
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "descriptors": get_all(), "checksum": ""}; state["checksum"] = compute_state_checksum(state); return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var next := {}
	for descriptor in state["descriptors"]: next[String(descriptor["construct_id"])] = Dictionary(descriptor).duplicate(true)
	_descriptors = next; _generation = int(state["generation"]); return _success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_RUNTIME_STORE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0: return _failure("INVALID_CONSTRUCTION_RUNTIME_STORE_GENERATION")
	if typeof(state.get("descriptors")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_RUNTIME_STORE_DESCRIPTORS")
	var seen := {}; var previous := ""
	for descriptor in state["descriptors"]:
		if typeof(descriptor) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_RUNTIME_STORE_DESCRIPTOR")
		var checked := DescriptorScript.validate(descriptor); if not bool(checked.get("success", false)): return checked
		var construct_id := String(descriptor["construct_id"])
		if seen.has(construct_id): return _failure("DUPLICATE_CONSTRUCTION_RUNTIME_STORE_CONSTRUCT")
		if not previous.is_empty() and construct_id < previous: return _failure("CONSTRUCTION_RUNTIME_STORE_NOT_SORTED")
		seen[construct_id] = true; previous = construct_id
	if String(state.get("checksum", "")) != compute_state_checksum(state): return _failure("CONSTRUCTION_RUNTIME_STORE_CHECKSUM_MISMATCH")
	return _success()

static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}
	for key in details: result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
