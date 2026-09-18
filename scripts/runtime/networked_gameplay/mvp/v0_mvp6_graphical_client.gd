extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_graphical_client.gd"

# The client receives only canonical snapshots from the gateway and derives
# presentation/collision locally. It never receives an authority/store object
# and never submits Construction state back; observations are checksum/count
# evidence only.
const RuntimeView6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_derived_construction_runtime_view.gd")
const Guard6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_enet_long_operation_guard.gd")
var _runtime_view6 = null
var _construction6: Dictionary = {}
var _view_result6: Dictionary = {}
var _phase_reports6: Dictionary = {}
var _observed_sent6 := {"BASE": false, "ADDED": false, "REMOVED": false}
var _mvp6_started := false
var _guard6_count := 0
var _guard6_last: Dictionary = {}
var _guard6_restore_count := 0
var _guard6_restore_last: Dictionary = {}
var _guard6_active := false

var _item_requests6: Array = []
var _item_complete_seen6 := false


func build_world() -> bool:
	if not super.build_world():
		return false
	_runtime_view6 = RuntimeView6.new()
	_runtime_view6.name = "MVP6DerivedConstructionRuntimeView"
	add_child(_runtime_view6)
	var configured: Dictionary = _runtime_view6.setup("client/" + actor)
	return bool(configured.get("success", false))


func send_request(kind: String, body: Dictionary = {}) -> void:
	if kind.begins_with("MVP6_ITEM_"):
		_item_requests6.append(kind)
	# Arm the MVP6-only ENet liveness window as soon as this client completes
	# HELLO. It stays armed through inherited MVP3-MVP5 because A can enter the
	# synchronous BASE100 operation before B sends its first MVP6 request. Once
	# MVP6 starts, each request refreshes the window and its reply restores the
	# unchanged ENet defaults before the next request/terminal FINISH.
	if (kind == "HELLO" or kind.begins_with("MVP6_")) and boundary != null:
		var was_active := _guard6_active
		var guarded: Dictionary = Guard6.apply(boundary, peer)
		if not bool(guarded.get("success", false)):
			finish(false, "MVP6_CLIENT_ENET_GUARD_FAILED:" + String(guarded.get("error_code", "")))
			return
		if not was_active:
			_guard6_count += 1
		_guard6_active = true
		_guard6_last = Dictionary(guarded.get("details", {})).duplicate(true)
	super.send_request(kind, body)


func _restore_guard6() -> Dictionary:
	if not _guard6_active:
		return {"success": true, "error_code": "", "details": {"already_restored": true}}
	var restored: Dictionary = Guard6.restore(boundary, peer)
	if not bool(restored.get("success", false)):
		return restored
	_guard6_restore_count += 1
	_guard6_restore_last = Dictionary(restored.get("details", {})).duplicate(true)
	_guard6_active = false
	return restored


func _apply_construction6(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return true
	var checksum := String(snapshot.get("checksum", ""))
	if checksum.is_empty():
		return false
	var applied: Dictionary = _runtime_view6.apply_snapshot(snapshot)
	if not bool(applied.get("success", false)):
		return false
	_construction6 = snapshot.duplicate(true)
	_view_result6 = Dictionary(applied.get("details", {})).duplicate(true)
	var phase := ""
	var count := int(_view_result6.get("part_count", -1))
	if count == 101:
		phase = "ADDED"
	elif count == 100:
		phase = "REMOVED" if _phase_reports6.has("ADDED") else "BASE"
	if not phase.is_empty():
		_phase_reports6[phase] = {
			"construction_checksum": checksum,
			"descriptor_checksum": String(_view_result6.get("descriptor_checksum", "")),
			"part_count": count,
			"collision_part_count": int(_view_result6.get("collision_part_count", -1)),
			"body_kind": String(_view_result6.get("body_kind", "")),
			"direct_authority_references": int(_view_result6.get("direct_authority_references", -1)),
			"canonical_truth_owner": bool(_view_result6.get("canonical_truth_owner", true)),
		}
	return true


func handle_reply(packet: Dictionary) -> void:
	if Protocol.verify(cfg, packet, "gateway", "client/" + actor, key) and int(packet.get("sequence", 0)) == pending_rpc:
		var requested := pending_kind
		var response: Dictionary = packet.get("body", {})
		if bool(response.get("success", false)) and requested.begins_with("MVP6_"):
			var details: Dictionary = response.get("details", {})
			var construction: Dictionary = details.get("construction", {})
			if not construction.is_empty() and not _apply_construction6(construction):
				finish(false, "MVP6_DERIVED_CONSTRUCTION_VIEW_FAILED")
				return
			_mvp6_started = _mvp6_started or not construction.is_empty()
		if requested.begins_with("MVP6_"):
			var restored: Dictionary = _restore_guard6()
			if not bool(restored.get("success", false)):
				finish(false, "MVP6_CLIENT_ENET_GUARD_RESTORE_FAILED:" + String(restored.get("error_code", "")))
				return
	super.handle_reply(packet)


func apply_snapshot(snapshot: Dictionary) -> void:
	super.apply_snapshot(snapshot)
	# Preserve the exact MVP4/MVP5 capture surface until Construction has
	# actually started. Adding an MVP6 status row earlier enlarges the derived
	# UI exclusion mask and can hide real terrain pixels from the unchanged MVP4
	# visible-mutation falsifier even though the UI itself is hidden in capture.
	if hud != null and (_mvp6_started or bool(snapshot.get("mvp6", {}).get("initialized", false))):
		var mvp6: Dictionary = snapshot.get("mvp6", {})
		hud.text += "\nMVP6 Construction: %s parts=%s collision=%s" % [
			String(mvp6.get("phase", "pending")),
			str(_view_result6.get("part_count", 0)),
			str(_view_result6.get("collision_part_count", 0)),
		]


func _send_observed6(phase: String) -> void:
	var report: Dictionary = _runtime_view6.get_report()
	_observed_sent6[phase] = true
	send_request("MVP6_OBSERVED", {
		"phase": phase,
		"checksum": String(_construction6.get("checksum", "")),
		"part_count": int(_view_result6.get("part_count", -1)),
		"collision_part_count": int(_view_result6.get("collision_part_count", -1)),
		"descriptor_checksum": String(_view_result6.get("descriptor_checksum", "")),
		"construct_count": int(report.get("construct_count", -1)),
		"canonical_truth_owner": bool(_view_result6.get("canonical_truth_owner", true)),
		"process_id": OS.get_process_id(),
	})


func _next_construction6(snapshot: Dictionary) -> void:
	var state: Dictionary = snapshot.get("mvp6", {})
	if not bool(state.get("initialized", false)):
		if actor == "a":
			send_request("MVP6_INIT")
		else:
			send_request("MVP6_OBSERVE")
		return
	var phase := String(state.get("phase", ""))
	if phase not in ["BASE", "ADDED", "REMOVED"]:
		finish(false, "MVP6_GRAPHICAL_PHASE_INVALID:" + phase)
		return
	if _construction6.is_empty() or String(_construction6.get("checksum", "")) != String(state.get("checksum", "")):
		send_request("MVP6_OBSERVE")
		return
	if not bool(_observed_sent6[phase]):
		_send_observed6(phase)
		return
	if phase == "BASE":
		if int(state.get("base_observers", 0)) < 2:
			send_request("MVP6_OBSERVE")
		elif actor == "a":
			send_request("MVP6_ADD")
		else:
			send_request("MVP6_OBSERVE")
		return
	if phase == "ADDED":
		if int(state.get("added_observers", 0)) < 2:
			send_request("MVP6_OBSERVE")
		elif not bool(state.get("replay_add", false)):
			if actor == "a": send_request("MVP6_REPLAY_ADD")
			else: send_request("MVP6_OBSERVE")
		elif actor == "a":
			send_request("MVP6_REMOVE")
		else:
			send_request("MVP6_OBSERVE")
		return
	if int(state.get("removed_observers", 0)) < 2:
		send_request("MVP6_OBSERVE")
	elif not bool(state.get("replay_remove", false)):
		if actor == "a": send_request("MVP6_REPLAY_REMOVE")
		else: send_request("MVP6_OBSERVE")
	elif bool(state.get("complete", false)):
		_phase4 = "FINISH"
		send_request("FINISH")
	else:
		send_request("MVP6_OBSERVE")


func _stationary6(row: Dictionary) -> bool:
	var velocity: Dictionary = Dictionary(row.get("velocity", {}))
	return absf(float(velocity.get("x", 1.0))) <= 0.000001 and absf(float(velocity.get("z", 1.0))) <= 0.000001


func _yaw_to6(origin: Dictionary, target: Dictionary) -> float:
	var dx := float(target.get("x", 0.0)) - float(origin.get("x", 0.0))
	var dz := float(target.get("z", 0.0)) - float(origin.get("z", 0.0))
	return atan2(dx, dz)


func _yaw_close6(current: float, target: float) -> bool:
	return absf(wrapf(current - target, -PI, PI)) <= 0.04


func _send_item_motion6(move_z: float, yaw: float) -> void:
	if not pending_kind.is_empty() or finishing:
		return
	input_sequence += 1
	last_sent_axis = move_z
	var operation := "operation/mvp6/item-motion/%s/%d" % [actor, input_sequence]
	var intent := {
		"move_x": 0.0,
		"move_z": clampf(move_z, -1.0, 1.0),
		"look_yaw": yaw,
		"look_pitch": 0.0,
		"jump_pressed": false,
		"sprint": false,
		"delta_seconds": 1.0 / 60.0,
	}
	var wire := InputDTO.create(
		"message/mvp6/item-motion/%s/%d" % [actor, input_sequence],
		operation,
		actor,
		Protocol.session(cfg, actor),
		1,
		1,
		input_sequence,
		"MOVEMENT_INTENT",
		intent
	)
	send_request("MOVE", {"wire": wire})


func _orient_for_target6(snapshot: Dictionary, target: Dictionary) -> bool:
	var row: Dictionary = snapshot.get("players", {}).get(actor, {})
	if row.is_empty() or target.is_empty():
		return false
	var yaw := _yaw_to6(Dictionary(row.get("position", {})), target)
	if not _stationary6(row) or not _yaw_close6(float(row.get("orientation_yaw", 0.0)), yaw):
		_send_item_motion6(0.0, yaw)
		return false
	return true


func _next_item6(snapshot: Dictionary) -> void:
	var state: Dictionary = snapshot.get("mvp6", {}).get("item", {})
	var phase := String(state.get("phase", ""))
	var players: Dictionary = snapshot.get("players", {})
	var own: Dictionary = players.get(actor, {})
	if own.is_empty():
		finish(false, "MVP6_LIVE_ITEM_PLAYER_SNAPSHOT_REQUIRED")
		return
	if bool(state.get("complete", false)):
		_item_complete_seen6 = true
		_next_construction6(snapshot)
		return
	match phase:
		"APPROACH":
			if actor == "a":
				var x := float(own.get("position", {}).get("x", -99.0))
				if x < -1.4:
					_send_item_motion6(1.0, PI / 2.0)
				elif not _stationary6(own) or not _yaw_close6(float(own.get("orientation_yaw", 0.0)), PI / 2.0):
					_send_item_motion6(0.0, PI / 2.0)
				elif not bool(state.get("ready", {}).get("a", false)):
					send_request("MVP6_ITEM_READY")
				else:
					send_request("MVP6_OBSERVE")
			else:
				if not _stationary6(own) or not _yaw_close6(float(own.get("orientation_yaw", 0.0)), -PI / 2.0):
					_send_item_motion6(0.0, -PI / 2.0)
				elif not bool(state.get("ready", {}).get("b", false)):
					send_request("MVP6_ITEM_READY")
				else:
					send_request("MVP6_OBSERVE")
		"DROP_READY":
			if actor == "a": send_request("MVP6_ITEM_DROP")
			else: send_request("MVP6_OBSERVE")
		"DROPPED":
			if actor == "b":
				if _orient_for_target6(snapshot, Dictionary(state.get("target_position", {}))):
					send_request("MVP6_ITEM_PICKUP")
			else:
				send_request("MVP6_OBSERVE")
		"PICKED":
			if actor == "b": send_request("MVP6_ITEM_PICKUP_REPLAY")
			else: send_request("MVP6_OBSERVE")
		"PICKUP_REPLAYED":
			if actor == "a": send_request("MVP6_ITEM_PICKUP_LOSER")
			else: send_request("MVP6_OBSERVE")
		"CONTENDED":
			if actor == "a":
				if _orient_for_target6(snapshot, Dictionary(state.get("container_position", {}))):
					send_request("MVP6_ITEM_OPEN")
			else:
				send_request("MVP6_OBSERVE")
		"A_OPEN":
			if actor == "b":
				if _orient_for_target6(snapshot, Dictionary(state.get("container_position", {}))):
					send_request("MVP6_ITEM_OPEN")
			else:
				send_request("MVP6_OBSERVE")
		"BOTH_OPEN":
			if actor == "b": send_request("MVP6_ITEM_DEPOSIT")
			else: send_request("MVP6_OBSERVE")
		"DEPOSITED":
			if actor == "a": send_request("MVP6_ITEM_WITHDRAW")
			else: send_request("MVP6_OBSERVE")
		"WITHDRAWN":
			if actor == "a":
				var x := float(own.get("position", {}).get("x", -99.0))
				if x < 0.05:
					_send_item_motion6(1.0, PI / 2.0)
				elif not _stationary6(own):
					_send_item_motion6(0.0, PI / 2.0)
				else:
					send_request("MVP6_ITEM_CARRY_OUT")
			else:
				send_request("MVP6_OBSERVE")
		"CARRY_OUT_PENDING":
			if actor == "a": _send_item_motion6(1.0, PI / 2.0)
			else: send_request("MVP6_OBSERVE")
		"CARRIED_OUT":
			if actor == "a":
				var x := float(own.get("position", {}).get("x", 99.0))
				if x > -0.05:
					_send_item_motion6(1.0, -PI / 2.0)
				elif not _stationary6(own):
					_send_item_motion6(0.0, -PI / 2.0)
				else:
					send_request("MVP6_ITEM_CARRY_BACK")
			else:
				send_request("MVP6_OBSERVE")
		"CARRY_BACK_PENDING":
			if actor == "a": _send_item_motion6(1.0, -PI / 2.0)
			else: send_request("MVP6_OBSERVE")
		"COMPLETE":
			_item_complete_seen6 = true
			_next_construction6(snapshot)
		_:
			finish(false, "MVP6_LIVE_ITEM_PHASE_INVALID:" + phase)


func _next_mvp6(snapshot: Dictionary) -> void:
	var item: Dictionary = snapshot.get("mvp6", {}).get("item", {})
	if not bool(item.get("complete", false)):
		_next_item6(snapshot)
		return
	_item_complete_seen6 = true
	_next_construction6(snapshot)


func next_automated(snapshot: Dictionary) -> void:
	# MVP5 can consume MVP5_AFTER and immediately fall through to its terminal
	# MVP5_WAIT_OBSERVERS -> FINISH branch in the same call. Intercept BOTH sides
	# of that transition here so the second material observer cannot disconnect
	# before entering MVP6. Preserve the exact inherited MVP5_AFTER assignment;
	# only replace its terminal FINISH with the live Construction continuation.
	if _phase4 == "MVP5_AFTER":
		_after5 = _material5.duplicate(true)
		_phase4 = "MVP5_WAIT_OBSERVERS"
		if not bool(snapshot.get("mvp5", {}).get("both_material_observed", false)):
			send_request("OBSERVE")
			return
		_next_mvp6(snapshot)
		return
	if _phase4 == "MVP5_WAIT_OBSERVERS":
		if not bool(snapshot.get("mvp5", {}).get("both_material_observed", false)):
			send_request("OBSERVE")
			return
		_next_mvp6(snapshot)
		return
	super.next_automated(snapshot)


func finish(passed: bool, error_code: String) -> void:
	if _guard6_active:
		var restored: Dictionary = _restore_guard6()
		if not bool(restored.get("success", false)):
			passed = false
			if error_code.is_empty():
				error_code = "MVP6_CLIENT_ENET_GUARD_RESTORE_FAILED:" + String(restored.get("error_code", ""))
	var report: Dictionary = _runtime_view6.get_report() if _runtime_view6 != null else {}
	var valid := passed and _phase_reports6.has("BASE") and _phase_reports6.has("ADDED") and _phase_reports6.has("REMOVED")
	valid = valid and int(_phase_reports6.get("BASE", {}).get("part_count", 0)) == 100
	valid = valid and int(_phase_reports6.get("ADDED", {}).get("part_count", 0)) == 101
	valid = valid and int(_phase_reports6.get("REMOVED", {}).get("part_count", 0)) == 100
	valid = valid and int(report.get("construct_count", 0)) == 1 and bool(report.get("canonical_truth_owner", true)) == false and int(report.get("direct_authority_references", -1)) == 0
	valid = valid and _guard6_count > 0 and _guard6_restore_count == _guard6_count and not _guard6_active
	var required_item_requests: Array = (
		["MVP6_ITEM_READY", "MVP6_ITEM_DROP", "MVP6_ITEM_PICKUP_LOSER", "MVP6_ITEM_OPEN", "MVP6_ITEM_WITHDRAW", "MVP6_ITEM_CARRY_OUT", "MVP6_ITEM_CARRY_BACK"]
		if actor == "a"
		else ["MVP6_ITEM_READY", "MVP6_ITEM_PICKUP", "MVP6_ITEM_PICKUP_REPLAY", "MVP6_ITEM_OPEN", "MVP6_ITEM_DEPOSIT"]
	)
	valid = valid and _item_complete_seen6 and required_item_requests.all(func(kind): return kind in _item_requests6)
	var evidence := {
		"schema": "distributed_world_simulator.mvp6_graphical_construction_client.v1",
		"subject_head": cfg.get("subject_head", ""),
		"run_id": cfg.get("run_id", ""),
		"actor": actor,
		"process_id": OS.get_process_id(),
		"phases": _phase_reports6.duplicate(true),
		"live_item": {
			"complete_seen": _item_complete_seen6,
			"requests": _item_requests6.duplicate(),
		},
		"runtime_view": report,
		"passed": valid and error_code.is_empty(),
		"canonical_state_owned": false,
		"direct_authority_references": 0,
		"manual_input_executed": false,
		"mvp6_transport_guard": {
			"activation_count": _guard6_count,
			"last": _guard6_last.duplicate(true),
			"restore_count": _guard6_restore_count,
			"restore_last": _guard6_restore_last.duplicate(true),
			"active": _guard6_active,
			"restored_before_finish": _guard6_count > 0 and _guard6_restore_count == _guard6_count and not _guard6_active,
			"shared_transport_changed": false,
			"payload_limit_changed": false,
			"reconnect_policy_changed": false,
		},
		"mvp6_predicate_verified": false,
	}
	var path := String(cfg.get("mvp6_evidence_file", ""))
	if path.is_empty() or not Support.write_json(path, evidence):
		valid = false
		if error_code.is_empty(): error_code = "MVP6_GRAPHICAL_EVIDENCE_WRITE_FAILED"
	super.finish(valid, error_code)
