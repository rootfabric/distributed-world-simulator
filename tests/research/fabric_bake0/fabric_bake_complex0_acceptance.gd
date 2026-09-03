extends SceneTree

const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")

var _checks := 0
var _failed := false
var _scale_summaries: Array = []

func _initialize() -> void:
	var selected := OS.get_environment("COMPLEX0_SCALE").strip_edges()
	if selected.is_empty():
		_run_scale(50)
		if not _failed:
			_run_scale(100)
		if not _failed:
			_run_scale(500)
		if not _failed:
			_run_scale(2000)
		_finish()
		return
	if not selected.is_valid_int():
		_require(false, "invalid COMPLEX0_SCALE", {"value": selected})
		_finish()
		return
	_run_scale(int(selected))
	_finish()

func _run_scale(count: int) -> void:
	print("COMPLEX0 TRACE: scale=%d begin" % count)
	match count:
		50:
			_test_50_full_floor()
		100:
			_test_100_bake_floor_and_safe_split_refusal()
		500, 2000:
			_test_full_lifecycle(count)
		_:
			_require(false, "unsupported COMPLEX0 scale", {"scale": count, "supported": [50, 100, 500, 2000]})
	print("COMPLEX0 TRACE: scale=%d end" % count)

func _finish() -> void:
	if _failed:
		printerr("FABRIC-BAKE COMPLEX0 Acceptance: FAIL (%d successful assertions) scales=%s" % [_checks, str(_scale_summaries)])
		quit(1)
		return
	print("FABRIC-BAKE COMPLEX0 Acceptance: PASS (%d assertions) scales=%s" % [_checks, str(_scale_summaries)])
	quit(0)

func _test_50_full_floor() -> void:
	var subject := Fixture.build(50)
	if not _require(bool(subject.get("success", false)), "50 subject build", subject):
		return
	var parent := Lifecycle.compile(subject["view_request"], Fixture.lifecycle_options(subject))
	if not _require(bool(parent.get("success", false)), "50 lifecycle compile", parent):
		return
	if not _require(String(parent.get("status", "")) == Lifecycle.STATUS_FULL, "50 remains FULL", parent):
		return
	if not _require(String(parent.get("reason", "")) == "INSUFFICIENT_COMPLEXITY_REDUCTION", "50 full reason", parent):
		return
	if not _require(not parent.has("artifact"), "50 must not fabricate bake artifact", parent):
		return
	_scale_summaries.append({"parts": 50, "mode": "FULL_FLOOR", "safe_bake": false})

func _test_100_bake_floor_and_safe_split_refusal() -> void:
	var subject := Fixture.build(100)
	if not _require(bool(subject.get("success", false)), "100 subject build", subject):
		return
	var parent := Lifecycle.compile(subject["view_request"], Fixture.lifecycle_options(subject))
	if not _require(bool(parent.get("success", false)), "100 lifecycle compile", parent):
		return
	if not _require(String(parent.get("status", "")) == Lifecycle.STATUS_READY, "100 parent BAKE_READY", parent):
		return
	if not _require(parent.has("artifact"), "100 parent artifact present", parent):
		return
	if not _require(bool(Artifact.validate(parent["artifact"]).get("success", false)), "100 parent artifact validates", parent["artifact"]):
		return
	var executed := Lifecycle.execute(parent, Fixture.reduced_state())
	if not _require(bool(executed.get("success", false)), "100 parent executes", executed):
		return
	if not _require(String(executed.get("status", "")) == "BRIDGE1_EXECUTED", "100 execution status", executed):
		return

	var structural := Fixture.compile_structural(subject)
	if not _require(bool(structural["aggregate"].get("success", false)), "100 aggregate compile", structural["aggregate"]):
		return
	if not _require(bool(structural["guard"].get("success", false)), "100 guard compile", structural["guard"]):
		return
	if not _require(not bool(structural["local"].get("success", false)), "100 local split must fail closed", structural["local"]):
		return
	if not _require(String(structural["local"].get("error_code", "")) == "NO_SAFE_BOUNDED_LOCAL_UNBAKE_RESIDUAL_TOO_SMALL", "100 split refusal reason", structural["local"]):
		return
	_scale_summaries.append({
		"parts": 100,
		"mode": "BAKE_READY",
		"split": "FULL_FALLBACK_REQUIRED",
		"reason": "POST_SPLIT_COMPONENT_BELOW_100",
	})

func _test_full_lifecycle(count: int) -> void:
	var subject := Fixture.build(count)
	if not _require(bool(subject.get("success", false)), "%d subject build" % count, subject):
		return
	var parent := Lifecycle.compile(subject["view_request"], Fixture.lifecycle_options(subject))
	if not _require(bool(parent.get("success", false)), "%d lifecycle compile" % count, parent):
		return
	if not _require(String(parent.get("status", "")) == Lifecycle.STATUS_READY, "%d parent BAKE_READY" % count, parent):
		return
	if not _require(parent.has("artifact"), "%d parent artifact present" % count, parent):
		return
	if not _require(bool(Artifact.validate(parent["artifact"]).get("success", false)), "%d parent artifact validates" % count, parent["artifact"]):
		return
	var reduced_state := Fixture.reduced_state()
	var parent_execution := Lifecycle.execute(parent, reduced_state)
	if not _require(bool(parent_execution.get("success", false)), "%d parent executes" % count, parent_execution):
		return

	var structural := Fixture.compile_structural(subject)
	if not _require(bool(structural.get("success", false)), "%d structural pipeline" % count, structural):
		return
	if not _require(bool(structural["aggregate"].get("success", false)), "%d aggregate" % count, structural["aggregate"]):
		return
	if not _require(bool(structural["guard"].get("success", false)), "%d guard" % count, structural["guard"]):
		return
	if not _require(bool(structural["local"].get("success", false)), "%d local unbake plan" % count, structural["local"]):
		return
	if not _require(int(structural["local"]["diagnostics"]["full_part_count"]) == Fixture.REGION_SIZE, "%d local full region size" % count, structural["local"]["diagnostics"]):
		return
	if not _require(int(structural["local"]["diagnostics"]["retained_component_count"]) == 2, "%d retained components" % count, structural["local"]["diagnostics"]):
		return

	var guard_result := Fixture.evaluate_guard(subject, structural)
	if not _require(bool(guard_result.get("success", false)), "%d guard runtime" % count, guard_result):
		return
	if not _require(String(guard_result.get("status", "")) == "STRUCTURAL_REFINEMENT_REQUIRED", "%d guard requires refinement" % count, guard_result):
		return
	if not _require(guard_result["refinement_requests"].size() == 1, "%d single-region refinement" % count, guard_result):
		return
	if not _require(String(guard_result["refinement_requests"][0]["mapped_source_region"]) == String(subject["target_region_id"]), "%d target region identity" % count, guard_result):
		return
	if not _require(String(guard_result["refinement_requests"][0]["peak_bond_id"]) == String(subject["break_bond_id"]), "%d peak weak bond identity" % count, guard_result):
		return

	var break_bundle := Fixture.make_break(subject, structural)
	if not _require(bool(break_bundle.get("success", false)), "%d canonical break bundle" % count, break_bundle):
		return
	if not _require(not break_bundle["source_invalidation"].is_empty(), "%d source invalidation present" % count, break_bundle):
		return
	var bake_invalidation := Fixture.make_bake_invalidation(parent, break_bundle)
	if not _require(bool(BakeInvalidation.validate(bake_invalidation).get("success", false)), "%d bake invalidation validates" % count, bake_invalidation):
		return
	if not _require(String(bake_invalidation["artifact_id"]) == String(parent["artifact"]["artifact_id"]), "%d invalidation binds parent artifact" % count, bake_invalidation):
		return

	var stale := Lifecycle.execute(parent, reduced_state, 0.0, [bake_invalidation])
	if not _require(not bool(stale.get("success", false)), "%d stale parent rejected" % count, stale):
		return
	if not _require(String(stale.get("error_code", "")) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "%d stale rejection code" % count, stale):
		return

	var compiled := Fixture.compile_transaction(break_bundle)
	if not _require(bool(compiled.get("success", false)), "%d topology transaction compile" % count, compiled):
		return
	if not _require(String(compiled.get("status", "")) == "STRUCTURAL_TOPOLOGY_REBAKE_TRANSACTION_READY", "%d topology transaction status" % count, compiled):
		return
	var transaction: Dictionary = compiled["transaction"]
	if not _require(transaction["invalidated_pieces"].size() == 3, "%d invalidated reduced pieces" % count, transaction):
		return
	if not _require(transaction["rebaked_components"].size() == 2, "%d rebaked components" % count, transaction):
		return
	var component_sizes: Array = []
	for component in transaction["rebaked_components"]:
		component_sizes.append(component["part_ids"].size())
		if not _require(bool(Artifact.validate(component["physical_bake_artifact"]).get("success", false)), "%d component artifact validates" % count, component["physical_bake_artifact"]):
			return
	component_sizes.sort()
	var expected_sizes := [int(subject["break_index"]), count - int(subject["break_index"])]
	expected_sizes.sort()
	if not _require(component_sizes == expected_sizes, "%d split component sizes" % count, {"actual": component_sizes, "expected": expected_sizes}):
		return

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
	if not _require(bool(result.get("success", false)), "%d topology runtime" % count, result):
		return
	if not _require(String(result.get("status", "")) == TopologyRuntime.READY, "%d topology runtime status" % count, result):
		return
	if not _require(String(result["event_commit"]["state"]) == "APPLIED", "%d event commit state" % count, result["event_commit"]):
		return
	if not _require(String(result["event_commit"]["event_id"]) == String(break_bundle["event"]["event_id"]), "%d event identity" % count, result["event_commit"]):
		return
	if not _require(int(result["diagnostics"]["split_component_count"]) == 2, "%d split count" % count, result["diagnostics"]):
		return
	if not _require(int(result["diagnostics"]["invalidated_reduced_piece_count"]) == 3, "%d invalidated count" % count, result["diagnostics"]):
		return
	if not _require(int(result["diagnostics"]["executable_physical_bake_artifact_count"]) == 2, "%d executable rebakes" % count, result["diagnostics"]):
		return
	if not _require(int(result["diagnostics"]["full_dof"]) == count * 13, "%d full dof" % count, result["diagnostics"]):
		return
	if not _require(int(result["diagnostics"]["mixed_before_event_dof"]) == Fixture.REGION_SIZE * 13 + 2 * 13, "%d mixed dof" % count, result["diagnostics"]):
		return
	if not _require(int(result["diagnostics"]["rebaked_dof"]) == 2 * 13, "%d rebaked dof" % count, result["diagnostics"]):
		return
	if not _require(absf(float(result["diagnostics"]["post_split_reduction_ratio"]) - float(count) / 2.0) <= 1.0e-12, "%d reduction ratio" % count, result["diagnostics"]):
		return
	if not _require(float(result["diagnostics"]["mass_error"]) <= Fixture.CONSERVATION_TOLERANCE, "%d mass conservation" % count, result["diagnostics"]):
		return
	if not _require(float(result["diagnostics"]["linear_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE, "%d linear momentum" % count, result["diagnostics"]):
		return
	if not _require(float(result["diagnostics"]["angular_momentum_error"]) <= Fixture.CONSERVATION_TOLERANCE, "%d angular momentum" % count, result["diagnostics"]):
		return
	if not _require(float(result["diagnostics"]["max_state_handoff_error"]) <= Fixture.CONTINUITY_TOLERANCE, "%d state handoff" % count, result["diagnostics"]):
		return

	if not _verify_reconstruction(count, transaction, result, structural, reduced_state):
		return

	# Exactly-once replay is proven on the 500-part full lifecycle. Re-validating the entire
	# already-applied 2000-part transaction would only duplicate O(N) contract validation
	# after the scale proof and creates unnecessary peak memory pressure in the acceptance harness.
	if count == 500:
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
		if not _require(not bool(replay.get("success", false)), "%d duplicate event rejected" % count, replay):
			return
		if not _require(String(replay.get("error_code", "")) == "STRUCTURAL_TOPOLOGY_EVENT_ALREADY_APPLIED", "%d duplicate event code" % count, replay):
			return

	_scale_summaries.append({
		"parts": count,
		"mode": "BAKE_BREAK_SPLIT_REBAKE",
		"active_full_at_event": Fixture.REGION_SIZE,
		"fragments": component_sizes,
		"post_split_reduction_ratio": float(result["diagnostics"]["post_split_reduction_ratio"]),
	})
	# Break large reference graphs before returning to SceneTree. This keeps the exact
	# 2000-part harness from spending its shutdown budget releasing nested copies at process exit.
	result.clear()
	transaction.clear()
	compiled.clear()
	break_bundle.clear()
	structural.clear()
	parent_execution.clear()
	parent.clear()
	subject.clear()

func _verify_reconstruction(count: int, transaction: Dictionary, result: Dictionary, structural: Dictionary, reduced_state: Dictionary) -> bool:
	var parent_full := Reconstruction.reconstruct(structural["aggregate"]["reconstruction_mapping"], reduced_state)
	if not _require(bool(parent_full.get("success", false)), "%d reconstruct parent" % count, parent_full):
		return false
	var expected: Dictionary = parent_full["details"]["full_states"]
	var state_by_component: Dictionary = {}
	for entry in result["rebaked_component_states"]:
		state_by_component[String(entry["component_id"])] = entry
	var rebuilt_parts: Dictionary = {}
	var max_state_error := 0.0
	for component in transaction["rebaked_components"]:
		var component_id := String(component["component_id"])
		if not _require(state_by_component.has(component_id), "%d component runtime state exists" % count, {"component_id": component_id}):
			return false
		var rebuilt := Reconstruction.reconstruct(
			component["reconstruction_mapping"],
			state_by_component[component_id]["reduced_state"]
		)
		if not _require(bool(rebuilt.get("success", false)), "%d reconstruct component" % count, rebuilt):
			return false
		for part_id in component["part_ids"]:
			var key := String(part_id)
			if rebuilt_parts.has(key):
				return _require(false, "%d no duplicate reconstructed part" % count, {"part_id": key})
			rebuilt_parts[key] = true
			max_state_error = maxf(max_state_error, _state_error(rebuilt["details"]["full_states"][key], expected[key]))
	if not _require(rebuilt_parts.size() == count, "%d reconstructed canonical coverage" % count, {"actual": rebuilt_parts.size(), "expected": count}):
		return false
	if not _require(max_state_error <= Fixture.CONTINUITY_TOLERANCE, "%d reconstructed state continuity" % count, {"max_state_error": max_state_error, "tolerance": Fixture.CONTINUITY_TOLERANCE}):
		return false
	return true

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

func _require(condition: bool, label: String, details = null) -> bool:
	if condition:
		_checks += 1
		return true
	_failed = true
	printerr("FABRIC-BAKE COMPLEX0 FAILURE: %s details=%s" % [label, str(details)])
	return false
