extends RefCounted

const SCHEMA := "planet_simulator.player_registry.v1"
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

func get_report() -> Dictionary:
	return {"schema": SCHEMA, "player_count": _players.size()}

func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String) -> Dictionary: return {"success": false, "error_code": error_code, "details": {}}
