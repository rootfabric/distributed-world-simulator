extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const BoundaryContract = preload("res://scripts/research/fabric_bake0/physical_boundary_contract_v1.gd")
const ValidatedDomain = preload("res://scripts/research/fabric_bake0/validated_domain_v1.gd")
const ErrorEnvelope = preload("res://scripts/research/fabric_bake0/error_envelope_v1.gd")
const ConservationEnvelope = preload("res://scripts/research/fabric_bake0/conservation_envelope_v1.gd")
const ReconstructionDescriptor = preload("res://scripts/research/fabric_bake0/reconstruction_descriptor_v1.gd")
const StateMapping = preload("res://scripts/research/fabric_bake0/bake_state_mapping_v1.gd")
const FoundationCompiler = preload("res://scripts/research/fabric_bake0/fabric_bake_foundation_compiler_v1.gd")
const AggregateCompiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const GuardCompiler = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_compiler_v1.gd")
const LocalPlan = preload("res://scripts/research/fabric_bake0/structural_local_unbake_plan_v1.gd")
const Transaction = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_transaction_v1.gd")

const READY := "STRUCTURAL_TOPOLOGY_REBAKE_TRANSACTION_READY"
const REQUEST_FIELDS: Array[String] = [
	"transaction_id", "previous_source_frontier", "current_source_frontier",
	"parent_structural_descriptor", "parent_reconstruction_mapping", "parent_guard_field",
	"local_unbake_plan", "previous_parts", "previous_bonds", "boundary_anchors",
	"current_parts", "current_bonds", "topology_event", "bond_capacity_specs",
	"authority_envelope", "dependency_set", "bake_policy_hash", "fabric_compiler_version",
	"build_generation", "minimum_rebake_component_parts", "continuity_tolerance",
	"conservation_tolerance", "transition_version",
]
const EVENT_REQUEST_FIELDS: Array[String] = [
	"event_id", "event_type", "bond_id", "target_region_id", "event_tick", "event_sequence",
]
const PART_FIELDS: Array[String] = [
	"part_id", "region_id", "mass", "position", "orientation", "inertia_tensor", "support_points",
]
const BOND_FIELDS: Array[String] = ["bond_id", "part_a", "part_b", "rigid"]
const ANCHOR_FIELDS: Array[String] = ["anchor_id", "part_id", "position_local", "orientation_local"]

static func compile(request: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(request, REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_canonical_id(request.get("transaction_id"), 2):
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_TRANSACTION_ID")
	if not Utils.is_lower_hex_64(request.get("bake_policy_hash")):
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_POLICY_HASH")
	if typeof(request.get("fabric_compiler_version")) != TYPE_STRING or String(request["fabric_compiler_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COMPILER_VERSION")
	if not Utils.is_json_integer(request.get("build_generation")) or int(request["build_generation"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_BUILD_GENERATION")
	if not Utils.is_json_integer(request.get("minimum_rebake_component_parts")) or int(request["minimum_rebake_component_parts"]) < 100:
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_MINIMUM")
	if not Utils.is_positive_number(request.get("continuity_tolerance")) or not Utils.is_positive_number(request.get("conservation_tolerance")):
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_TOLERANCE")
	if typeof(request.get("transition_version")) != TYPE_STRING or String(request["transition_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_VERSION")

	for field in ["previous_source_frontier", "current_source_frontier", "parent_structural_descriptor", "parent_reconstruction_mapping", "parent_guard_field", "local_unbake_plan", "authority_envelope", "dependency_set", "topology_event"]:
		if typeof(request.get(field)) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_CONTRACT", {"field": field})
	for field in ["previous_parts", "previous_bonds", "boundary_anchors", "current_parts", "current_bonds", "bond_capacity_specs"]:
		if typeof(request.get(field)) != TYPE_ARRAY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COLLECTION", {"field": field})

	var previous_frontier: Dictionary = request["previous_source_frontier"]
	var current_frontier: Dictionary = request["current_source_frontier"]
	checked = Frontier.validate(previous_frontier)
	if not bool(checked.get("success", false)):
		return checked
	checked = Frontier.validate(current_frontier)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_frontier_transition(previous_frontier, current_frontier)
	if not bool(checked.get("success", false)):
		return checked
	checked = AuthorityEnvelope.validate_b0_safety(request["authority_envelope"])
	if not bool(checked.get("success", false)):
		return checked
	checked = DependencySet.validate(request["dependency_set"])
	if not bool(checked.get("success", false)):
		return checked

	var descriptor: Dictionary = request["parent_structural_descriptor"]
	var mapping: Dictionary = request["parent_reconstruction_mapping"]
	var guard_field: Dictionary = request["parent_guard_field"]
	var local_plan: Dictionary = request["local_unbake_plan"]
	checked = Descriptor.validate(descriptor)
	if not bool(checked.get("success", false)):
		return checked
	checked = Reconstruction.validate(mapping)
	if not bool(checked.get("success", false)):
		return checked
	checked = GuardField.validate(guard_field)
	if not bool(checked.get("success", false)):
		return checked
	checked = LocalPlan.validate(local_plan)
	if not bool(checked.get("success", false)):
		return checked
	var previous_hash := String(previous_frontier["frontier_hash"])
	var current_hash := String(current_frontier["frontier_hash"])
	if String(descriptor["source_frontier_hash"]) != previous_hash or String(mapping["source_frontier_hash"]) != previous_hash or String(guard_field["source_frontier_hash"]) != previous_hash or String(local_plan["source_frontier_hash"]) != previous_hash:
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PREDECESSOR_FRONTIER_MISMATCH")
	if String(descriptor["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PARENT_MAPPING_MISMATCH")
	if String(guard_field["structural_descriptor_hash"]) != String(descriptor["checksum"]) or String(guard_field["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PARENT_GUARD_MISMATCH")
	if String(local_plan["parent_structural_descriptor_hash"]) != String(descriptor["checksum"]) or String(local_plan["parent_reconstruction_mapping_hash"]) != String(mapping["checksum"]) or String(local_plan["guard_field_hash"]) != String(guard_field["checksum"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_LOCAL_PLAN_BINDING_MISMATCH")

	var event_request: Dictionary = request["topology_event"]
	checked = Utils.validate_exact_fields(event_request, EVENT_REQUEST_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	for field in ["event_id", "bond_id", "target_region_id"]:
		if not Utils.is_canonical_id(event_request.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_EVENT_ID", {"field": field})
	if String(event_request.get("event_type", "")) != "BOND_BREAK":
		return Utils.failure("UNSUPPORTED_STRUCTURAL_TOPOLOGY_EVENT")
	if not Utils.is_json_integer(event_request.get("event_tick")) or int(event_request["event_tick"]) < 0 or not Utils.is_json_integer(event_request.get("event_sequence")) or int(event_request["event_sequence"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_EVENT_ORDER")
	if String(event_request["target_region_id"]) != String(local_plan["target_region_id"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_EVENT_REGION_MISMATCH")
	if not local_plan["target_internal_bond_ids"].has(String(event_request["bond_id"])):
		return Utils.failure("STRUCTURAL_TOPOLOGY_EVENT_OUTSIDE_UNBAKED_REGION", {"bond_id": event_request["bond_id"]})

	var previous_parts := Utils.sorted_dicts(request["previous_parts"], "part_id")
	var current_parts := Utils.sorted_dicts(request["current_parts"], "part_id")
	var previous_bonds := Utils.sorted_dicts(request["previous_bonds"], "bond_id")
	var current_bonds := Utils.sorted_dicts(request["current_bonds"], "bond_id")
	var anchors := Utils.sorted_dicts(request["boundary_anchors"], "anchor_id")
	checked = _validate_parts(previous_parts)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_parts(current_parts)
	if not bool(checked.get("success", false)):
		return checked
	if JSON.stringify(previous_parts) != JSON.stringify(current_parts):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PART_STATE_MUTATION_UNSUPPORTED")
	checked = _validate_bonds(previous_bonds, previous_parts)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_bonds(current_bonds, current_parts)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_anchors(anchors, current_parts)
	if not bool(checked.get("success", false)):
		return checked
	checked = _validate_exact_bond_break(previous_bonds, current_bonds, String(event_request["bond_id"]))
	if not bool(checked.get("success", false)):
		return checked

	# Prove the predecessor canonical inventory still materializes the exact D parent.
	var parent_recompile := AggregateCompiler.compile({
		"descriptor_id": String(descriptor["descriptor_id"]),
		"mapping_id": String(mapping["mapping_id"]),
		"source_frontier_hash": previous_hash,
		"construct_id": String(descriptor["construct_id"]),
		"parts": previous_parts,
		"bonds": previous_bonds,
		"boundary_anchors": anchors,
		"reconstruction_version": String(mapping["reconstruction_version"]),
		"minimum_part_count": 100,
	})
	if not bool(parent_recompile.get("success", false)):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PARENT_RECOMPILE_FAILED", parent_recompile)
	if String(parent_recompile["descriptor"]["checksum"]) != String(descriptor["checksum"]) or String(parent_recompile["reconstruction_mapping"]["checksum"]) != String(mapping["checksum"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PREDECESSOR_SOURCE_MISMATCH")

	var part_by_id: Dictionary = {}
	for part in current_parts:
		part_by_id[String(part["part_id"])] = part
	var adjacency: Dictionary = {}
	for part_id in part_by_id.keys():
		adjacency[part_id] = []
	for bond in current_bonds:
		var a := String(bond["part_a"])
		var b := String(bond["part_b"])
		adjacency[a].append(b)
		adjacency[b].append(a)
	var component_parts_list := _connected_components(part_by_id.keys(), adjacency)
	if component_parts_list.size() < 2:
		return Utils.failure("STRUCTURAL_TOPOLOGY_EVENT_DID_NOT_SPLIT_GRAPH")
	for component_parts in component_parts_list:
		if component_parts.size() < int(request["minimum_rebake_component_parts"]):
			return Utils.failure("NO_SAFE_TOPOLOGY_REBAKE_COMPONENT_TOO_SMALL", {
				"part_count": component_parts.size(),
				"minimum": int(request["minimum_rebake_component_parts"]),
			})

	var parent_guard_bond := _guard_bond_by_id(guard_field["bond_models"], String(event_request["bond_id"]))
	if parent_guard_bond.is_empty():
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_EVENT_BOND_NOT_GUARDED")
	var old_parent_com := _vec3(descriptor["center_of_mass"])
	var break_point_absolute := old_parent_com + _vec3(parent_guard_bond["point_from_com"])
	var broken_bond := _bond_by_id(previous_bonds, String(event_request["bond_id"]))
	if broken_bond.is_empty():
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_EVENT_BOND_MISSING")

	var current_capacity_by_bond: Dictionary = {}
	for raw in request["bond_capacity_specs"]:
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_CAPACITY_SPEC")
		var bond_id := String(raw.get("bond_id", ""))
		if current_capacity_by_bond.has(bond_id):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_DUPLICATE_CAPACITY", {"bond_id": bond_id})
		current_capacity_by_bond[bond_id] = raw
	for bond in current_bonds:
		if not current_capacity_by_bond.has(String(bond["bond_id"])):
			return Utils.failure("NO_SAFE_TOPOLOGY_REBAKE_CAPACITY_COVERAGE_MISMATCH", {"bond_id": bond["bond_id"]})

	var invalidated_pieces: Array = [{
		"piece_id": "piece/b0-2-e-parent",
		"piece_kind": "PARENT_AGGREGATE",
		"descriptor_hash": String(descriptor["checksum"]),
		"predecessor_frontier_hash": previous_hash,
		"current_frontier_hash": current_hash,
		"reason": "TOPOLOGY_EVENT",
	}]
	for index in range(local_plan["residual_components"].size()):
		var residual: Dictionary = local_plan["residual_components"][index]
		invalidated_pieces.append({
			"piece_id": "piece/b0-2-d-residual-%03d" % index,
			"piece_kind": "LOCAL_RESIDUAL",
			"descriptor_hash": String(residual["descriptor"]["checksum"]),
			"predecessor_frontier_hash": previous_hash,
			"current_frontier_hash": current_hash,
			"reason": "TOPOLOGY_EVENT",
		})

	var rebaked_components: Array = []
	for index in range(component_parts_list.size()):
		var component_part_ids: Array = component_parts_list[index]
		var component_set: Dictionary = {}
		var component_parts: Array = []
		for part_id in component_part_ids:
			component_set[String(part_id)] = true
			component_parts.append(part_by_id[String(part_id)].duplicate(true))
		var component_bonds: Array = []
		var component_bond_ids: Array = []
		for bond in current_bonds:
			if component_set.has(String(bond["part_a"])) and component_set.has(String(bond["part_b"])):
				component_bonds.append(bond.duplicate(true))
				component_bond_ids.append(String(bond["bond_id"]))
		component_bond_ids.sort()
		if component_bonds.size() != component_parts.size() - 1:
			return Utils.failure("NO_SAFE_TOPOLOGY_REBAKE_NON_TREE_COMPONENT", {"component_index": index})
		var component_anchors: Array = []
		for anchor in anchors:
			if component_set.has(String(anchor["part_id"])):
				component_anchors.append(anchor.duplicate(true))
		for endpoint_field in ["part_a", "part_b"]:
			var endpoint := String(broken_bond[endpoint_field])
			if component_set.has(endpoint):
				var endpoint_part: Dictionary = part_by_id[endpoint]
				var local_point := _quat(endpoint_part["orientation"]).inverse() * (break_point_absolute - _vec3(endpoint_part["position"]))
				component_anchors.append({
					"anchor_id": "anchor/b0-2-e-break-%03d" % index,
					"part_id": endpoint,
					"position_local": _arr3(local_point),
					"orientation_local": [0.0, 0.0, 0.0, 1.0],
				})
		component_anchors = Utils.sorted_dicts(component_anchors, "anchor_id")
		var compiled := AggregateCompiler.compile({
			"descriptor_id": "aggregate/b0-2-e-%03d" % index,
			"mapping_id": "mapping/b0-2-e-%03d" % index,
			"source_frontier_hash": current_hash,
			"construct_id": String(descriptor["construct_id"]),
			"parts": component_parts,
			"bonds": component_bonds,
			"boundary_anchors": component_anchors,
			"reconstruction_version": String(request["transition_version"]),
			"minimum_part_count": int(request["minimum_rebake_component_parts"]),
		})
		if not bool(compiled.get("success", false)):
			return Utils.failure("NO_SAFE_TOPOLOGY_REBAKE_COMPONENT_COMPILE_FAILED", {"component_index": index, "cause": compiled})
		var new_descriptor: Dictionary = compiled["descriptor"]
		var new_mapping: Dictionary = compiled["reconstruction_mapping"]
		var component_capacities: Array = []
		var new_com := _vec3(new_descriptor["center_of_mass"])
		for bond in component_bonds:
			var old_capacity: Dictionary = current_capacity_by_bond[String(bond["bond_id"])]
			var absolute_point := old_parent_com + _vec3(old_capacity["point_from_com"])
			component_capacities.append({
				"bond_id": String(old_capacity["bond_id"]),
				"point_from_com": _arr3(absolute_point - new_com),
				"certified_force_capacity": float(old_capacity["certified_force_capacity"]),
				"certified_moment_capacity": float(old_capacity["certified_moment_capacity"]),
				"uncertainty_ratio": float(old_capacity["uncertainty_ratio"]),
			})
		var component_guard := GuardCompiler.compile({
			"field_id": "guard-field/b0-2-e-%03d" % index,
			"source_frontier_hash": current_hash,
			"structural_descriptor": new_descriptor,
			"reconstruction_mapping": new_mapping,
			"parts": component_parts,
			"bonds": component_bonds,
			"root_part_id": String(component_part_ids[0]),
			"bond_capacity_specs": component_capacities,
			"capacity_certificate_hash": _capacity_hash(current_hash, component_capacities),
			"trigger_ratio": float(guard_field["trigger_ratio"]),
			"required_refinement_level": int(guard_field["required_refinement_level"]),
			"residual_force_tolerance": float(guard_field["residual_force_tolerance"]),
			"residual_moment_tolerance": float(guard_field["residual_moment_tolerance"]),
			"evaluator_version": String(request["transition_version"]),
		})
		if not bool(component_guard.get("success", false)):
			return Utils.failure("NO_SAFE_TOPOLOGY_REBAKE_GUARD_COMPILE_FAILED", {"component_index": index, "cause": component_guard})
		var new_guard_field: Dictionary = component_guard["guard_field"]
		var physical_artifact := _compile_physical_artifact(
			index, current_frontier, request["authority_envelope"], request["dependency_set"],
			new_descriptor, new_mapping, new_guard_field, component_bond_ids,
			String(request["fabric_compiler_version"]), String(request["bake_policy_hash"]),
			int(request["build_generation"]), float(request["continuity_tolerance"]),
			float(request["conservation_tolerance"]), String(request["transition_version"]),
			Transaction.event_hash(_event_with_hash(event_request))
		)
		if not bool(physical_artifact.get("success", false)):
			return Utils.failure("NO_SAFE_TOPOLOGY_REBAKE_PHYSICAL_ARTIFACT_FAILED", {"component_index": index, "cause": physical_artifact})
		var anchor_ids: Array = []
		for anchor in component_anchors:
			anchor_ids.append(String(anchor["anchor_id"]))
		anchor_ids.sort()
		rebaked_components.append({
			"component_id": "component/b0-2-e-%03d" % index,
			"part_ids": component_part_ids.duplicate(),
			"bond_ids": component_bond_ids,
			"anchor_ids": anchor_ids,
			"descriptor": new_descriptor,
			"reconstruction_mapping": new_mapping,
			"guard_field": new_guard_field,
			"physical_bake_artifact": physical_artifact["artifact"],
			"predecessor_piece_ids": _predecessor_piece_ids(component_set, local_plan),
		})

	var event := _event_with_hash(event_request)
	var transaction := Transaction.create(
		String(request["transaction_id"]), previous_hash, current_hash, String(descriptor["construct_id"]),
		String(descriptor["checksum"]), String(mapping["checksum"]), String(guard_field["checksum"]),
		String(local_plan["checksum"]), event, invalidated_pieces, rebaked_components,
		current_parts.size(), previous_bonds.size(), current_bonds.size(), int(request["minimum_rebake_component_parts"]),
		float(request["continuity_tolerance"]), float(request["conservation_tolerance"]), String(request["transition_version"])
	)
	if transaction.is_empty():
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_TRANSACTION_ASSEMBLY_FAILED")
	var full_dof := current_parts.size() * 13
	var rebaked_dof := rebaked_components.size() * 13
	return {
		"success": true,
		"status": READY,
		"transaction": transaction,
		"diagnostics": {
			"event_id": event["event_id"],
			"broken_bond_id": event["bond_id"],
			"split_component_count": rebaked_components.size(),
			"invalidated_reduced_piece_count": invalidated_pieces.size(),
			"physical_bake_artifact_count": rebaked_components.size(),
			"full_dof": full_dof,
			"rebaked_dof": rebaked_dof,
			"post_split_reduction_ratio": float(full_dof) / float(rebaked_dof),
			"physical_bake_artifact_emitted": true,
			"next_required_stage": "B0.2_COMPLETE",
		},
	}

static func _compile_physical_artifact(
	index: int, current_frontier: Dictionary, authority: Dictionary, dependencies: Dictionary,
	descriptor: Dictionary, mapping: Dictionary, guard_field: Dictionary, bond_ids: Array,
	fabric_compiler_version: String, bake_policy_hash: String, build_generation: int,
	continuity_tolerance: float, conservation_tolerance: float, transition_version: String,
	event_hash_value: String
) -> Dictionary:
	var boundary := _boundary_contract(index, descriptor)
	if boundary.is_empty():
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_BOUNDARY_CONTRACT_FAILED")
	var graph_hash := Utils.canonical_hash({
		"schema": "planet_simulator.fabric_bake_structural_rebake_graph.v1",
		"frontier_hash": current_frontier["frontier_hash"],
		"descriptor_hash": descriptor["checksum"],
		"guard_field_hash": guard_field["checksum"],
		"bond_ids": bond_ids,
	})
	var validated := ValidatedDomain.create(String(current_frontier["frontier_hash"]), graph_hash, [], ["RIGID"], 1.0)
	var error_envelope := ErrorEnvelope.create(
		conservation_tolerance, 0.0, conservation_tolerance, 0.0,
		conservation_tolerance, 0.0, continuity_tolerance, 0.0,
		0.0, conservation_tolerance, 0.0, 1.0, true
	)
	var conservation := ConservationEnvelope.create(0.0, 0.0, conservation_tolerance, conservation_tolerance, 0.0)
	var source_keys := Frontier.source_keys(current_frontier)
	var reconstruction := ReconstructionDescriptor.create(
		"reconstruction/b0-2-e-%03d" % index,
		String(current_frontier["frontier_hash"]), String(mapping["checksum"]), "CANONICAL_PLUS_REDUCED",
		[{"region_id": "region/b0-2-e-%03d" % index, "source_keys": source_keys}],
		"STRICT", event_hash_value, transition_version
	)
	if reconstruction.is_empty():
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_RECONSTRUCTION_DESCRIPTOR_FAILED")
	var state_mapping := StateMapping.create(
		"state-mapping/b0-2-e-%03d" % index,
		String(descriptor["full_state_schema_hash"]), String(descriptor["reduced_state_schema_hash"]),
		String(mapping["checksum"]), String(reconstruction["checksum"])
	)
	if state_mapping.is_empty():
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_STATE_MAPPING_FAILED")
	var result := FoundationCompiler.compile({
		"artifact_id": "bake/b0-2-e-%03d" % index,
		"reduction_class": "APPROXIMATE",
		"canonical_source_frontier": current_frontier,
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"fabric_graph_hash": graph_hash,
		"fabric_compiler_version": fabric_compiler_version,
		"boundary_contract": boundary,
		"bake_policy_hash": bake_policy_hash,
		"reduced_model_descriptor_hash": String(descriptor["checksum"]),
		"reduced_state_schema_hash": String(descriptor["reduced_state_schema_hash"]),
		"validated_domain": validated,
		"error_envelope": error_envelope,
		"conservation_envelope": conservation,
		"refinement_guards": guard_field["region_guards"],
		"reconstruction_descriptor": reconstruction,
		"state_mapping": state_mapping,
		"build_generation": build_generation,
		"error_certified": true,
		"refinement_guard_certified": true,
		"complexity_reduction_certified": true,
	})
	if result.is_empty() or String(result.get("status", "")) != "BAKE_READY":
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_FOUNDATION_COMPILE_NOT_READY", {"result": result})
	return {"success": true, "artifact": result["artifact"]}

static func _boundary_contract(index: int, descriptor: Dictionary) -> Dictionary:
	var ports: Array = []
	for anchor_index in range(descriptor["boundary_anchors"].size()):
		var frame_id := "frame/b0-2-e-%03d-%03d" % [index, anchor_index]
		ports.append({
			"port_id": "port/b0-2-e-%03d-%03d-force" % [index, anchor_index],
			"physical_domain": "MECHANICAL",
			"effort_quantity": "quantity/force",
			"flow_quantity": "quantity/linear-velocity",
			"effort_dimension": [1, 1, -2, 0, 0, 0, 0],
			"flow_dimension": [0, 1, -1, 0, 0, 0, 0],
			"frame": frame_id,
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/b0-2-e-%03d" % index,
			"event_observables": ["TOPOLOGY_BREAK"],
		})
		ports.append({
			"port_id": "port/b0-2-e-%03d-%03d-torque" % [index, anchor_index],
			"physical_domain": "MECHANICAL",
			"effort_quantity": "quantity/torque",
			"flow_quantity": "quantity/angular-velocity",
			"effort_dimension": [1, 2, -2, 0, 0, 0, 0],
			"flow_dimension": [0, 0, -1, 0, 0, 0, 0],
			"frame": frame_id,
			"orientation": "INTO_SUBSYSTEM",
			"conservation_group": "group/b0-2-e-%03d" % index,
			"event_observables": ["TOPOLOGY_BREAK"],
		})
	return BoundaryContract.create(ports)

static func _validate_frontier_transition(previous: Dictionary, current: Dictionary) -> Dictionary:
	if String(previous["frontier_hash"]) == String(current["frontier_hash"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_FRONTIER_NOT_ADVANCED")
	var previous_by_key: Dictionary = {}
	for source in previous["sources"]:
		previous_by_key[Utils.source_key(String(source["source_domain"]), String(source["source_id"]))] = source
	var current_by_key: Dictionary = {}
	for source in current["sources"]:
		current_by_key[Utils.source_key(String(source["source_domain"]), String(source["source_id"]))] = source
	var previous_keys: Array = previous_by_key.keys(); previous_keys.sort()
	var current_keys: Array = current_by_key.keys(); current_keys.sort()
	if previous_keys != current_keys:
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_SOURCE_SET_CHANGED")
	var changed := 0
	for key in previous_keys:
		var before: Dictionary = previous_by_key[key]
		var after: Dictionary = current_by_key[key]
		if int(before["authority_epoch"]) != int(after["authority_epoch"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_AUTHORITY_EPOCH_CHANGED", {"source_key": key})
		if String(before["dependency_hash"]) != String(after["dependency_hash"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_SOURCE_DEPENDENCY_CHANGED", {"source_key": key})
		if String(before["checksum"]) == String(after["checksum"]):
			continue
		changed += 1
		if String(before["source_domain"]) != "CONSTRUCTION":
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_NON_CONSTRUCTION_SOURCE_CHANGED", {"source_key": key})
		if int(after["source_revision"]) != int(before["source_revision"]) + 1:
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_CONSTRUCTION_REVISION_NOT_NEXT")
		if String(after["source_hash"]) == String(before["source_hash"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_CONSTRUCTION_HASH_UNCHANGED")
	if changed != 1:
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_REQUIRES_ONE_CONSTRUCTION_REVISION", {"changed": changed})
	return Utils.success()

static func _validate_parts(parts: Array) -> Dictionary:
	var previous := ""
	for index in range(parts.size()):
		var raw = parts[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_PART", {"index": index})
		var part: Dictionary = raw
		var checked := Utils.validate_exact_fields(part, PART_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var part_id := String(part.get("part_id", ""))
		if not Utils.is_canonical_id(part_id, 2) or index > 0 and part_id <= previous:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_PART_ID", {"index": index})
		previous = part_id
	return Utils.success()

static func _validate_bonds(bonds: Array, parts: Array) -> Dictionary:
	var part_ids: Dictionary = {}
	for part in parts:
		part_ids[String(part["part_id"])] = true
	var previous := ""
	for index in range(bonds.size()):
		var raw = bonds[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_BOND", {"index": index})
		var bond: Dictionary = raw
		var checked := Utils.validate_exact_fields(bond, BOND_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var bond_id := String(bond.get("bond_id", ""))
		if not Utils.is_canonical_id(bond_id, 2) or index > 0 and bond_id <= previous:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_BOND_ID", {"index": index})
		previous = bond_id
		if typeof(bond.get("rigid")) != TYPE_BOOL or not bool(bond["rigid"]):
			return Utils.failure("NO_SAFE_TOPOLOGY_REBAKE_NON_RIGID_BOND", {"bond_id": bond_id})
		if String(bond["part_a"]) == String(bond["part_b"]) or not part_ids.has(String(bond["part_a"])) or not part_ids.has(String(bond["part_b"])):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_BOND_ENDPOINT", {"bond_id": bond_id})
	return Utils.success()

static func _validate_anchors(anchors: Array, parts: Array) -> Dictionary:
	var part_ids: Dictionary = {}
	for part in parts:
		part_ids[String(part["part_id"])] = true
	var previous := ""
	for index in range(anchors.size()):
		var raw = anchors[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_ANCHOR", {"index": index})
		var anchor: Dictionary = raw
		var checked := Utils.validate_exact_fields(anchor, ANCHOR_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var anchor_id := String(anchor.get("anchor_id", ""))
		if not Utils.is_canonical_id(anchor_id, 2) or index > 0 and anchor_id <= previous or not part_ids.has(String(anchor.get("part_id", ""))):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_ANCHOR_ID", {"index": index})
		previous = anchor_id
	return Utils.success()

static func _validate_exact_bond_break(previous_bonds: Array, current_bonds: Array, broken_bond_id: String) -> Dictionary:
	if current_bonds.size() != previous_bonds.size() - 1:
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_BOND_DELTA_COUNT_INVALID")
	var previous_by_id: Dictionary = {}
	for bond in previous_bonds:
		previous_by_id[String(bond["bond_id"])] = bond
	if not previous_by_id.has(broken_bond_id):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_BROKEN_BOND_MISSING")
	var current_by_id: Dictionary = {}
	for bond in current_bonds:
		current_by_id[String(bond["bond_id"])] = bond
	if current_by_id.has(broken_bond_id):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_BROKEN_BOND_STILL_PRESENT")
	for bond_id in previous_by_id.keys():
		if String(bond_id) == broken_bond_id:
			continue
		if not current_by_id.has(bond_id) or JSON.stringify(previous_by_id[bond_id]) != JSON.stringify(current_by_id[bond_id]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_UNDECLARED_BOND_MUTATION", {"bond_id": bond_id})
	return Utils.success()

static func _connected_components(part_ids_raw: Array, adjacency: Dictionary) -> Array:
	var part_ids: Array = part_ids_raw.duplicate(); part_ids.sort()
	var visited: Dictionary = {}
	var output: Array = []
	for seed_raw in part_ids:
		var seed := String(seed_raw)
		if visited.has(seed):
			continue
		var queue: Array = [seed]
		visited[seed] = true
		var component: Array = []
		while not queue.is_empty():
			var current := String(queue.pop_front())
			component.append(current)
			var neighbors: Array = adjacency[current].duplicate(); neighbors.sort()
			for neighbor_raw in neighbors:
				var neighbor := String(neighbor_raw)
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				queue.append(neighbor)
		component.sort()
		output.append(component)
	output.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	return output

static func _predecessor_piece_ids(component_set: Dictionary, local_plan: Dictionary) -> Array:
	var ids: Array = []
	for part_id in local_plan["target_part_ids"]:
		if component_set.has(String(part_id)):
			ids.append("piece/b0-2-d-full-target")
			break
	for index in range(local_plan["residual_components"].size()):
		for part_id in local_plan["residual_components"][index]["part_ids"]:
			if component_set.has(String(part_id)):
				ids.append("piece/b0-2-d-residual-%03d" % index)
				break
	ids.sort()
	return ids

static func _capacity_hash(source_frontier_hash: String, capacities: Array) -> String:
	return Utils.canonical_hash({
		"schema": "planet_simulator.fabric_bake_structural_capacity_set.v1",
		"source_frontier_hash": source_frontier_hash,
		"bond_capacity_specs": Utils.sorted_dicts(capacities, "bond_id"),
	})

static func _event_with_hash(event_request: Dictionary) -> Dictionary:
	var event := event_request.duplicate(true)
	event["event_hash"] = ""
	event["event_hash"] = Transaction.event_hash(event)
	return event

static func _guard_bond_by_id(models: Array, bond_id: String) -> Dictionary:
	for model in models:
		if String(model["bond_id"]) == bond_id:
			return model
	return {}

static func _bond_by_id(bonds: Array, bond_id: String) -> Dictionary:
	for bond in bonds:
		if String(bond["bond_id"]) == bond_id:
			return bond
	return {}

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _quat(value: Array) -> Quaternion:
	return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3])).normalized()

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
