extends RefCounted
## T3 battery compiler. Derives pack behavior from cells/materials/geometry/quality.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/battery_cell_graph_v1.gd")
const CellPhysics = preload("res://scripts/research/fabric_bake0/battery_cell_physics_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/battery_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/battery_pack_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/battery_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")

const VERSION := "FABRIC_R5_2_T3_BATTERY_COMPILER_R1"
const SYNCHRONY_REL_TOL := 1.0e-10

static func compile(graph: Dictionary, request: Dictionary, capsule_id: String) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	if typeof(request.get("canonical_source_frontier")) != TYPE_DICTIONARY:
		return U.failure("BATTERY_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound := false
	var matter_bound := false
	for source in request.canonical_source_frontier.get("sources", []):
		if String(source.get("source_domain", "")) == "CONSTRUCTION" and String(source.get("source_hash", "")) == String(graph.graph_hash):
			graph_bound = true
		if String(source.get("source_domain", "")) == "MATTER" and String(source.get("source_hash", "")) == String(graph.material_catalog.catalog_hash):
			matter_bound = true
	if not graph_bound:
		return U.failure("BATTERY_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:
		return U.failure("BATTERY_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var series_count: int = int(graph.series_group_count)
	var groups: Array = []
	groups.resize(series_count)
	for group_index in range(series_count):
		groups[group_index] = []
	var all_rows: Array = []
	var active_cell_count: int = 0
	for cell in graph.cells:
		var derived := CellPhysics.derive(graph, cell)
		if not derived.success:
			return derived
		var row: Dictionary = derived.details.cell
		all_rows.append(row)
		groups[int(row.series_index)].append(row)
		if bool(row.enabled):
			active_cell_count += 1

	var group_profile_ids: Array = []
	var group_capacity_c: Array = []
	var group_resistance_ref_ohm: Array = []
	var group_empty_voltage_v: Array = []
	var group_nominal_voltage_v: Array = []
	var group_full_voltage_v: Array = []
	var group_max_current_a: Array = []
	var group_alpha: Array = []
	var group_reference_temperature_k: Array = []
	var total_mass_kg := 0.0
	var thermal_capacity_j_k := 0.0
	var thermal_conductance_w_k := 0.0
	var pack_min_temperature_k := 0.0
	var pack_max_temperature_k := INF
	var pack_empty_voltage_v := 0.0
	var pack_nominal_voltage_v := 0.0
	var pack_full_voltage_v := 0.0
	var full_chemical_energy_j := 0.0
	var max_continuous_current_a := INF

	for row in all_rows:
		total_mass_kg += float(row.mass_kg)
		thermal_capacity_j_k += float(row.thermal_capacity_j_k)
		thermal_conductance_w_k += float(row.thermal_conductance_w_k)
		pack_min_temperature_k = maxf(pack_min_temperature_k, float(row.min_temperature_k))
		pack_max_temperature_k = minf(pack_max_temperature_k, float(row.max_temperature_k))

	for group_index in range(series_count):
		var rows: Array = groups[group_index]
		var active_rows: Array = []
		for row in rows:
			if bool(row.enabled):
				active_rows.append(row)
		if active_rows.is_empty():
			return U.failure("BATTERY_SERIES_GROUP_OPEN", {"series_index": group_index})
		var profile_id := String(active_rows[0].profile_id)
		var synchrony_reference := float(active_rows[0].synchrony_ratio_s_per_c)
		var capacity_sum := 0.0
		var conductance_sum := 0.0
		var max_current_sum := 0.0
		for row in active_rows:
			if String(row.profile_id) != profile_id:
				return U.failure("BATTERY_PARALLEL_PROFILE_MISMATCH", {"series_index": group_index})
			var ratio := float(row.synchrony_ratio_s_per_c)
			var scale := maxf(1.0e-18, maxf(absf(ratio), absf(synchrony_reference)))
			if absf(ratio - synchrony_reference) > SYNCHRONY_REL_TOL * scale:
				return U.failure("BATTERY_PARALLEL_SOC_SYNCHRONY_UNSAFE", {
					"series_index": group_index,
					"cell_id": row.cell_id,
					"reference_ratio": synchrony_reference,
					"actual_ratio": ratio,
				})
			capacity_sum += float(row.capacity_c)
			conductance_sum += float(row.conductance_ref_s)
			max_current_sum += float(row.max_current_a)
		if capacity_sum <= 0.0 or conductance_sum <= 0.0 or max_current_sum <= 0.0:
			return U.failure("BATTERY_GROUP_AGGREGATE_INVALID", {"series_index": group_index})
		var first: Dictionary = active_rows[0]
		var resistance := 1.0 / conductance_sum
		group_profile_ids.append(profile_id)
		group_capacity_c.append(capacity_sum)
		group_resistance_ref_ohm.append(resistance)
		group_empty_voltage_v.append(float(first.empty_voltage_v))
		group_nominal_voltage_v.append(float(first.nominal_voltage_v))
		group_full_voltage_v.append(float(first.full_voltage_v))
		group_max_current_a.append(max_current_sum)
		group_alpha.append(float(first.resistance_temp_coefficient_per_k))
		group_reference_temperature_k.append(float(first.reference_temperature_k))
		pack_empty_voltage_v += float(first.empty_voltage_v)
		pack_nominal_voltage_v += float(first.nominal_voltage_v)
		pack_full_voltage_v += float(first.full_voltage_v)
		full_chemical_energy_j += CellPhysics.chemical_energy_j(
			capacity_sum, capacity_sum, float(first.empty_voltage_v), float(first.full_voltage_v)
		)
		max_continuous_current_a = minf(max_continuous_current_a, max_current_sum)

	if pack_min_temperature_k >= pack_max_temperature_k:
		return U.failure("BATTERY_PACK_TEMPERATURE_DOMAIN_EMPTY")
	var interface := Interface.create()
	if interface.is_empty():
		return U.failure("BATTERY_INTERFACE_CREATE_FAILED")
	var source_operations: int = graph.cells.size() * 8
	var compiled_operations: int = series_count * 3 + 6
	var descriptor := Descriptor.create({
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"interface_contract": interface,
		"series_group_count": series_count,
		"source_cell_count": graph.cells.size(),
		"active_cell_count": active_cell_count,
		"group_profile_ids": group_profile_ids,
		"group_capacity_c": group_capacity_c,
		"group_resistance_ref_ohm": group_resistance_ref_ohm,
		"group_empty_voltage_v": group_empty_voltage_v,
		"group_nominal_voltage_v": group_nominal_voltage_v,
		"group_full_voltage_v": group_full_voltage_v,
		"group_max_current_a": group_max_current_a,
		"group_resistance_temp_coefficient_per_k": group_alpha,
		"group_reference_temperature_k": group_reference_temperature_k,
		"total_mass_kg": total_mass_kg,
		"thermal_capacity_j_k": thermal_capacity_j_k,
		"thermal_conductance_w_k": thermal_conductance_w_k,
		"min_temperature_k": pack_min_temperature_k,
		"max_temperature_k": pack_max_temperature_k,
		"max_continuous_current_a": max_continuous_current_a,
		"empty_voltage_v": pack_empty_voltage_v,
		"nominal_voltage_v": pack_nominal_voltage_v,
		"full_voltage_v": pack_full_voltage_v,
		"full_chemical_energy_j": full_chemical_energy_j,
		"source_operation_count": source_operations,
		"compiled_operation_count": compiled_operations,
	})
	if descriptor.is_empty():
		return U.failure("BATTERY_DESCRIPTOR_CREATE_FAILED")
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
		return U.failure("BATTERY_ARTIFACT_CREATE_FAILED")
	var provenance := U.canonical_hash({
		"compiler_version": VERSION,
		"graph_hash": graph.graph_hash,
		"material_catalog_hash": graph.material_catalog.catalog_hash,
		"descriptor_hash": descriptor.descriptor_hash,
		"artifact_hash": artifact.artifact_hash,
	})
	var capsule := Capsule.create(
		capsule_id,
		"BATTERY_PACK",
		"GROUP_AGGREGATE",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"BATTERY_PACK",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		int(graph.cells.size()),
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["BATTERY", "ELECTRICAL", "STATEFUL", "THERMAL"],
		provenance
	)
	if capsule.is_empty():
		return U.failure("BATTERY_CAPSULE_CREATE_FAILED")
	return U.success({
		"descriptor": descriptor,
		"artifact": artifact,
		"capsule": capsule,
		"compile_stats": {
			"source_cells": graph.cells.size(),
			"active_cells": active_cell_count,
			"series_groups": series_count,
			"source_operations": source_operations,
			"compiled_operations": compiled_operations,
		},
	})
