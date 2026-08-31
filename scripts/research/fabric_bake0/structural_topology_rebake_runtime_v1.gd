extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const AggregateCompiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const LocalPlan = preload("res://scripts/research/fabric_bake0/structural_local_unbake_plan_v1.gd")
const LocalRuntime = preload("res://scripts/research/fabric_bake0/structural_local_unbake_runtime_v1.gd")
const Transaction = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_transaction_v1.gd")
const BakeExecutionGate = preload("res://scripts/research/fabric_bake0/bake_execution_gate_v1.gd")
const RuntimeErrorEstimator = preload("res://scripts/research/fabric_bake0/runtime_error_estimator_v1.gd")

const READY := "STRUCTURAL_TOPOLOGY_SPLIT_REBAKED"

static func execute(
	transaction: Dictionary, local_plan: Dictionary, parent_descriptor: Dictionary,
	parent_mapping: Dictionary, parent_guard_field: Dictionary, parent_reduced_state: Dictionary,
	guard_runtime_context: Dictionary, current_source_frontier: Dictionary,
	live_authority_envelope: Dictionary, live_dependency_set: Dictionary,
	applied_event_ids: Array = []
) -> Dictionary:
	var checked := Transaction.validate(transaction)
	if not bool(checked.get("success", false)):
		return checked
	checked = LocalPlan.validate(local_plan)
	if not bool(checked.get("success", false)):
		return checked
	checked = Descriptor.validate(parent_descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = Reconstruction.validate(parent_mapping)
	if not bool(checked.get("success", false)):
		return checked
	checked = GuardField.validate(parent_guard_field)
	if not bool(checked.get("success", false)):
		return checked
	checked = Frontier.validate(current_source_frontier)
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(live_authority_envelope)
	if not bool(checked.get("success", false)):
		return checked
	checked = DependencySet.validate(live_dependency_set)
	if not bool(checked.get("success", false)):
		return checked
	checked = Utils.validate_sorted_unique_strings(applied_event_ids, true)
	if not bool(checked.get("success", false)):
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_EVENT_HISTORY")
	for event_id in applied_event_ids:
		if not Utils.is_canonical_id(event_id, 2):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_EVENT_HISTORY")
	var event: Dictionary = transaction["event"]
	if applied_event_ids.has(String(event["event_id"])):
		return Utils.failure("STRUCTURAL_TOPOLOGY_EVENT_ALREADY_APPLIED", {
			"event_id": event["event_id"],
			"event_hash": event["event_hash"],
		})
	if String(transaction["parent_structural_descriptor_hash"]) != String(parent_descriptor["checksum"]) or String(transaction["parent_reconstruction_mapping_hash"]) != String(parent_mapping["checksum"]) or String(transaction["parent_guard_field_hash"]) != String(parent_guard_field["checksum"]) or String(transaction["local_unbake_plan_hash"]) != String(local_plan["checksum"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_RUNTIME_BINDING_MISMATCH")
	if String(transaction["previous_source_frontier_hash"]) != String(parent_descriptor["source_frontier_hash"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PREDECESSOR_FRONTIER_MISMATCH")
	if String(current_source_frontier["frontier_hash"]) != String(transaction["current_source_frontier_hash"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_CURRENT_FRONTIER_MISMATCH")

	# Re-run D at the exact event instant. E may only consume a topology event after the certified
	# region has really entered FULL representation through the C guard.
	var local_transition := LocalRuntime.execute(
		local_plan, parent_descriptor, parent_mapping, parent_guard_field,
		parent_reduced_state, guard_runtime_context
	)
	if not bool(local_transition.get("success", false)):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_LOCAL_UNBAKE_REQUIRED", {"cause": local_transition})
	if String(local_transition.get("target_region_id", "")) != String(event["target_region_id"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_EVENT_REGION_NOT_FULL")

	var parent_full := Reconstruction.reconstruct(parent_mapping, parent_reduced_state)
	if not bool(parent_full.get("success", false)):
		return parent_full
	var full_states: Dictionary = parent_full["details"]["full_states"]
	if full_states.size() != int(transaction["canonical_part_count"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PARENT_FULL_COVERAGE_MISMATCH")

	var rebaked_states: Array = []
	var max_state_handoff_error := 0.0
	var executable_artifact_count := 0
	var parent_com_world := _vec3(parent_reduced_state["position"])
	var combined_mass := 0.0
	var combined_linear := Vector3.ZERO
	var combined_angular := Vector3.ZERO
	for component in transaction["rebaked_components"]:
		var component_full: Dictionary = {}
		for part_id in component["part_ids"]:
			var key := String(part_id)
			if not full_states.has(key):
				return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_HANDOFF_PART_MISSING", {"part_id": key})
			component_full[key] = full_states[key]
		var projected := Reconstruction.project(
			component["reconstruction_mapping"], component_full, float(transaction["continuity_tolerance"])
		)
		if not bool(projected.get("success", false)):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_STATE_PROJECTION_FAILED", {
				"component_id": component["component_id"], "cause": projected,
			})
		var reduced_state: Dictionary = projected["details"]["reduced_state"]
		var rebuilt := Reconstruction.reconstruct(component["reconstruction_mapping"], reduced_state)
		if not bool(rebuilt.get("success", false)):
			return rebuilt
		var rebuilt_full: Dictionary = rebuilt["details"]["full_states"]
		for part_id in component["part_ids"]:
			var key := String(part_id)
			max_state_handoff_error = maxf(max_state_handoff_error, _state_error(component_full[key], rebuilt_full[key]))
		if max_state_handoff_error > float(transaction["continuity_tolerance"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_STATE_HANDOFF_DISCONTINUITY", {
				"component_id": component["component_id"],
				"error": max_state_handoff_error,
				"tolerance": transaction["continuity_tolerance"],
			})

		var artifact: Dictionary = component["physical_bake_artifact"]
		var guard_values: Dictionary = {}
		for guard in artifact["refinement_guards"]:
			guard_values[String(guard["guard_id"])] = 0.0
		var estimator := RuntimeErrorEstimator.create(
			"estimator/b0-2-e-%s" % String(component["component_id"]).replace("/", "-"),
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.5
		)
		var gate := BakeExecutionGate.can_execute(artifact, {
			"artifact_state": "READY",
			"canonical_source_frontier": current_source_frontier,
			"authority_envelope": live_authority_envelope,
			"dependency_set": live_dependency_set,
			"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
			"fabric_compiler_version": artifact["source_binding"]["fabric_compiler_version"],
			"boundary_contract_hash": artifact["source_binding"]["boundary_contract_hash"],
			"bake_policy_hash": artifact["source_binding"]["bake_policy_hash"],
			"runtime_domain": {
				"source_frontier_hash": current_source_frontier["frontier_hash"],
				"fabric_graph_hash": artifact["source_binding"]["fabric_graph_hash"],
				"elapsed_s": 0.0,
				"mode": "RIGID",
				"quantities": {},
			},
			"runtime_error_estimator": estimator,
			"guard_values": guard_values,
			"invalidations": [],
		})
		if not bool(gate.get("success", false)):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_NEW_ARTIFACT_NOT_EXECUTABLE", {
				"component_id": component["component_id"], "cause": gate,
			})
		executable_artifact_count += 1

		var momentum := AggregateCompiler.reduced_momentum(component["descriptor"], reduced_state)
		if not bool(momentum.get("success", false)):
			return momentum
		var linear := _vec3(momentum["details"]["linear_momentum"])
		var angular_about_component := _vec3(momentum["details"]["angular_momentum_about_com"])
		var component_com_world := _vec3(reduced_state["position"])
		combined_mass += float(component["descriptor"]["total_mass"])
		combined_linear += linear
		combined_angular += angular_about_component + (component_com_world - parent_com_world).cross(linear)
		rebaked_states.append({
			"component_id": String(component["component_id"]),
			"descriptor_hash": String(component["descriptor"]["checksum"]),
			"reconstruction_mapping_hash": String(component["reconstruction_mapping"]["checksum"]),
			"guard_field_hash": String(component["guard_field"]["checksum"]),
			"artifact_id": String(artifact["artifact_id"]),
			"artifact_hash": String(artifact["checksum"]),
			"reduced_state": reduced_state.duplicate(true),
			"execution_gate": gate["details"].duplicate(true),
		})
	rebaked_states = Utils.sorted_dicts(rebaked_states, "component_id")

	var mass_error := absf(combined_mass - float(parent_descriptor["total_mass"]))
	var parent_momentum := AggregateCompiler.reduced_momentum(parent_descriptor, parent_reduced_state)
	if not bool(parent_momentum.get("success", false)):
		return parent_momentum
	var expected_linear := _vec3(parent_momentum["details"]["linear_momentum"])
	var expected_angular := _vec3(parent_momentum["details"]["angular_momentum_about_com"])
	var linear_momentum_error := combined_linear.distance_to(expected_linear)
	var angular_momentum_error := combined_angular.distance_to(expected_angular)
	if mass_error > float(transaction["conservation_tolerance"]) or linear_momentum_error > float(transaction["conservation_tolerance"]) or angular_momentum_error > float(transaction["conservation_tolerance"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_CONSERVATION_MISMATCH", {
			"mass_error": mass_error,
			"linear_momentum_error": linear_momentum_error,
			"angular_momentum_error": angular_momentum_error,
			"tolerance": transaction["conservation_tolerance"],
		})

	var full_dof := int(transaction["canonical_part_count"]) * 13
	var mixed_before_event_dof: int = local_plan["target_part_ids"].size() * 13 + local_plan["residual_components"].size() * 13
	var rebaked_dof: int = transaction["rebaked_components"].size() * 13
	return {
		"success": true,
		"status": READY,
		"event_commit": {
			"event_id": String(event["event_id"]),
			"event_hash": String(event["event_hash"]),
			"event_sequence": int(event["event_sequence"]),
			"state": "APPLIED",
		},
		"invalidated_pieces": transaction["invalidated_pieces"].duplicate(true),
		"rebaked_component_states": rebaked_states,
		"diagnostics": {
			"split_component_count": transaction["rebaked_components"].size(),
			"invalidated_reduced_piece_count": transaction["invalidated_pieces"].size(),
			"executable_physical_bake_artifact_count": executable_artifact_count,
			"full_dof": full_dof,
			"mixed_before_event_dof": mixed_before_event_dof,
			"rebaked_dof": rebaked_dof,
			"post_split_reduction_ratio": float(full_dof) / float(rebaked_dof),
			"mass_error": mass_error,
			"linear_momentum_error": linear_momentum_error,
			"angular_momentum_error": angular_momentum_error,
			"max_state_handoff_error": max_state_handoff_error,
			"duplicate_event_count": 0,
			"physical_bake_artifact_emitted": true,
			"b0_2_complete": true,
		},
	}

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
