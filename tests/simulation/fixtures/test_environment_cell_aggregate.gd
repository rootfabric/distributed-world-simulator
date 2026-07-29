extends RefCounted

const STATE_SCHEMA: String = "planet_simulator.test_environment_cell_state.v1"
const AGGREGATE_KIND: String = "ENVIRONMENT_CELL"

var aggregate_id: String = ""
var cell_id: String = ""
var authority_owner_id: String = ""
var authority_epoch: int = 0
var state_revision: int = 0
var server_tick: int = 0
var state: Dictionary = {}


func setup(context: Dictionary) -> bool:
	aggregate_id = String(context.get("aggregate_id", ""))
	cell_id = String(context.get("cell_id", ""))
	authority_owner_id = String(context.get("authority_owner_id", ""))
	authority_epoch = int(context.get("authority_epoch", 0))
	state_revision = int(context.get("state_revision", 0))
	server_tick = int(context.get("server_tick", 0))
	var state_value = context.get("state", {})
	if aggregate_id.is_empty() or cell_id.is_empty() or authority_owner_id.is_empty() or authority_epoch < 1 or state_revision < 0 or server_tick < 0 or typeof(state_value) != TYPE_DICTIONARY:
		return false
	var encoded: String = JSON.stringify(state_value, "", true, true)
	var decoded = JSON.parse_string(encoded)
	if typeof(decoded) != TYPE_DICTIONARY:
		return false
	state = Dictionary(decoded)
	return true


func apply_state_patch(patch: Dictionary, expected_revision: int, tick: int) -> Dictionary:
	if expected_revision != state_revision:
		return {"success": false, "error_code": "REVISION_CONFLICT"}
	if tick < server_tick:
		return {"success": false, "error_code": "STALE_SERVER_TICK"}
	var next_state: Dictionary = state.duplicate(true)
	for raw_key in patch.keys():
		var key: String = String(raw_key)
		if patch[raw_key] == null:
			next_state.erase(key)
		else:
			next_state[key] = patch[raw_key]
	if next_state == state and tick == server_tick:
		return {"success": true, "changed": false, "state_revision": state_revision}
	state = next_state
	state_revision += 1
	server_tick = tick
	return {"success": true, "changed": true, "state_revision": state_revision}
