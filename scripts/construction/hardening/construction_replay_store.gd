extends RefCounted

const H = preload("res://scripts/construction/hardening/construction_hardening_utils.gd")
const ContractUtils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.construction_replay_store.v1"
const STATE_FIELDS: Array[String] = ["schema", "generation", "entries", "checksum"]

var _entries: Dictionary = {}
var _generation := 0

func lookup(operation_id: String, operation_checksum: String) -> Dictionary:
	if not H.is_path_id(operation_id, "operation/") or not H.is_hash(operation_checksum):
		return H.failure("INVALID_CONSTRUCTION_REPLAY_KEY")
	if not _entries.has(operation_id):
		return H.success({"found": false})
	var entry: Dictionary = _entries[operation_id]
	if String(entry["operation_checksum"]) != operation_checksum:
		return H.failure("CONSTRUCTION_PRODUCTION_OPERATION_ID_CONFLICT")
	return H.success({"found": true, "result": Dictionary(entry["result"]).duplicate(true)})

func record(operation_id: String, operation_checksum: String, result: Dictionary) -> Dictionary:
	var normalized := ContractUtils.canonicalize(result)
	if not bool(normalized.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_REPLAY_RESULT")
	var normalized_result: Dictionary = normalized.get("value", {})
	var replay := lookup(operation_id, operation_checksum)
	if not bool(replay.get("success", false)):
		return replay
	if bool(replay.get("found", false)):
		return H.success({"replay": true, "result": replay["result"]})
	_entries[operation_id] = {
		"operation_id": operation_id,
		"operation_checksum": operation_checksum,
		"result": normalized_result.duplicate(true),
	}
	_generation += 1
	return H.success({"replay": false, "result": normalized_result.duplicate(true)})

func get_generation() -> int:
	return _generation

func get_entry_count() -> int:
	return _entries.size()

func export_state() -> Dictionary:
	var ids: Array = _entries.keys()
	ids.sort()
	var rows: Array = []
	for operation_id in ids:
		rows.append(Dictionary(_entries[operation_id]).duplicate(true))
	var state := {"schema": SCHEMA, "generation": _generation, "entries": rows, "checksum": ""}
	state["checksum"] = H.checksum(state)
	return state

func load_state(state: Dictionary) -> Dictionary:
	var checked := validate_state(state)
	if not bool(checked.get("success", false)):
		return checked
	var entries: Dictionary = {}
	for row in state["entries"]:
		entries[String(row["operation_id"])] = Dictionary(row).duplicate(true)
	_entries = entries
	_generation = int(state["generation"])
	return H.success()

static func validate_state(state: Dictionary) -> Dictionary:
	var exact := H.exact_fields(state, STATE_FIELDS)
	if not bool(exact.get("success", false)):
		return H.failure("INVALID_CONSTRUCTION_REPLAY_STATE_FIELDS")
	if state.get("schema") != SCHEMA or not H.is_non_negative_integer(state.get("generation")):
		return H.failure("INVALID_CONSTRUCTION_REPLAY_STATE")
	if typeof(state.get("entries")) != TYPE_ARRAY:
		return H.failure("INVALID_CONSTRUCTION_REPLAY_ENTRIES")
	if int(state["generation"]) != state["entries"].size():
		return H.failure("INVALID_CONSTRUCTION_REPLAY_GENERATION")
	var previous := ""
	for raw_row in state["entries"]:
		if typeof(raw_row) != TYPE_DICTIONARY:
			return H.failure("INVALID_CONSTRUCTION_REPLAY_ENTRY")
		var row: Dictionary = raw_row
		if row.keys().size() != 3 or not row.has("operation_id") or not row.has("operation_checksum") or not row.has("result"):
			return H.failure("INVALID_CONSTRUCTION_REPLAY_ENTRY")
		if typeof(row.get("operation_id")) != TYPE_STRING:
			return H.failure("INVALID_CONSTRUCTION_REPLAY_ENTRY")
		var operation_id := String(row["operation_id"])
		if not H.is_path_id(operation_id, "operation/") or (not previous.is_empty() and operation_id <= previous):
			return H.failure("NON_CANONICAL_CONSTRUCTION_REPLAY_ENTRIES")
		if not H.is_hash(row["operation_checksum"]) or typeof(row["result"]) != TYPE_DICTIONARY:
			return H.failure("INVALID_CONSTRUCTION_REPLAY_ENTRY")
		if not bool(ContractUtils.canonicalize(row["result"]).get("success", false)):
			return H.failure("INVALID_CONSTRUCTION_REPLAY_RESULT")
		previous = operation_id
	return H.validate_checksum(state, "CONSTRUCTION_REPLAY_STATE_CHECKSUM_MISMATCH")
