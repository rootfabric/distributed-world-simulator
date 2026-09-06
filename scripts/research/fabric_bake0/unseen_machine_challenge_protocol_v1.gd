extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_graph_v1.gd")
const GenericCompiler = preload("res://scripts/research/fabric_bake0/unseen_machine_generic_compiler_v1.gd")
const ExactCompiler = preload("res://scripts/research/fabric_bake0/exact_boundary_bake_compiler_v1.gd")
const Reducer = preload("res://scripts/research/fabric_bake0/exact_boundary_reducer_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/exact_boundary_runtime_v1.gd")
const LinearAlgebra = preload("res://scripts/research/fabric_bake0/dense_linear_algebra_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")

const RESULT_SCHEMA := "planet_simulator.fabric_b0_7_unseen_challenge_result.v1"

static func run_case(
	base_spec: Dictionary,
	successor_spec: Dictionary,
	failure_event_id: String,
	failed_edge_ids: Array,
	excitations: Array,
	observation_port_id: String
) -> Dictionary:
	var relationship := validate_successor(base_spec, successor_spec, failure_event_id, failed_edge_ids)
	if not bool(relationship.get("success", false)):
		return relationship
	if excitations.is_empty():
		return Utils.failure("B0_7_EXCITATIONS_REQUIRED")
	if not base_spec["boundary_node_ids"].has(observation_port_id):
		return Utils.failure("B0_7_OBSERVATION_PORT_NOT_BOUNDARY")
	var port_index: int = int(base_spec["boundary_node_ids"].find(observation_port_id))

	var compile_start := Time.get_ticks_usec()
	var base := GenericCompiler.compile(base_spec)
	var base_compile_us := Time.get_ticks_usec() - compile_start
	if String(base.get("status", "")) != "BAKE_READY":
		return Utils.failure("B0_7_BASE_BAKE_NOT_READY", {"status": base.get("status", ""), "reason": base.get("reason", "")})
	var successor_start := Time.get_ticks_usec()
	var successor := GenericCompiler.compile(successor_spec)
	var successor_compile_us := Time.get_ticks_usec() - successor_start
	if String(successor.get("status", "")) != "BAKE_READY":
		return Utils.failure("B0_7_SUCCESSOR_BAKE_NOT_READY", {"status": successor.get("status", ""), "reason": successor.get("reason", "")})

	var base_result: Dictionary = base["compile_result"]
	var successor_result: Dictionary = successor["compile_result"]
	var base_descriptor: Dictionary = base_result["diagnostics"]["reduction"]
	var successor_descriptor: Dictionary = successor_result["diagnostics"]["reduction"]
	var base_system: Dictionary = base["context"]["linear_system"]
	var successor_system: Dictionary = successor["context"]["linear_system"]
	var max_flow_error := 0.0
	var max_power_error := 0.0
	var max_successor_flow_error := 0.0
	var max_successor_power_error := 0.0
	var base_observation_flow := 0.0
	var successor_observation_flow := 0.0
	var full_eval_us := 0
	var reduced_eval_us := 0
	var first := true
	for excitation in excitations:
		if typeof(excitation) != TYPE_ARRAY or excitation.size() != base_spec["boundary_node_ids"].size():
			return Utils.failure("B0_7_INVALID_EXCITATION")
		var t0 := Time.get_ticks_usec()
		var full_base := Reducer.evaluate_full(base_system, excitation, GenericCompiler.PIVOT_TOLERANCE)
		var full_successor := Reducer.evaluate_full(successor_system, excitation, GenericCompiler.PIVOT_TOLERANCE)
		full_eval_us += Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var reduced_base := Reducer.evaluate_reduced(base_descriptor, excitation)
		var reduced_successor := Reducer.evaluate_reduced(successor_descriptor, excitation)
		reduced_eval_us += Time.get_ticks_usec() - t0
		if not bool(full_base.get("success", false)) or not bool(full_successor.get("success", false)) or not bool(reduced_base.get("success", false)) or not bool(reduced_successor.get("success", false)):
			return Utils.failure("B0_7_REFERENCE_OR_REDUCED_EVALUATION_FAILED")
		max_flow_error = maxf(max_flow_error, LinearAlgebra.max_abs_delta(full_base["details"]["boundary_flow"], reduced_base["details"]["boundary_flow"]))
		max_power_error = maxf(max_power_error, absf(float(full_base["details"]["boundary_power"]) - float(reduced_base["details"]["boundary_power"])))
		max_successor_flow_error = maxf(max_successor_flow_error, LinearAlgebra.max_abs_delta(full_successor["details"]["boundary_flow"], reduced_successor["details"]["boundary_flow"]))
		max_successor_power_error = maxf(max_successor_power_error, absf(float(full_successor["details"]["boundary_power"]) - float(reduced_successor["details"]["boundary_power"])))
		if first:
			base_observation_flow = float(full_base["details"]["boundary_flow"][port_index])
			successor_observation_flow = float(full_successor["details"]["boundary_flow"][port_index])
			first = false

	if max_flow_error > GenericCompiler.FLOW_ERROR_LIMIT or max_successor_flow_error > GenericCompiler.FLOW_ERROR_LIMIT:
		return Utils.failure("B0_7_FLOW_EQUIVALENCE_EXCEEDED", {"base": max_flow_error, "successor": max_successor_flow_error})
	if max_power_error > GenericCompiler.POWER_ERROR_LIMIT or max_successor_power_error > GenericCompiler.POWER_ERROR_LIMIT:
		return Utils.failure("B0_7_POWER_EQUIVALENCE_EXCEEDED", {"base": max_power_error, "successor": max_successor_power_error})

	var old_artifact: Dictionary = base_result["artifact"]
	var invalidation := BakeInvalidation.create(
		"invalidation/b0-7-%s-r%03d" % [_slug(String(base_spec["machine_id"])), int(successor_spec["revision"])],
		String(old_artifact["artifact_id"]),
		"SOURCE_REVISION",
		String(old_artifact["source_binding"]["frontier_hash"]),
		String(successor_result["artifact"]["source_binding"]["frontier_hash"]),
		int(successor_spec["revision"])
	)
	if invalidation.is_empty():
		return Utils.failure("B0_7_INVALIDATION_BUILD_FAILED")
	var stale_live := GenericCompiler.live_context(successor["context"], [invalidation])
	var stale_attempt := Runtime.execute(old_artifact, base_descriptor, stale_live, excitations[0])
	if String(stale_attempt.get("error_code", "")) != "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN":
		return Utils.failure("B0_7_STALE_ARTIFACT_NOT_FENCED", {"error": stale_attempt.get("error_code", "")})

	var fresh_artifact: Dictionary = successor_result["artifact"]
	var fresh_live := GenericCompiler.live_context(successor["context"])
	var runtime_result := Runtime.execute(fresh_artifact, successor_descriptor, fresh_live, excitations[0])
	if not bool(runtime_result.get("success", false)):
		return Utils.failure("B0_7_FRESH_REBAKE_RUNTIME_FAILED", {"error": runtime_result.get("error_code", "")})

	var successor_again := GenericCompiler.compile(successor_spec)
	if String(successor_again.get("status", "")) != "BAKE_READY":
		return Utils.failure("B0_7_RECOMPILE_FAILED")
	if String(successor_again["compile_result"]["artifact"]["checksum"]) != String(fresh_artifact["checksum"]):
		return Utils.failure("B0_7_REBUILD_ARTIFACT_NONDETERMINISTIC")
	if String(successor_again["compile_result"]["diagnostics"]["reduction"]["checksum"]) != String(successor_descriptor["checksum"]):
		return Utils.failure("B0_7_REBUILD_DESCRIPTOR_NONDETERMINISTIC")

	var result := {
		"schema": RESULT_SCHEMA,
		"machine_id": base_spec["machine_id"],
		"base_revision": base_spec["revision"],
		"successor_revision": successor_spec["revision"],
		"failure_event_id": failure_event_id,
		"failed_edge_ids": Utils.sorted_strings(failed_edge_ids),
		"full_equation_count": base_descriptor["full_equation_count"],
		"reduced_equation_count": base_descriptor["reduced_equation_count"],
		"runtime_work_ratio": base_descriptor["runtime_work_ratio"],
		"base_max_flow_error": max_flow_error,
		"base_max_power_error": max_power_error,
		"successor_max_flow_error": max_successor_flow_error,
		"successor_max_power_error": max_successor_power_error,
		"observation_port_id": observation_port_id,
		"base_observation_flow": base_observation_flow,
		"successor_observation_flow": successor_observation_flow,
		"observation_flow_delta": absf(base_observation_flow - successor_observation_flow),
		"base_active_edges": Graph.active_edge_ids(base_spec).size(),
		"successor_active_edges": Graph.active_edge_ids(successor_spec).size(),
		"stale_error": String(stale_attempt.get("error_code", "")),
		"base_compile_us_observed": base_compile_us,
		"successor_compile_us_observed": successor_compile_us,
		"full_eval_us_observed": full_eval_us,
		"reduced_eval_us_observed": reduced_eval_us,
		"artifact_hash": fresh_artifact["checksum"],
		"descriptor_hash": successor_descriptor["checksum"],
		"result_hash": "",
	}
	result["result_hash"] = Utils.canonical_hash(_deterministic_result_payload(result))
	return Utils.success(result)

static func validate_successor(
	base_spec: Dictionary,
	successor_spec: Dictionary,
	failure_event_id: String,
	failed_edge_ids: Array
) -> Dictionary:
	var checked := Graph.validate(base_spec)
	if not bool(checked.get("success", false)):
		return checked
	checked = Graph.validate(successor_spec)
	if not bool(checked.get("success", false)):
		return checked
	if String(base_spec["machine_id"]) != String(successor_spec["machine_id"]):
		return Utils.failure("B0_7_SUCCESSOR_MACHINE_ID_MISMATCH")
	if int(successor_spec["revision"]) != int(base_spec["revision"]) + 1:
		return Utils.failure("B0_7_SUCCESSOR_REVISION_MISMATCH")
	if not Utils.is_canonical_id(failure_event_id, 2):
		return Utils.failure("B0_7_FAILURE_EVENT_ID_INVALID")
	if base_spec["applied_event_ids"].has(failure_event_id) or not successor_spec["applied_event_ids"].has(failure_event_id):
		return Utils.failure("B0_7_EVENT_LEDGER_MISMATCH")
	if successor_spec["applied_event_ids"].size() != base_spec["applied_event_ids"].size() + 1:
		return Utils.failure("B0_7_EVENT_NOT_EXACTLY_ONCE")
	var expected_events: Array = base_spec["applied_event_ids"].duplicate()
	expected_events.append(failure_event_id)
	expected_events.sort()
	if successor_spec["applied_event_ids"] != expected_events:
		return Utils.failure("B0_7_EVENT_HISTORY_NOT_PRESERVED")
	if base_spec["boundary_node_ids"] != successor_spec["boundary_node_ids"] or base_spec["internal_node_ids"] != successor_spec["internal_node_ids"]:
		return Utils.failure("B0_7_SUCCESSOR_NODE_SET_CHANGED")
	for raw_id in failed_edge_ids:
		if not Utils.is_canonical_id(raw_id, 2):
			return Utils.failure("B0_7_FAILURE_EDGE_ID_INVALID")
	var expected_failed := Utils.sorted_strings(failed_edge_ids)
	if expected_failed.is_empty():
		return Utils.failure("B0_7_FAILURE_EDGE_SET_EMPTY")
	if not Utils.validate_sorted_unique_strings(expected_failed, false).success:
		return Utils.failure("B0_7_FAILURE_EDGE_SET_DUPLICATE")
	if base_spec["edges"].size() != successor_spec["edges"].size():
		return Utils.failure("B0_7_SUCCESSOR_EDGE_COUNT_CHANGED")
	var actual_failed: Array = []
	for index in range(base_spec["edges"].size()):
		var edge: Dictionary = base_spec["edges"][index]
		var edge_id := String(edge["edge_id"])
		var next: Dictionary = successor_spec["edges"][index]
		if next.is_empty():
			return Utils.failure("B0_7_SUCCESSOR_EDGE_MISSING", {"edge_id": edge_id})
		for field in ["edge_id", "node_a", "node_b", "conductance"]:
			if edge[field] != next[field]:
				return Utils.failure("B0_7_SUCCESSOR_EDGE_METADATA_CHANGED", {"edge_id": edge_id, "field": field})
		if bool(edge["active"]) and not bool(next["active"]):
			actual_failed.append(edge_id)
		elif bool(edge["active"]) != bool(next["active"]):
			return Utils.failure("B0_7_SUCCESSOR_ILLEGAL_EDGE_REACTIVATION", {"edge_id": edge_id})
	actual_failed.sort()
	if actual_failed != expected_failed:
		return Utils.failure("B0_7_SUCCESSOR_FAILURE_SET_MISMATCH", {"expected": expected_failed, "actual": actual_failed})
	return Utils.success({"failed_edge_ids": actual_failed})

static func expect_no_safe_bake(spec: Dictionary) -> Dictionary:
	var compiled := GenericCompiler.compile(spec)
	if String(compiled.get("status", "")) != "NO_SAFE_BAKE":
		return Utils.failure("B0_7_UNSAFE_CASE_DID_NOT_FAIL_CLOSED", {"status": compiled.get("status", ""), "reason": compiled.get("reason", "")})
	return Utils.success({"reason": compiled.get("reason", ""), "error_code": compiled.get("error_code", "")})

static func _deterministic_result_payload(result: Dictionary) -> Dictionary:
	var payload := result.duplicate(true)
	for field in ["base_compile_us_observed", "successor_compile_us_observed", "full_eval_us_observed", "reduced_eval_us_observed", "result_hash"]:
		payload.erase(field)
	return payload

static func _slug(machine_id: String) -> String:
	return machine_id.replace("/", "-").replace("_", "-").to_lower()
