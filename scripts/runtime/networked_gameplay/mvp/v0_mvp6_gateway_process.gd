extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_gateway_process.gd"

# Transport/orchestration only. The gateway owns neither Construction nor an
# Item Graph. Mutations enter the real authority/b process first, are attested,
# then commit on the single canonical writer authority/a. The A-signed result
# is immediately installed as a read-only B replica before clients may observe.
var _construction6: Dictionary = {}
var _replica6: Dictionary = {}
var _phase6 := "EMPTY"
var _observed6 := {"BASE": {}, "ADDED": {}, "REMOVED": {}}
var _replays6 := {"ADD": false, "REMOVE": false}
var _route_processes6: Array = []
var _mutation_count6 := 0


func _authority6(authority_id: String, actor: String, request: Dictionary) -> Dictionary:
	var body := request.duplicate(true)
	body["actor"] = actor
	body["session"] = Protocol.session(cfg, actor)
	return call_authority(authority_id, body)


func _native6(rpc: Dictionary) -> Dictionary:
	return native_result(rpc)


func _sync_b6(actor: String, owner_rpc: Dictionary) -> Dictionary:
	var owner_result := _native6(owner_rpc)
	if not bool(owner_result.get("success", false)):
		return owner_result
	var snapshot: Dictionary = owner_result.get("details", {}).get("construction", {})
	if snapshot.is_empty():
		return Protocol.failure("MVP6_CANONICAL_CONSTRUCTION_SNAPSHOT_REQUIRED")
	var owner_attestation: Dictionary = links["authority/a"].last_signed_reply.duplicate(true)
	var replica_rpc := _authority6("authority/b", actor, {
		"kind": "MVP6_REPLICA_SYNC",
		"checksum": String(snapshot.get("checksum", "")),
		"source_attestation": owner_attestation,
	})
	var replica := _native6(replica_rpc)
	if not bool(replica.get("success", false)):
		return replica
	var replica_details: Dictionary = replica.get("details", {})
	if String(replica_details.get("checksum", "")) != String(snapshot.get("checksum", "")) or replica_details.get("canonical_construction_owned") != false or replica_details.get("replica_read_only") != true:
		return Protocol.failure("MVP6_AUTHORITY_B_REPLICA_DIVERGED")
	_construction6 = snapshot.duplicate(true)
	_replica6 = Dictionary(replica_details.get("construction", {})).duplicate(true)
	return Protocol.success({
		"construction": _construction6.duplicate(true),
		"replica": _replica6.duplicate(true),
		"owner_process_id": owner_result.get("details", {}).get("authority_process_id", 0),
		"replica_process_id": replica_details.get("authority_process_id", 0),
	})


func _initialize6(actor: String) -> Dictionary:
	if not _construction6.is_empty():
		return Protocol.success({"construction":_construction6.duplicate(true), "replica":_replica6.duplicate(true), "replay":true})
	if actor != "a" or not _complete5():
		return Protocol.failure("MVP6_LIVE_MVP5_PREREQUISITE_REQUIRED")
	var rpc := _authority6("authority/a", actor, {"kind":"MVP6_CONSTRUCTION_INIT"})
	var synced := _sync_b6(actor, rpc)
	if not bool(synced.get("success", false)):
		return synced
	if Array(_construction6.get("parts", [])).size() != 100:
		return Protocol.failure("MVP6_LIVE_BASE100_REQUIRED")
	_phase6 = "BASE"
	return Protocol.success(synced.get("details", {}))


func _route6(actor: String, intent: String) -> Dictionary:
	if actor != "a" or intent not in ["ADD", "REMOVE", "REPLAY_ADD", "REPLAY_REMOVE"]:
		return Protocol.failure("MVP6_LIVE_MUTATION_ACTOR_OR_INTENT_INVALID")
	var route_rpc := _authority6("authority/b", actor, {"kind":"MVP6_CONSTRUCTION_ROUTE", "intent":intent})
	var routed := _native6(route_rpc)
	if not bool(routed.get("success", false)):
		return routed
	var route_details: Dictionary = routed.get("details", {})
	if route_details.get("route_validated") != true or route_details.get("canonical_construction_owned") != false:
		return Protocol.failure("MVP6_LIVE_NONOWNER_ROUTE_INVALID")
	var route_attestation: Dictionary = links["authority/b"].last_signed_reply.duplicate(true)
	var owner_rpc := _authority6("authority/a", actor, {
		"kind":"MVP6_CONSTRUCTION_APPLY",
		"intent":intent,
		"route_attestation":route_attestation,
	})
	var owner := _native6(owner_rpc)
	if not bool(owner.get("success", false)):
		return owner
	var synced := _sync_b6(actor, owner_rpc)
	if not bool(synced.get("success", false)):
		return synced
	var details: Dictionary = owner.get("details", {})
	var owner_pid := int(details.get("authority_process_id", 0))
	var b_pid := int(details.get("authority_b_process_id", 0))
	if owner_pid <= 0 or b_pid <= 0 or owner_pid == b_pid:
		return Protocol.failure("MVP6_LIVE_DISTINCT_AUTHORITY_PROCESSES_REQUIRED")
	_route_processes6.append({"intent":intent, "authority_b_process_id":b_pid, "authority_a_process_id":owner_pid})
	if intent == "ADD":
		_phase6 = "ADDED"
		_mutation_count6 += 1
	elif intent == "REMOVE":
		_phase6 = "REMOVED"
		_mutation_count6 += 1
	elif intent == "REPLAY_ADD":
		_replays6["ADD"] = bool(details.get("replay", false)) or bool(details.get("gateway_result", {}).get("replay", false))
	elif intent == "REPLAY_REMOVE":
		_replays6["REMOVE"] = bool(details.get("replay", false)) or bool(details.get("gateway_result", {}).get("replay", false))
	return Protocol.success({
		"construction": _construction6.duplicate(true),
		"replica": _replica6.duplicate(true),
		"intent": intent,
		"owner_result": details.duplicate(true),
	})


func _phase_count6(phase: String) -> int:
	return Dictionary(_observed6.get(phase, {})).size()


func _expected_parts6(phase: String) -> int:
	if phase == "ADDED": return 101
	if phase in ["BASE", "REMOVED"]: return 100
	return -1


func _observe6(actor: String, body: Dictionary) -> Dictionary:
	var phase := String(body.get("phase", ""))
	if phase not in _observed6 or phase != _phase6:
		return Protocol.failure("MVP6_CLIENT_OBSERVATION_PHASE_INVALID")
	var expected := _expected_parts6(phase)
	var checksum := String(_construction6.get("checksum", ""))
	if String(body.get("checksum", "")) != checksum or int(body.get("part_count", -1)) != expected:
		return Protocol.failure("MVP6_CLIENT_OBSERVATION_DIVERGED")
	if int(body.get("collision_part_count", -1)) != expected or body.get("canonical_truth_owner") != false or int(body.get("construct_count", -1)) != 1:
		return Protocol.failure("MVP6_CLIENT_DERIVED_RUNTIME_VIEW_INVALID")
	_observed6[phase][actor] = {
		"checksum": checksum,
		"part_count": expected,
		"collision_part_count": int(body.get("collision_part_count", -1)),
		"descriptor_checksum": String(body.get("descriptor_checksum", "")),
		"process_id": int(body.get("process_id", 0)),
	}
	return Protocol.success({"accepted":true, "phase":phase, "actor":actor})


func _complete6() -> bool:
	if _mutation_count6 != 2 or not bool(_replays6["ADD"]) or not bool(_replays6["REMOVE"]):
		return false
	if _phase6 != "REMOVED" or Array(_construction6.get("parts", [])).size() != 100:
		return false
	for phase in ["BASE", "ADDED", "REMOVED"]:
		if _phase_count6(phase) != 2:
			return false
		var rows: Dictionary = _observed6[phase]
		if int(rows["a"].get("process_id", 0)) <= 0 or int(rows["b"].get("process_id", 0)) <= 0 or rows["a"].get("process_id") == rows["b"].get("process_id"):
			return false
	return not _route_processes6.is_empty()


func world_snapshot() -> Dictionary:
	var value: Dictionary = super.world_snapshot()
	value["mvp6"] = {
		"initialized": not _construction6.is_empty(),
		"phase": _phase6,
		"checksum": String(_construction6.get("checksum", "")),
		"part_count": Array(_construction6.get("parts", [])).size(),
		"base_observers": _phase_count6("BASE"),
		"added_observers": _phase_count6("ADDED"),
		"removed_observers": _phase_count6("REMOVED"),
		"replay_add": _replays6["ADD"],
		"replay_remove": _replays6["REMOVE"],
		"complete": _complete6(),
	}
	return value


func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP6_"):
		return super.handle_client(actor, body)
	if not bool(client_hello.get(actor, false)):
		return Protocol.failure("MVP6_HELLO_REQUIRED")
	var result: Dictionary
	match kind:
		"MVP6_INIT":
			result = _initialize6(actor)
		"MVP6_OBSERVE":
			result = Protocol.success({"construction":_construction6.duplicate(true), "replica":_replica6.duplicate(true)})
		"MVP6_ADD":
			if _phase_count6("BASE") != 2:
				result = Protocol.failure("MVP6_BOTH_BASE_OBSERVERS_REQUIRED")
			else:
				result = _route6(actor, "ADD")
		"MVP6_REPLAY_ADD":
			if _phase_count6("ADDED") != 2:
				result = Protocol.failure("MVP6_BOTH_ADDED_OBSERVERS_REQUIRED")
			else:
				result = _route6(actor, "REPLAY_ADD")
		"MVP6_REMOVE":
			if not bool(_replays6["ADD"]):
				result = Protocol.failure("MVP6_ADD_REPLAY_REQUIRED")
			else:
				result = _route6(actor, "REMOVE")
		"MVP6_REPLAY_REMOVE":
			if _phase_count6("REMOVED") != 2:
				result = Protocol.failure("MVP6_BOTH_REMOVED_OBSERVERS_REQUIRED")
			else:
				result = _route6(actor, "REPLAY_REMOVE")
		"MVP6_OBSERVED":
			result = _observe6(actor, body)
		_:
			result = Protocol.failure("MVP6_UNKNOWN_CLIENT_COMMAND")
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = result.get("details", {}).duplicate(true)
	if not _construction6.is_empty():
		details["construction"] = _construction6.duplicate(true)
		details["replica"] = _replica6.duplicate(true)
	details["snapshot"] = world_snapshot()
	return Protocol.success(details)


func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp6"] = {
		"phase": _phase6,
		"construction": _construction6.duplicate(true),
		"authority_b_replica": _replica6.duplicate(true),
		"observed": _observed6.duplicate(true),
		"replays": _replays6.duplicate(true),
		"route_processes": _route_processes6.duplicate(true),
		"mutation_count": _mutation_count6,
		"complete": _complete6(),
		"canonical_state_owned": false,
		"predicate_verified": false,
	}
	return value


func finish_interactive(seam_criterion: bool, error_code: String = "") -> void:
	if error_code.is_empty() and not _complete6():
		error_code = "MVP6_LIVE_CONSTRUCTION_CONVERGENCE_FAILED"
	super.finish_interactive(seam_criterion and _complete6(), error_code)
