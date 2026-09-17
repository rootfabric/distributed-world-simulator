extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_graphical_client.gd"

# The client receives only canonical snapshots from the gateway and derives
# presentation/collision locally. It never receives an authority/store object
# and never submits Construction state back; observations are checksum/count
# evidence only.
const RuntimeView6 = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_derived_construction_runtime_view.gd")
var _runtime_view6 = null
var _construction6: Dictionary = {}
var _view_result6: Dictionary = {}
var _phase_reports6: Dictionary = {}
var _observed_sent6 := {"BASE": false, "ADDED": false, "REMOVED": false}
var _mvp6_started := false


func build_world() -> bool:
	if not super.build_world():
		return false
	_runtime_view6 = RuntimeView6.new()
	_runtime_view6.name = "MVP6DerivedConstructionRuntimeView"
	add_child(_runtime_view6)
	var configured: Dictionary = _runtime_view6.setup("client/" + actor)
	return bool(configured.get("success", false))


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
	super.handle_reply(packet)


func apply_snapshot(snapshot: Dictionary) -> void:
	super.apply_snapshot(snapshot)
	if hud != null:
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


func _next_mvp6(snapshot: Dictionary) -> void:
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


func next_automated(snapshot: Dictionary) -> void:
	# Intercept the exact point where MVP5 would otherwise finish. All inherited
	# M3 movement/seam, MVP4 visible dig and MVP5 exactly-once material work has
	# completed before this live Construction phase begins.
	if _phase4 == "MVP5_WAIT_OBSERVERS" and bool(snapshot.get("mvp5", {}).get("both_material_observed", false)):
		_next_mvp6(snapshot)
		return
	super.next_automated(snapshot)


func finish(passed: bool, error_code: String) -> void:
	var report: Dictionary = _runtime_view6.get_report() if _runtime_view6 != null else {}
	var valid := passed and _phase_reports6.has("BASE") and _phase_reports6.has("ADDED") and _phase_reports6.has("REMOVED")
	valid = valid and int(_phase_reports6.get("BASE", {}).get("part_count", 0)) == 100
	valid = valid and int(_phase_reports6.get("ADDED", {}).get("part_count", 0)) == 101
	valid = valid and int(_phase_reports6.get("REMOVED", {}).get("part_count", 0)) == 100
	valid = valid and int(report.get("construct_count", 0)) == 1 and bool(report.get("canonical_truth_owner", true)) == false and int(report.get("direct_authority_references", -1)) == 0
	var evidence := {
		"schema": "distributed_world_simulator.mvp6_graphical_construction_client.v1",
		"subject_head": cfg.get("subject_head", ""),
		"run_id": cfg.get("run_id", ""),
		"actor": actor,
		"process_id": OS.get_process_id(),
		"phases": _phase_reports6.duplicate(true),
		"runtime_view": report,
		"passed": valid and error_code.is_empty(),
		"canonical_state_owned": false,
		"direct_authority_references": 0,
		"manual_input_executed": false,
		"mvp6_predicate_verified": false,
	}
	var path := String(cfg.get("mvp6_evidence_file", ""))
	if path.is_empty() or not Support.write_json(path, evidence):
		valid = false
		if error_code.is_empty(): error_code = "MVP6_GRAPHICAL_EVIDENCE_WRITE_FAILED"
	super.finish(valid, error_code)
