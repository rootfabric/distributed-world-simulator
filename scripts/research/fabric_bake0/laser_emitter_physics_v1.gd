extends RefCounted
## Per-gain-cell electro-optical derivation and evaluation.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/laser_emitter_graph_v1.gd")

const PLANCK_J_S := 6.62607015e-34
const LIGHT_SPEED_M_S := 299792458.0

static func derive_cell(graph: Dictionary, cell: Dictionary) -> Dictionary:
	var profile := Graph.profile_by_id(graph, String(cell.profile_id))
	if profile.is_empty():
		return U.failure("LASER_GAIN_CELL_PROFILE_NOT_FOUND")
	var material := MatterCatalog.material_by_id(graph.material_catalog, String(profile.active_material_id))
	if material.is_empty():
		return U.failure("LASER_GAIN_CELL_MATERIAL_NOT_FOUND")
	var q := float(cell.quality_ratio)
	var area := float(cell.active_area_m2)
	var length := float(cell.current_path_length_m)
	var resistance := float(profile.effective_resistivity_ohm_m) * length / area / q
	var threshold_current := float(profile.threshold_current_density_a_m2) * area / q
	var max_current := float(profile.max_current_density_a_m2) * area * q
	var mass := float(material.density_kg_m3) * area * length
	var aperture_area := area * q
	var row := {
		"cell_id": String(cell.cell_id),
		"profile_id": String(cell.profile_id),
		"enabled": bool(cell.enabled),
		"resistance_ref_ohm": resistance,
		"threshold_current_a": threshold_current,
		"max_current_a": max_current,
		"forward_voltage_v": float(profile.forward_voltage_v),
		"reference_optical_efficiency_ratio": float(profile.reference_optical_efficiency_ratio),
		"efficiency_temp_coefficient_per_k": float(profile.efficiency_temp_coefficient_per_k),
		"reference_temperature_k": float(profile.reference_temperature_k),
		"min_temperature_k": float(profile.min_temperature_k),
		"max_temperature_k": float(profile.max_temperature_k),
		"wavelength_m": float(profile.wavelength_m),
		"beam_quality_m2": float(profile.beam_quality_m2),
		"aperture_area_m2": aperture_area,
		"mass_kg": mass,
	}
	for field in [
		"resistance_ref_ohm", "threshold_current_a", "max_current_a", "forward_voltage_v",
		"reference_optical_efficiency_ratio", "reference_temperature_k", "min_temperature_k",
		"max_temperature_k", "wavelength_m", "beam_quality_m2", "aperture_area_m2", "mass_kg"
	]:
		if not U.is_positive_number(row[field]):
			return U.failure("LASER_GAIN_CELL_DERIVATION_NONPOSITIVE", {"cell_id": cell.cell_id, "field": field})
	if float(row.max_current_a) <= float(row.threshold_current_a):
		return U.failure("LASER_GAIN_CELL_CURRENT_WINDOW_EMPTY", {"cell_id": cell.cell_id})
	return U.success({"cell": row})

static func evaluate_cell(row: Dictionary, current_a: float, temperature_k: float, dt_s: float) -> Dictionary:
	if not U.is_non_negative_number(current_a) or not U.is_positive_number(temperature_k) or not U.is_positive_number(dt_s):
		return U.failure("LASER_GAIN_CELL_STEP_INVALID")
	if temperature_k < float(row.min_temperature_k) or temperature_k > float(row.max_temperature_k):
		return U.failure("LASER_GAIN_CELL_TEMPERATURE_OUT_OF_DOMAIN")
	if current_a > float(row.max_current_a):
		return U.failure("LASER_GAIN_CELL_CURRENT_LIMIT")
	var voltage := float(row.forward_voltage_v) + current_a * float(row.resistance_ref_ohm)
	var electrical_power := voltage * current_a
	var efficiency := float(row.reference_optical_efficiency_ratio)
	if temperature_k > float(row.reference_temperature_k):
		efficiency *= maxf(0.0, 1.0 - float(row.efficiency_temp_coefficient_per_k) * (temperature_k - float(row.reference_temperature_k)))
	efficiency = clampf(efficiency, 0.0, 0.999999999)
	var above_fraction := 0.0
	if current_a > float(row.threshold_current_a) and current_a > 0.0:
		above_fraction = (current_a - float(row.threshold_current_a)) / current_a
	var optical_power := electrical_power * efficiency * above_fraction
	var heat_power := electrical_power - optical_power
	var electrical_energy := electrical_power * dt_s
	var optical_energy := optical_power * dt_s
	var heat_energy := heat_power * dt_s
	var photon_energy := PLANCK_J_S * LIGHT_SPEED_M_S / float(row.wavelength_m)
	var photon_count := optical_energy / photon_energy if photon_energy > 0.0 else 0.0
	return U.success({
		"terminal_voltage_v": voltage,
		"electrical_energy_j": electrical_energy,
		"optical_energy_j": optical_energy,
		"waste_heat_j": heat_energy,
		"photon_count": photon_count,
		"optical_efficiency_ratio": efficiency * above_fraction,
		"energy_residual_j": electrical_energy - optical_energy - heat_energy,
	})
