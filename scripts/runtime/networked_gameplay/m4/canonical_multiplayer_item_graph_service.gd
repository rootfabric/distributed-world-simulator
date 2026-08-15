extends "res://scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_base.gd"

# V0-P1 R4 repair boundary.
#
# Player inventory materialization changes the canonical Item Graph and must
# therefore advance the Item Graph clock exactly once. The inherited service
# remains the sole owner of items/inventories/containers/mounts; this adapter
# only makes the already-existing ensure_player() mutation observable through
# the canonical revision contract. Reconnect remains idempotent because an
# existing inventory returns before the inherited mutation is invoked.


func ensure_player(logical_player_id: String) -> void:
	var player_id := logical_player_id.strip_edges().to_lower()
	if player_id.is_empty() or _inventories.has(player_id):
		return
	super.ensure_player(player_id)
	_revision += 1
	_tick += 1
