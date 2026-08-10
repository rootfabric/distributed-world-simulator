class_name Ch9NetworkItemCommandBridge
extends "res://scripts/runtime/networked_gameplay/m7/m7_network_item_command_bridge.gd"

const EquipmentAdapter = preload("res://scripts/runtime/networked_gameplay/ch9/ch9_3_item_graph_replica_adapter.gd")


func setup(runtime, local_player_id: String, selected_item_provider: Callable = Callable()) -> Dictionary:
	var result: Dictionary = super.setup(runtime, local_player_id, selected_item_provider)
	if not bool(result.get("success", false)):
		return result
	var equipment_adapter = EquipmentAdapter.new()
	var adapter_setup: Dictionary = equipment_adapter.setup(local_player_id)
	if not bool(adapter_setup.get("success", false)):
		stop("CH9_3_EQUIPMENT_ADAPTER_SETUP_FAILED")
		return adapter_setup
	_adapter = equipment_adapter
	return _success({
		"prediction_enabled": _prediction_enabled(),
		"character_equipment_enabled": true,
		"prediction": _prediction_journal.get_report() if _prediction_journal != null else {},
	})
