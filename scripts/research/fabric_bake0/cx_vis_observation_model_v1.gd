extends RefCounted

const Complex0Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const Complex1AFixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")
const TopologyRuntime = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_runtime_v1.gd")

const SCHEMA := "planet_simulator.fabric_cx_vis_observation.v1"
const SCALE := 2000
const LAMP_ID := "load/lamp-a"
const STAGES_BASE := [
	"BASELINE_BAKED",
	"IMPACT_GUARD",
	"LOCAL_FULL",
	"CANONICAL_BREAK",
	"STALE_REJECTED",
	"SPLIT_REBAKED",
]
const STAGES_POWERED := [
	"BASELINE_BAKED",
	"IMPACT_GUARD",
	"LOCAL_FULL",
	"CANONICAL_BREAK",
	"STALE_REJECTED",
	"SPLIT_REBAKED",
	"WIRE_TOPOLOGY_LOST",
	"LAMP_OFF",
]

static func build(include_power: bool = true) -> Dictionary:
	var subject := Complex0Fixture.build(SCALE)
	if not bool(subject.get("success", false)):
		return _failure("CX_VIS0_SUBJECT_BUILD_FAILED", subject)

	var parent := Lifecycle.compile(subject["view_request"], Complex0Fixture.lifecycle_options(subject))
	if not bool(parent.get("success", false)):
		return _failure("CX_VIS0_PARENT_LIFECYCLE_FAILED", parent)
	if String(parent.get("status", "")) != Lifecycle.STATUS_READY or not parent.has("artifact"):
		return _failure("CX_VIS0_PARENT_NOT_BAKE_READY", parent)
	if not bool(Artifact.validate(parent["artifact"]).get("success", false)):
		return _failure("CX_VIS0_PARENT_ARTIFACT_INVALID", parent["artifact"])

	var reduced_state := Complex0Fixture.reduced_state()
	var parent_execution := Lifecycle.execute(parent, reduced_state)
	if not bool(parent_execution.get("success", false)):
		return _failure("CX_VIS0_PARENT_EXECUTION_FAILED", parent_execution)

	var structural := Complex0Fixture.compile_structural(subject)
	if not bool(structural.get("success", false)):
		return _failure("CX_VIS0_STRUCTURAL_PIPELINE_FAILED", structural)
	if not bool(structural["aggregate"].get("success", false)):
		return _failure("CX_VIS0_AGGREGATE_FAILED", structural["aggregate"])
	if not bool(structural["guard"].get("success", false)):
		return _failure("CX_VIS0_GUARD_COMPILE_FAILED", structural["guard"])
	if not bool(structural["local"].get("success", false)):
		return _failure("CX_VIS0_LOCAL_UNBAKE_PLAN_FAILED", structural["local"])

	var guard_result := Complex0Fixture.evaluate_guard(subject, structural)
	if not bool(guard_result.get("success", false)):
		return _failure("CX_VIS0_GUARD_RUNTIME_FAILED", guard_result)
	if String(guard_result.get("status", "")) != "STRUCTURAL_REFINEMENT_REQUIRED":
		return _failure("CX_VIS0_GUARD_DID_NOT_REFINE", guard_result)

	var break_bundle := Complex0Fixture.make_break(subject, structural)
	if not bool(break_bundle.get("success", false)):
		return _failure("CX_VIS0_BREAK_BUNDLE_FAILED", break_bundle)

	var bake_invalidation := Complex0Fixture.make_bake_invalidation(parent, break_bundle)
	if not bool(BakeInvalidation.validate(bake_invalidation).get("success", false)):
		return _failure("CX_VIS0_BAKE_INVALIDATION_INVALID", bake_invalidation)

	var stale_execution := Lifecycle.execute(parent, reduced_state, 0.0, [bake_invalidation])
	if bool(stale_execution.get("success", false)):
		return _failure("CX_VIS0_STALE_ARTIFACT_EXECUTED", stale_execution)
	if String(stale_execution.get("error_code", "")) != "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN":
		return _failure("CX_VIS0_STALE_REJECTION_MISMATCH", stale_execution)

	var compiled := Complex0Fixture.compile_transaction(break_bundle)
	if not bool(compiled.get("success", false)):
		return _failure("CX_VIS0_TOPOLOGY_COMPILE_FAILED", compiled)
	if String(compiled.get("status", "")) != "STRUCTURAL_TOPOLOGY_REBAKE_TRANSACTION_READY":
		return _failure("CX_VIS0_TOPOLOGY_COMPILE_STATUS_MISMATCH", compiled)
	var transaction: Dictionary = compiled["transaction"]

	var topology_result := TopologyRuntime.execute(
		transaction,
		structural["local"]["plan"],
		structural["aggregate"]["descriptor"],
		structural["aggregate"]["reconstruction_mapping"],
		structural["guard"]["guard_field"],
		reduced_state,
		Complex0Fixture.guard_context(subject, structural),
		break_bundle["current_frontier"],
		break_bundle["current_authority"],
		break_bundle["dependencies"],
		[]
	)
	if not bool(topology_result.get("success", false)):
		return _failure("CX_VIS0_TOPOLOGY_RUNTIME_FAILED", topology_result)
	if String(topology_result.get("status", "")) != TopologyRuntime.READY:
		return _failure("CX_VIS0_TOPOLOGY_RUNTIME_STATUS_MISMATCH", topology_result)

	var visual_parts := _visual_parts(subject["parts"])
	var target_part_ids := _part_ids_for_region(subject["parts"], String(subject["target_region_id"]))
	var components := _component_summaries(transaction["rebaked_components"])
	var bounds := _bounds(visual_parts)
	var break_segment := _break_segment(subject)
	var diagnostics: Dictionary = topology_result["diagnostics"]

	if target_part_ids.size() != Complex0Fixture.REGION_SIZE:
		return _failure("CX_VIS0_ACTIVE_FULL_REGION_SIZE_MISMATCH", {"part_ids": target_part_ids})
	if components.size() != 2:
		return _failure("CX_VIS0_SPLIT_COMPONENT_COUNT_MISMATCH", {"components": components})
	if int(diagnostics.get("split_component_count", -1)) != 2:
		return _failure("CX_VIS0_RUNTIME_SPLIT_COUNT_MISMATCH", diagnostics)
	if int(diagnostics.get("executable_physical_bake_artifact_count", -1)) != 2:
		return _failure("CX_VIS0_REBAKE_COUNT_MISMATCH", diagnostics)

	var event: Dictionary = break_bundle["event"]
	var power := {}
	if include_power:
		power = _build_power_observation(String(subject["break_bond_id"]), String(event["event_id"]))
		if not bool(power.get("success", false)):
			return power

	var observation := {
		"schema": SCHEMA,
		"success": true,
		"scale": SCALE,
		"parts": visual_parts,
		"bounds": bounds,
		"target_region_id": String(subject["target_region_id"]),
		"target_part_ids": target_part_ids,
		"break_index": int(subject["break_index"]),
		"break_bond_id": String(subject["break_bond_id"]),
		"break_segment": break_segment,
		"parent_artifact_id": String(parent["artifact"]["artifact_id"]),
		"parent_artifact_state_after_break": "STALE",
		"stale_rejection_error": String(stale_execution.get("error_code", "")),
		"guard_status": String(guard_result.get("status", "")),
		"guard_request": Dictionary(guard_result["refinement_requests"][0]).duplicate(true),
		"active_full_part_count": int(structural["local"]["diagnostics"]["full_part_count"]),
		"retained_component_count": int(structural["local"]["diagnostics"]["retained_component_count"]),
		"event": event.duplicate(true),
		"event_commit": Dictionary(topology_result["event_commit"]).duplicate(true),
		"components": components,
		"invalidated_reduced_piece_count": int(diagnostics["invalidated_reduced_piece_count"]),
		"executable_rebake_count": int(diagnostics["executable_physical_bake_artifact_count"]),
		"full_dof": int(diagnostics["full_dof"]),
		"mixed_before_event_dof": int(diagnostics["mixed_before_event_dof"]),
		"rebaked_dof": int(diagnostics["rebaked_dof"]),
		"post_split_reduction_ratio": float(diagnostics["post_split_reduction_ratio"]),
		"mass_error": float(diagnostics["mass_error"]),
		"linear_momentum_error": float(diagnostics["linear_momentum_error"]),
		"angular_momentum_error": float(diagnostics["angular_momentum_error"]),
		"max_state_handoff_error": float(diagnostics["max_state_handoff_error"]),
		"powered": include_power,
		"power": power,
		"stages": STAGES_POWERED.duplicate() if include_power else STAGES_BASE.duplicate(),
		"inspection_note": "Stages are causal inspection frames, not artificial physical delays.",
	}
	observation["checksum"] = _observation_checksum(observation)
	return observation

static func _build_power_observation(structural_bond_id: String, event_id: String) -> Dictionary:
	var subject := Complex1AFixture.single_path()
	if not subject["structural_bonds"].has("support/critical-a"):
		return _failure("CX_VIS1_POWER_FIXTURE_SHAPE_MISMATCH", subject)

	subject["structural_bonds"].erase("support/critical-a")
	subject["structural_bonds"][structural_bond_id] = true
	for index in range(subject["functional_links"].size()):
		var link: Dictionary = subject["functional_links"][index]
		var support_ids: Array = Array(link.get("support_bond_ids", [])).duplicate()
		for support_index in range(support_ids.size()):
			if String(support_ids[support_index]) == "support/critical-a":
				support_ids[support_index] = structural_bond_id
		link["support_bond_ids"] = support_ids
		subject["functional_links"][index] = link

	var before := Complex1AFixture.solve(subject)
	if not bool(before.get("success", false)):
		return _failure("CX_VIS1_POWER_BEFORE_SOLVE_FAILED", before)
	if not bool(before["loads"][LAMP_ID]["on"]):
		return _failure("CX_VIS1_LAMP_NOT_ON_BEFORE_BREAK", before)

	var broken := Complex1AFixture.apply_structural_break(subject, structural_bond_id, event_id)
	if not bool(broken.get("success", false)):
		return _failure("CX_VIS1_STRUCTURAL_TO_FUNCTIONAL_BREAK_FAILED", broken)
	if broken["functional_topology_mutations"].size() != 1:
		return _failure("CX_VIS1_FUNCTIONAL_MUTATION_COUNT_MISMATCH", broken)

	var mutation: Dictionary = broken["functional_topology_mutations"][0]
	if String(mutation.get("support_bond_id", "")) != structural_bond_id:
		return _failure("CX_VIS1_FUNCTIONAL_SUPPORT_ID_MISMATCH", mutation)

	var after := Complex1AFixture.solve(broken["subject"])
	if not bool(after.get("success", false)):
		return _failure("CX_VIS1_POWER_AFTER_SOLVE_FAILED", after)
	if bool(after["loads"][LAMP_ID]["on"]):
		return _failure("CX_VIS1_LAMP_STILL_ON_AFTER_BREAK", after)

	var duplicate := Complex1AFixture.apply_structural_break(
		broken["subject"], structural_bond_id, event_id
	)
	if bool(duplicate.get("success", false)):
		return _failure("CX_VIS1_DUPLICATE_EVENT_APPLIED", duplicate)
	if String(duplicate.get("error_code", "")) != "COMPLEX1A_STRUCTURAL_EVENT_ALREADY_APPLIED":
		return _failure("CX_VIS1_DUPLICATE_EVENT_REJECTION_MISMATCH", duplicate)

	return {
		"success": true,
		"event_id": event_id,
		"structural_support_bond_id": structural_bond_id,
		"functional_bond_id": String(mutation["bond_id"]),
		"functional_mutation_reason": String(mutation["reason"]),
		"before": _load_summary(before, LAMP_ID),
		"after": _load_summary(after, LAMP_ID),
		"active_functional_bond_ids_before": Array(before["active_functional_bond_ids"]).duplicate(),
		"active_functional_bond_ids_after": Array(after["active_functional_bond_ids"]).duplicate(),
		"duplicate_event_error": String(duplicate.get("error_code", "")),
	}

static func _load_summary(solution: Dictionary, load_id: String) -> Dictionary:
	var load: Dictionary = solution["loads"][load_id]
	return {
		"load_id": load_id,
		"on": bool(load["on"]),
		"voltage": float(load["voltage"]),
		"current": float(load["current"]),
		"absorbed_power": float(load["absorbed_power"]),
		"network_hash": String(solution["network_hash"]),
		"max_balance_residual": float(solution["max_balance_residual"]),
		"max_power_residual": float(solution["max_power_residual"]),
	}

static func _visual_parts(parts: Array) -> Array:
	var result: Array = []
	for raw_part in parts:
		var part: Dictionary = raw_part
		result.append({
			"part_id": String(part["part_id"]),
			"region_id": String(part["region_id"]),
			"position": Array(part["position"]).duplicate(),
			"orientation": Array(part["orientation"]).duplicate(),
			"size": _part_size(Array(part["support_points"])),
		})
	return result

static func _part_size(support_points: Array) -> Array:
	var maximum := Vector3.ZERO
	for raw_point in support_points:
		var point := _vec3(raw_point)
		maximum.x = maxf(maximum.x, absf(point.x))
		maximum.y = maxf(maximum.y, absf(point.y))
		maximum.z = maxf(maximum.z, absf(point.z))
	return [maximum.x * 2.0, maximum.y * 2.0, maximum.z * 2.0]

static func _part_ids_for_region(parts: Array, region_id: String) -> Array:
	var ids: Array = []
	for raw_part in parts:
		var part: Dictionary = raw_part
		if String(part["region_id"]) == region_id:
			ids.append(String(part["part_id"]))
	ids.sort()
	return ids

static func _component_summaries(rebaked_components: Array) -> Array:
	var result: Array = []
	for raw_component in rebaked_components:
		var component: Dictionary = raw_component
		var ids: Array = Array(component["part_ids"]).duplicate()
		ids.sort()
		result.append({
			"component_id": String(component["component_id"]),
			"part_ids": ids,
			"part_count": ids.size(),
			"artifact_id": String(component["physical_bake_artifact"]["artifact_id"]),
			"artifact_valid": bool(Artifact.validate(component["physical_bake_artifact"]).get("success", false)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["part_ids"][0]) < String(b["part_ids"][0])
	)
	return result

static func _break_segment(subject: Dictionary) -> Dictionary:
	var index := int(subject["break_index"])
	var left_id := "part/b0-2-%04d" % (index - 1)
	var right_id := "part/b0-2-%04d" % index
	var positions := {}
	for raw_part in subject["parts"]:
		var part: Dictionary = raw_part
		var part_id := String(part["part_id"])
		if part_id == left_id or part_id == right_id:
			positions[part_id] = Array(part["position"]).duplicate()
	if not positions.has(left_id) or not positions.has(right_id):
		return {}
	return {
		"left_part_id": left_id,
		"right_part_id": right_id,
		"left_position": positions[left_id],
		"right_position": positions[right_id],
	}

static func _bounds(parts: Array) -> Dictionary:
	if parts.is_empty():
		return {"center": [0.0, 0.0, 0.0], "size": [1.0, 1.0, 1.0]}
	var first: Dictionary = parts[0]
	var minimum := _vec3(first["position"]) - _vec3(first["size"]) * 0.5
	var maximum := _vec3(first["position"]) + _vec3(first["size"]) * 0.5
	for raw_part in parts:
		var part: Dictionary = raw_part
		var position := _vec3(part["position"])
		var half_size := _vec3(part["size"]) * 0.5
		minimum.x = minf(minimum.x, position.x - half_size.x)
		minimum.y = minf(minimum.y, position.y - half_size.y)
		minimum.z = minf(minimum.z, position.z - half_size.z)
		maximum.x = maxf(maximum.x, position.x + half_size.x)
		maximum.y = maxf(maximum.y, position.y + half_size.y)
		maximum.z = maxf(maximum.z, position.z + half_size.z)
	var center := (minimum + maximum) * 0.5
	var size := maximum - minimum
	return {
		"minimum": _arr3(minimum),
		"maximum": _arr3(maximum),
		"center": _arr3(center),
		"size": _arr3(size),
	}

static func _observation_checksum(observation: Dictionary) -> String:
	var component_tokens: Array = []
	for component in observation["components"]:
		component_tokens.append({
			"component_id": component["component_id"],
			"part_count": component["part_count"],
			"artifact_id": component["artifact_id"],
		})
	return Complex0Fixture.h({
		"schema": SCHEMA,
		"scale": observation["scale"],
		"target_region_id": observation["target_region_id"],
		"break_bond_id": observation["break_bond_id"],
		"event_id": observation["event"]["event_id"],
		"event_commit_state": observation["event_commit"]["state"],
		"components": component_tokens,
		"powered": observation["powered"],
		"lamp_before_on": observation["power"].get("before", {}).get("on", false) if observation["powered"] else false,
		"lamp_after_on": observation["power"].get("after", {}).get("on", false) if observation["powered"] else false,
	})

static func _vec3(value) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _failure(error_code: String, details = null) -> Dictionary:
	return {
		"schema": SCHEMA,
		"success": false,
		"error_code": error_code,
		"details": details,
	}
