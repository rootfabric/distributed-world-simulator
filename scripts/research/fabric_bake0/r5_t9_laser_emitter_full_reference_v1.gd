extends RefCounted
## Detailed T9 reference: evaluates every physical gain cell on every execute.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/laser_emitter_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/laser_emitter_physics_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var rows: Array = []
	var active_count := 0
	for cell in graph.gain_cells:
		var derived := Physics.derive_cell(graph, cell)
		if not derived.success:
			return derived
		rows.append(derived.details.cell)
		if bool(derived.details.cell.enabled):
			active_count += 1
	if active_count < 1:
		return U.failure("LASER_REFERENCE_NO_ACTIVE_GAIN_CELLS")
	return U.success({"rows": rows, "source_cell_count": rows.size(), "active_cell_count": active_count})

static func execute(plan: Dictionary, current_a: float, junction_temperature_k: float, dt_s: float) -> Dictionary:
	if not U.is_non_negative_number(current_a) or not U.is_positive_number(junction_temperature_k) or not U.is_positive_number(dt_s):
		return U.failure("LASER_REFERENCE_STEP_INVALID")
	var active_count := int(plan.active_cell_count)
	var per_cell_current := current_a / float(active_count)
	var electrical_energy := 0.0
	var optical_energy := 0.0
	var waste_heat := 0.0
	var photon_count := 0.0
	var terminal_voltage := -1.0
	var wavelength := -1.0
	var aperture_area := 0.0
	var beam_quality := -1.0
	for row in plan.rows:
		if not bool(row.enabled):
			continue
		var one := Physics.evaluate_cell(row, per_cell_current, junction_temperature_k, dt_s)
		if not one.success:
			return one
		if terminal_voltage < 0.0:
			terminal_voltage = float(one.details.terminal_voltage_v)
			wavelength = float(row.wavelength_m)
			beam_quality = float(row.beam_quality_m2)
		elif absf(terminal_voltage - float(one.details.terminal_voltage_v)) > 1.0e-10:
			return U.failure("LASER_REFERENCE_PARALLEL_VOLTAGE_MISMATCH")
		electrical_energy += float(one.details.electrical_energy_j)
		optical_energy += float(one.details.optical_energy_j)
		waste_heat += float(one.details.waste_heat_j)
		photon_count += float(one.details.photon_count)
		aperture_area += float(row.aperture_area_m2)
	if terminal_voltage < 0.0 or aperture_area <= 0.0:
		return U.failure("LASER_REFERENCE_NO_ACTIVE_GAIN_CELLS")
	var waist_radius := sqrt(aperture_area / PI)
	var divergence := beam_quality * wavelength / (PI * waist_radius)
	return U.success({
		"terminal_voltage_v": terminal_voltage,
		"electrical_energy_j": electrical_energy,
		"optical_energy_j": optical_energy,
		"waste_heat_j": waste_heat,
		"photon_count": photon_count,
		"wavelength_m": wavelength,
		"beam_divergence_half_angle_rad": divergence,
		"energy_residual_j": electrical_energy - optical_energy - waste_heat,
		"source_cell_traversals": int(plan.source_cell_count),
	})
