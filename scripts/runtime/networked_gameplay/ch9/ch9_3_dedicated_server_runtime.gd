class_name Ch9DedicatedServerRuntime
extends "res://scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd"

const Ch9Service = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_networked_gameplay_service.gd")


func setup(config: Dictionary) -> Dictionary:
	# CH9.3 transport validation intentionally runs without M6 persistence; durable
	# equipment recovery is the CH9.4 acceptance surface. All accepted M3/NX
	# transport, fixed-tick and replication machinery remains inherited.
	if not String(config.get("persistence_root", "")).strip_edges().is_empty():
		return _failure("CH9_3_PERSISTENCE_DEFERRED_TO_CH9_4")
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)):
		return result
	var replacement = Ch9Service.new()
	var replacement_setup: Dictionary = replacement.setup(
		_authority_owner_id,
		_authority_epoch,
		_server_tick,
		{
			"profile": Ch9Service.PROFILE_MULTIPLAYER_CORE,
			"topology_adapter": "ENET",
			"region_id": "region/m3/single-server",
			"playable_sandbox": _playable_sandbox,
			"fixed_tick_authority": true,
		}
	)
	if not bool(replacement_setup.get("success", false)):
		shutdown()
		return replacement_setup
	if _service != null:
		_service.shutdown()
	_service = replacement
	return _success({
		"host": _host,
		"port": _port,
		"character_equipment_authority": true,
		"item_graph_channel": "ITEM",
	})


func _is_item_command_type(command_type: String) -> bool:
	return command_type.begins_with("equipment.") or super._is_item_command_type(command_type)
