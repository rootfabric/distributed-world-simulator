extends RefCounted

const Service = preload("res://scripts/runtime/networked_gameplay/services/player_ownership_service.gd")
const SCHEMA := "planet_simulator.player_ownership_registry.v1"
const SNAPSHOT_SCHEMA := Service.SNAPSHOT_SCHEMA
const DELTA_SCHEMA := Service.DELTA_SCHEMA
var _service

func setup(authority_owner_id: String, authority_epoch: int, server_tick: int = 0) -> Dictionary:
	_service = Service.new()
	return _service.setup(authority_owner_id, authority_epoch, server_tick)
func join(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary: return _service.join(logical_player_id, transport_session_id, operation_id)
func leave(logical_player_id: String, transport_session_id: String, operation_id: String) -> Dictionary: return _service.leave(logical_player_id, transport_session_id, operation_id)
func leave_transport_session(transport_session_id: String, operation_id: String) -> Dictionary: return _service.leave_transport_session(transport_session_id, operation_id)
func create_snapshot() -> Dictionary: return _service.create_snapshot()
func validate_snapshot(snapshot: Dictionary) -> Dictionary: return _service.validate_snapshot(snapshot)
func get_report() -> Dictionary:
	var report: Dictionary = _service.get_report() if _service != null else {}
	report["schema"] = SCHEMA
	return report
func get_player(logical_player_id: String) -> Dictionary: return _service.get_player(logical_player_id)
func get_player_for_session(transport_session_id: String) -> Dictionary: return _service.get_player_for_session(transport_session_id)
func get_player_ownership_service_for_tests(): return _service
