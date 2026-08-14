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
	return {
		"id": int(phase.get("id", 0)),
		"code": String(phase.get("code", "")),
		"name": String(phase.get("name", "")),
		"dependency": String(phase.get("dependency", "")),
		"state": normalized_state,
		"reason": reason.strip_edges(),
		"evidence": evidence.duplicate(true),
	}


static func aggregate_state(results: Array) -> String:
	var has_pending := false
	var has_not_implemented := false
	for value in results:
		if not value is Dictionary:
			return STATE_FAIL
		match String(value.get("state", "")):
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
			var state := String(value.get("state", ""))
			if counts.has(state):
				counts[state] = int(counts[state]) + 1
	return counts


static func build_summary(
	results: Array,
	integration_base: String,
	soak_seconds: int,
	run_id: String = ""
) -> Dictionary:
	return {
		"schema": SCHEMA,
		"run_id": run_id,
		"integration_base": integration_base,
		"aggregate_state": aggregate_state(results),
		"counts": state_counts(results),
		"required_phase_count": phases().size(),
		"soak_seconds_requested": soak_seconds,
		"soak_seconds_required_for_final": FINAL_SOAK_SECONDS,
		"final_soak_duration_satisfied": soak_seconds >= FINAL_SOAK_SECONDS,
		"phases": results.duplicate(true),
	}


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
	var _pending_declined := false
	var _reliable_queue_declined := false

	func observe(sample: Dictionary) -> void:
		var copy := sample.duplicate(true)
		if not _samples.is_empty():
			var previous: Dictionary = _samples[-1]
			if int(copy.get("pending_operations", 0)) < int(previous.get("pending_operations", 0)):
				_pending_declined = true
			if int(copy.get("reliable_queue_depth", 0)) < int(previous.get("reliable_queue_depth", 0)):
				_reliable_queue_declined = true
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

	func finish(elapsed_seconds: int, required_seconds: int = FINAL_SOAK_SECONDS) -> Dictionary:
		var enforced_required_seconds := maxi(required_seconds, FINAL_SOAK_SECONDS)
		if _samples.is_empty():
			_add_failure("SOAK_NO_SAMPLES")
		else:
			var first: Dictionary = _samples[0]
			var last: Dictionary = _samples[-1]
			var pending_growth := int(last.get("pending_operations", 0)) - int(first.get("pending_operations", 0))
			if pending_growth > 32 and not _pending_declined:
				_add_failure("UNBOUNDED_PENDING_OPERATION_GROWTH")
			var reliable_growth := int(last.get("reliable_queue_depth", 0)) - int(first.get("reliable_queue_depth", 0))
			if reliable_growth > 32 and not _reliable_queue_declined:
				_add_failure("UNBOUNDED_RELIABLE_QUEUE_GROWTH")
		if not _failure_codes.is_empty():
			return {
				"state": STATE_FAIL,
				"success": false,
				"error_code": "V0_SOAK_FAILED",
				"details": {"failure_codes": _failure_codes.duplicate(), "sample_count": _samples.size()},
			}
		if elapsed_seconds < enforced_required_seconds:
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
