class_name FabricConstruct0LifecycleRuntime
extends RefCounted

# Tangible adapter over the exact research subjects already used to close
# BRIDGE-1 and B0.2-D/E. No bake/unbake physics is implemented here.
const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const LocalCompiler = preload("res://scripts/research/fabric_bake0/structural_local_unbake_compiler_v1.gd")
const LocalRuntime = preload("res://scripts/research/fabric_bake0/structural_local_unbake_runtime_v1.gd")
const TopologyCompiler = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_compiler_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")

# Exact verification subjects. This lab intentionally consumes them rather
# than maintaining a second copy of the 500-part topology.
const ABFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")
const CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")
const DFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_d_fixture.gd")
const EFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_e_fixture.gd")
const BridgeFixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge1_fixture.gd")

const REPRESENTATIONS: Array[String] = ["AUTO", "FULL", "BAKED"]
const FULL_DOF_PER_PART := 13
const REDUCED_RIGID_DOF := 13
const ANCHOR_TOLERANCE := 1.0e-9

var _initial: Dictionary = {}
var _bundle: Dictionary = {}
var _reduced_state: Dictionary = {}
var _state: Dictionary = {}
var _events: Array = []
var _applied_invalidation_ids: Array = []

func setup() -> Dictionary:
	_initial = BridgeFixture.build(0)
	_bundle = Lifecycle.compile(_initial["view_request"])
	if not bool(_bundle.get("success", false)):
		return _failure("C0_4_BRIDGE1_COMPILE_FAILED", {"cause": _bundle})
	_reduced_state = BridgeFixture.reduced_state()
	_events = []
	_applied_invalidation_ids = []
	var switched := switch_representation("AUTO")
	if not bool(switched.get("success", false)):
		return switched
	return {"success": true, "state": state()}

func state() -> Dictionary:
	return _state.duplicate(true)

func switch_representation(mode: String) -> Dictionary:
	if not REPRESENTATIONS.has(mode):
		return _failure("C0_4_UNKNOWN_REPRESENTATION")
	if _bundle.is_empty():
		var ready := setup()
		if not bool(ready.get("success", false)):
			return ready
	if mode == "FULL":
		return _enter_full("FORCE_FULL")
	if mode == "BAKED":
		var baked := _enter_baked("FORCE_BAKED")
		if not bool(baked.get("success", false)):
			_state = _representation_failure_state("BAKED", baked)
			return baked
		return baked
	var auto_baked := _enter_baked("AUTO")
	if bool(auto_baked.get("success", false)):
		_state["requested_representation"] = "AUTO"
		return {"success": true, "state": state()}
	var fallback := _enter_full("AUTO_FULL_FALLBACK")
	if bool(fallback.get("success", false)):
		_state["requested_representation"] = "AUTO"
		_state["auto_fallback_reason"] = String(auto_baked.get("error_code", "UNKNOWN"))
	return fallback

func probe_no_safe_bake() -> Dictionary:
	var fixture := DFixture.build(false)
	if not bool(fixture.get("success", false)):
		return _failure("C0_4_NO_SAFE_PROBE_FIXTURE_FAILED", {"cause": fixture})
	var request: Dictionary = fixture["request"].duplicate(true)
	request["max_full_parts"] = 19
	var result := LocalCompiler.compile(request)
	if bool(result.get("success", false)):
		return _failure("C0_4_NO_SAFE_PROBE_UNEXPECTEDLY_ACCEPTED")
	var code := String(result.get("error_code", ""))
	if code != "NO_SAFE_BOUNDED_LOCAL_UNBAKE_LIMIT":
		return _failure("C0_4_NO_SAFE_PROBE_WRONG_CODE", {"actual": code})
	_events.append({
		"stage": "C0.4",
		"event": "NO_SAFE_BAKE",
		"detail": code,
	})
	_state["no_safe_bake"] = {
		"visible": true,
		"reason": code,
		"policy": "FAIL_CLOSED_OR_FULL",
	}
	_state["events"] = _events.duplicate(true)
	return {"success": true, "state": state(), "reason": code}

func mutate_and_rebuild(force_full_fallback: bool = false) -> Dictionary:
	if _bundle.is_empty():
		var ready := setup()
		if not bool(ready.get("success", false)):
			return ready
	var changed := BridgeFixture.build(1)
	var invalidation_id := "invalidation/construct0-c0-5-mass-change"
	var invalidation := BridgeFixture.invalidation(_initial, changed, invalidation_id)
	var old_artifact_hash := String(_bundle["artifact"]["checksum"])
	var old_generation := int(_bundle["build_generation"])
	var result := Lifecycle.rebuild_same_topology(
		_bundle,
		_reduced_state,
		invalidation,
		changed["view_request"],
		{"force_full_fallback": force_full_fallback},
		_applied_invalidation_ids
	)
	if not bool(result.get("success", false)):
		return _failure("C0_5_REBUILD_FAILED", {"cause": result})
	_applied_invalidation_ids.append(invalidation_id)
	var metrics := {
		"old_artifact_hash": old_artifact_hash,
		"old_generation": old_generation,
		"stale_rejection_code": String(result["stale_rejection_code"]),
		"full_state_count": Dictionary(result["full_states"]).size(),
		"full_state_hash": String(result["full_state_hash"]),
		"contact_state_policy": String(result["contact_state_policy"]),
		"accepted_previous_contact_impulse": bool(result["accepted_previous_contact_impulse"]),
		"force_full_fallback": force_full_fallback,
	}
	if String(result["status"]) == Lifecycle.STATUS_REBUILT:
		metrics["new_artifact_hash"] = String(result["rebuilt_bundle"]["artifact"]["checksum"])
		metrics["new_generation"] = int(result["rebuilt_bundle"]["build_generation"])
		metrics["handoff_error"] = float(result["handoff_error"])
		metrics["fresh_gate_artifact_id"] = String(result["fresh_execution_gate"]["artifact_id"])
		_bundle = result["rebuilt_bundle"]
		_reduced_state = result["rebuilt_reduced_state"]
		_initial = changed
	else:
		metrics["new_artifact_hash"] = ""
		metrics["new_generation"] = old_generation
		metrics["handoff_error"] = 0.0
	_events.append({
		"stage": "C0.5",
		"event": "SOURCE_MUTATION_REBUILD",
		"status": String(result["status"]),
	})
	_state = {
		"stage": "C0.5",
		"requested_representation": "AUTO",
		"effective_representation": "BAKED" if String(result["status"]) == Lifecycle.STATUS_REBUILT else "FULL",
		"status": String(result["status"]),
		"metrics": metrics,
		"events": _events.duplicate(true),
	}
	return {"success": true, "state": state(), "result": result}

func trigger_local_unbake(load_magnitude: float = 30.0) -> Dictionary:
	var fixture := DFixture.build(false)
	if not bool(fixture.get("success", false)):
		return _failure("C0_6_D_FIXTURE_FAILED", {"cause": fixture})
	var compiled := LocalCompiler.compile(fixture["request"])
	if not bool(compiled.get("success", false)):
		return _failure("C0_6_LOCAL_PLAN_FAILED", {"cause": compiled})
	var reduced := ABFixture.reduced_state()
	var context := CFixture.runtime_context(fixture["c_fixture"], load_magnitude, true)
	var result := LocalRuntime.execute(
		compiled["plan"],
		fixture["c_fixture"]["aggregate"]["descriptor"],
		fixture["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["c_compiled"]["guard_field"],
		reduced,
		context
	)
	if not bool(result.get("success", false)):
		return _failure("C0_6_LOCAL_UNBAKE_FAILED", {"cause": result})
	_events.append({
		"stage": "C0.6",
		"event": "LOCAL_UNBAKE",
		"region": String(result["target_region_id"]),
	})
	_state = {
		"stage": "C0.6",
		"status": String(result["status"]),
		"requested_representation": "AUTO",
		"effective_representation": "MIXED_FULL_BAKED",
		"metrics": {
			"target_region_id": String(result["target_region_id"]),
			"full_part_count": int(result["diagnostics"]["full_part_count"]),
			"retained_part_count": int(result["diagnostics"]["retained_part_count"]),
			"retained_component_count": int(result["diagnostics"]["retained_component_count"]),
			"cut_interface_count": int(result["diagnostics"]["cut_interface_count"]),
			"full_dof": int(result["diagnostics"]["full_dof"]),
			"mixed_dof": int(result["diagnostics"]["mixed_dof"]),
			"preserved_reduction_ratio": float(result["diagnostics"]["preserved_reduction_ratio"]),
			"unbaked_fraction": float(result["diagnostics"]["full_part_count"]) / 500.0,
			"mass_error": float(result["diagnostics"]["mass_error"]),
			"linear_momentum_error": float(result["diagnostics"]["linear_momentum_error"]),
			"angular_momentum_error": float(result["diagnostics"]["angular_momentum_error"]),
			"max_interface_position_error": float(result["diagnostics"]["max_interface_position_error"]),
			"max_interface_velocity_error": float(result["diagnostics"]["max_interface_velocity_error"]),
			"next_required_stage": String(result["diagnostics"]["next_required_stage"]),
		},
		"events": _events.duplicate(true),
	}
	return {"success": true, "state": state(), "result": result, "fixture": fixture, "compiled": compiled}

func break_split_and_rebake() -> Dictionary:
	var fixture := EFixture.build(false)
	if not bool(fixture.get("success", false)):
		return _failure("C0_6_E_FIXTURE_FAILED", {"cause": fixture})
	var compiled := TopologyCompiler.compile(fixture["request"])
	if not bool(compiled.get("success", false)):
		return _failure("C0_6_TOPOLOGY_COMPILE_FAILED", {"cause": compiled})
	var transaction: Dictionary = compiled["transaction"]
	var reduced := ABFixture.reduced_state()
	var guard_context := CFixture.runtime_context(fixture["d_fixture"]["c_fixture"], 30.0, true)
	var result := TopologyRuntime.execute(
		transaction,
		fixture["d_compiled"]["plan"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["descriptor"],
		fixture["d_fixture"]["c_fixture"]["aggregate"]["reconstruction_mapping"],
		fixture["d_fixture"]["c_compiled"]["guard_field"],
		reduced,
		guard_context,
		fixture["current_frontier"],
		fixture["authority"],
		fixture["dependencies"],
		[]
	)
	if not bool(result.get("success", false)):
		return _failure("C0_6_TOPOLOGY_EXECUTE_FAILED", {"cause": result})
	_events.append({
		"stage": "C0.6",
		"event": "TOPOLOGY_SPLIT_REBAKE",
		"event_id": String(result["event_commit"]["event_id"]),
	})
	_state = {
		"stage": "C0.6",
		"status": String(result["status"]),
		"requested_representation": "AUTO",
		"effective_representation": "REBAKED_COMPONENTS",
		"metrics": {
			"event_id": String(result["event_commit"]["event_id"]),
			"event_state": String(result["event_commit"]["state"]),
			"split_component_count": int(result["diagnostics"]["split_component_count"]),
			"invalidated_reduced_piece_count": int(result["diagnostics"]["invalidated_reduced_piece_count"]),
			"executable_artifact_count": int(result["diagnostics"]["executable_physical_bake_artifact_count"]),
			"full_dof": int(result["diagnostics"]["full_dof"]),
			"mixed_before_event_dof": int(result["diagnostics"]["mixed_before_event_dof"]),
			"rebaked_dof": int(result["diagnostics"]["rebaked_dof"]),
			"post_split_reduction_ratio": float(result["diagnostics"]["post_split_reduction_ratio"]),
			"mass_error": float(result["diagnostics"]["mass_error"]),
			"linear_momentum_error": float(result["diagnostics"]["linear_momentum_error"]),
			"angular_momentum_error": float(result["diagnostics"]["angular_momentum_error"]),
			"max_state_handoff_error": float(result["diagnostics"]["max_state_handoff_error"]),
			"physical_bake_artifact_emitted": bool(result["diagnostics"]["physical_bake_artifact_emitted"]),
		},
		"events": _events.duplicate(true),
	}
	return {"success": true, "state": state(), "result": result, "transaction": transaction}

func reset() -> Dictionary:
	return setup()

func _enter_full(reason: String) -> Dictionary:
	var reconstructed := Reconstruction.reconstruct(
		_bundle["aggregate"]["reconstruction_mapping"],
		_reduced_state
	)
	if not bool(reconstructed.get("success", false)):
		return _failure("C0_4_FULL_RECONSTRUCTION_FAILED", {"cause": reconstructed})
	var full_states: Dictionary = reconstructed["details"]["full_states"]
	var anchor_error := _compare_anchors(full_states)
	_state = {
		"stage": "C0.4",
		"requested_representation": "FULL" if reason == "FORCE_FULL" else "AUTO",
		"effective_representation": "FULL",
		"status": "FULL_RECONSTRUCTED",
		"metrics": _representation_metrics(full_states.size(), FULL_DOF_PER_PART * full_states.size(), anchor_error),
		"events": _events.duplicate(true),
	}
	return {"success": true, "state": state()}

func _enter_baked(reason: String) -> Dictionary:
	var executed := Lifecycle.execute(_bundle, _reduced_state)
	if not bool(executed.get("success", false)):
		return executed
	var reconstructed := Reconstruction.reconstruct(
		_bundle["aggregate"]["reconstruction_mapping"],
		_reduced_state
	)
	if not bool(reconstructed.get("success", false)):
		return reconstructed
	var anchor_error := _compare_executed_anchors(Dictionary(reconstructed["details"]["full_states"]), executed["anchors"])
	var metrics := _representation_metrics(
		int(_bundle["aggregate"]["descriptor"]["part_count"]),
		REDUCED_RIGID_DOF,
		anchor_error
	)
	metrics["artifact_id"] = String(executed["artifact_id"])
	metrics["artifact_hash"] = String(executed["artifact_hash"])
	metrics["minimum_guard_margin"] = float(executed["gate"]["minimum_guard_margin"])
	metrics["minimum_safe_fidelity"] = String(executed["gate"]["minimum_safe_fidelity"])
	_state = {
		"stage": "C0.4",
		"requested_representation": "BAKED" if reason == "FORCE_BAKED" else "AUTO",
		"effective_representation": "BAKED",
		"status": String(executed["status"]),
		"metrics": metrics,
		"events": _events.duplicate(true),
	}
	return {"success": true, "state": state()}

func _representation_metrics(part_count: int, current_dof: int, anchor_error: float) -> Dictionary:
	var full_dof := part_count * FULL_DOF_PER_PART
	return {
		"canonical_part_count": part_count,
		"full_dof": full_dof,
		"current_dof": current_dof,
		"reduction_ratio": float(full_dof) / float(maxi(1, current_dof)),
		"boundary_anchor_error": anchor_error,
		"source_frontier_hash": String(_bundle["source_view"]["frontier"]["frontier_hash"]),
		"build_generation": int(_bundle["build_generation"]),
	}

func _compare_anchors(full_states: Dictionary) -> float:
	var baked := Lifecycle.execute(_bundle, _reduced_state)
	if not bool(baked.get("success", false)):
		return INF
	return _compare_executed_anchors(full_states, baked["anchors"])

func _compare_executed_anchors(full_states: Dictionary, executed_anchors: Array) -> float:
	var expected_by_id := {}
	for anchor_any in _initial["construction_payload"]["boundary_anchors"]:
		var anchor: Dictionary = anchor_any
		var part_id := String(anchor["part_id"])
		if not full_states.has(part_id):
			return INF
		var part: Dictionary = full_states[part_id]
		var q := _quat(part["orientation"])
		var local := _vec3(anchor["position_local"])
		var offset := q * local
		expected_by_id[String(anchor["anchor_id"])] = {
			"position": _vec3(part["position"]) + offset,
			"linear_velocity": _vec3(part["linear_velocity"]) + _vec3(part["angular_velocity"]).cross(offset),
		}
	var max_error := 0.0
	for entry_any in executed_anchors:
		var entry: Dictionary = entry_any
		var anchor_id := String(entry["anchor_id"])
		if not expected_by_id.has(anchor_id):
			return INF
		var actual: Dictionary = entry["state"]
		var expected: Dictionary = expected_by_id[anchor_id]
		max_error = maxf(max_error, _vec3(actual["position"]).distance_to(expected["position"]))
		max_error = maxf(max_error, _vec3(actual["linear_velocity"]).distance_to(expected["linear_velocity"]))
	return max_error

func _representation_failure_state(requested: String, failure: Dictionary) -> Dictionary:
	return {
		"stage": "C0.4",
		"requested_representation": requested,
		"effective_representation": "UNAVAILABLE",
		"status": "NO_SAFE_BAKE",
		"metrics": {
			"error_code": String(failure.get("error_code", "")),
		},
		"events": _events.duplicate(true),
	}

func _vec3(value) -> Vector3:
	if value is Vector3:
		return value
	var a: Array = value
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _quat(value) -> Quaternion:
	if value is Quaternion:
		return value.normalized()
	var a: Array = value
	return Quaternion(float(a[0]), float(a[1]), float(a[2]), float(a[3])).normalized()

func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
