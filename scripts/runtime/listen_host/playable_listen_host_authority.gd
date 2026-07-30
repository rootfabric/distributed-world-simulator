extends Node

const Service = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")

const SCHEMA := "planet_simulator.playable_listen_host_authority.v1"
const PLAYER_ENTITY_ID := "player/local-astronaut"
const ITEM_GRAPH_ENTITY_ID := "item-graph/player/local-astronaut"
const PLAYER_ENTITY_TYPE := "player"
const ITEM_GRAPH_ENTITY_TYPE := "item_graph"

var _service

func setup(config: Dictionary) -> Dictionary:
	if _service != null:
		return _failure("PLAYABLE_AUTHORITY_ALREADY_CONFIGURED")
	_service = Service.new()
	var service_config := config.duplicate(true)
	service_config["topology_adapter"] = String(config.get("topology_adapter", "LOOPBACK"))
	var result: Dictionary = _service.setup_playable(service_config)
	if not bool(result.get("success", false)):
		_service = null
	return result

func handle_command(command_value: Dictionary) -> Dictionary:
	return _service.handle_network_command(command_value) if _service != null else {}

func create_initial_snapshots() -> Array[Dictionary]:
	return _service.create_initial_entity_snapshots() if _service != null else []

func create_snapshot(entity_id: String) -> Dictionary:
	return _service.create_entity_snapshot(entity_id) if _service != null else {}

func get_report() -> Dictionary:
	var report: Dictionary = _service.get_report() if _service != null else {"configured": false}
	report["schema"] = SCHEMA
	return report

func get_world_entity_store_for_kernel():
	return _service.get_world_entity_store_for_kernel() if _service != null else null

func get_item_controller_for_authority_tests():
	return _service.get_item_controller_for_authority_tests() if _service != null else null

func get_networked_gameplay_service_for_tests():
	return _service

func shutdown() -> Dictionary:
	if _service == null:
		return _success()
	var result: Dictionary = _service.shutdown()
	_service = null
	return result

func _success(details: Dictionary = {}) -> Dictionary: return {"success": true, "error_code": "", "details": details.duplicate(true)}
func _failure(error_code: String) -> Dictionary: return {"success": false, "error_code": error_code, "details": {}}
