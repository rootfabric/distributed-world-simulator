class_name Ch9NetworkedGameplayService
extends "res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd"

const EquipmentItemGraph = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_equipment_item_graph_service.gd")


func setup(authority_owner_id: String, authority_epoch: int, server_tick: int = 0, config: Dictionary = {}) -> Dictionary:
	var result: Dictionary = super.setup(authority_owner_id, authority_epoch, server_tick, config)
	if not bool(result.get("success", false)):
		return result
	var equipment_graph = EquipmentItemGraph.new()
	var graph_setup: Dictionary = equipment_graph.setup(authority_owner_id, authority_epoch, {
		"playable_sandbox": bool(config.get("playable_sandbox", false)),
	})
	if not bool(graph_setup.get("success", false)):
		shutdown()
		return graph_setup
	_canonical_multiplayer_items = equipment_graph
	return _success({
		"snapshot": create_snapshot(),
		"profile": _profile,
		"topology_adapter": _topology_adapter,
		"character_equipment_authority": true,
	})


func handle_join_command(command: Dictionary) -> Dictionary:
	var result: Dictionary = super.handle_join_command(command)
	if bool(result.get("success", false)) and _canonical_multiplayer_items != null:
		_canonical_multiplayer_items.ensure_player(String(command.get("logical_player_id", "")))
	return result


func get_character_equipment_container(logical_player_id: String) -> Dictionary:
	if _canonical_multiplayer_items == null or not _canonical_multiplayer_items.has_method("equipment_container_snapshot"):
		return {}
	return _canonical_multiplayer_items.equipment_container_snapshot(logical_player_id)
