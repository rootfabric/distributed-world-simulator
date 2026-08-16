extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_p4_closure.gd"

var captured_gameplay: Array[Dictionary] = []
var captured_control: Array[Dictionary] = []


func configure_admission_fixture(
	authority_id: String,
	directory: Dictionary,
	peer_synced: bool
) -> void:
	_p4_enabled = true
	_authority_id = authority_id
	_zone_id = Contracts.ZONE_A if authority_id == Contracts.AUTHORITY_A else Contracts.ZONE_B
	_peer_authority_id = Contracts.peer_authority(authority_id)
	_peer_zone_id = Contracts.peer_zone(_zone_id)
	_directory = directory.duplicate(true)
	_peer_synced = peer_synced


func install_reservation(prewarm: Dictionary, expires_at_local_ms: int) -> void:
	_prewarmed_transfers[String(prewarm.get("prewarm_id", ""))] = {
		"prewarm": prewarm.duplicate(true),
		"expires_at_local_ms": expires_at_local_ms,
	}


func invoke_join(payload: Dictionary) -> void:
	captured_gameplay.clear()
	_handle_client_join("join/test", payload, "127.0.0.1", 24780)


func invoke_prewarm(prewarm: Dictionary) -> void:
	captured_control.clear()
	_handle_p4_prewarm("prewarm/test", {"prewarm": prewarm.duplicate(true)})


func last_gameplay_error() -> String:
	if captured_gameplay.is_empty():
		return ""
	return String(Dictionary(captured_gameplay[-1].get("payload", {})).get("error_code", ""))


func last_control_error() -> String:
	if captured_control.is_empty():
		return ""
	return String(Dictionary(captured_control[-1].get("payload", {})).get("error_code", ""))


func _send_gameplay(host: String, port: int, message_type: String, payload: Dictionary, request_id: String = "") -> void:
	captured_gameplay.append({
		"host": host,
		"port": port,
		"message_type": message_type,
		"payload": payload.duplicate(true),
		"request_id": request_id,
	})


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	captured_control.append({
		"message_type": message_type,
		"payload": payload.duplicate(true),
		"request_id": request_id,
	})
