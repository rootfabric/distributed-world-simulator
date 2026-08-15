extends RefCounted

const BaseService = preload("res://scripts/runtime/networked_gameplay/networked_gameplay_service.gd")
const AuthorityService = preload("res://scripts/runtime/networked_gameplay/multiplayer_gameplay_authority_service.gd")
const SCHEMA := "planet_simulator.multiplayer_gameplay_authority.v1"
const SNAPSHOT_SCHEMA := BaseService.SNAPSHOT_SCHEMA
const DELTA_SCHEMA := BaseService.DELTA_SCHEMA
const SHARED_ITEM_ID := BaseService.SHARED_ITEM_ID

var _service

func setup(authority_owner_id: String, authority_epoch: int, server_tick: int = 0) -> Dictionary:
	_service = AuthorityService.new()
	return _service.setup(authority_owner_id, authority_epoch, server_tick, {"profile": BaseService.PROFILE_MULTIPLAYER_CORE, "topology_adapter": "ENET", "region_id": "region/h3/test-arena"})

func join(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary: return _service.join(logical_player_id, transport_session_id, operation_id)
func leave(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary: return _service.leave(logical_player_id, transport_session_id, operation_id)
func leave_transport_session(transport_session_id: String, operation_id: String) -> Dictionary: return _service.leave_transport_session(transport_session_id, operation_id)
func move_player(logical_player_id: String, transport_session_id: String, ownership_epoch: int, input_sequence: int, delta_x: float, delta_z: float, operation_id: String) -> Dictionary: return _service.move_player(logical_player_id, transport_session_id, ownership_epoch, input_sequence, delta_x, delta_z, operation_id)
func import_handoff_player_state(logical_player_id: String, transport_session_id: String, ownership_epoch: int, handoff_state: Dictionary, operation_id: String) -> Dictionary: return _service.import_handoff_player_state(logical_player_id, transport_session_id, ownership_epoch, handoff_state, operation_id)
func pickup_shared_item(logical_player_id: String, transport_session_id: String, ownership_epoch: int, item_id: String, operation_id: String) -> Dictionary: return _service.pickup_shared_item(logical_player_id, transport_session_id, ownership_epoch, item_id, operation_id)
func request_inventory_write(requester_player_id: String, target_player_id: String, transport_session_id: String, ownership_epoch: int, operation_id: String) -> Dictionary: return _service.request_inventory_write(requester_player_id, target_player_id, transport_session_id, ownership_epoch, operation_id)
func create_snapshot() -> Dictionary: return _service.create_snapshot()
func validate_snapshot(snapshot: Dictionary) -> Dictionary: return _service.validate_snapshot(snapshot)
func validate_delta(delta: Dictionary) -> Dictionary: return _service.validate_delta(delta)
func get_player(logical_player_id: String) -> Dictionary: return _service.get_player(logical_player_id)
func get_report() -> Dictionary:
	var report: Dictionary = _service.get_report() if _service != null else {}
	report["schema"] = SCHEMA
	return report
func create_targeted_command_result(message_id: String, operation_id: String, result: Dictionary) -> Dictionary: return _service.create_targeted_command_result(message_id, operation_id, result)

# SM0 recovery consumes the existing canonical gameplay durability contract.
# These methods intentionally remain thin pass-throughs so this wrapper never
# becomes a second persistence owner.
func export_durable_state() -> Dictionary:
	return _service.export_durable_state() if _service != null else {}

func restore_durable_state(value: Dictionary) -> Dictionary:
	return _service.restore_durable_state(value) if _service != null else _not_ready()

func validate_durable_state(value: Dictionary) -> Dictionary:
	return _service.validate_durable_state(value) if _service != null else _not_ready()

func export_replay_state() -> Dictionary:
	return _service.export_replay_state() if _service != null else {}

func restore_replay_state(value: Dictionary) -> Dictionary:
	return _service.restore_replay_state(value) if _service != null else _not_ready()

func validate_replay_state(value: Dictionary) -> Dictionary:
	return _service.validate_replay_state(value) if _service != null else _not_ready()

func get_recovery_report() -> Dictionary:
	return _service.get_recovery_report() if _service != null else {}

func get_networked_gameplay_service_for_tests(): return _service

func _not_ready() -> Dictionary:
	return {"success": false, "error_code": "MULTIPLAYER_GAMEPLAY_AUTHORITY_NOT_READY", "details": {}}
