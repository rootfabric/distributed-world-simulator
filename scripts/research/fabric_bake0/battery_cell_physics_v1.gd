extends RefCounted
## Derives cell electrical/thermal behavior from Matter material + geometry + quality.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/battery_cell_graph_v1.gd")

static func derive(graph: Dictionary, cell: Dictionary) -> Dictionary:
	var profile := Graph.profile_by_id(graph, String(cell.profile_id))
	if profile.is_empty():
		return U.failure("BATTERY_CELL_PROFILE_NOT_FOUND")
	var active_material := MatterCatalog.material_by_id(graph.material_catalog, String(profile.active_material_id))
	var case_material := MatterCatalog.material_by_id(graph.material_catalog, String(cell.case_material_id))
	if active_material.is_empty() or case_material.is_empty():
		return U.failure("BATTERY_CELL_MATERIAL_NOT_FOUND")
	var quality := float(cell.quality_ratio)
	var active_mass := float(active_material.density_kg_m3) * float(cell.active_volume_m3)
	var case_mass := float(case_material.density_kg_m3) * float(cell.case_volume_m3)
	var base_capacity := float(profile.specific_capacity_c_per_kg) * active_mass
	var capacity := base_capacity * quality
	var base_resistance := float(cell.current_path_length_m) / (float(profile.effective_conductivity_s_m) * float(cell.electrode_area_m2))
	base_resistance += float(profile.contact_resistivity_ohm_m2) / float(cell.electrode_area_m2)
	var resistance := base_resistance / quality
	var conductance := 1.0 / resistance
	var max_current := float(profile.max_current_density_a_m2) * float(cell.electrode_area_m2) * quality
	var thermal_capacity := active_mass * float(active_material.heat_capacity_j_kg_k) + case_mass * float(case_material.heat_capacity_j_kg_k)
	var thermal_conductance := float(case_material.thermal_conductivity_w_m_k) * float(cell.case_surface_area_m2) / float(cell.case_wall_thickness_m)
	var row := {
		"cell_id": String(cell.cell_id),
		"series_index": int(cell.series_index),
		"parallel_index": int(cell.parallel_index),
		"profile_id": String(cell.profile_id),
		"enabled": bool(cell.enabled),
		"quality_ratio": quality,
		"active_mass_kg": active_mass,
		"case_mass_kg": case_mass,
		"mass_kg": active_mass + case_mass,
		"capacity_c": capacity,
		"resistance_ref_ohm": resistance,
		"conductance_ref_s": conductance,
		"max_current_a": max_current,
		"thermal_capacity_j_k": thermal_capacity,
		"thermal_conductance_w_k": thermal_conductance,
		"empty_voltage_v": float(profile.empty_voltage_v),
		"nominal_voltage_v": float(profile.nominal_voltage_v),
		"full_voltage_v": float(profile.full_voltage_v),
		"resistance_temp_coefficient_per_k": float(profile.resistance_temp_coefficient_per_k),
		"reference_temperature_k": float(profile.reference_temperature_k),
		"min_temperature_k": float(profile.min_temperature_k),
		"max_temperature_k": float(profile.max_temperature_k),
		"synchrony_ratio_s_per_c": conductance / capacity,
	}
	for field in [
		"active_mass_kg", "case_mass_kg", "mass_kg", "capacity_c", "resistance_ref_ohm",
		"conductance_ref_s", "max_current_a", "thermal_capacity_j_k", "thermal_conductance_w_k"
	]:
		if not U.is_positive_number(row[field]):
			return U.failure("BATTERY_CELL_DERIVATION_NONPOSITIVE", {"field": field})
	return U.success({"cell": row})

static func resistance_at_temperature(cell_row: Dictionary, temperature_k: float) -> float:
	var factor := 1.0 + float(cell_row.resistance_temp_coefficient_per_k) * (temperature_k - float(cell_row.reference_temperature_k))
	return float(cell_row.resistance_ref_ohm) * maxf(factor, 0.05)

static func ocv_at_soc(cell_row: Dictionary, soc: float) -> float:
	var bounded := clampf(soc, 0.0, 1.0)
	return float(cell_row.empty_voltage_v) + (float(cell_row.full_voltage_v) - float(cell_row.empty_voltage_v)) * bounded

static func chemical_energy_j(capacity_c: float, charge_c: float, empty_v: float, full_v: float) -> float:
	var q := clampf(charge_c, 0.0, capacity_c)
	if capacity_c <= 0.0:
		return 0.0
	return empty_v * q + 0.5 * (full_v - empty_v) * q * q / capacity_c
