extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RecordScript = preload("res://scripts/construction/damage/construction_damage_record.gd")

const SCHEMA := "planet_simulator.construction_damage_history.v1"
const FIELDS: Array[String] = ["schema", "generation", "records", "checksum"]

var _records: Dictionary = {}
var _generation := 0

func setup() -> Dictionary:
	_records.clear()
	_generation = 0
	return _success()

func append(record: Dictionary) -> Dictionary:
	var validation := RecordScript.validate(record)
	if not bool(validation.get("success", false)): return validation
	var damage_id := String(record["damage_id"])
	if _records.has(damage_id):
		if String(_records[damage_id]["checksum"]) == String(record["checksum"]):
			return _success({"replay": true, "generation": _generation, "record": Dictionary(_records[damage_id]).duplicate(true)})
		return _failure("CONSTRUCTION_DAMAGE_RECORD_CONFLICT")
	_records[damage_id] = record.duplicate(true)
	_generation += 1
	return _success({"replay": false, "generation": _generation, "record": record.duplicate(true)})

func mark_repaired(damage_id: String, expected_checksum: String, repaired_generation: int) -> Dictionary:
	if not _records.has(damage_id): return _failure("CONSTRUCTION_DAMAGE_RECORD_NOT_FOUND")
	var current: Dictionary = _records[damage_id]
	if String(current["checksum"]) != expected_checksum: return _failure("CONSTRUCTION_DAMAGE_RECORD_PRECONDITION_MISMATCH")
	if String(current["status"]) == "REPAIRED": return _success({"replay": true, "generation": _generation, "record": current.duplicate(true)})
	var next := RecordScript.mark_repaired(current, repaired_generation)
	var validation := RecordScript.validate(next)
	if not bool(validation.get("success", false)): return validation
	_records[damage_id] = next
	_generation += 1
	return _success({"replay": false, "generation": _generation, "record": next.duplicate(true)})

func get_record(damage_id: String) -> Dictionary:
	return Dictionary(_records.get(damage_id, {})).duplicate(true)

func list_records() -> Array:
	var ids := _records.keys()
	ids.sort()
	var output: Array = []
	for damage_id in ids:
		output.append(Dictionary(_records[damage_id]).duplicate(true))
	return output

func get_generation() -> int:
	return _generation

func to_dict() -> Dictionary:
	var value := {"schema": SCHEMA, "generation": _generation, "records": list_records(), "checksum": ""}
	value["checksum"] = compute_checksum(value)
	return value

func load_dict(value: Dictionary) -> Dictionary:
	var validation := validate_state(value)
	if not bool(validation.get("success", false)): return validation
	var candidate: Dictionary = {}
	for record in value["records"]:
		candidate[String(record["damage_id"])] = record.duplicate(true)
	_records = candidate
	_generation = int(value["generation"])
	return _success()

static func validate_state(value: Dictionary) -> Dictionary:
	var exact := UtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return _failure("UNSUPPORTED_CONSTRUCTION_DAMAGE_HISTORY_SCHEMA")
	if not UtilsScript.is_json_integer(value.get("generation")) or int(value["generation"]) < 0: return _failure("INVALID_CONSTRUCTION_DAMAGE_HISTORY_GENERATION")
	if typeof(value.get("records")) != TYPE_ARRAY: return _failure("INVALID_CONSTRUCTION_DAMAGE_HISTORY_RECORDS")
	var previous := ""
	var seen := {}
	for record in value["records"]:
		if typeof(record) != TYPE_DICTIONARY: return _failure("INVALID_CONSTRUCTION_DAMAGE_HISTORY_RECORD")
		var checked := RecordScript.validate(record)
		if not bool(checked.get("success", false)): return checked
		var damage_id := String(record["damage_id"])
		if seen.has(damage_id) or (not previous.is_empty() and damage_id < previous): return _failure("NON_CANONICAL_CONSTRUCTION_DAMAGE_HISTORY")
		seen[damage_id] = true
		previous = damage_id
	if typeof(value.get("checksum")) != TYPE_STRING or String(value["checksum"]) != compute_checksum(value): return _failure("CONSTRUCTION_DAMAGE_HISTORY_CHECKSUM_MISMATCH")
	return UtilsScript.validation_success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
