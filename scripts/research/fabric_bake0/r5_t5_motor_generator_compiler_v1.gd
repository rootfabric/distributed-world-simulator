extends RefCounted
## T5 compiler: series winding + rigid rotor -> bidirectional motor/generator capsule.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/motor_generator_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/motor_generator_physics_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/motor_generator_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/motor_generator_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/motor_generator_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T5_MOTOR_GENERATOR_COMPILER_R1"

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("MOTOR_GENERATOR_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound := false
	var matter_bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			graph_bound = true
		if String(source.get("source_domain", "")) == "MATTER" and String(source.get("source_hash", "")) == String(graph.material_catalog.catalog_hash):
			matter_bound = true
	if not graph_bound:
		return U.failure("MOTOR_GENERATOR_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:
		return U.failure("MOTOR_GENERATOR_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var total_resistance := 0.0
	var total_k := 0.0
	var max_current := INF
	var winding_mass := 0.0
	for winding in graph.winding_segments:
		if not bool(winding.enabled):
			return U.failure("MOTOR_WINDING_OPEN", {"winding_id": winding.winding_id})
		var derived := Physics.derive_winding(graph, winding)
		if not derived.success:
			return derived
		var row: Dictionary = derived.details.winding
		total_resistance += float(row.resistance_ohm)
		total_k += float(row.torque_constant_nm_a)
		max_current = minf(max_current, float(row.max_current_a))
		winding_mass += float(row.wire_mass_kg)

	var rotor_mass := 0.0
	var rotor_inertia := 0.0
	var max_omega := INF
	for sector in graph.rotor_sectors:
		if not bool(sector.enabled):
			return U.failure("MOTOR_ROTOR_INCOMPLETE", {"sector_id": sector.sector_id})
		var derived := Physics.derive_rotor_sector(graph, sector)
		if not derived.success:
			return derived
		var row: Dictionary = derived.details.sector
		rotor_mass += float(row.mass_kg)
		rotor_inertia += float(row.inertia_kg_m2)
		max_omega = minf(max_omega, float(row.max_abs_angular_velocity_rad_s))

	for number in [total_resistance, total_k, max_current, winding_mass, rotor_mass, rotor_inertia, max_omega]:
		if not U.is_positive_number(number):
			return U.failure("MOTOR_GENERATOR_AGGREGATE_INVALID")

	var interface := Interface.create()
	if interface.is_empty():
		return U.failure("MOTOR_GENERATOR_INTERFACE_CREATE_FAILED")
	var source_count := int(graph.winding_segments.size()) + int(graph.rotor_sectors.size())
	var source_operations := int(graph.winding_segments.size()) * 6 + int(graph.rotor_sectors.size()) * 4
	var compiled_operations := 14
	var descriptor := Descriptor.create({
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"interface_contract": interface,
		"winding_segment_count": graph.winding_segments.size(),
		"rotor_sector_count": graph.rotor_sectors.size(),
		"total_resistance_ohm": total_resistance,
		"torque_constant_nm_a": total_k,
		"back_emf_constant_v_s_rad": total_k,
		"max_abs_current_a": max_current,
		"winding_mass_kg": winding_mass,
		"rotor_mass_kg": rotor_mass,
		"rotor_inertia_kg_m2": rotor_inertia,
		"max_abs_angular_velocity_rad_s": max_omega,
		"source_operation_count": source_operations,
		"compiled_operation_count": compiled_operations,
	})
	if descriptor.is_empty():
		return U.failure("MOTOR_GENERATOR_DESCRIPTOR_CREATE_FAILED")
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
		return U.failure("MOTOR_GENERATOR_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
		"reduction": "ADDITIVE_SERIES_WINDING_RIGID_ROTOR",
	})
	var capsule := Capsule.create(
		capsule_id,
		"MOTOR_GENERATOR",
		"ADDITIVE_RIGID_ROTOR",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"MOTOR_GENERATOR",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		source_count,
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["BIDIRECTIONAL", "ELECTRICAL", "MECHANICAL", "STATEFUL"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("MOTOR_GENERATOR_CAPSULE_CREATE_FAILED")
	return U.success({
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"source_components": source_count,
			"winding_segments": graph.winding_segments.size(),
			"rotor_sectors": graph.rotor_sectors.size(),
			"state_scalars": 1,
			"source_operations": source_operations,
			"compiled_operations": compiled_operations,
		},
	})
