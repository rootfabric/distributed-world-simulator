extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA := "planet_simulator.player_registry.v1"
const DURABLE_SCHEMA := "planet_simulator.player_registry_state.v1"
var _players: Dictionary = {}

func clear() -> void:
	_players.clear()

func upsert(record: Dictionary) -> Dictionary:
	var logical_id := String(record.get("logical_player_id", "")).strip_edges().to_lower()
	if logical_id.is_empty():
		return _failure("LOGICAL_PLAYER_ID_REQUIRED")
	_players[logical_id] = record.duplicate(true)
	return _success({"player": get_player(logical_id)})

func has_player(logical_player_id: String) -> bool:
	return _players.has(logical_player_id.strip_edges().to_lower())

func get_player(logical_player_id: String) -> Dictionary:
	return Dictionary(_players.get(logical_player_id.strip_edges().to_lower(), {})).duplicate(true)

func get_players() -> Array:
	var result: Array = []
	var ids := _players.keys()
	ids.sort()
	for logical_id in ids:
		result.append(Dictionary(_players[logical_id]).duplicate(true))
	return result

func export_durable_state() -> Dictionary:
	var players: Array = []
	for record_value in get_players():
		var record: Dictionary = Dictionary(record_value).duplicate(true)
		record["connected"] = false
		record["transport_session_id"] = ""
		players.append(record)
	var state: Dictionary = {
		"schema": DURABLE_SCHEMA,
		"players": players,
		"checksum": "",
	}
	return Utils.finalize_json_checksum(state)

func restore_durable_state(value: Dictionary) -> Dictionary:
	var validation := validate_durable_state(value)
	if not bool(validation.get("success", false)):
		return validation
	var staged: Dictionary = {}
	for record_value in value.get("players", []):
		var record: Dictionary = Dictionary(record_value).duplicate(true)
		var logical_id := String(record.get("logical_player_id", "")).strip_edges().to_lower()
		staged[logical_id] = record
	_players = staged
	return _success({"player_count": _players.size()})

func validate_durable_state(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != DURABLE_SCHEMA:
		return _failure("INVALID_PLAYER_REGISTRY_STATE_SCHEMA")
	if typeof(value.get("players")) != TYPE_ARRAY or typeof(value.get("checksum")) != TYPE_STRING:
		return _failure("INVALID_PLAYER_REGISTRY_STATE")
	if String(value.get("checksum", "")) != _checksum(value):
		return _failure("PLAYER_REGISTRY_STATE_CHECKSUM_MISMATCH")
	var seen: Dictionary = {}
	for record_value in value.get("players", []):
		if not record_value is Dictionary:
			return _failure("INVALID_PLAYER_REGISTRY_RECORD")
		var record: Dictionary = record_value
		var logical_id := String(record.get("logical_player_id", "")).strip_edges().to_lower()
		if logical_id.is_empty() or logical_id != String(record.get("logical_player_id", "")):
			return _failure("INVALID_PLAYER_REGISTRY_RECORD_ID")
		if seen.has(logical_id):
			return _failure("DUPLICATE_PLAYER_REGISTRY_RECORD")
		if String(record.get("player_entity_id", "")) != "player/%s" % logical_id:
			return _failure("INVALID_PLAYER_ENTITY_ID")
		if int(record.get("ownership_epoch", 0)) < 1 or int(record.get("state_revision", 0)) < 1:
			return _failure("INVALID_PLAYER_REGISTRY_REVISION")
		if typeof(record.get("connected")) != TYPE_BOOL:
			return _failure("INVALID_PLAYER_CONNECTED_STATE")
		if bool(record.get("connected", true)) or not String(record.get("transport_session_id", "")).is_empty():
			return _failure("DURABLE_PLAYER_SESSION_MUST_BE_DISCONNECTED")
		if typeof(record.get("position")) != TYPE_DICTIONARY or typeof(record.get("velocity")) != TYPE_DICTIONARY:
			return _failure("INVALID_PLAYER_SPATIAL_STATE")
		if not _valid_vector3(Dictionary(record.get("position", {}))) or not _valid_vector3(Dictionary(record.get("velocity", {}))):
			return _failure("INVALID_PLAYER_SPATIAL_STATE")
		if not _finite_number(record.get("orientation_yaw")) or typeof(record.get("flashlight_enabled")) != TYPE_BOOL:
			return _failure("INVALID_PLAYER_PRESENTATION_STATE")
		if int(record.get("last_input_sequence", -1)) < 0:
			return _failure("INVALID_PLAYER_INPUT_SEQUENCE")
		if typeof(record.get("inventory")) != TYPE_ARRAY:
			return _failure("INVALID_PLAYER_INVENTORY_STATE")
		var inventory_ids: Dictionary = {}
		for item_id_value in record.get("inventory", []):
			var item_id := String(item_id_value)
			if item_id.strip_edges().is_empty() or inventory_ids.has(item_id):
				return _failure("INVALID_PLAYER_INVENTORY_STATE")
			inventory_ids[item_id] = true
		seen[logical_id] = true
	var safe := Utils.canonicalize(value, "$.player_registry")
	if not bool(safe.get("success", false)):
		return _failure("PLAYER_REGISTRY_STATE_NOT_JSON_SAFE", {"message": String(safe.get("error", ""))})
	return _success({"player_count": seen.size()})

func _valid_vector3(value: Dictionary) -> bool:
	for axis in ["x", "y", "z"]:
		if not value.has(axis) or not _finite_number(value.get(axis)):
			return false
	return true


func _finite_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number)

func get_report() -> Dictionary:
	return {"schema": SCHEMA, "player_count": _players.size()}

func _checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true)
	payload.erase("checksum")
	return Utils.payload_hash(payload)

func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
