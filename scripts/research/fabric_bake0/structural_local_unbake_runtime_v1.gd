extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const AggregateCompiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const GuardRuntime = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_runtime_v1.gd")
const LocalPlan = preload("res://scripts/research/fabric_bake0/structural_local_unbake_plan_v1.gd")

const READY := "STRUCTURAL_BOUNDED_LOCAL_UNBAKE_READY"

static func execute(
	plan: Dictionary, parent_descriptor: Dictionary, parent_mapping: Dictionary,
	guard_field: Dictionary, reduced_state: Dictionary, guard_runtime_context: Dictionary
) -> Dictionary:
	var checked := LocalPlan.validate(plan)
	if not bool(checked.get("success", false)):
		return checked
	checked = Descriptor.validate(parent_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = Reconstruction.validate(parent_mapping)
	if not bool(checked.get("success", false)):
		return checked
	checked = GuardField.validate(guard_field)
	if not bool(checked.get("success", false)):
		return checked
	if String(parent_descriptor["checksum"]) != String(plan["parent_structural_descriptor_hash"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_DESCRIPTOR_BINDING_MISMATCH")
	if String(parent_mapping["checksum"]) != String(plan["parent_reconstruction_mapping_hash"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_MAPPING_BINDING_MISMATCH")
	if String(guard_field["checksum"]) != String(plan["guard_field_hash"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_GUARD_BINDING_MISMATCH")
	if String(parent_descriptor["source_frontier_hash"]) != String(plan["source_frontier_hash"]) or String(parent_mapping["source_frontier_hash"]) != String(plan["source_frontier_hash"]) or String(guard_field["source_frontier_hash"]) != String(plan["source_frontier_hash"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_SOURCE_BINDING_MISMATCH")

	# D never trusts a caller-provided refinement assertion. Re-run the exact C evaluator and
	# require a single certified regional request for this plan.
	var guard_result := GuardRuntime.evaluate(guard_field, guard_runtime_context)
	if not bool(guard_result.get("success", false)):
		return guard_result
	if String(guard_result.get("status", "")) != GuardRuntime.REFINEMENT_REQUIRED:
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_GUARD_NOT_TRIGGERED")
	if guard_result["refinement_requests"].size() != 1:
		return Utils.failure("NO_SAFE_BOUNDED_LOCAL_UNBAKE_MULTI_REGION_TRIGGER", {
			"request_count": guard_result["refinement_requests"].size(),
		})
	var refinement_request: Dictionary = guard_result["refinement_requests"][0]
	if String(refinement_request["mapped_source_region"]) != String(plan["target_region_id"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_TARGET_NOT_REQUESTED", {
			"requested": refinement_request["mapped_source_region"],
			"planned": plan["target_region_id"],
		})

	var reconstructed := Reconstruction.reconstruct(parent_mapping, reduced_state)
	if not bool(reconstructed.get("success", false)):
		return reconstructed
	var parent_full_states: Dictionary = reconstructed["details"]["full_states"]
	var target_full_states: Dictionary = {}
	for part_id in plan["target_part_ids"]:
		var key := String(part_id)
		if not parent_full_states.has(key):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_RECONSTRUCTED_TARGET_MISSING", {"part_id": key})
		target_full_states[key] = parent_full_states[key].duplicate(true)

	var residual_states: Array = []
	var residual_state_by_component: Dictionary = {}
	var max_residual_state_error := 0.0
	for component in plan["residual_components"]:
		var component_id := String(component["component_id"])
		var component_full_states: Dictionary = {}
		for part_id in component["part_ids"]:
			var key := String(part_id)
			if not parent_full_states.has(key):
				return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_RECONSTRUCTED_RESIDUAL_MISSING", {"part_id": key})
			component_full_states[key] = parent_full_states[key]
		var projected := Reconstruction.project(component["reconstruction_mapping"], component_full_states, float(plan["continuity_tolerance"]))
		if not bool(projected.get("success", false)):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_RESIDUAL_PROJECTION_FAILED", {
				"component_id": component_id,
				"cause": projected,
			})
		var component_state: Dictionary = projected["details"]["reduced_state"]
		var rebuilt := Reconstruction.reconstruct(component["reconstruction_mapping"], component_state)
		if not bool(rebuilt.get("success", false)):
			return rebuilt
		var rebuilt_states: Dictionary = rebuilt["details"]["full_states"]
		for part_id in component["part_ids"]:
			var key := String(part_id)
			max_residual_state_error = maxf(max_residual_state_error, _state_error(component_full_states[key], rebuilt_states[key]))
		if max_residual_state_error > float(plan["continuity_tolerance"]):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_RESIDUAL_STATE_DISCONTINUITY", {
				"component_id": component_id,
				"error": max_residual_state_error,
				"tolerance": plan["continuity_tolerance"],
			})
		var state_entry := {
			"component_id": component_id,
			"descriptor_hash": String(component["descriptor"]["checksum"]),
			"reconstruction_mapping_hash": String(component["reconstruction_mapping"]["checksum"]),
			"reduced_state": component_state.duplicate(true),
		}
		residual_states.append(state_entry)
		residual_state_by_component[component_id] = component_state
	residual_states = Utils.sorted_dicts(residual_states, "component_id")

	# Cut bonds become explicit FULL<->BAKED interfaces. Both sides must reproduce the same
	# world-space point and velocity at the exact transition instant.
	var interface_results: Array = []
	var max_interface_position_error := 0.0
	var max_interface_velocity_error := 0.0
	var parent_q := _quat(reduced_state["orientation"])
	var parent_com_world := _vec3(reduced_state["position"])
	for interface in plan["cut_interfaces"]:
		var component_id := String(interface["residual_component_id"])
		if not residual_state_by_component.has(component_id):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_INTERFACE_COMPONENT_STATE_MISSING", {"component_id": component_id})
		var component: Dictionary = _component_by_id(plan["residual_components"], component_id)
		var residual_anchor := AggregateCompiler.evaluate_anchor(
			component["descriptor"], residual_state_by_component[component_id], String(interface["residual_anchor_id"])
		)
		if not bool(residual_anchor.get("success", false)):
			return residual_anchor
		var residual_point: Dictionary = residual_anchor["details"]
		var full_state: Dictionary = target_full_states[String(interface["full_part_id"])]
		var full_q := _quat(full_state["orientation"])
		var full_r := full_q * _vec3(interface["full_position_local"])
		var full_position := _vec3(full_state["position"]) + full_r
		var full_velocity := _vec3(full_state["linear_velocity"]) + _vec3(full_state["angular_velocity"]).cross(full_r)
		var expected_position := parent_com_world + parent_q * _vec3(interface["point_from_parent_com"])
		var residual_position := _vec3(residual_point["position"])
		var residual_velocity := _vec3(residual_point["linear_velocity"])
		var position_error := maxf(full_position.distance_to(residual_position), maxf(full_position.distance_to(expected_position), residual_position.distance_to(expected_position)))
		var velocity_error := full_velocity.distance_to(residual_velocity)
		max_interface_position_error = maxf(max_interface_position_error, position_error)
		max_interface_velocity_error = maxf(max_interface_velocity_error, velocity_error)
		if position_error > float(plan["continuity_tolerance"]) or velocity_error > float(plan["continuity_tolerance"]):
			return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_INTERFACE_DISCONTINUITY", {
				"interface_id": interface["interface_id"],
				"position_error": position_error,
				"velocity_error": velocity_error,
				"tolerance": plan["continuity_tolerance"],
			})
		interface_results.append({
			"interface_id": String(interface["interface_id"]),
			"bond_id": String(interface["bond_id"]),
			"full_part_id": String(interface["full_part_id"]),
			"residual_component_id": component_id,
			"residual_part_id": String(interface["residual_part_id"]),
			"position_error": position_error,
			"velocity_error": velocity_error,
		})
	interface_results = Utils.sorted_dicts(interface_results, "interface_id")

	# Conservation reconciliation: FULL target + all retained reduced components must equal the
	# original aggregate mass and momentum about the original aggregate COM.
	var target_mass := 0.0
	for model in plan["target_part_models"]:
		target_mass += float(model["mass"])
	var residual_mass := 0.0
	for component in plan["residual_components"]:
		residual_mass += float(component["descriptor"]["total_mass"])
	var mass_error := absf(target_mass + residual_mass - float(parent_descriptor["total_mass"]))
	if mass_error > float(plan["conservation_tolerance"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_MASS_MISMATCH", {"mass_error": mass_error})

	var parent_momentum := AggregateCompiler.reduced_momentum(parent_descriptor, reduced_state)
	if not bool(parent_momentum.get("success", false)):
		return parent_momentum
	var target_momentum := AggregateCompiler.full_momentum(plan["target_part_models"], target_full_states, reduced_state["position"])
	if not bool(target_momentum.get("success", false)):
		return target_momentum
	var combined_linear := _vec3(target_momentum["details"]["linear_momentum"])
	var combined_angular := _vec3(target_momentum["details"]["angular_momentum_about_com"])
	for component in plan["residual_components"]:
		var component_id := String(component["component_id"])
		var component_state: Dictionary = residual_state_by_component[component_id]
		var momentum := AggregateCompiler.reduced_momentum(component["descriptor"], component_state)
		if not bool(momentum.get("success", false)):
			return momentum
		var linear := _vec3(momentum["details"]["linear_momentum"])
		var angular_about_component := _vec3(momentum["details"]["angular_momentum_about_com"])
		var offset := _vec3(component_state["position"]) - parent_com_world
		combined_linear += linear
		combined_angular += angular_about_component + offset.cross(linear)
	var expected_linear := _vec3(parent_momentum["details"]["linear_momentum"])
	var expected_angular := _vec3(parent_momentum["details"]["angular_momentum_about_com"])
	var linear_momentum_error := combined_linear.distance_to(expected_linear)
	var angular_momentum_error := combined_angular.distance_to(expected_angular)
	if linear_momentum_error > float(plan["conservation_tolerance"]) or angular_momentum_error > float(plan["conservation_tolerance"]):
		return Utils.failure("STRUCTURAL_LOCAL_UNBAKE_MOMENTUM_MISMATCH", {
			"linear_momentum_error": linear_momentum_error,
			"angular_momentum_error": angular_momentum_error,
			"tolerance": plan["conservation_tolerance"],
		})

	var mixed_dof: int = plan["target_part_ids"].size() * 13 + plan["residual_components"].size() * 13
	var full_dof: int = int(plan["canonical_part_count"]) * 13
	return {
		"success": true,
		"status": READY,
		"target_region_id": String(plan["target_region_id"]),
		"trigger": refinement_request.duplicate(true),
		"full_part_states": target_full_states,
		"residual_reduced_states": residual_states,
		"cut_interfaces": interface_results,
		"diagnostics": {
			"full_part_count": plan["target_part_ids"].size(),
			"retained_component_count": plan["residual_components"].size(),
			"retained_part_count": int(plan["canonical_part_count"]) - plan["target_part_ids"].size(),
			"cut_interface_count": plan["cut_interfaces"].size(),
			"full_dof": full_dof,
			"mixed_dof": mixed_dof,
			"preserved_reduction_ratio": float(full_dof) / float(mixed_dof),
			"mass_error": mass_error,
			"linear_momentum_error": linear_momentum_error,
			"angular_momentum_error": angular_momentum_error,
			"max_residual_state_error": max_residual_state_error,
			"max_interface_position_error": max_interface_position_error,
			"max_interface_velocity_error": max_interface_velocity_error,
			"physical_bake_artifact_emitted": false,
			"next_required_stage": "B0.2-E_TOPOLOGY_SPLIT_REBAKE",
		},
	}

static func _component_by_id(components: Array, component_id: String) -> Dictionary:
	for component in components:
		if String(component["component_id"]) == component_id:
			return component
	return {}

static func _state_error(left: Dictionary, right: Dictionary) -> float:
	return maxf(
		_vec3(left["position"]).distance_to(_vec3(right["position"])),
		maxf(
			_vec3(left["linear_velocity"]).distance_to(_vec3(right["linear_velocity"])),
			maxf(
				_vec3(left["angular_velocity"]).distance_to(_vec3(right["angular_velocity"])),
				_quat_distance(_quat(left["orientation"]), _quat(right["orientation"]))
			)
		)
	)

static func _quat_distance(a: Quaternion, b: Quaternion) -> float:
	return 1.0 - absf(a.normalized().dot(b.normalized()))

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()
