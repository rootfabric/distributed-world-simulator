extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_graphical_client.gd"

const Protocol8 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Support8 = preload("res://scripts/runtime/networked_gameplay/sm1/sm1_6_process_support.gd")

var _mvp8_active := false
var _mvp8_move_round := -1
var _mvp8_neutral_round := -1
var _mvp8_rounds_seen: Array[int] = []
var _mvp8_exit_after_reply := false
var _mvp8_reconnect_prepared := false
var _mvp8_checkpoint_observed := false


func _next_mvp6(snapshot: Dictionary) -> void:
	if bool(snapshot.get("mvp6", {}).get("complete", false)):
		_mvp8_active = true
		_next_mvp8(snapshot)
		return
	super._next_mvp6(snapshot)


func _publish_progress8(snapshot: Dictionary) -> void:
	var path := String(cfg.get("mvp8_progress_file", ""))
	if path.is_empty():
		return
	Support8.write_json(path, {
		"schema": "distributed_world_simulator.mvp8_client_progress.v1",
		"actor": actor,
		"process_id": OS.get_process_id(),
		"phase4": _phase4,
		"mvp8_active": _mvp8_active,
		"mvp8_move_round": _mvp8_move_round,
		"mvp8_neutral_round": _mvp8_neutral_round,
		"pending_kind": pending_kind,
		"pending_rpc": pending_rpc,
		"input_sequence": input_sequence,
		"finishing": finishing,
		"failure_count": failures.size(),
		"last_sent_axis": last_sent_axis,
		"mvp6": Dictionary(snapshot.get("mvp6", {})).duplicate(true),
		"mvp8": Dictionary(snapshot.get("mvp8", {})).duplicate(true),
	})


func _next_mvp8(snapshot: Dictionary) -> void:
	_publish_progress8(snapshot)
	if _mvp8_exit_after_reply:
		finish(true, "")
		return
	var state: Dictionary = snapshot.get("mvp8", {})
	if state.is_empty() or not bool(state.get("active", false)):
		# The first inherited MVP6-complete snapshot is produced before the
		# gateway has seen any MVP8 command. Activate the workload explicitly
		# before sending the first round MOVE; otherwise that MOVE is valid
		# gameplay but intentionally not counted by the bounded workload gate.
		send_request("MVP8_STATUS")
		return
	var round_index := int(state.get("round", -1))
	if round_index >= 0 and round_index not in _mvp8_rounds_seen:
		_mvp8_rounds_seen.append(round_index)
	if bool(state.get("checkpointed", false)) or bool(state.get("complete", false)):
		_mvp8_checkpoint_observed = _mvp8_checkpoint_observed or bool(state.get("checkpointed", false))
		send_request("MVP8_PHASE_FINISH")
		return
	if bool(state.get("reconnect_due", false)):
		if actor == "a":
			send_request("MVP8_RECONNECT_PREPARE")
		else:
			send_request("MVP8_STATUS")
		return
	if bool(state.get("checkpoint_due", false)):
		# Original A has already been replaced. B remains connected and waits for
		# the replacement A to publish the quiescent checkpoint.
		send_request("MVP8_STATUS")
		return
	if _mvp8_move_round != round_index:
		_mvp8_move_round = round_index
		var decision: Dictionary = snapshot.get("decisions", {}).get("a", {})
		var axis := 1.0
		if actor == "a":
			axis = -1.0 if String(decision.get("active_authority_id", "authority/a")) == "authority/b" else 1.0
		else:
			var player: Dictionary = snapshot.get("players", {}).get(actor, {})
			var x := float(player.get("position", {}).get("x", 0.0))
			# B is the stable Matter observer. Keep its non-zero responsiveness
			# bounded around the Matter bubble instead of accumulating timing-
			# dependent drift while long canonical RPCs are in flight.
			axis = -1.0 if x > 0.0 else 1.0
		send_move(axis)
		return
	if _mvp8_neutral_round != round_index:
		# A fixed-tick intent is held by the native owner between packets. Stop it
		# explicitly before running the potentially long canonical round action so
		# CI/runtime speed cannot move the player outside the bounded terrain area.
		_mvp8_neutral_round = round_index
		send_move(0.0)
		return
	var moves: Dictionary = state.get("round_moves", {})
	if actor == "a" and bool(moves.get("a", false)) and bool(moves.get("b", false)):
		send_request("MVP8_ROUND", {"round": round_index})
	else:
		send_request("MVP8_STATUS")


func next_automated(snapshot: Dictionary) -> void:
	_publish_progress8(snapshot)
	if _mvp8_exit_after_reply:
		finish(true, "")
		return
	if _mvp8_active:
		_next_mvp8(snapshot)
		return
	super.next_automated(snapshot)


func handle_reply(packet: Dictionary) -> void:
	var requested := pending_kind
	if Protocol8.verify(cfg, packet, "gateway", "client/" + actor, key) and int(packet.get("sequence", 0)) == pending_rpc:
		var response: Dictionary = packet.get("body", {})
		if bool(response.get("success", false)):
			if requested == "MVP8_RECONNECT_PREPARE":
				_mvp8_reconnect_prepared = true
				_mvp8_exit_after_reply = true
			elif requested == "MVP8_PHASE_FINISH":
				_mvp8_exit_after_reply = true
	super.handle_reply(packet)


func finish(passed: bool, error_code: String) -> void:
	var path := String(cfg.get("mvp8_evidence_file", ""))
	var evidence := {
		"schema": "distributed_world_simulator.mvp8_initial_graphical_client.v1",
		"subject_head": cfg.get("subject_head", ""),
		"run_id": cfg.get("run_id", ""),
		"actor": actor,
		"process_id": OS.get_process_id(),
		"passed": passed and error_code.is_empty() and _mvp8_active,
		"rounds_seen": _mvp8_rounds_seen.duplicate(),
		"reconnect_prepared": _mvp8_reconnect_prepared,
		"checkpoint_observed": _mvp8_checkpoint_observed,
		"fixed_input_receipts": fixed_input_receipts,
		"canonical_state_owned": false,
		"mvp8_predicate_verified": false,
	}
	if not path.is_empty() and not Support8.write_json(path, evidence):
		passed = false
		if error_code.is_empty():
			error_code = "MVP8_INITIAL_CLIENT_EVIDENCE_WRITE_FAILED"
	super.finish(passed, error_code)
