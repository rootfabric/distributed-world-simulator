extends RefCounted
## Detailed T6 reference. Every execute traverses all source dies.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/power_stage_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/power_stage_physics_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var rows: Array = []
	for die in graph.switch_dies:
		var derived := Physics.derive_die(graph, die)
		if not derived.success:
			return derived
		rows.append(derived.details.die)
	return U.success({"graph_hash": graph.graph_hash, "rows": rows, "source_die_count": rows.size()})

static func execute(
	plan: Dictionary,
	bus_voltage_v: float,
	duty_ratio: float,
	load_current_a: float,
	pwm_frequency_hz: float,
	junction_temperature_k: float,
	dt_s: float
) -> Dictionary:
	if not U.is_positive_number(bus_voltage_v) or not U.is_finite_number(duty_ratio) or absf(duty_ratio) > 1.0:
		return U.failure("POWER_STAGE_REFERENCE_INPUT_INVALID")
	if not U.is_finite_number(load_current_a) or not U.is_non_negative_number(pwm_frequency_hz) or not U.is_positive_number(junction_temperature_k) or not U.is_positive_number(dt_s):
		return U.failure("POWER_STAGE_REFERENCE_INPUT_INVALID")
	var conductance := [0.0, 0.0, 0.0, 0.0]
	var max_current := [0.0, 0.0, 0.0, 0.0]
	var transition_weighted := [0.0, 0.0, 0.0, 0.0]
	var max_bus := INF
	var min_t := 0.0
	var max_t := INF
	for row in plan.rows:
		if not bool(row.enabled):
			continue
		var bank := int(row.bank_index)
		var r := Physics.resistance_at_temperature(row, junction_temperature_k)
		var g := 1.0 / r
		conductance[bank] = float(conductance[bank]) + g
		max_current[bank] = float(max_current[bank]) + float(row.max_abs_current_a)
		transition_weighted[bank] = float(transition_weighted[bank]) + g * float(row.transition_time_s)
		max_bus = minf(max_bus, float(row.max_bus_voltage_v))
		min_t = maxf(min_t, float(row.min_temperature_k))
		max_t = minf(max_t, float(row.max_temperature_k))
	if bus_voltage_v > max_bus:
		return U.failure("POWER_STAGE_REFERENCE_BUS_VOLTAGE_LIMIT")
	if junction_temperature_k < min_t or junction_temperature_k > max_t:
		return U.failure("POWER_STAGE_REFERENCE_TEMPERATURE_OUT_OF_DOMAIN")
	for bank in range(4):
		if float(conductance[bank]) <= 0.0:
			return U.failure("POWER_STAGE_REFERENCE_BANK_OPEN", {"bank_index": bank})
	var bank_r := []
	var bank_transition := []
	for bank in range(4):
		bank_r.append(1.0 / float(conductance[bank]))
		bank_transition.append(float(transition_weighted[bank]) / float(conductance[bank]))
	var positive_path := duty_ratio >= 0.0
	var a := 0 if positive_path else 1
	var b := 3 if positive_path else 2
	var current_limit := minf(float(max_current[a]), float(max_current[b]))
	if absf(load_current_a) > current_limit:
		return U.failure("POWER_STAGE_REFERENCE_CURRENT_LIMIT")
	var path_r := float(bank_r[a]) + float(bank_r[b])
	var transition_time := float(bank_transition[a]) + float(bank_transition[b])
	var switching_activity := 1.0 - absf(duty_ratio)
	var load_voltage := duty_ratio * bus_voltage_v - load_current_a * path_r
	var conduction_heat := load_current_a * load_current_a * path_r * dt_s
	var switching_heat := bus_voltage_v * absf(load_current_a) * pwm_frequency_hz * transition_time * switching_activity * dt_s
	var output_energy := load_voltage * load_current_a * dt_s
	var input_energy := output_energy + conduction_heat + switching_heat
	var bus_current := input_energy / (bus_voltage_v * dt_s)
	return U.success({
		"load_voltage_v": load_voltage,
		"bus_current_a": bus_current,
		"electrical_input_energy_j": input_energy,
		"electrical_output_energy_j": output_energy,
		"conduction_heat_j": conduction_heat,
		"switching_heat_j": switching_heat,
		"energy_residual_j": input_energy - output_energy - conduction_heat - switching_heat,
		"source_die_traversals": int(plan.source_die_count),
	})
