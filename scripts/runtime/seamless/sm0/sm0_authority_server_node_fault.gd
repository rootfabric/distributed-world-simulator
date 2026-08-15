extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_v2.gd"

# Deterministic transport-fault layer for SM0-H1.
# It is activated only by an explicit fault_profile and leaves the healthy V2
# path unchanged when the normal server process is launched without a profile.
#
# transport-chaos-v1 applies exactly once per transfer/message pair:
# - drop the first PREPARE, forcing source retry;
# - duplicate the first PREPARED, exercising source idempotence;
# - delay the first COMMIT by 350 ms so the 200 ms retry overtakes it;
# - drop the first successful COMMITTED, forcing target replay/ack recovery.

const FAULT_PROFILE_TRANSPORT_CHAOS_V1 := "transport-chaos-v1"
const COMMIT_DELAY_MS := 350

var _fault_profile := ""
var _fault_applied: Dictionary = {}
var _fault_delayed_control: Array = []
var _fault_pending_shutdown: Dictionary = {}


func setup(config: Dictionary) -> Dictionary:
	_fault_profile = String(config.get("fault_profile", "")).strip_edges()
	if not _fault_profile.is_empty() and _fault_profile != FAULT_PROFILE_TRANSPORT_CHAOS_V1:
		return _failure("SM0_UNKNOWN_FAULT_PROFILE", {"fault_profile": _fault_profile})
	var result: Dictionary = super.setup(config)
	if bool(result.get("success", false)) and not _fault_profile.is_empty():
		_event("SM0_FAULT_PROFILE_ENABLED", {"fault_profile": _fault_profile})
	return result


func _process(delta: float) -> void:
	_flush_delayed_control()
	if not _fault_pending_shutdown.is_empty() and _fault_delayed_control.is_empty():
		var pending: Dictionary = _fault_pending_shutdown.duplicate(true)
		_fault_pending_shutdown.clear()
		super._shutdown(int(pending.get("exit_code", 0)), String(pending.get("reason", "fault-drain")))
		return
	super._process(delta)


func _shutdown(exit_code: int, reason: String) -> void:
	if _fault_profile == FAULT_PROFILE_TRANSPORT_CHAOS_V1 and not _fault_delayed_control.is_empty():
		if _fault_pending_shutdown.is_empty():
			_fault_pending_shutdown = {"exit_code": exit_code, "reason": reason}
			_event("SM0_FAULT_SHUTDOWN_DEFERRED", {
				"fault_profile": _fault_profile,
				"pending_delayed_control": _fault_delayed_control.size(),
				"reason": reason,
			})
		return
	super._shutdown(exit_code, reason)


func _send_control(message_type: String, payload: Dictionary, request_id: String = "") -> void:
	if _fault_profile != FAULT_PROFILE_TRANSPORT_CHAOS_V1:
		super._send_control(message_type, payload, request_id)
		return

	var transfer_id := _fault_transfer_id(message_type, payload)
	if transfer_id.is_empty():
		super._send_control(message_type, payload, request_id)
		return

	# Never hide a protocol rejection. The COMMITTED drop is applied only to the
	# first successful acknowledgement so faults do not turn a real error into a timeout.
	if message_type == "PLAYER_HANDOFF_COMMITTED" and not bool(payload.get("success", false)):
		super._send_control(message_type, payload, request_id)
		return

	var fault_key := "%s|%s" % [message_type, transfer_id]
	if _fault_applied.has(fault_key):
		super._send_control(message_type, payload, request_id)
		return
	_fault_applied[fault_key] = true

	match message_type:
		"PLAYER_HANDOFF_PREPARE":
			_fault_event("drop", message_type, transfer_id, request_id)
			return
		"PLAYER_HANDOFF_PREPARED":
			_fault_event("duplicate", message_type, transfer_id, request_id)
			super._send_control(message_type, payload, request_id)
			super._send_control(message_type, payload, request_id)
			return
		"PLAYER_HANDOFF_COMMIT":
			var due_ms := Time.get_ticks_msec() + COMMIT_DELAY_MS
			_fault_delayed_control.append({
				"due_ms": due_ms,
				"message_type": message_type,
				"payload": payload.duplicate(true),
				"request_id": request_id,
				"transfer_id": transfer_id,
			})
			_fault_event("delay_reorder", message_type, transfer_id, request_id, {"delay_ms": COMMIT_DELAY_MS})
			return
		"PLAYER_HANDOFF_COMMITTED":
			_fault_event("drop", message_type, transfer_id, request_id)
			return
		_:
			_fault_applied.erase(fault_key)
			super._send_control(message_type, payload, request_id)


func _flush_delayed_control() -> void:
	if _fault_delayed_control.is_empty():
		return
	var now := Time.get_ticks_msec()
	var pending: Array = []
	for item_value in _fault_delayed_control:
		var item: Dictionary = Dictionary(item_value)
		if int(item.get("due_ms", 0)) > now:
			pending.append(item)
			continue
		var message_type := String(item.get("message_type", ""))
		var transfer_id := String(item.get("transfer_id", ""))
		var request_id := String(item.get("request_id", ""))
		_event("SM0_FAULT_RELEASED", {
			"fault_profile": _fault_profile,
			"fault_action": "delay_reorder",
			"message_type": message_type,
			"transfer_id": transfer_id,
			"request_id": request_id,
			"delay_ms": COMMIT_DELAY_MS,
		})
		super._send_control(message_type, Dictionary(item.get("payload", {})), request_id)
	_fault_delayed_control = pending


func _fault_transfer_id(message_type: String, payload: Dictionary) -> String:
	if message_type == "PLAYER_HANDOFF_PREPARE":
		return String(Dictionary(payload.get("package", {})).get("transfer_id", "")).strip_edges()
	if message_type in ["PLAYER_HANDOFF_PREPARED", "PLAYER_HANDOFF_COMMIT", "PLAYER_HANDOFF_COMMITTED"]:
		return String(payload.get("transfer_id", "")).strip_edges()
	return ""


func _fault_event(action: String, message_type: String, transfer_id: String, request_id: String, extra: Dictionary = {}) -> void:
	var details := {
		"fault_profile": _fault_profile,
		"fault_action": action,
		"message_type": message_type,
		"transfer_id": transfer_id,
		"request_id": request_id,
	}
	for key in extra.keys():
		details[key] = extra[key]
	_event("SM0_FAULT_INJECTED", details)
