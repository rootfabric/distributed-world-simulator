extends RefCounted
## T4 compiler: exact symmetry lumping of many physical thermal cells into a compact stateful filter.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/thermal_pack_graph_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/thermal_filter_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/thermal_filter_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/thermal_filter_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T4_THERMAL_FILTER_COMPILER_R1"

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("THERMAL_FILTER_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound := false
	var matter_bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			graph_bound = true
		if String(source.get("source_domain", "")) == "MATTER" and String(source.get("source_hash", "")) == String(graph.material_catalog.catalog_hash):
			matter_bound = true
	if not graph_bound:
		return U.failure("THERMAL_FILTER_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:
		return U.failure("THERMAL_FILTER_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var layers := int(graph.layer_count)
	var lanes := int(graph.lane_count)
	var layer_capacity: Array = []
	var layer_material_ids: Array = []
	var layer_conductivity: Array = []
	var total_mass := 0.0
	var max_temperature := INF

	for layer_index in range(layers):
		var reference := Graph.cell_by_slot(graph, layer_index, 0)
		if reference.is_empty() or not bool(reference.enabled):
			return U.failure("THERMAL_PACK_LAYER_SYMMETRY_BROKEN", {"layer": layer_index, "reason": "reference_disabled_or_missing"})
		var material := MatterCatalog.material_by_id(graph.material_catalog, String(reference.material_id))
		if material.is_empty():
			return U.failure("THERMAL_PACK_CELL_MATERIAL_MISSING", {"layer": layer_index})
		var reference_capacity := _cell_capacity(material, reference)
		var reference_mass := float(material.density_kg_m3) * float(reference.volume_m3)
		for lane_index in range(lanes):
			var cell := Graph.cell_by_slot(graph, layer_index, lane_index)
			if cell.is_empty() or not bool(cell.enabled):
				return U.failure("THERMAL_PACK_LAYER_SYMMETRY_BROKEN", {"layer": layer_index, "lane": lane_index, "reason": "disabled_or_missing"})
			if String(cell.material_id) != String(reference.material_id):
				return U.failure("THERMAL_PACK_LAYER_SYMMETRY_BROKEN", {"layer": layer_index, "lane": lane_index, "reason": "material"})
			if absf(float(cell.volume_m3) - float(reference.volume_m3)) > 1.0e-15:
				return U.failure("THERMAL_PACK_LAYER_SYMMETRY_BROKEN", {"layer": layer_index, "lane": lane_index, "reason": "volume"})
		layer_capacity.append(reference_capacity * float(lanes))
		layer_material_ids.append(String(reference.material_id))
		layer_conductivity.append(float(material.thermal_conductivity_w_m_k))
		total_mass += reference_mass * float(lanes)
		max_temperature = minf(max_temperature, float(material.melting_temperature_k))

	var link_conductance: Array = []
	for layer_index in range(layers - 1):
		var k_a := float(layer_conductivity[layer_index])
		var k_b := float(layer_conductivity[layer_index + 1])
		var k_eff := 2.0 * k_a * k_b / (k_a + k_b)
		var per_lane := k_eff * float(graph.interlayer_contact_area_m2) / float(graph.interlayer_contact_length_m)
		link_conductance.append(per_lane * float(lanes))
	var ambient_conductance := float(layer_conductivity[layers - 1]) * float(graph.ambient_surface_area_m2) / float(graph.ambient_wall_thickness_m) * float(lanes)
	if ambient_conductance <= 0.0 or max_temperature <= 1.0:
		return U.failure("THERMAL_FILTER_DERIVATION_INVALID")

	var interface := Interface.create()
	if interface.is_empty():
		return U.failure("THERMAL_FILTER_INTERFACE_CREATE_FAILED")
	var source_count := layers * lanes
	var source_operations := source_count * 6
	var compiled_operations := layers * 4 + 4
	var descriptor := Descriptor.create({
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"interface_contract": interface,
		"layer_count": layers,
		"lane_count": lanes,
		"source_cell_count": source_count,
		"layer_capacity_j_k": layer_capacity,
		"layer_link_conductance_w_k": link_conductance,
		"ambient_conductance_w_k": ambient_conductance,
		"total_mass_kg": total_mass,
		"min_temperature_k": 1.0,
		"max_temperature_k": max_temperature,
		"source_operation_count": source_operations,
		"compiled_operation_count": compiled_operations,
	})
	if descriptor.is_empty():
		return U.failure("THERMAL_FILTER_DESCRIPTOR_CREATE_FAILED")
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
		return U.failure("THERMAL_FILTER_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
		"reduction": "EXACT_SYMMETRY_LUMPING",
	})
	var capsule := Capsule.create(
		capsule_id,
		"THERMAL_FILTER",
		"EXACT_SYMMETRY_LUMPING",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"THERMAL_FILTER",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		source_count,
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["STATEFUL", "THERMAL", "FILTER", "EXACT_LUMPING"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("THERMAL_FILTER_CAPSULE_CREATE_FAILED")
	return U.success({
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"source_cells": source_count,
			"layers": layers,
			"lanes": lanes,
			"state_scalars": layers,
			"source_operations": source_operations,
			"compiled_operations": compiled_operations,
		},
	})

static func _cell_capacity(material: Dictionary, cell: Dictionary) -> float:
	var mass := float(material.density_kg_m3) * float(cell.volume_m3)
	return mass * float(material.heat_capacity_j_kg_k)
