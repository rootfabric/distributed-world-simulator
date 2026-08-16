extends "res://scripts/runtime/seamless/sm0/sm0_automated_client_node.gd"

# Exact HANDOFF_REDIRECT replay boundary for P4.
# The base client historically treated transfer_id alone as replay identity.
# P4 stores a fingerprint of every accepted redirect and only ACKs an exact
# duplicate; same-id/different-route payloads fail closed.

var _p4_redirect_fingerprints: Dictionary = {}


func _handle_redirect(payload: Dictionary, remote_ip: String, remote_port: int) -> void:
	var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
	if transfer_id.is_empty():
		_fail("SM0_CLIENT_REDIRECT_TRANSFER_ID_REQUIRED", payload)
		return
	var fingerprint_check := _p4_validate_redirect_payload(payload)
	if not bool(fingerprint_check.get("success", false)):
		_fail(String(fingerprint_check.get("error_code", "SM0_CLIENT_REDIRECT_INVALID")), payload)
		return
	var fingerprint := String(fingerprint_check.get("details", {}).get("fingerprint", ""))

	if _completed_transfers.has(transfer_id):
		var expected_completed := String(_p4_redirect_fingerprints.get(transfer_id, ""))
		if expected_completed.is_empty() or expected_completed != fingerprint:
			_fail("SM0_CLIENT_REDIRECT_REPLAY_CONFLICT", payload)
			return
		_send_redirect_ack(remote_ip, remote_port, transfer_id)
		return

	if _state == "ACTIVATING" and transfer_id == String(_pending_transfer.get("transfer_id", "")):
		var expected_pending := String(_pending_transfer.get("redirect_fingerprint", ""))
		if expected_pending.is_empty() or expected_pending != fingerprint:
			_fail("SM0_CLIENT_REDIRECT_REPLAY_CONFLICT", payload)
			return
		_send_redirect_ack(remote_ip, remote_port, transfer_id)
		return

	# For a new redirect preserve all base route/epoch/identity checks, then bind
	# the accepted payload fingerprint to the pending activation.
	super._handle_redirect(payload, remote_ip, remote_port)
	if (
		_state == "ACTIVATING"
		and not _pending_transfer.is_empty()
		and String(_pending_transfer.get("transfer_id", "")) == transfer_id
	):
		_pending_transfer["redirect_fingerprint"] = fingerprint


func _handle_activate_ack(request_id: String, payload: Dictionary) -> void:
	var transfer_id := String(_pending_transfer.get("transfer_id", ""))
	var fingerprint := String(_pending_transfer.get("redirect_fingerprint", ""))
	var before := _handoffs_completed
	super._handle_activate_ack(request_id, payload)
	if (
		not transfer_id.is_empty()
		and not fingerprint.is_empty()
		and _handoffs_completed == before + 1
		and _completed_transfers.has(transfer_id)
	):
		_p4_redirect_fingerprints[transfer_id] = fingerprint


func _p4_validate_redirect_payload(payload: Dictionary) -> Dictionary:
	var transfer_id := String(payload.get("transfer_id", "")).strip_edges()
	var target_authority := String(payload.get("target_authority_id", "")).strip_edges()
	var target_zone := String(payload.get("target_zone_id", "")).strip_edges()
	var target_host := String(payload.get("target_host", "")).strip_edges()
	var target_port := int(payload.get("target_port", 0))
	var target_epoch := int(payload.get("authority_epoch", 0))
	var player_entity_id := String(payload.get("player_entity_id", "")).strip_edges()
	var directory: Dictionary = Dictionary(payload.get("directory", {}))
	var directory_check := Contracts.validate_directory(directory)
	if not bool(directory_check.get("success", false)):
		return {"success": false, "error_code": "SM0_CLIENT_REDIRECT_DIRECTORY_INVALID", "details": {"cause": directory_check}}
	if target_authority not in [Contracts.AUTHORITY_A, Contracts.AUTHORITY_B]:
		return {"success": false, "error_code": "SM0_CLIENT_REDIRECT_TARGET_INVALID", "details": {}}
	if Contracts.authority_for_zone(target_zone) != target_authority:
		return {"success": false, "error_code": "SM0_CLIENT_REDIRECT_ZONE_MISMATCH", "details": {}}
	if target_host.is_empty() or target_port < 1 or target_port > 65535:
		return {"success": false, "error_code": "SM0_CLIENT_REDIRECT_ROUTE_INVALID", "details": {}}
	if target_epoch < 1 or int(directory.get("authority_epoch", 0)) != target_epoch:
		return {"success": false, "error_code": "SM0_CLIENT_REDIRECT_DIRECTORY_EPOCH_MISMATCH", "details": {}}
	if String(directory.get("owner_authority_id", "")) != target_authority:
		return {"success": false, "error_code": "SM0_CLIENT_REDIRECT_DIRECTORY_OWNER_MISMATCH", "details": {}}
	if player_entity_id.is_empty():
		return {"success": false, "error_code": "SM0_CLIENT_REDIRECT_PLAYER_ID_REQUIRED", "details": {}}
	var canonical := "%s|%s|%s|%s|%d|%d|%s|%s" % [
		transfer_id,
		target_authority,
		target_zone,
		target_host,
		target_port,
		target_epoch,
		player_entity_id,
		String(directory.get("checksum", "")),
	]
	return {"success": true, "error_code": "", "details": {"fingerprint": canonical.sha256_text()}}
