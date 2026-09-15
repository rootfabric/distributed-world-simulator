extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_graphical_client.gd"

# Same real client, input, replica and terrain-only capture path as MVP4.
# Material fields are read-only observations, never optimistic local balances.
var _material5: Dictionary = {}
var _before5: Dictionary = {}
var _after5: Dictionary = {}
var _receipts5: Array = []

func _players_stationary5(snapshot: Dictionary) -> bool:
	var players: Dictionary = snapshot.get("players", {})
	for player_id in ["a", "b"]:
		var player: Dictionary = players.get(player_id, {})
		if player.is_empty() or not bool(player.get("connected", false)):
			return false
		if int(player.get("last_input_sequence", 0)) < 2:
			return false
		var velocity: Dictionary = player.get("velocity", {})
		for axis in ["x", "y", "z"]:
			if absf(float(velocity.get(axis, 1.0))) > 0.000001:
				return false
	return true

func handle_reply(packet: Dictionary) -> void:
	if Protocol.verify(cfg, packet, "gateway", "client/" + actor, key) and int(packet.get("sequence", 0)) == pending_rpc:
		var response: Dictionary = packet.get("body", {})
		if response.get("success") == true and pending_kind in ["MVP5_BASELINE", "MVP5_MATERIAL"]:
			_material5 = Dictionary(response.get("details", {}).get("matter", {})).duplicate(true)
	super.handle_reply(packet)

func apply_snapshot(snapshot: Dictionary) -> void:
	super.apply_snapshot(snapshot)
	if hud != null:
		# Reuse the existing last status row, rather than extending the HUD down
		# over the excavated surface. The actual UI rect is still fully excluded
		# by the unchanged terrain-pixel validator; its threshold stays 32.
		var totals: Dictionary = _material5.get("totals", {})
		var status := "MVP5 ore (server): A=%s B=%s" % [str(totals.get("a", "pending")), str(totals.get("b", "pending"))]
		var separator := hud.text.rfind("\n")
		hud.text = hud.text.substr(0, separator + 1) + status

func _receipt5() -> bool:
	var receipt: Dictionary = _matter4.get("material_output", {})
	if receipt.is_empty() or receipt.get("logical_player_id") != actor or int(receipt.get("output_quantity", 0)) <= 0 or String(receipt.get("output_item_id", "")).is_empty():
		finish(false, "MVP5_NATIVE_MATERIAL_RECEIPT_REQUIRED")
		return false
	_receipts5.append(receipt.duplicate(true))
	return true

func next_automated(snapshot: Dictionary) -> void:
	if _capture_busy4 or finishing: return
	if not bool(cfg.get("automated", false)):
		super.next_automated(snapshot)
		return
	# The two clients execute their startup movement concurrently. Do not let
	# either client capture the terrain baseline until BOTH authoritative player
	# states have consumed the stop input and report zero velocity. This keeps
	# the existing static-player pixel falsifier strict instead of weakening it
	# to tolerate startup scheduling races.
	if _phase4 == "POLL_BASELINE" and not _players_stationary5(snapshot):
		send_request("OBSERVE")
		return
	match _phase4:
		"EQUIP":
			_phase4 = "MVP5_BEFORE"
			send_request("MVP5_BASELINE")
			return
		"MVP5_BEFORE":
			_before5 = _material5.duplicate(true)
			_phase4 = "MVP5_WAIT_BASELINES"
		"EXECUTE":
			if not _receipt5(): return
			_phase4 = "MVP5_REPLAY_1"
			send_request("MVP4_EXECUTE", {"plan": _prepared4})
			return
		"MVP5_REPLAY_1":
			if not _receipt5(): return
			_phase4 = "MVP5_REPLAY_2"
			send_request("MVP4_EXECUTE", {"plan": _prepared4})
			return
		"MVP5_REPLAY_2":
			if not _receipt5(): return
			_phase4 = "EXECUTE"
			super.next_automated(snapshot)
			return
		"WAIT_OBSERVERS":
			if not bool(snapshot.get("mvp4", {}).get("both_observed", false)):
				send_request("OBSERVE")
				return
			_phase4 = "MVP5_AFTER"
			send_request("MVP5_MATERIAL")
			return
		"MVP5_AFTER":
			_after5 = _material5.duplicate(true)
			_phase4 = "MVP5_WAIT_OBSERVERS"
	if _phase4 == "MVP5_WAIT_BASELINES":
		if not bool(snapshot.get("mvp5", {}).get("both_material_baselines_ready", false)):
			send_request("OBSERVE")
			return
		_phase4 = "EQUIP"
		super.next_automated(snapshot)
		return
	if _phase4 == "MVP5_WAIT_OBSERVERS":
		if not bool(snapshot.get("mvp5", {}).get("both_material_observed", false)):
			send_request("OBSERVE")
			return
		_phase4 = "FINISH"
		send_request("FINISH")
		return
	super.next_automated(snapshot)

func finish(passed: bool, error_code: String) -> void:
	var valid := passed and not _before5.is_empty() and not _after5.is_empty() and _receipts5.size() == (3 if actor == "a" else 0)
	var value := {"schema": "distributed_world_simulator.mvp5_material_client.v1", "subject_head": cfg.get("subject_head", ""), "run_id": cfg.get("run_id", ""), "actor": actor, "process_id": OS.get_process_id(), "before": _before5, "after": _after5, "receipts": _receipts5, "passed": valid and error_code.is_empty(), "canonical_state_owned": false, "manual_input_executed": false, "mvp5_predicate_verified": false}
	var path := String(cfg.get("mvp5_evidence_file", ""))
	if path.is_empty() or not Support.write_json(path, value):
		valid = false
		if error_code.is_empty(): error_code = "MVP5_MATERIAL_EVIDENCE_WRITE_FAILED"
	super.finish(valid, error_code)
