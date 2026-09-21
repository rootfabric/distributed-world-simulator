extends RefCounted
## T8 compiler: exact symmetric lane lumping for an active coolant loop.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/cooling_loop_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/cooling_loop_physics_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/cooling_loop_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/cooling_loop_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/cooling_loop_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T8_COOLING_LOOP_COMPILER_R1"

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("COOLING_LOOP_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound := false
	var matter_bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			graph_bound = true
		if String(source.get("source_domain", "")) == "MATTER" and String(source.get("source_hash", "")) == String(graph.material_catalog.catalog_hash):
			matter_bound = true
	if not graph_bound:
		return U.failure("COOLING_LOOP_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:
		return U.failure("COOLING_LOOP_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var reference_row: Dictionary = {}
	var reference_signature := ""
	for index in range(graph.lanes.size()):
		var derived := Physics.derive_lane(graph, graph.lanes[index])
		if not derived.success:
			return derived
		var row: Dictionary = derived.details.lane
		var signature := U.canonical_hash(_lane_signature(row))
		if index == 0:
			reference_row = row
			reference_signature = signature
		elif signature != reference_signature:
			return U.failure("COOLING_LANE_SYMMETRY_BROKEN", {"lane_id": row.lane_id})
	if reference_row.is_empty():
		return U.failure("COOLING_LOOP_NO_LANES")

	var lane_count: int = int(graph.lanes.size())
	var node_count: int = lane_count * 4
	var interface := Interface.create()
	if interface.is_empty():
		return U.failure("COOLING_LOOP_INTERFACE_CREATE_FAILED")
	var source_operations: int = node_count * 6
	var compiled_operations: int = 32
	var descriptor := Descriptor.create({
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"interface_contract": interface,
		"lane_count": lane_count,
		"source_thermal_node_count": node_count,
		"plate_capacity_j_k": float(reference_row.plate_capacity_j_k) * lane_count,
		"hot_coolant_capacity_j_k": float(reference_row.hot_coolant_capacity_j_k) * lane_count,
		"radiator_capacity_j_k": float(reference_row.radiator_capacity_j_k) * lane_count,
		"cold_coolant_capacity_j_k": float(reference_row.cold_coolant_capacity_j_k) * lane_count,
		"plate_to_hot_conductance_w_k": float(reference_row.plate_to_hot_conductance_w_k) * lane_count,
		"cold_to_radiator_conductance_w_k": float(reference_row.cold_to_radiator_conductance_w_k) * lane_count,
		"radiator_to_ambient_conductance_w_k": float(reference_row.radiator_to_ambient_conductance_w_k) * lane_count,
		"coolant_heat_capacity_j_kg_k": reference_row.coolant_heat_capacity_j_kg_k,
		"coolant_density_kg_m3": reference_row.coolant_density_kg_m3,
		"dynamic_viscosity_pa_s": reference_row.dynamic_viscosity_pa_s,
		"laminar_reynolds_limit": reference_row.laminar_reynolds_limit,
		"channel_flow_area_m2": reference_row.channel_flow_area_m2,
		"channel_hydraulic_diameter_m": reference_row.channel_hydraulic_diameter_m,
		"channel_flow_length_m": reference_row.channel_flow_length_m,
		"max_total_mass_flow_kg_s": float(reference_row.max_lane_mass_flow_kg_s) * lane_count,
		"total_mass_kg": float(reference_row.total_mass_kg) * lane_count,
		"min_temperature_k": reference_row.min_temperature_k,
		"max_temperature_k": reference_row.max_temperature_k,
		"source_operation_count": source_operations,
		"compiled_operation_count": compiled_operations,
	})
	if descriptor.is_empty():
		return U.failure("COOLING_LOOP_DESCRIPTOR_CREATE_FAILED")
	var artifact := Artifact.create(
		String(request.get("artifact_id", "")),
		request.canonical_source_frontier,
		request.authority_envelope,
		request.dependency_set,
		String(graph.graph_hash),
		String(graph.material_catalog.catalog_hash),
		interface,
		descriptor,
		int(request.get("build_generation", 1))
	)
	if artifact.is_empty():
		return U.failure("COOLING_LOOP_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
		"reduction": "EXACT_SYMMETRIC_COOLING_LANES",
	})
	var capsule := Capsule.create(
		capsule_id,
		"COOLING_LOOP",
		"EXACT_SYMMETRIC_COOLING_LANES",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"COOLING_LOOP",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		node_count,
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["ACTIVE_COOLING", "HYDRAULIC", "STATEFUL", "THERMAL"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("COOLING_LOOP_CAPSULE_CREATE_FAILED")
	return U.success({
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"lanes": lane_count,
			"source_thermal_nodes": node_count,
			"state_scalars": 4,
			"source_operations": source_operations,
			"compiled_operations": compiled_operations,
		},
	})

static func _lane_signature(row: Dictionary) -> Dictionary:
	var value := row.duplicate(true)
	value.erase("lane_id")
	return value
