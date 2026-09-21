extends RefCounted
## Detailed T3 reference. Cell properties are pre-derived once, but every execute traverses every cell.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/battery_cell_graph_v1.gd")
const CellPhysics = preload("res://scripts/research/fabric_bake0/battery_cell_physics_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var groups: Array = []
	groups.resize(int(graph.series_group_count))
	for index in range(groups.size()):
		groups[index] = []
	var rows: Array = []
	for cell in graph.cells:
		var derived := CellPhysics.derive(graph, cell)
		if not derived.success:
			return derived
		var row: Dictionary = derived.details.cell
		rows.append(row)
		groups[int(row.series_index)].append(row)
	return U.success({
		"graph_hash": graph.graph_hash,
		"series_group_count": int(graph.series_group_count),
		"rows": rows,
		"groups": groups,
	})

static func initial_state(plan: Dictionary, soc: float, temperature_k: float) -> Dictionary:
	if soc < 0.0 or soc > 1.0:
		return {}
	var charges: Array = []
	for group in plan.groups:
		var capacity := 0.0
		for row in group:
			if bool(row.enabled):
				capacity += float(row.capacity_c)
		if capacity <= 0.0:
			return {}
		charges.append(capacity * soc)
	return {"group_charge_c": charges, "temperature_k": temperature_k}

static func execute(plan: Dictionary, state: Dictionary, current_a: float, dt_s: float, ambient_temperature_k: float) -> Dictionary:
	if typeof(state.get("group_charge_c")) != TYPE_ARRAY or state.group_charge_c.size() != int(plan.series_group_count):
		return U.failure("BATTERY_FULL_REFERENCE_STATE_INVALID")
	if not U.is_positive_number(state.get("temperature_k")) or not U.is_positive_number(dt_s) or not U.is_positive_number(ambient_temperature_k):
		return U.failure("BATTERY_FULL_REFERENCE_STEP_INVALID")
	var temperature := float(state.temperature_k)
	var total_thermal_capacity := 0.0
	var total_thermal_conductance := 0.0
	var min_temperature := 0.0
	var max_temperature := INF
	var terminal_voltage := 0.0
	var heat_j := 0.0
	var chemical_delta_j := 0.0
	var pack_current_limit := INF
	var next_charges: Array = []
	var traversals := 0

	for group_index in range(plan.groups.size()):
		var group: Array = plan.groups[group_index]
		var active_rows: Array = []
		var capacity := 0.0
		var conductance_t := 0.0
		var group_current_limit := 0.0
		var profile_id := ""
		var empty_v := 0.0
		var full_v := 0.0
		for row in group:
			traversals += 1
			total_thermal_capacity += float(row.thermal_capacity_j_k)
			total_thermal_conductance += float(row.thermal_conductance_w_k)
			min_temperature = maxf(min_temperature, float(row.min_temperature_k))
			max_temperature = minf(max_temperature, float(row.max_temperature_k))
			if not bool(row.enabled):
				continue
			if profile_id.is_empty():
				profile_id = String(row.profile_id)
				empty_v = float(row.empty_voltage_v)
				full_v = float(row.full_voltage_v)
			elif String(row.profile_id) != profile_id:
				return U.failure("BATTERY_FULL_REFERENCE_PROFILE_MISMATCH")
			active_rows.append(row)
			capacity += float(row.capacity_c)
			var resistance_t := CellPhysics.resistance_at_temperature(row, temperature)
			conductance_t += 1.0 / resistance_t
			group_current_limit += float(row.max_current_a)
		if active_rows.is_empty() or capacity <= 0.0 or conductance_t <= 0.0:
			return U.failure("BATTERY_FULL_REFERENCE_OPEN_GROUP")
		pack_current_limit = minf(pack_current_limit, group_current_limit)
		var old_charge := float(state.group_charge_c[group_index])
		var next_charge := old_charge - current_a * dt_s
		if next_charge < -1.0e-9 or next_charge > capacity + 1.0e-9:
			return U.failure("BATTERY_FULL_REFERENCE_CHARGE_OUT_OF_DOMAIN")
		var midpoint_charge := 0.5 * (old_charge + next_charge)
		var soc_mid := midpoint_charge / capacity
		var ocv := empty_v + (full_v - empty_v) * clampf(soc_mid, 0.0, 1.0)
		var group_voltage := ocv - current_a / conductance_t
		terminal_voltage += group_voltage
		for row in active_rows:
			var resistance_t := CellPhysics.resistance_at_temperature(row, temperature)
			var cell_conductance := 1.0 / resistance_t
			var cell_current := current_a * cell_conductance / conductance_t
			heat_j += cell_current * cell_current * resistance_t * dt_s
			chemical_delta_j += CellPhysics.chemical_energy_j(
				float(row.capacity_c),
				old_charge * float(row.capacity_c) / capacity,
				float(row.empty_voltage_v),
				float(row.full_voltage_v)
			)
			chemical_delta_j -= CellPhysics.chemical_energy_j(
				float(row.capacity_c),
				next_charge * float(row.capacity_c) / capacity,
				float(row.empty_voltage_v),
				float(row.full_voltage_v)
			)
		next_charges.append(clampf(next_charge, 0.0, capacity))

	if absf(current_a) > pack_current_limit:
		return U.failure("BATTERY_FULL_REFERENCE_CURRENT_LIMIT")
	if temperature < min_temperature or temperature > max_temperature:
		return U.failure("BATTERY_FULL_REFERENCE_TEMPERATURE_OUT_OF_DOMAIN")
	var electrical_energy_j := terminal_voltage * current_a * dt_s
	var passive_heat_removed_j := total_thermal_conductance * (temperature - ambient_temperature_k) * dt_s
	var next_temperature := temperature + (heat_j - passive_heat_removed_j) / total_thermal_capacity
	if next_temperature < min_temperature or next_temperature > max_temperature:
		return U.failure("BATTERY_FULL_REFERENCE_NEXT_TEMPERATURE_OUT_OF_DOMAIN")
	return U.success({
		"terminal_voltage_v": terminal_voltage,
		"heat_generated_j": heat_j,
		"passive_heat_removed_j": passive_heat_removed_j,
		"electrical_energy_j": electrical_energy_j,
		"chemical_energy_delta_j": chemical_delta_j,
		"energy_residual_j": chemical_delta_j - electrical_energy_j - heat_j,
		"next_state": {"group_charge_c": next_charges, "temperature_k": next_temperature},
		"source_cell_traversals": traversals,
		"pack_current_limit_a": pack_current_limit,
	})
