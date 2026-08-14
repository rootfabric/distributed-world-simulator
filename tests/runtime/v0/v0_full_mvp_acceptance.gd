extends RefCounted

const SCHEMA := "distributed_world_simulator.v0_full_mvp_acceptance.v1"
const STATE_PASS := "PASS"
const STATE_FAIL := "FAIL"
const STATE_DEPENDENCY_PENDING := "DEPENDENCY_PENDING"
const STATE_NOT_IMPLEMENTED := "NOT_IMPLEMENTED"
const VALID_STATES: Array[String] = [
	STATE_PASS,
	STATE_FAIL,
	STATE_DEPENDENCY_PENDING,
	STATE_NOT_IMPLEMENTED,
]
const FINAL_SOAK_SECONDS := 1800
const DEFAULT_DEV_SOAK_SECONDS := 30
const REQUIRED_PHASE_COUNT := 37


static func phases() -> Array[Dictionary]:
	return [
		_phase(1, "dedicated server boot", "NETWORK_BOOT"),
		_phase(2, "client A connects", "NETWORK_CLIENT_A"),
		_phase(3, "client B connects", "NETWORK_CLIENT_B"),
		_phase(4, "both playable characters exist", "PLAYER_REPLICATION"),
		_phase(5, "players spawn approximately 10 metres apart", "PLAYER_SPAWN_SPACING"),
		_phase(6, "A moves", "PLAYER_MOVEMENT_A"),
		_phase(7, "B observes remote movement", "REMOTE_MOVEMENT_B"),
		_phase(8, "B moves", "PLAYER_MOVEMENT_B"),
		_phase(9, "A observes remote movement", "REMOTE_MOVEMENT_A"),
		_phase(10, "canonical world resource item exists", "WORLD_ITEM_CANONICAL"),
		_phase(11, "A interacts with and picks up item", "ITEM_PICKUP"),
		_phase(12, "B observes world-item removal", "WORLD_ITEM_REPLICATION"),
		_phase(13, "A inventory contains canonical item", "ITEM_GRAPH_INVENTORY"),
		_phase(14, "A drops item", "ITEM_DROP"),
		_phase(15, "B observes world item again", "WORLD_ITEM_REPLICATION"),
		_phase(16, "A interacts with external container", "CONTAINER_INTERACTION"),
		_phase(17, "Player | Container state opens correctly", "CONTAINER_UI_STATE"),
		_phase(18, "canonical item transfers between player/container", "CONTAINER_TRANSFER"),
		_phase(19, "B observes converged canonical container state", "CONTAINER_REPLICATION"),
		_phase(20, "A obtains required construction resource", "CONSTRUCTION_RESOURCE"),
		_phase(21, "A creates foundation", "CONSTRUCTION_BUILD"),
		_phase(22, "required resource quantity decreases canonically", "CONSTRUCTION_ECONOMY"),
		_phase(23, "A creates walls", "CONSTRUCTION_BUILD"),
		_phase(24, "A creates roof / minimal closed outpost target", "CONSTRUCTION_BUILD"),
		_phase(25, "B observes construction state", "CONSTRUCTION_REPLICATION"),
		_phase(26, "B disconnects", "RECONNECT_LIFECYCLE"),
		_phase(27, "A continues to move/interact while B is absent", "ABSENT_PEER_CONTINUATION"),
		_phase(28, "world state changes while B is absent", "ABSENT_PEER_WORLD_MUTATION"),
		_phase(29, "B reconnects", "RECONNECT_LIFECYCLE"),
		_phase(30, "B converges to current player state", "RECONNECT_PLAYER_STATE"),
		_phase(31, "B converges to Item Graph state", "RECONNECT_ITEM_GRAPH"),
		_phase(32, "B converges to world items", "RECONNECT_WORLD_ITEMS"),
		_phase(33, "B converges to container contents", "RECONNECT_CONTAINERS"),
		_phase(34, "B converges to Construction state", "RECONNECT_CONSTRUCTION"),
		_phase(35, "bounded soak", "SOAK"),
		_phase(36, "clean shutdown", "SHUTDOWN"),
		_phase(37, "final leak/error/assertion checks", "FINAL_CHECKS"),
	]


static func phase_result(
	phase: Dictionary,
	state: String,
	reason: String = "",
	evidence: Dictionary = {}
) -> Dictionary:
	var normalized_state := state.strip_edges().to_upper()
	if normalized_state not in VALID_STATES:
		normalized_state = STATE_FAIL
		reason = "INVALID_PHASE_STATE"
	var result := {
		"id": int(phase.get("id", 0)),
		"code": String(phase.get("code", "")),
		"name": String(phase.get("name", "")),
		"dependency": String(phase.get("dependency", "")),
		"state": normalized_state,
		"reason": reason.strip_edges(),
		"evidence": evidence.duplicate(true),
	}
	if normalized_state == STATE_PASS:
		var evidence_check := validate_phase_evidence(int(result["id"]), evidence)
		if not bool(evidence_check.get("success", false)):
			result["state"] = STATE_FAIL
			result["reason"] = String(evidence_check.get("error_code", "PASS_EVIDENCE_INVALID"))
			result["evidence_validation"] = evidence_check
	return result


static func aggregate_state(results: Array) -> String:
	var integrity := validate_result_set(results)
	if not bool(integrity.get("success", false)):
		return STATE_FAIL
	var has_pending := false
	var has_not_implemented := false
	for value in results:
		var result := Dictionary(value)
		match String(result.get("state", "")):
			STATE_FAIL:
				return STATE_FAIL
			STATE_NOT_IMPLEMENTED:
				has_not_implemented = true
			STATE_DEPENDENCY_PENDING:
				has_pending = true
			STATE_PASS:
				pass
			_:
				return STATE_FAIL
	if has_not_implemented:
		return STATE_NOT_IMPLEMENTED
	if has_pending:
		return STATE_DEPENDENCY_PENDING
	return STATE_PASS


static func state_counts(results: Array) -> Dictionary:
	var counts := {
		STATE_PASS: 0,
		STATE_FAIL: 0,
		STATE_DEPENDENCY_PENDING: 0,
		STATE_NOT_IMPLEMENTED: 0,
	}
	for value in results:
		if value is Dictionary:
			var state := String(Dictionary(value).get("state", ""))
			if counts.has(state):
				counts[state] = int(counts[state]) + 1
	return counts


static func build_summary(
	results: Array,
	integration_base: String,
	soak_seconds: int,
	run_id: String = ""
) -> Dictionary:
	var integrity := validate_result_set(results)
	return {
		"schema": SCHEMA,
		"run_id": run_id,
		"integration_base": integration_base,
		"aggregate_state": aggregate_state(results),
		"counts": state_counts(results),
		"required_phase_count": REQUIRED_PHASE_COUNT,
		"result_set_integrity": integrity,
		"soak_seconds_requested": soak_seconds,
		"soak_seconds_required_for_final": FINAL_SOAK_SECONDS,
		"final_soak_duration_satisfied": _trusted_soak_satisfied(results),
		"phases": results.duplicate(true),
	}


static func validate_result_set(results: Array) -> Dictionary:
	var expected := phases()
	var errors: Array[String] = []
	var seen: Dictionary = {}
	if results.size() != REQUIRED_PHASE_COUNT:
		errors.append("PHASE_COUNT_MISMATCH")
	for value in results:
		if not value is Dictionary:
			errors.append("NON_DICTIONARY_PHASE_RESULT")
			continue
		var result := Dictionary(value)
		var id := int(result.get("id", -1))
		if id < 1 or id > REQUIRED_PHASE_COUNT:
			errors.append("UNEXPECTED_PHASE_ID_%d" % id)
			continue
		if seen.has(id):
			errors.append("DUPLICATE_PHASE_ID_%d" % id)
			continue
		seen[id] = true
		var phase: Dictionary = expected[id - 1]
		if String(result.get("code", "")) != String(phase.get("code", "")):
			errors.append("PHASE_%02d_CODE_MISMATCH" % id)
		if String(result.get("name", "")) != String(phase.get("name", "")):
			errors.append("PHASE_%02d_NAME_MISMATCH" % id)
		if String(result.get("dependency", "")) != String(phase.get("dependency", "")):
			errors.append("PHASE_%02d_DEPENDENCY_MISMATCH" % id)
		var state := String(result.get("state", ""))
		if state not in VALID_STATES:
			errors.append("PHASE_%02d_INVALID_STATE" % id)
		elif state == STATE_PASS:
			var evidence_value = result.get("evidence", null)
			if not evidence_value is Dictionary:
				errors.append("PHASE_%02d_PASS_EVIDENCE_NOT_DICTIONARY" % id)
			else:
				var evidence_check := validate_phase_evidence(id, Dictionary(evidence_value))
				if not bool(evidence_check.get("success", false)):
					errors.append("PHASE_%02d_%s" % [id, String(evidence_check.get("error_code", "PASS_EVIDENCE_INVALID"))])
	for id in range(1, REQUIRED_PHASE_COUNT + 1):
		if not seen.has(id):
			errors.append("MISSING_PHASE_ID_%d" % id)
	return {
		"success": errors.is_empty(),
		"error_code": "" if errors.is_empty() else "V0_RESULT_SET_INTEGRITY_FAILED",
		"details": {
			"required_phase_count": REQUIRED_PHASE_COUNT,
			"observed_phase_count": results.size(),
			"errors": errors,
		},
	}


static func validate_phase_evidence(phase_id: int, evidence: Dictionary) -> Dictionary:
	if evidence.is_empty():
		return _evidence_failure("PASS_EVIDENCE_EMPTY")
	var required_keys := _required_evidence_keys(phase_id)
	var missing: Array[String] = []
	for key in required_keys:
		if not evidence.has(key) or not _has_content(evidence.get(key)):
			missing.append(key)
	if not missing.is_empty():
		return _evidence_failure("PASS_EVIDENCE_MISSING_REQUIRED_FIELDS", {"missing": missing})
	if phase_id == 1 and not _valid_process(Dictionary(evidence["server"])):
		return _evidence_failure("PASS_EVIDENCE_INVALID_SERVER_PROCESS")
	if phase_id == 2 and not _valid_client(Dictionary(evidence["client_a"])):
		return _evidence_failure("PASS_EVIDENCE_INVALID_CLIENT_A")
	if phase_id == 3 and not _valid_client(Dictionary(evidence["client_b"])):
		return _evidence_failure("PASS_EVIDENCE_INVALID_CLIENT_B")
	if phase_id in [4, 5]:
		if not _valid_player(Dictionary(evidence["player_a"])) or not _valid_player(Dictionary(evidence["player_b"])):
			return _evidence_failure("PASS_EVIDENCE_INVALID_PLAYER_IDENTITIES")
	if phase_id in [6, 7, 8, 9]:
		if String(evidence.get("player_entity_id", "")).is_empty():
			return _evidence_failure("PASS_EVIDENCE_INVALID_MOVEMENT_PLAYER_ID")
		for key in ["authoritative_before", "authoritative_after", "rendered_before", "rendered_after"]:
			if not _valid_state_frame(Dictionary(evidence[key])):
				return _evidence_failure("PASS_EVIDENCE_INVALID_MOVEMENT_STATE")
	if phase_id in [10, 11, 12, 13, 14, 15, 20, 28, 31]:
		for key in ["item_graph", "item_graph_authority", "item_graph_client_b"]:
			if evidence.has(key) and not _valid_item_graph(Dictionary(evidence[key])):
				return _evidence_failure("PASS_EVIDENCE_INVALID_ITEM_GRAPH")
	if phase_id in [10, 11, 12, 13, 14, 15, 28, 32]:
		for key in ["world_item", "world_item_authority", "world_item_client_b"]:
			if evidence.has(key) and not _valid_world_item(Dictionary(evidence[key])):
				return _evidence_failure("PASS_EVIDENCE_INVALID_WORLD_ITEM")
	if phase_id in [16, 17, 18, 19, 33]:
		for key in ["container", "container_authority", "container_client_b"]:
			if evidence.has(key) and not _valid_container(Dictionary(evidence[key])):
				return _evidence_failure("PASS_EVIDENCE_INVALID_CONTAINER")
	if phase_id in [21, 22, 23, 24, 25, 34]:
		for key in ["construction", "construction_authority", "construction_client_b"]:
			if evidence.has(key) and not _valid_construction(Dictionary(evidence[key])):
				return _evidence_failure("PASS_EVIDENCE_INVALID_CONSTRUCTION")
	if phase_id == 26:
		var disconnect_session := Dictionary(evidence["client_b_session"])
		if not _valid_session(disconnect_session) or bool(disconnect_session.get("connected", true)):
			return _evidence_failure("PASS_EVIDENCE_INVALID_DISCONNECT_IDENTITY")
		if int(evidence.get("ownership_epoch", -1)) < 0:
			return _evidence_failure("PASS_EVIDENCE_INVALID_DISCONNECT_IDENTITY")
	if phase_id == 27 and not bool(evidence.get("continuation_check", false)):
		return _evidence_failure("PASS_EVIDENCE_ABSENT_PEER_CONTINUATION_NOT_PROVEN")
	if phase_id == 29:
		var session_before := Dictionary(evidence["session_before"])
		var session_after := Dictionary(evidence["session_after"])
		if not _valid_session(session_before) or not _valid_session(session_after):
			return _evidence_failure("PASS_EVIDENCE_INVALID_RECONNECT_SESSIONS")
		if String(session_before.get("session_id", "")) == String(session_after.get("session_id", "")):
			return _evidence_failure("PASS_EVIDENCE_RECONNECT_SESSION_DID_NOT_CHANGE")
		if bool(session_before.get("connected", true)) or not bool(session_after.get("connected", false)):
			return _evidence_failure("PASS_EVIDENCE_RECONNECT_CONNECTED_STATE_INVALID")
		if int(evidence.get("ownership_epoch_after", -1)) <= int(evidence.get("ownership_epoch_before", -1)):
			return _evidence_failure("PASS_EVIDENCE_INVALID_OWNERSHIP_EPOCH_TRANSITION")
	if phase_id in [11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34] and not bool(evidence.get("convergence", false)):
		return _evidence_failure("PASS_EVIDENCE_CONVERGENCE_NOT_PROVEN")
	if phase_id == 35:
		var samples := Array(evidence.get("observation_samples", []))
		if samples.size() < 2 or int(evidence.get("trusted_sample_count", -1)) != samples.size():
			return _evidence_failure("PASS_EVIDENCE_SOAK_SAMPLES_INVALID")
		if float(evidence.get("trusted_elapsed_seconds", 0.0)) < float(FINAL_SOAK_SECONDS):
			return _evidence_failure("PASS_EVIDENCE_SOAK_ELAPSED_TOO_SHORT")
		if int(evidence.get("trusted_end_ticks_msec", -1)) < int(evidence.get("trusted_start_ticks_msec", 0)):
			return _evidence_failure("PASS_EVIDENCE_SOAK_CLOCK_INVALID")
		if not _all_checks_true(Dictionary(evidence.get("checks", {}))):
			return _evidence_failure("PASS_EVIDENCE_SOAK_CHECKS_FAILED")
	if phase_id == 36 and not bool(evidence.get("shutdown_clean", false)):
		return _evidence_failure("PASS_EVIDENCE_SHUTDOWN_NOT_CLEAN")
	if phase_id == 37:
		for key in ["error_count", "assertion_failures", "process_exit_failures", "leak_count"]:
			if int(evidence.get(key, -1)) != 0:
				return _evidence_failure("PASS_EVIDENCE_FINAL_COUNTER_NONZERO", {"counter": key})
	return {"success": true, "error_code": "", "details": {"required_keys": required_keys}}


static func validate_spawn_spacing(
	player_a: Dictionary,
	player_b: Dictionary,
	target_metres: float = 10.0,
	tolerance_metres: float = 2.0
) -> Dictionary:
	var position_a := _vector3_from_dict(Dictionary(player_a.get("position", {})))
	var position_b := _vector3_from_dict(Dictionary(player_b.get("position", {})))
	var distance := position_a.distance_to(position_b)
	var minimum := maxf(0.0, target_metres - tolerance_metres)
	var maximum := target_metres + tolerance_metres
	var success := distance >= minimum and distance <= maximum
	return {
		"success": success,
		"error_code": "" if success else "V0_PLAYER_SPAWN_SPACING_OUT_OF_RANGE",
		"details": {
			"distance_metres": distance,
			"target_metres": target_metres,
			"tolerance_metres": tolerance_metres,
			"minimum_metres": minimum,
			"maximum_metres": maximum,
		},
	}


static func compare_player_identity(authority: Dictionary, replica: Dictionary) -> Dictionary:
	var mismatches: Array[String] = []
	for key in ["logical_player_id", "player_entity_id", "ownership_epoch", "connected"]:
		if authority.get(key) != replica.get(key):
			mismatches.append(key)
	if bool(authority.get("connected", false)) and bool(replica.get("connected", false)):
		if String(authority.get("transport_session_id", "")) != String(replica.get("transport_session_id", "")):
			mismatches.append("transport_session_id")
	return _comparison("PLAYER_IDENTITY_DIVERGENCE", mismatches)


static func compare_player_state(
	authority: Dictionary,
	replica: Dictionary,
	position_tolerance: float = 0.001,
	velocity_tolerance: float = 0.001
) -> Dictionary:
	var mismatches: Array[String] = []
	for key in ["state_revision", "last_input_sequence", "orientation_yaw", "flashlight_enabled"]:
		if authority.has(key) or replica.has(key):
			if authority.get(key) != replica.get(key):
				mismatches.append(key)
	if _vector3_from_dict(Dictionary(authority.get("position", {}))).distance_to(
		_vector3_from_dict(Dictionary(replica.get("position", {})))
	) > position_tolerance:
		mismatches.append("position")
	if _vector3_from_dict(Dictionary(authority.get("velocity", {}))).distance_to(
		_vector3_from_dict(Dictionary(replica.get("velocity", {})))
	) > velocity_tolerance:
		mismatches.append("velocity")
	return _comparison("PLAYER_STATE_DIVERGENCE", mismatches)


static func compare_item_graph(authority: Dictionary, replica: Dictionary) -> Dictionary:
	var authority_checksum := String(authority.get("checksum", ""))
	var replica_checksum := String(replica.get("checksum", ""))
	var mismatches: Array[String] = []
	if authority_checksum.length() != 64 or replica_checksum.length() != 64:
		mismatches.append("checksum_format")
	elif authority_checksum != replica_checksum:
		mismatches.append("checksum")
	return _comparison("ITEM_GRAPH_DIVERGENCE", mismatches)


static func compare_world_items(authority_graph: Dictionary, replica_graph: Dictionary) -> Dictionary:
	var authority_projection := _world_item_projection(authority_graph)
	var replica_projection := _world_item_projection(replica_graph)
	return _comparison(
		"WORLD_ITEM_DIVERGENCE",
		[] if authority_projection == replica_projection else ["world_items"],
		{"authority": authority_projection, "replica": replica_projection}
	)


static func compare_containers(authority_graph: Dictionary, replica_graph: Dictionary) -> Dictionary:
	var authority_projection := _container_projection(authority_graph)
	var replica_projection := _container_projection(replica_graph)
	return _comparison(
		"CONTAINER_DIVERGENCE",
		[] if authority_projection == replica_projection else ["containers"],
		{"authority": authority_projection, "replica": replica_projection}
	)


static func compare_construction(authority: Dictionary, replica: Dictionary) -> Dictionary:
	var mismatches: Array[String] = []
	for key in ["server_generation", "checksum"]:
		if authority.get(key) != replica.get(key):
			mismatches.append(key)
	if authority.has("last_event_index") or replica.has("last_event_index"):
		if authority.get("last_event_index") != replica.get("last_event_index"):
			mismatches.append("last_event_index")
	return _comparison("CONSTRUCTION_DIVERGENCE", mismatches)


static func reconnect_convergence(
	authority_player: Dictionary,
	replica_player: Dictionary,
	authority_item_graph: Dictionary,
	replica_item_graph: Dictionary,
	authority_construction: Dictionary,
	replica_construction: Dictionary
) -> Dictionary:
	var checks := {
		"player_identity": compare_player_identity(authority_player, replica_player),
		"player_state": compare_player_state(authority_player, replica_player),
		"item_graph": compare_item_graph(authority_item_graph, replica_item_graph),
		"world_items": compare_world_items(authority_item_graph, replica_item_graph),
		"containers": compare_containers(authority_item_graph, replica_item_graph),
		"construction": compare_construction(authority_construction, replica_construction),
	}
	var failed: Array[String] = []
	for key in checks.keys():
		if not bool(Dictionary(checks[key]).get("success", false)):
			failed.append(String(key))
	return {
		"success": failed.is_empty(),
		"error_code": "" if failed.is_empty() else "V0_RECONNECT_CONVERGENCE_FAILED",
		"details": {"failed_domains": failed, "checks": checks},
	}


class SoakTracker:
	extends RefCounted

	var _samples: Array[Dictionary] = []
	var _failure_codes: Array[String] = []

	func observe(sample: Dictionary) -> void:
		var copy := sample.duplicate(true)
		_samples.append(copy)
		if not bool(copy.get("process_alive", true)):
			_add_failure("PROCESS_EXIT")
		if int(copy.get("assertion_failures", 0)) > 0:
			_add_failure("ASSERTION_FAILURE")
		if int(copy.get("disconnect_reconnect_failures", 0)) > 0:
			_add_failure("DISCONNECT_RECONNECT_FAILURE")
		if int(copy.get("serious_error_count", 0)) > 0:
			_add_failure("SERIOUS_ERROR_LOG_MARKER")
		if bool(copy.get("state_divergence", false)):
			_add_failure("PERSISTENT_STATE_DIVERGENCE")

	func finish(elapsed_seconds: float, required_seconds: int = FINAL_SOAK_SECONDS) -> Dictionary:
		var enforced_required_seconds := maxi(required_seconds, FINAL_SOAK_SECONDS)
		if _samples.size() < 2:
			_add_failure("SOAK_INSUFFICIENT_SAMPLES")
		else:
			var first: Dictionary = _samples[0]
			var last: Dictionary = _samples[-1]
			var pending_growth := int(last.get("pending_operations", 0)) - int(first.get("pending_operations", 0))
			if pending_growth > 32:
				_add_failure("UNBOUNDED_PENDING_OPERATION_GROWTH")
			var reliable_growth := int(last.get("reliable_queue_depth", 0)) - int(first.get("reliable_queue_depth", 0))
			if reliable_growth > 32:
				_add_failure("UNBOUNDED_RELIABLE_QUEUE_GROWTH")
		if not _failure_codes.is_empty():
			return {
				"state": STATE_FAIL,
				"success": false,
				"error_code": "V0_SOAK_FAILED",
				"details": {"failure_codes": _failure_codes.duplicate(), "sample_count": _samples.size()},
			}
		if elapsed_seconds < float(enforced_required_seconds):
			return {
				"state": STATE_DEPENDENCY_PENDING,
				"success": false,
				"error_code": "SOAK_DURATION_BELOW_FINAL_REQUIREMENT",
				"details": {
					"elapsed_seconds": elapsed_seconds,
					"configured_required_seconds": required_seconds,
					"required_seconds": enforced_required_seconds,
					"sample_count": _samples.size(),
				},
			}
		return {
			"state": STATE_PASS,
			"success": true,
			"error_code": "",
			"details": {
				"elapsed_seconds": elapsed_seconds,
				"configured_required_seconds": required_seconds,
				"required_seconds": enforced_required_seconds,
				"sample_count": _samples.size(),
			},
		}

	func _add_failure(code: String) -> void:
		if code not in _failure_codes:
			_failure_codes.append(code)


static func _required_evidence_keys(phase_id: int) -> Array[String]:
	match phase_id:
		1:
			return ["server"]
		2:
			return ["client_a"]
		3:
			return ["client_b"]
		4, 5:
			return ["player_a", "player_b"]
		6, 7, 8, 9:
			return ["player_entity_id", "authoritative_before", "authoritative_after", "rendered_before", "rendered_after"]
		10:
			return ["item_graph", "world_item"]
		11, 12, 13, 14, 15:
			return ["item_graph", "world_item", "player_inventory", "convergence"]
		16, 17, 18, 19:
			return ["item_graph", "container", "convergence"]
		20:
			return ["item_graph", "player_inventory"]
		21, 22, 23, 24, 25:
			return ["construction", "convergence"]
		26:
			return ["client_b_session", "ownership_epoch"]
		27:
			return ["player_a", "continuation_check"]
		28:
			return ["item_graph", "world_item"]
		29:
			return ["session_before", "session_after", "ownership_epoch_before", "ownership_epoch_after"]
		30:
			return ["player_a", "player_b", "convergence"]
		31:
			return ["item_graph_authority", "item_graph_client_b", "convergence"]
		32:
			return ["world_item_authority", "world_item_client_b", "convergence"]
		33:
			return ["container_authority", "container_client_b", "convergence"]
		34:
			return ["construction_authority", "construction_client_b", "convergence"]
		35:
			return ["observation_samples", "checks", "trusted_start_ticks_msec", "trusted_end_ticks_msec", "trusted_elapsed_seconds", "trusted_sample_count"]
		36:
			return ["processes", "shutdown_clean"]
		37:
			return ["error_count", "assertion_failures", "process_exit_failures", "leak_count"]
		_:
			return []


static func _trusted_soak_satisfied(results: Array) -> bool:
	for value in results:
		if not value is Dictionary:
			continue
		var result := Dictionary(value)
		if int(result.get("id", -1)) != 35 or String(result.get("state", "")) != STATE_PASS:
			continue
		var evidence_value = result.get("evidence", null)
		if evidence_value is Dictionary:
			return bool(validate_phase_evidence(35, Dictionary(evidence_value)).get("success", false))
	return false


static func _has_content(value) -> bool:
	if value == null:
		return false
	if value is String:
		return not String(value).strip_edges().is_empty()
	if value is Dictionary:
		return not Dictionary(value).is_empty()
	if value is Array:
		return not Array(value).is_empty()
	return true


static func _valid_process(value: Dictionary) -> bool:
	return _has_content(value.get("process_id")) and bool(value.get("alive", false))


static func _valid_client(value: Dictionary) -> bool:
	return _valid_process(value) and _has_content(value.get("session_id"))


static func _valid_player(value: Dictionary) -> bool:
	return _has_content(value.get("player_entity_id"))


static func _valid_session(value: Dictionary) -> bool:
	return _has_content(value.get("session_id"))


static func _valid_item_graph(value: Dictionary) -> bool:
	return (
		_has_content(value.get("graph_id"))
		and int(value.get("revision", -1)) >= 0
		and String(value.get("checksum", "")).length() == 64
	)


static func _valid_world_item(value: Dictionary) -> bool:
	return _has_content(value.get("item_id")) and _has_content(value.get("state"))


static func _valid_state_frame(value: Dictionary) -> bool:
	return value.has("position") and value.get("position") is Dictionary and not Dictionary(value.get("position", {})).is_empty()


static func _valid_container(value: Dictionary) -> bool:
	return _has_content(value.get("container_id")) and _has_content(value.get("state")) and int(value.get("revision", -1)) >= 0


static func _valid_construction(value: Dictionary) -> bool:
	return int(value.get("server_generation", -1)) >= 0 and _has_content(value.get("checksum"))


static func _all_checks_true(checks: Dictionary) -> bool:
	if checks.is_empty():
		return false
	for value in checks.values():
		if value is bool:
			if not bool(value):
				return false
		elif value is Dictionary:
			if not bool(Dictionary(value).get("success", false)):
				return false
		else:
			return false
	return true


static func _evidence_failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}


static func _phase(id: int, name: String, dependency: String) -> Dictionary:
	return {
		"id": id,
		"code": "%02d" % id,
		"name": name,
		"dependency": dependency,
	}


static func _comparison(
	error_code: String,
	mismatches: Array,
	details: Dictionary = {}
) -> Dictionary:
	var payload := details.duplicate(true)
	payload["mismatches"] = mismatches.duplicate()
	return {
		"success": mismatches.is_empty(),
		"error_code": "" if mismatches.is_empty() else error_code,
		"details": payload,
	}


static func _world_item_projection(graph: Dictionary) -> Array:
	var projection: Array = []
	for item_value in graph.get("items", []):
		if not item_value is Dictionary:
			continue
		var item := Dictionary(item_value)
		if String(Dictionary(item.get("location", {})).get("kind", "")) != "WORLD":
			continue
		projection.append(_canonicalize({
			"item_id": String(item.get("item_id", "")),
			"definition_id": String(item.get("definition_id", "")),
			"quantity": int(item.get("quantity", 0)),
			"location": item.get("location", {}),
			"transform": item.get("transform", {}),
		}))
	projection.sort_custom(func(a, b): return String(a.get("item_id", "")) < String(b.get("item_id", "")))
	return projection


static func _container_projection(graph: Dictionary) -> Dictionary:
	var container_items: Array = []
	for item_value in graph.get("items", []):
		if not item_value is Dictionary:
			continue
		var item := Dictionary(item_value)
		var location := Dictionary(item.get("location", {}))
		if String(location.get("kind", "")) != "CONTAINER":
			continue
		container_items.append(_canonicalize({
			"item_id": String(item.get("item_id", "")),
			"definition_id": String(item.get("definition_id", "")),
			"quantity": int(item.get("quantity", 0)),
			"location": location,
		}))
	container_items.sort_custom(func(a, b): return String(a.get("item_id", "")) < String(b.get("item_id", "")))
	return _canonicalize({
		"containers": graph.get("containers", {}),
		"container_items": container_items,
	})


static func _canonicalize(value):
	if value is Dictionary:
		var source := Dictionary(value)
		var keys: Array[String] = []
		for key_value in source.keys():
			keys.append(String(key_value))
		keys.sort()
		var result := {}
		for key in keys:
			result[key] = _canonicalize(source.get(key))
		return result
	if value is Array:
		var result: Array = []
		for child in Array(value):
			result.append(_canonicalize(child))
		return result
	return value


static func _vector3_from_dict(value: Dictionary) -> Vector3:
	return Vector3(
		float(value.get("x", 0.0)),
		float(value.get("y", 0.0)),
		float(value.get("z", 0.0))
	)
