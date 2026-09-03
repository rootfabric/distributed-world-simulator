extends SceneTree

const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")

var _checks := 0
var _scale_summaries: Array = []

func _initialize() -> void:
	_test_50_full_floor()
	_test_100_bake_floor_and_safe_split_refusal()
	_test_full_lifecycle(500)
	_test_full_lifecycle(2000)
	print("FABRIC-BAKE COMPLEX0 Acceptance: PASS (%d assertions) scales=%s" % [_checks, str(_scale_summaries)])
	quit(0)

func _test_50_full_floor() -> void:
	var subject := Fixture.build(50)
	_check(bool(subject.get("success", false)))
	var parent := Lifecycle.compile(subject["view_request"], Fixture.lifecycle_options(subject))
	_check(bool(parent.get("success", false)))
	_check(String(parent.get("status", "")) == Lifecycle.STATUS_FULL)
	_check(String(parent.get("reason", "")) == "INSUFFICIENT_COMPLEXITY_REDUCTION")
	_check(not parent.has("artifact"))
	_scale_summaries.append({"parts": 50, "mode": "FULL_FLOOR", "safe_bake": false})

func _test_100_bake_floor_and_safe_split_refusal() -> void:
	var subject := Fixture.build(100)
	_check(bool(subject.get("success", false)))
	var parent := Lifecycle.compile(subject["view_request"], Fixture.lifecycle_options(subject))
	_check(bool(parent.get("success", false)))
	_check(String(parent.get("status", "")) == Lifecycle.STATUS_READY)
	_check(bool(Artifact.validate(parent["artifact"]).get("success", false)))
	var executed := Lifecycle.execute(parent, Fixture.reduced_state())
	_check(bool(executed.get("success", false)))
	_check(String(executed.get("status", "")) == "BRIDGE1_EXECUTED")

	var structural := Fixture.compile_structural(subject)
	_check(bool(structural["aggregate"].get("success", false)))
	_check(bool(structural["guard"].get("success", false)))
	_check(not bool(structural["local"].get("success", false)))
	_check(String(structural["local"].get("error_code", "")) == "NO_SAFE_BOUNDED_LOCAL_UNBAKE_RESIDUAL_TOO_SMALL")
	_scale_summaries.append({
		"parts": 100,
		"mode": "BAKE_READY",
		"split": "FULL_FALLBACK_REQUIRED",
		"reason": "POST_SPLIT_COMPONENT_BELOW_100",
	})

func _test_full_lifecycle(count: int) -> void:
	var subject := Fixture.build(count)
	_check(bool(subject.get("success", false)))
	var parent := Lifecycle.compile(subject["view_request"], Fixture.lifecycle_options(subject))
	_check(bool(parent.get("success", false)))
	_check(String(parent.get("status", "")) == Lifecycle.STATUS_READY)
	_check(bool(Artifact.validate(parent["artifact"]).get("success", false)))
	var reduced_state := Fixture.reduced_state()
	var parent_execution := Lifecycle.execute(parent, reduced_state)
	_check(bool(parent_execution.get("success", false)))

	var structural := Fixture.compile_structural(subject)
	_check(bool(structural.get("success", false)))
	_check(bool(structural["aggregate"].get("success", false)))
	_check(bool(structural["guard"].get("success", false)))
	_check(bool(structural["local"].get("success", false)))
	_check(int(structural["local"]["diagnostics"]["full_part_count"]) == Fixture.REGION_SIZE)
	_check(int(structural["local"]["diagnostics"]["retained_component_count"]) == 2)

	var guard_result := Fixture.evaluate_guard(subject, structural)
	_check(bool(guard_result.get("success", false)))
	_check(String(guard_result.get("status", "")) == "STRUCTURAL_REFINEMENT_REQUIRED")
	_check(guard_result["refinement_requests"].size() == 1)
	_check(String(guard_result["refinement_requests"][0]["mapped_source_region"]) == String(subject["target_region_id"]))
	_check(String(guard_result["refinement_requests"][0]["peak_bond_id"]) == String(subject["break_bond_id"]))

	var break_bundle := Fixture.make_break(subject, structural)
	_check(bool(break_bundle.get("success", false)))
	_check(not break_bundle["source_invalidation"].is_empty())
	var bake_invalidation := Fixture.make_bake_invalidation(parent, break_bundle)
	_check(bool(BakeInvalidation.validate(bake_invalidation).get("success", false)))
	_check(String(bake_invalidation["artifact_id"]) == String(parent["artifact"]["artifact_id"]))
	_check(String(bake_invalidation["reason"]) == "SOURCE_REVISION")

	var stale := Lifecycle.execute(parent, reduced_state, 0.0, [bake_invalidation])
	_check(not bool(stale.get("success", false)))
	_check(String(stale.get("error_code", "")) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN")

	var compiled := Fixture.compile_transaction(break_bundle)
	_check(bool(compiled.get("success", false)))
	_check(String(compiled.get("status", "")) == "STRUCTURAL_TOPOLOGY_REBAKE_TRANSACTION_READY")
	var transaction: Dictionary = compiled["transaction"]
	_check(transaction["invalidated_pieces"].size() == 3)
	_check(transaction["rebaked_components"].size() == 2)
	var component_sizes: Array = []
	for component in transaction["rebaked_components"]:
		component_sizes.append(component["part_ids"].size())
		_check(bool(Artifact.validate(component["physical_bake_artifact"]).get("success", false)))
	component_sizes.sort()
	var expected_sizes := [int(subject["break_index"]), count - int(subject["break_index"])]
	expected_sizes.sort()
	_check(component_sizes == expected_sizes)

	var deterministic := Fixture.compile_transaction(break_bundle)
	_check(bool(deterministic.get("success", false)))
	_check(String(deterministic["transaction"]["checksum"]) == String(transaction["checksum"]))

	var result := TopologyRuntime.execute(
		transaction,
		structural["local"]["plan"],
		structural["aggregate"]["descriptor"],
		structural["aggregate"]["reconstruction_mapping"],
		structural["guard"]["guard_field"],
		reduced_state,
		Fixture.guard_context(subject, structural),
		break_bundle["current_frontier"],
		break_bundle["current_authority"],
		break_bundle["dependencies"],
		[]
	)
	_check(bool(result.get("success", false)))
	_check(String(result.get("status", "")) == TopologyRuntime.READY)
	_check(String(result["event_commit"]["state"]) == "APPLIED")
	_check(String(result["event_commit"]["event_id"]) == String(break_bundle["event"]["event_id"]))
	_check(int(result["diagnostics"]["split_component_count"]) == 2)
	_check(int(result["diagnostics"]["invalidated_reduced_piece_count"]) == 3)
	_check(int(result["diagnostics"]["executable_physical_bake_artifact_count"]) == 2)
	_check(int(result["diagnostics"]["full_dof"]) == count * 13)
	_check(int(result["diagnostics"]["mixed_before_event_dof"]) == Fixture.REGION_SIZE * 13 + 2 * 13)
	_check(int(result["diagnostics"]["rebaked_dof"]) == 2 * 13)
	_check(absf(float(result["diagnostics"]["post_split_reduction_ratio"]) - float(count) / 2.0) <= 1.0e-12)
	_check(float(result["diagnostics"]["mass_error"]) <= Fixture.CONSERVATION_TOLERANCE)
	_check(float(result["diagnostics"]["linear_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE)
	_check(float(result["diagnostics"]["angular_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE)
	_check(float(result["diagnostics"]["max_state_handoff_error"]) <= Fixture.CONTINUITY_TOLERANCE)

	_verify_reconstruction(count, transaction, result, structural, reduced_state)

	var replay := TopologyRuntime.execute(
		transaction,
		structural["local"]["plan"],
		structural["aggregate"]["descriptor"],
		structural["aggregate"]["reconstruction_mapping"],
		structural["guard"]["guard_field"],
		reduced_state,
		Fixture.guard_context(subject, structural),
		break_bundle["current_frontier"],
		break_bundle["current_authority"],
		break_bundle["dependencies"],
		[String(break_bundle["event"]["event_id"])]
	)
	_check(not bool(replay.get("success", false)))
	_check(String(replay.get("error_code", "")) == "STRUCTURAL_TOPOLOGY_EVENT_ALREADY_APPLIED")

	_scale_summaries.append({
		"parts": count,
		"mode": "BAKE_BREAK_SPLIT_REBAKE",
		"active_full_at_event": Fixture.REGION_SIZE,
		"fragments": component_sizes,
		"post_split_reduction_ratio": float(result["diagnostics"]["post_split_reduction_ratio"]),
	})

func _verify_reconstruction(count: int, transaction: Dictionary, result: Dictionary, structural: Dictionary, reduced_state: Dictionary) -> void:
	var parent_full := Reconstruction.reconstruct(structural["aggregate"]["reconstruction_mapping"], reduced_state)
	_check(bool(parent_full.get("success", false)))
	var expected: Dictionary = parent_full["details"]["full_states"]
	var state_by_component: Dictionary = {}
	for entry in result["rebaked_component_states"]:
		state_by_component[String(entry["component_id"])] = entry
	var rebuilt_parts: Dictionary = {}
	for component in transaction["rebaked_components"]:
		var component_id := String(component["component_id"])
		_check(state_by_component.has(component_id))
		var rebuilt := Reconstruction.reconstruct(
			component["reconstruction_mapping"],
			state_by_component[component_id]["reduced_state"]
		)
		_check(bool(rebuilt.get("success", false)))
		for part_id in component["part_ids"]:
			var key := String(part_id)
			_check(not rebuilt_parts.has(key))
			rebuilt_parts[key] = true
			_check(_state_error(rebuilt["details"]["full_states"][key], expected[key]) <= Fixture.CONTINUITY_TOLERANCE)
	_check(rebuilt_parts.size() == count)

func _state_error(left: Dictionary, right: Dictionary) -> float:
	return maxf(
		_vec3(left["position"]).distance_to(_vec3(right["position"])),
		maxf(
			_vec3(left["linear_velocity"]).distance_to(_vec3(right["linear_velocity"])),
			maxf(
				_vec3(left["angular_velocity"]).distance_to(_vec3(right["angular_velocity"])),
				1.0 - absf(_quat(left["orientation"]).dot(_quat(right["orientation"])))
			)
		)
	)

func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

func _check(condition: bool) -> void:
	assert(condition)
	_checks += 1
