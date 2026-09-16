extends RefCounted

# Local execution readiness, AND the decision of the EXISTING SM1 owner.
# This adapter never chooses an owner or advances an authority epoch.
var _coordinator = null
var _local_authority := ""
var _player := ""
var _session := ""
var _ownership_epoch := 0
var _installed_epoch := 0
var _highest_observed_epoch := 0
var _installed_transfer := ""


func configure(coordinator, local_authority: String, player: String, session: String, ownership_epoch: int, installed_epoch: int) -> Dictionary:
	if _coordinator != null:
		return _failure("LIVE_PLAYER_GATE_REBIND_FORBIDDEN")
	if coordinator == null or not coordinator.has_method("snapshot") or not coordinator.has_method("authorize_write") or not coordinator.has_method("get_completed_transfer"):
		return _failure("SM1_DECISION_PORT_REQUIRED")
	if local_authority.is_empty() or player.is_empty() or not session.begins_with("transport-session/") or ownership_epoch < 1 or installed_epoch < 0:
		return _failure("LIVE_PLAYER_GATE_CONFIGURATION_INVALID")
	_coordinator = coordinator
	_local_authority = local_authority
	_player = player
	_session = session
	_ownership_epoch = ownership_epoch
	_installed_epoch = installed_epoch
	if decision_snapshot().is_empty():
		return _failure("SM1_PLAYER_BINDING_MISMATCH")
	return _success()


func decision_snapshot() -> Dictionary:
	if _coordinator == null:
		return {}
	var state: Dictionary = _coordinator.snapshot()
	var player: Dictionary = state.get("player_snapshot", {})
	var epoch_value = state.get("authority_epoch")
	if typeof(epoch_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(epoch_value)) or float(epoch_value) != floorf(float(epoch_value)) or float(epoch_value) < 1.0 or float(epoch_value) > 9007199254740991.0:
		return {}
	var epoch := int(epoch_value)
	if epoch < _highest_observed_epoch:
		return {}
	if player.get("logical_player_id") != "player/mvp3/" + _player or player.get("player_entity_id") != "entity/mvp3/" + _player:
		return {}
	_highest_observed_epoch = epoch
	return state


func is_locally_ready() -> bool:
	var state := decision_snapshot()
	return not state.is_empty() and state.get("state") == "ACTIVE" and state.get("active_authority_id") == _local_authority and int(state.get("authority_epoch", 0)) == _installed_epoch and _installed_epoch > 0


func is_locally_presentable() -> bool:
	# A frozen source row remains a read-only presentation until explicit local
	# retirement. The Service advances its revision at retirement/installation,
	# not merely because an external coordinator label changed.
	var state := decision_snapshot()
	if state.is_empty() or _installed_epoch < 1:
		return false
	if state.get("active_authority_id") == _local_authority and int(state.get("authority_epoch", 0)) == _installed_epoch:
		return state.get("state") in ["ACTIVE", "SOURCE_FROZEN", "TARGET_WARM_VALIDATED"]
	var transfer: Dictionary = state.get("transfer", {})
	return state.get("state") == "OWNERSHIP_COMMITTED" and transfer.get("source_authority_id") == _local_authority and int(transfer.get("source_epoch", 0)) == _installed_epoch


func authorize_record_write(record: Dictionary) -> Dictionary:
	if not is_locally_ready():
		return _failure("LIVE_PLAYER_AUTHORITY_NOT_READY")
	var identity := validate_record_identity(record)
	if not bool(identity.get("success", false)):
		return identity
	return _coordinator.authorize_write(_local_authority, _installed_epoch)


func validate_record_identity(record: Dictionary) -> Dictionary:
	if record.get("logical_player_id") != _player or record.get("player_entity_id") != "player/" + _player or record.get("transport_session_id") != _session or record.get("ownership_epoch") != _ownership_epoch:
		return _failure("LIVE_PLAYER_IDENTITY_OR_SESSION_CHANGED")
	return _success()


func check_transfer_phase(transfer_id: String, purpose: String, token: String = "") -> Dictionary:
	var state := decision_snapshot()
	if state.is_empty():
		return _failure("SM1_DECISION_UNAVAILABLE")
	if purpose == "TARGET_INSTALL":
		var completed: Dictionary = _coordinator.get_completed_transfer(transfer_id)
		if completed.is_empty() or state.get("state") != "ACTIVE" or state.get("active_authority_id") != _local_authority or completed.get("target_authority_id") != _local_authority or int(state.get("authority_epoch", 0)) != int(completed.get("target_epoch", -1)):
			return _failure("LIVE_PLAYER_TARGET_NOT_CURRENT")
		if token.is_empty() or completed.get("commit_token") != token or completed.get("completed") != true:
			return _failure("LIVE_PLAYER_COMMIT_PROOF_INVALID")
		return _success({"transfer": completed})
	var transfer: Dictionary = state.get("transfer", {})
	if transfer.get("transfer_id") != transfer_id:
		return _failure("LIVE_PLAYER_TRANSFER_NOT_CURRENT")
	if purpose == "SOURCE_EXPORT":
		if state.get("state") not in ["SOURCE_FROZEN", "TARGET_WARM_VALIDATED"] or transfer.get("source_authority_id") != _local_authority or int(transfer.get("source_epoch", 0)) != _installed_epoch:
			return _failure("LIVE_PLAYER_SOURCE_NOT_FROZEN")
	elif purpose == "TARGET_STAGE":
		if state.get("state") not in ["SOURCE_FROZEN", "TARGET_WARM_VALIDATED"] or transfer.get("target_authority_id") != _local_authority:
			return _failure("LIVE_PLAYER_TARGET_STAGE_NOT_AUTHORIZED")
	elif purpose == "SOURCE_RETIRE":
		if state.get("state") not in ["OWNERSHIP_COMMITTED", "SOURCE_RETIRED"] or transfer.get("source_authority_id") != _local_authority or token.is_empty() or transfer.get("commit_token") != token:
			return _failure("LIVE_PLAYER_RETIRE_PROOF_INVALID")
	else:
		return _failure("LIVE_PLAYER_TRANSFER_PURPOSE_INVALID")
	return _success({"transfer": transfer.duplicate(true)})


func completed_transfer(transfer_id: String) -> Dictionary:
	return _coordinator.get_completed_transfer(transfer_id) if _coordinator != null else {}


func mark_installed(transfer_id: String, token: String) -> Dictionary:
	var checked := check_transfer_phase(transfer_id, "TARGET_INSTALL", token)
	if not bool(checked.get("success", false)):
		return checked
	_installed_epoch = int(checked["details"]["transfer"]["target_epoch"])
	_installed_transfer = transfer_id
	return _success()


func mark_retired(transfer_id: String, token: String) -> Dictionary:
	var checked := check_transfer_phase(transfer_id, "SOURCE_RETIRE", token)
	if not bool(checked.get("success", false)):
		return checked
	_installed_epoch = 0
	return _success()


func get_report() -> Dictionary:
	return {"canonical_state_owned": false, "decision_owner": "EXISTING_SM1_COORDINATOR", "local_authority_id": _local_authority, "logical_player_id": _player, "transport_session_id": _session, "ownership_epoch": _ownership_epoch, "installed_epoch": _installed_epoch, "installed_transfer": _installed_transfer, "locally_ready": is_locally_ready(), "decision": decision_snapshot()}


static func normalize_live_record(record: Dictionary) -> Dictionary:
	# Call only AFTER strict integer/finite/identity validation. JSON transports
	# represent numbers as floats; native canonical counters remain integers.
	var normalized := record.duplicate(true)
	for field in ["ownership_epoch", "last_input_sequence", "state_revision", "joined_tick", "left_tick"]:
		if normalized.has(field):
			normalized[field] = int(normalized[field])
	return normalized


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}


static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "details": {}}
