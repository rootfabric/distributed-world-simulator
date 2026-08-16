extends "res://scripts/runtime/seamless/sm0/sm0_automated_client_node_p4_hardened.gd"

var captured_redirect_acks: Array[Dictionary] = []
var captured_failures: Array[Dictionary] = []


func install_completed_redirect(payload: Dictionary) -> Dictionary:
	var check := _p4_validate_redirect_payload(payload)
	if not bool(check.get("success", false)):
		return check
	var transfer_id := String(payload.get("transfer_id", ""))
	_completed_transfers[transfer_id] = true
	_p4_redirect_fingerprints[transfer_id] = String(Dictionary(check.get("details", {})).get("fingerprint", ""))
	return check


func invoke_redirect(payload: Dictionary) -> void:
	captured_redirect_acks.clear()
	captured_failures.clear()
	_handle_redirect(payload.duplicate(true), "127.0.0.1", 24580)


func last_failure_code() -> String:
	if captured_failures.is_empty():
		return ""
	return String(captured_failures[-1].get("error_code", ""))


func _send_redirect_ack(host: String, port: int, transfer_id: String) -> void:
	captured_redirect_acks.append({"host": host, "port": port, "transfer_id": transfer_id})


func _fail(error_code: String, details: Dictionary) -> void:
	captured_failures.append({"error_code": error_code, "details": details.duplicate(true)})
