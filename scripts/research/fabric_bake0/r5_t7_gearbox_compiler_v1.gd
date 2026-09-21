extends RefCounted
## T7 compiler: explicit multi-stage gears/teeth -> compact lossless rigid gearbox boundary.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/gearbox_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/gearbox_physics_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/gearbox_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/gearbox_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/gearbox_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T7_GEARBOX_COMPILER_R1"

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("GEARBOX_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound := false
	var matter_bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			graph_bound = true
		if String(source.get("source_domain", "")) == "MATTER" and String(source.get("source_hash", "")) == String(graph.material_catalog.catalog_hash):
			matter_bound = true
	if not graph_bound:
		return U.failure("GEARBOX_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:
		return U.failure("GEARBOX_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var stages: int = Graph.stage_count(graph)
	var stage_ratios: Array = []
	var total_ratio := 1.0
	var equivalent_input_inertia := 0.0
	var total_mass := 0.0
	var max_input_torque := INF
	var max_input_omega := INF
	var driver_omega_ratio := 1.0

	for stage in range(stages):
		var driver := Graph.gear_by_stage_role(graph, stage, "DRIVER")
		var driven := Graph.gear_by_stage_role(graph, stage, "DRIVEN")
		if driver.is_empty() or driven.is_empty():
			return U.failure("GEARBOX_STAGE_INCOMPLETE", {"stage": stage})
		if absf(float(driver.module_m) - float(driven.module_m)) > 1.0e-15:
			return U.failure("GEARBOX_MESH_MODULE_MISMATCH", {"stage": stage})
		var driver_result := Physics.derive_gear(graph, driver, Graph.teeth_for_gear(graph, String(driver.gear_id)))
		if not driver_result.success:
			return driver_result
		var driven_result := Physics.derive_gear(graph, driven, Graph.teeth_for_gear(graph, String(driven.gear_id)))
		if not driven_result.success:
			return driven_result
		var a: Dictionary = driver_result.details.gear
		var b: Dictionary = driven_result.details.gear
		var stage_ratio := -float(a.tooth_count) / float(b.tooth_count)
		var driven_omega_ratio := driver_omega_ratio * stage_ratio
		stage_ratios.append(stage_ratio)
		total_ratio *= stage_ratio
		equivalent_input_inertia += float(a.inertia_kg_m2) * driver_omega_ratio * driver_omega_ratio
		equivalent_input_inertia += float(b.inertia_kg_m2) * driven_omega_ratio * driven_omega_ratio
		total_mass += float(a.mass_kg) + float(b.mass_kg)
		max_input_omega = minf(max_input_omega, float(a.max_abs_omega_rad_s) / absf(driver_omega_ratio))
		max_input_omega = minf(max_input_omega, float(b.max_abs_omega_rad_s) / absf(driven_omega_ratio))
		var mesh_force_limit := minf(float(a.tangential_force_limit_n), float(b.tangential_force_limit_n))
		var stage_input_torque_limit := mesh_force_limit * absf(driver_omega_ratio) * float(a.pitch_radius_m)
		max_input_torque = minf(max_input_torque, stage_input_torque_limit)
		driver_omega_ratio = driven_omega_ratio

	if absf(total_ratio) <= 1.0e-18 or not is_finite(total_ratio):
		return U.failure("GEARBOX_TOTAL_RATIO_INVALID")
	var interface := Interface.create()
	if interface.is_empty():
		return U.failure("GEARBOX_INTERFACE_CREATE_FAILED")
	var source_gears: int = int(graph.gears.size())
	var source_teeth: int = int(graph.teeth.size())
	var source_components: int = source_gears + source_teeth
	var source_operations: int = source_components * 6
	var compiled_operations: int = 16
	var descriptor := Descriptor.create({
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"interface_contract": interface,
		"stage_count": stages,
		"source_gear_count": source_gears,
		"source_tooth_count": source_teeth,
		"stage_speed_ratios": stage_ratios,
		"total_speed_ratio": total_ratio,
		"equivalent_input_inertia_kg_m2": equivalent_input_inertia,
		"total_mass_kg": total_mass,
		"max_abs_input_torque_nm": max_input_torque,
		"max_abs_output_torque_nm": max_input_torque / absf(total_ratio),
		"max_abs_input_omega_rad_s": max_input_omega,
		"max_abs_output_omega_rad_s": max_input_omega * absf(total_ratio),
		"source_operation_count": source_operations,
		"compiled_operation_count": compiled_operations,
	})
	if descriptor.is_empty():
		return U.failure("GEARBOX_DESCRIPTOR_CREATE_FAILED")
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
		return U.failure("GEARBOX_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
		"reduction": "RIGID_MULTI_STAGE_GEAR_TRAIN",
	})
	var capsule := Capsule.create(
		capsule_id,
		"GEARBOX",
		"RIGID_MULTI_STAGE_GEAR_TRAIN",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"GEARBOX",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		source_components,
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["BIDIRECTIONAL", "KINEMATIC", "MECHANICAL", "STATELESS"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("GEARBOX_CAPSULE_CREATE_FAILED")
	return U.success({
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"source_gears": source_gears,
			"source_teeth": source_teeth,
			"source_components": source_components,
			"source_operations": source_operations,
			"compiled_operations": compiled_operations,
		},
	})
