extends RefCounted
## T9 compiler: identical parallel gain cells in a common optical aperture -> compact laser emitter.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/laser_emitter_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/laser_emitter_physics_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/laser_emitter_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/laser_emitter_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/laser_emitter_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T9_LASER_EMITTER_COMPILER_R1"

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("LASER_EMITTER_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound := false
	var matter_bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			graph_bound = true
		if String(source.get("source_domain", "")) == "MATTER" and String(source.get("source_hash", "")) == String(graph.material_catalog.catalog_hash):
			matter_bound = true
	if not graph_bound:
		return U.failure("LASER_EMITTER_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:
		return U.failure("LASER_EMITTER_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var source_count: int = int(graph.gain_cells.size())
	var active_count := 0
	var total_mass := 0.0
	var reference: Dictionary = {}
	var reference_signature := ""
	for cell in graph.gain_cells:
		var derived := Physics.derive_cell(graph, cell)
		if not derived.success:
			return derived
		var row: Dictionary = derived.details.cell
		total_mass += float(row.mass_kg)
		if not bool(row.enabled):
			continue
		active_count += 1
		var signature := U.canonical_hash(_synchrony_signature(row))
		if reference.is_empty():
			reference = row
			reference_signature = signature
		elif String(row.profile_id) != String(reference.profile_id):
			return U.failure("LASER_GAIN_PROFILE_MISMATCH", {"cell_id": row.cell_id})
		elif signature != reference_signature:
			return U.failure("LASER_GAIN_CELL_SYNCHRONY_UNSAFE", {"cell_id": row.cell_id})
	if active_count < 1 or reference.is_empty():
		return U.failure("LASER_EMITTER_NO_ACTIVE_GAIN_CELLS")

	var effective_aperture := float(reference.aperture_area_m2) * float(active_count)
	var waist_radius := sqrt(effective_aperture / PI)
	var divergence := float(reference.beam_quality_m2) * float(reference.wavelength_m) / (PI * waist_radius)
	var interface := Interface.create()
	if interface.is_empty():
		return U.failure("LASER_EMITTER_INTERFACE_CREATE_FAILED")
	var source_operations: int = source_count * 6
	var compiled_operations: int = 20
	var descriptor := Descriptor.create({
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"interface_contract": interface,
		"source_cell_count": source_count,
		"active_cell_count": active_count,
		"profile_id": reference.profile_id,
		"per_cell_resistance_ref_ohm": reference.resistance_ref_ohm,
		"per_cell_threshold_current_a": reference.threshold_current_a,
		"per_cell_max_current_a": reference.max_current_a,
		"per_cell_aperture_area_m2": reference.aperture_area_m2,
		"forward_voltage_v": reference.forward_voltage_v,
		"reference_optical_efficiency_ratio": reference.reference_optical_efficiency_ratio,
		"efficiency_temp_coefficient_per_k": reference.efficiency_temp_coefficient_per_k,
		"reference_temperature_k": reference.reference_temperature_k,
		"min_temperature_k": reference.min_temperature_k,
		"max_temperature_k": reference.max_temperature_k,
		"wavelength_m": reference.wavelength_m,
		"beam_quality_m2": reference.beam_quality_m2,
		"effective_aperture_area_m2": effective_aperture,
		"beam_divergence_half_angle_rad": divergence,
		"total_threshold_current_a": float(reference.threshold_current_a) * float(active_count),
		"total_max_current_a": float(reference.max_current_a) * float(active_count),
		"total_physical_mass_kg": total_mass,
		"source_operation_count": source_operations,
		"compiled_operation_count": compiled_operations,
	})
	if descriptor.is_empty():
		return U.failure("LASER_EMITTER_DESCRIPTOR_CREATE_FAILED")
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
		return U.failure("LASER_EMITTER_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
		"reduction": "IDENTICAL_GAIN_CELLS_COMMON_APERTURE",
	})
	var capsule := Capsule.create(
		capsule_id,
		"LASER_EMITTER",
		"IDENTICAL_GAIN_CELLS_COMMON_APERTURE",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"LASER_EMITTER",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		source_count,
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["ELECTRICAL", "OPTICAL", "THERMAL", "STATELESS"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("LASER_EMITTER_CAPSULE_CREATE_FAILED")
	return U.success({
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"source_cells": source_count,
			"active_cells": active_count,
			"source_operations": source_operations,
			"compiled_operations": compiled_operations,
		},
	})

static func _synchrony_signature(row: Dictionary) -> Dictionary:
	return {
		"profile_id": row.profile_id,
		"resistance_ref_ohm": row.resistance_ref_ohm,
		"threshold_current_a": row.threshold_current_a,
		"max_current_a": row.max_current_a,
		"forward_voltage_v": row.forward_voltage_v,
		"reference_optical_efficiency_ratio": row.reference_optical_efficiency_ratio,
		"efficiency_temp_coefficient_per_k": row.efficiency_temp_coefficient_per_k,
		"reference_temperature_k": row.reference_temperature_k,
		"min_temperature_k": row.min_temperature_k,
		"max_temperature_k": row.max_temperature_k,
		"wavelength_m": row.wavelength_m,
		"beam_quality_m2": row.beam_quality_m2,
		"aperture_area_m2": row.aperture_area_m2,
	}
