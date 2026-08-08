extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SurfaceCellKeyScript = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")

const STATE_REQUESTED: String = "REQUESTED"
const STATE_BUILDING: String = "BUILDING"
const STATE_ACTIVE: String = "ACTIVE"
const STATE_RETIRING: String = "RETIRING"
const STATES: Array[String] = [STATE_REQUESTED, STATE_BUILDING, STATE_ACTIVE, STATE_RETIRING]

var _records: Dictionary = {}
var _reconcile_serial: int = 0


func reconcile(desired_cells: Array) -> Dictionary:
	var desired: Dictionary = {}
	for raw_cell in desired_cells:
		if not raw_cell is Dictionary:
			return GeoUtilsScript.failure("INVALID_DESIRED_SURFACE_CELL")
		var cell: Dictionary = raw_cell
		var validation: Dictionary = SurfaceCellKeyScript.validate(cell)
		if not bool(validation.get("success", false)):
			return GeoUtilsScript.failure("INVALID_DESIRED_SURFACE_CELL", {"cause": validation.get("error_code", "")})
		var token: String = SurfaceCellKeyScript.identity_token(cell)
		if desired.has(token):
			return GeoUtilsScript.failure("DUPLICATE_DESIRED_SURFACE_CELL", {"cell": token})
		desired[token] = cell.duplicate(true)

	_reconcile_serial += 1
	var requested: Array[String] = []
	var retiring: Array[String] = []
	var revived: Array[String] = []

	var existing_tokens: Array = _records.keys()
	existing_tokens.sort()
	for token in existing_tokens:
		if desired.has(token):
			continue
		var record: Dictionary = _records[token]
		if String(record["state"]) != STATE_RETIRING:
			record["state"] = STATE_RETIRING
			record["last_transition_serial"] = _reconcile_serial
			_records[token] = record
			retiring.append(String(token))

	var desired_tokens: Array = desired.keys()
	desired_tokens.sort()
	for token in desired_tokens:
		var cell: Dictionary = desired[token]
		if not _records.has(token):
			_records[token] = {
				"cell": cell.duplicate(true),
				"state": STATE_REQUESTED,
				"has_active_artifact": false,
				"last_transition_serial": _reconcile_serial,
			}
			requested.append(String(token))
			continue
		var record: Dictionary = _records[token]
		if String(record["state"]) == STATE_RETIRING:
			if bool(record["has_active_artifact"]):
				record["state"] = STATE_ACTIVE
			else:
				record["state"] = STATE_REQUESTED
				requested.append(String(token))
			record["last_transition_serial"] = _reconcile_serial
			_records[token] = record
			revived.append(String(token))

	return GeoUtilsScript.success({
		"requested": requested,
		"retiring": retiring,
		"revived": revived,
		"snapshot": snapshot(),
	})


func begin_build(cell: Dictionary) -> Dictionary:
	return _transition(cell, STATE_REQUESTED, STATE_BUILDING, false)


func activate(cell: Dictionary) -> Dictionary:
	return _transition(cell, STATE_BUILDING, STATE_ACTIVE, true)


func begin_retire(cell: Dictionary) -> Dictionary:
	var lookup: Dictionary = _lookup(cell)
	if not bool(lookup.get("success", false)):
		return lookup
	var token: String = String(lookup["details"]["token"])
	var record: Dictionary = _records[token]
	if String(record["state"]) == STATE_RETIRING:
		return GeoUtilsScript.success({"state": STATE_RETIRING})
	_reconcile_serial += 1
	record["state"] = STATE_RETIRING
	record["last_transition_serial"] = _reconcile_serial
	_records[token] = record
	return GeoUtilsScript.success({"state": STATE_RETIRING})


func complete_retire(cell: Dictionary) -> Dictionary:
	var lookup: Dictionary = _lookup(cell)
	if not bool(lookup.get("success", false)):
		return lookup
	var token: String = String(lookup["details"]["token"])
	var record: Dictionary = _records[token]
	if String(record["state"]) != STATE_RETIRING:
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_LIFECYCLE_TRANSITION", {
			"from": String(record["state"]), "to": "REMOVED",
		})
	_records.erase(token)
	return GeoUtilsScript.success({"removed": token})


func get_state(cell: Dictionary) -> String:
	var token: String = SurfaceCellKeyScript.identity_token(cell)
	if token.is_empty() or not _records.has(token):
		return ""
	return String(_records[token]["state"])


func size() -> int:
	return _records.size()


func snapshot() -> Array:
	var tokens: Array = _records.keys()
	tokens.sort()
	var result: Array = []
	for token in tokens:
		var record: Dictionary = _records[token]
		result.append({
			"cell": Dictionary(record["cell"]).duplicate(true),
			"state": String(record["state"]),
			"has_active_artifact": bool(record["has_active_artifact"]),
			"last_transition_serial": int(record["last_transition_serial"]),
		})
	return result


func _transition(cell: Dictionary, expected_state: String, next_state: String, active_artifact: bool) -> Dictionary:
	var lookup: Dictionary = _lookup(cell)
	if not bool(lookup.get("success", false)):
		return lookup
	var token: String = String(lookup["details"]["token"])
	var record: Dictionary = _records[token]
	if String(record["state"]) != expected_state:
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_LIFECYCLE_TRANSITION", {
			"from": String(record["state"]), "to": next_state,
		})
	_reconcile_serial += 1
	record["state"] = next_state
	record["has_active_artifact"] = active_artifact or bool(record["has_active_artifact"])
	record["last_transition_serial"] = _reconcile_serial
	_records[token] = record
	return GeoUtilsScript.success({"state": next_state})


func _lookup(cell: Dictionary) -> Dictionary:
	var validation: Dictionary = SurfaceCellKeyScript.validate(cell)
	if not bool(validation.get("success", false)):
		return GeoUtilsScript.failure("INVALID_SURFACE_CELL_KEY", {"cause": validation.get("error_code", "")})
	var token: String = SurfaceCellKeyScript.identity_token(cell)
	if not _records.has(token):
		return GeoUtilsScript.failure("UNKNOWN_SURFACE_CELL_LIFECYCLE_RECORD", {"cell": token})
	return GeoUtilsScript.success({"token": token})
