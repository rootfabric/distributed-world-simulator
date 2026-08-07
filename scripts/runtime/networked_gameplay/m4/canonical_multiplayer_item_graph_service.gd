extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd"

# Composition correction for multiplayer player materialization.
# The accepted base historically created a sandbox player's starter inventory
# lazily on the first item command without advancing ItemGraph identity. That
# made JOIN_ACK legitimately empty and allowed same-revision graph mutation.

var _player_materializations: int = 0


func ensure_player(logical_player_id: String) -> void:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return
	var existed := _inventories.has(player_id)
	super.ensure_player(player_id)
	if not existed and _inventories.has(player_id):
		_revision += 1
		_tick += 1
		_player_materializations += 1


func ensure_player_for_join(logical_player_id: String) -> Dictionary:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty():
		return {"success": false, "error_code": "ITEM_GRAPH_PLAYER_ID_REQUIRED", "details": {}}
	var before_revision := _revision
	ensure_player(player_id)
	if not _inventories.has(player_id):
		return {"success": false, "error_code": "ITEM_GRAPH_PLAYER_MATERIALIZATION_FAILED", "details": {"logical_player_id": player_id}}
	var inventory: Dictionary = Dictionary(_inventories[player_id]).duplicate(true)
	return {
		"success": true,
		"error_code": "",
		"details": {
			"logical_player_id": player_id,
			"created": _revision > before_revision,
			"revision": _revision,
			"tick": _tick,
			"inventory_item_count": Array(inventory.get("inventory", [])).size(),
			"hotbar_size": Array(inventory.get("hotbar", [])).size(),
		}
	}


func get_player_materialization_report() -> Dictionary:
	return {
		"player_materializations": _player_materializations,
		"inventory_count": _inventories.size(),
		"revision": _revision,
		"tick": _tick,
	}
