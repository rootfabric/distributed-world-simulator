extends RefCounted

# R3.1: copy a previously committed wire projection, not a live ITEM snapshot.
# Only kinematic scalars are allowed to differ. The canonical gameplay
# revision, per-player state revision, item, inventory, ownership and sessions
# are pinned until the M6 writer reports the exact durable generation.
const Full = preload("res://scripts/runtime/networked_gameplay/contracts/player_state_snapshot.gd")

static func project(committed: Dictionary, live_players: Array, tick: int) -> Dictionary:
	if String(committed.get("schema", "")) != Full.SCHEMA:
		return _failure("COMMITTED_VIEW_SCHEMA_REQUIRED")
	if not committed.get("players") is Array or not committed.get("shared_item") is Dictionary:
		return _failure("COMMITTED_VIEW_FIELDS_REQUIRED")
	var indexed: Dictionary = {}
	for value in live_players:
		if value is Dictionary:
			var row: Dictionary = value
			var id := String(row.get("logical_player_id", ""))
			if not id.is_empty() and not indexed.has(id):
				indexed[id] = row
	var rows: Array = Array(committed["players"]).duplicate(true)
	for value in rows:
		if not value is Dictionary:
			return _failure("COMMITTED_VIEW_PLAYER_INVALID")
		var frozen: Dictionary = value
		var logical_id := String(frozen.get("logical_player_id", ""))
		if not indexed.has(logical_id):
			continue
		var live: Dictionary = indexed[logical_id]
		if (String(live.get("player_entity_id", "")) != String(frozen.get("player_entity_id", ""))
			or String(live.get("transport_session_id", "")) != String(frozen.get("transport_session_id", ""))
			or int(live.get("ownership_epoch", -1)) != int(frozen.get("ownership_epoch", -2))
			or bool(live.get("connected", false)) != bool(frozen.get("connected", false))):
			continue  # never inherit movement across a new USER1 epoch or session
		for field in ["position", "velocity", "orientation_yaw", "last_input_sequence"]:
			if not live.has(field):
				return _failure("COMMITTED_VIEW_MOVEMENT_REQUIRED", {"field": field})
			var value_now = live[field]
			frozen[field] = Dictionary(value_now).duplicate(true) if value_now is Dictionary else value_now
	var snapshot: Dictionary = Full.create(
		String(committed.get("authority_owner_id", "")), int(committed.get("authority_epoch", 0)),
		int(committed.get("revision", 0)), maxi(tick, int(committed.get("server_tick", 0))),
		String(committed.get("region_id", "")), rows, Dictionary(committed["shared_item"])
	)
	return _success({"snapshot": snapshot})


static func peer_is_fenced(view: Dictionary, player_id: String, session_id: String) -> bool:
	if player_id.is_empty() or session_id.is_empty():
		return false
	for value in view.get("players", []):
		if value is Dictionary:
			var player: Dictionary = value
			if String(player.get("logical_player_id", "")) == player_id:
				return bool(player.get("connected", false)) and String(player.get("transport_session_id", "")) == session_id
	return false


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details}
