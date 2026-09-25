extends "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_gateway_process.gd"

# Reuses the existing authenticated client/gateway and backend links. This is
# a routing/presentation barrier, never a canonical Matter or player authority.
var _baseline4: Dictionary = {}
var _observed4: Dictionary = {}
var _source4: Dictionary = {}

func _owner4(actor: String, command: Dictionary) -> Dictionary:
	var request := command.duplicate(true)
	# Actor and session are derived from the authenticated peer, not payload.
	request["actor"] = actor
	request["session"] = Protocol.session(cfg, actor)
	var response: Dictionary = call_authority("authority/a", request)
	return native_result(response)

func _refresh_source4(actor: String) -> Dictionary:
	var result := _owner4(actor, {"kind": "MVP4_REPORT"})
	if bool(result.get("success", false)): _source4 = Dictionary(result["details"]).duplicate(true)
	return result

func _complete4() -> bool:
	if _observed4.size() != 2 or int(_source4.get("stream_sequence", 0)) < 1:
		return false
	for actor in ["a", "b"]:
		var observed: Dictionary = _observed4[actor]
		if observed.get("store_hash") != _source4.get("store_hash") or observed.get("replica", {}).get("state_hash") != _source4.get("state_hash"):
			return false
	return _observed4["a"].get("geometry_hash") == _observed4["b"].get("geometry_hash")

func world_snapshot() -> Dictionary:
	var value: Dictionary = super.world_snapshot()
	value["mvp4"] = {"both_baselines_ready": _baseline4.size() == 2, "both_observed": _complete4(), "source_stream_sequence": _source4.get("stream_sequence", 0), "source_state_hash": _source4.get("state_hash", ""), "source_store_hash": _source4.get("store_hash", "")}
	return value

func handle_client(actor: String, body: Dictionary) -> Dictionary:
	var kind := String(body.get("kind", ""))
	if not kind.begins_with("MVP4_"): return super.handle_client(actor, body)
	if not bool(client_hello.get(actor, false)):
		return Protocol.failure("MVP4_HELLO_REQUIRED")
	var result: Dictionary
	if kind in ["MVP4_CONNECT", "MVP4_EQUIP", "MVP4_POLL", "MVP4_PREPARE", "MVP4_EXECUTE"]:
		if kind in ["MVP4_PREPARE", "MVP4_EXECUTE"] and _baseline4.size() != 2:
			return Protocol.failure("MVP4_BOTH_BASELINE_OBSERVERS_REQUIRED")
		result = _owner4(actor, body)
		if not bool(result.get("success", false)): return result
		if kind in ["MVP4_CONNECT", "MVP4_EXECUTE"]:
			var refreshed := _refresh_source4(actor)
			if not bool(refreshed.get("success", false)): return refreshed
	elif kind in ["MVP4_BASELINE", "MVP4_OBSERVED"]:
		if not body.get("projection") is Dictionary or not body.get("ack") is Dictionary:
			return Protocol.failure("MVP4_REPLICA_EVIDENCE_REQUIRED")
		var projection: Dictionary = body["projection"]
		if JSON.stringify(projection).to_utf8_buffer().size() > 32768 or projection.get("actor") != actor or projection.get("canonical_state_owned") != false or projection.get("excavation_service_retained") != false:
			return Protocol.failure("MVP4_REPLICA_EVIDENCE_INVALID")
		result = _owner4(actor, {"kind": "MVP4_ACK", "ack": body["ack"]})
		if not bool(result.get("success", false)): return result
		var refreshed := _refresh_source4(actor)
		if not bool(refreshed.get("success", false)): return refreshed
		if projection.get("store_hash") != _source4.get("store_hash") or projection.get("replica", {}).get("state_hash") != _source4.get("state_hash"):
			return Protocol.failure("MVP4_REPLICA_NOT_CONVERGED")
		if kind == "MVP4_BASELINE":
			if _baseline4.has(actor) or int(_source4.get("stream_sequence", -1)) != 0:
				return Protocol.failure("MVP4_BASELINE_PHASE_INVALID")
			_baseline4[actor] = projection.duplicate(true)
		else:
			if not _baseline4.has(actor) or int(_source4.get("stream_sequence", 0)) < 1 or projection.get("geometry_hash") == _baseline4[actor].get("geometry_hash") or projection.get("network_mutation_proven") != true:
				return Protocol.failure("MVP4_VISIBLE_MUTATION_NOT_PROVEN")
			_observed4[actor] = projection.duplicate(true)
	else:
		return Protocol.failure("MVP4_UNKNOWN_CLIENT_COMMAND")
	return Protocol.success({"kind": kind, "actor": actor, "matter": result.get("details", {}), "snapshot": world_snapshot()})

func base_report(schema: String, passed: bool, graphical: bool) -> Dictionary:
	var value: Dictionary = super.base_report(schema, passed, graphical)
	value["mvp4"] = {"canonical_source": _source4.duplicate(true), "baselines": _baseline4.duplicate(true), "observed": _observed4.duplicate(true), "both_observed": _complete4(), "predicate_verified": false, "scope": "SINGLE_REGION_SHARED_DIG_NOT_ITEM_BEARING_HANDOFF"}
	return value

func finish_interactive(_seam_criterion: bool, error_code: String = "") -> void:
	# The parent calls this hook after FINISH, or with a concrete failure. MVP4
	# has a different leaf criterion; no MVP3 assertion/result is relabelled.
	var completed := error_code.is_empty() and failures.is_empty() and bool(client_finished["a"]) and bool(client_finished["b"]) and _complete4()
	for actor in ["a", "b"]:
		completed = completed and int(sequences[actor]) >= 2 and not input_observations[actor].is_empty()
	if not completed and error_code.is_empty(): error_code = "MVP4_SHARED_DIG_COMPLETION_FAILED"
	super.finish_interactive(completed, error_code)
