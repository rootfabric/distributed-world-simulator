extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ParametricUtils = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const RecordScript = preload("res://scripts/construction/geometry_edit/construction_geometry_edit_record.gd")

const STATE_SCHEMA := "planet_simulator.construction_geometry_edit_history_state.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "records", "checksum"]

var _records: Dictionary = {}
var _generation := 0

func publish(record: Dictionary) -> Dictionary:
	var checked := RecordScript.validate(record); if not bool(checked.get("success", false)): return checked
	var operation_id := String(record["operation_id"])
	if _records.has(operation_id):
		if String(_records[operation_id]["checksum"]) == String(record["checksum"]): return ParametricUtils.success({"replay": true, "generation": _generation})
		return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_HISTORY_CONFLICT")
	_records[operation_id] = record.duplicate(true); _generation += 1
	return ParametricUtils.success({"replay": false, "generation": _generation})

func get_record(operation_id: String) -> Dictionary:
	return Dictionary(_records.get(operation_id, {})).duplicate(true)
func get_generation() -> int: return _generation

func export_state() -> Dictionary:
	var ids: Array = _records.keys(); ids.sort(); var records: Array = []
	for operation_id in ids: records.append(Dictionary(_records[operation_id]).duplicate(true))
	var state := {"schema": STATE_SCHEMA, "generation": _generation, "records": records, "checksum": ""}; state["checksum"] = compute_state_checksum(state); return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state); if not bool(checked.get("success", false)): return checked
	var candidate := {}
	for record in state["records"]:
		candidate[String(record["operation_id"])] = Dictionary(record).duplicate(true)
	_records = candidate
	_generation = int(state["generation"])
	return ParametricUtils.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(state, STATE_FIELDS); if not bool(exact.get("success", false)): return exact
	if state.get("schema") != STATE_SCHEMA: return ParametricUtils.failure("UNSUPPORTED_CONSTRUCTION_GEOMETRY_EDIT_HISTORY_STATE_SCHEMA")
	if not UtilsScript.is_json_integer(state.get("generation")) or int(state["generation"]) < 0: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_HISTORY_GENERATION")
	if typeof(state.get("records")) != TYPE_ARRAY: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_HISTORY_RECORDS")
	var previous := ""; var seen := {}
	for record in state["records"]:
		if typeof(record) != TYPE_DICTIONARY: return ParametricUtils.failure("INVALID_CONSTRUCTION_GEOMETRY_EDIT_HISTORY_RECORD")
		var checked := RecordScript.validate(record); if not bool(checked.get("success", false)): return checked
		var operation_id := String(record["operation_id"]); if seen.has(operation_id) or (not previous.is_empty() and operation_id < previous): return ParametricUtils.failure("NON_CANONICAL_CONSTRUCTION_GEOMETRY_EDIT_HISTORY_ORDER")
		seen[operation_id] = true; previous = operation_id
	if String(state.get("checksum", "")) != compute_state_checksum(state): return ParametricUtils.failure("CONSTRUCTION_GEOMETRY_EDIT_HISTORY_STATE_CHECKSUM_MISMATCH")
	return ParametricUtils.success()
static func compute_state_checksum(state: Dictionary) -> String:
	var payload := state.duplicate(true); payload["checksum"] = ""; return UtilsScript.payload_hash(payload)
