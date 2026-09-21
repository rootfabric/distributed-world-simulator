extends RefCounted
## Detailed T8 reference: four temperatures per lane, every lane re-derived every execute.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/cooling_loop_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/cooling_loop_physics_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var rows: Array = []
	for lane in graph.lanes:
		var derived := Physics.derive_lane(graph, lane)
		if not derived.success:
			return derived
		rows.append(derived.details.lane)
	return U.success({
		"rows": rows,
		"lane_count": int(rows.size()),
		"source_thermal_node_count": int(rows.size()) * 4,
	})

static func initial_state(plan: Dictionary, temperature_k: float) -> Dictionary:
	if not U.is_positive_number(temperature_k):
		return {}
	var n := int(plan.lane_count)
	var p: Array = []
	var h: Array = []
	var r: Array = []
	var c: Array = []
	for _i in range(n):
		p.append(temperature_k)
		h.append(temperature_k)
		r.append(temperature_k)
		c.append(temperature_k)
	return {
		"plate_temperature_k": p,
		"hot_coolant_temperature_k": h,
		"radiator_temperature_k": r,
		"cold_coolant_temperature_k": c,
	}

static func execute(
	plan: Dictionary,
	state: Dictionary,
	heat_input_w: float,
	mass_flow_kg_s: float,
	ambient_temperature_k: float,
	dt_s: float
) -> Dictionary:
	if not U.is_non_negative_number(heat_input_w) or not U.is_non_negative_number(mass_flow_kg_s) or not U.is_positive_number(ambient_temperature_k) or not U.is_positive_number(dt_s):
		return U.failure("COOLING_REFERENCE_STEP_INVALID")
	var n := int(plan.lane_count)
	for field in ["plate_temperature_k", "hot_coolant_temperature_k", "radiator_temperature_k", "cold_coolant_temperature_k"]:
		if typeof(state.get(field)) != TYPE_ARRAY or state[field].size() != n:
			return U.failure("COOLING_REFERENCE_STATE_INVALID", {"field": field})
	var next_p: Array = []
	var next_h: Array = []
	var next_r: Array = []
	var next_c: Array = []
	var state_delta := 0.0
	var ambient_exchange_j := 0.0
	var pump_energy_j := 0.0
	var max_reynolds := 0.0
	var lane_flow := mass_flow_kg_s / float(n)
	var lane_heat := heat_input_w / float(n)
	for lane_index in range(n):
		var row: Dictionary = plan.rows[lane_index]
		var re := Physics.reynolds_number(row, lane_flow)
		if re > float(row.laminar_reynolds_limit) * (1.0 + 1.0e-12):
			return U.failure("COOLING_REFERENCE_FLOW_REGIME_UNSUPPORTED", {"lane": lane_index, "reynolds": re})
		max_reynolds = maxf(max_reynolds, re)
		var p := float(state.plate_temperature_k[lane_index])
		var h := float(state.hot_coolant_temperature_k[lane_index])
		var r := float(state.radiator_temperature_k[lane_index])
		var c := float(state.cold_coolant_temperature_k[lane_index])
		for pair in [["plate",p],["hot",h],["radiator",r],["cold",c]]:
			var t := float(pair[1])
			if not is_finite(t) or t < float(row.min_temperature_k) or t > float(row.max_temperature_k):
				return U.failure("COOLING_REFERENCE_TEMPERATURE_OUT_OF_DOMAIN", {"lane": lane_index, "node": String(pair[0])})
		var pump_power := Physics.hydraulic_power_w(row, lane_flow)
		var flow_g := lane_flow * float(row.coolant_heat_capacity_j_kg_k)
		var q_ph := float(row.plate_to_hot_conductance_w_k) * (p - h)
		var q_hc := flow_g * (h - c)
		var q_cr := float(row.cold_to_radiator_conductance_w_k) * (c - r)
		var q_amb := float(row.radiator_to_ambient_conductance_w_k) * (r - ambient_temperature_k)
		var np := p + (lane_heat - q_ph) * dt_s / float(row.plate_capacity_j_k)
		var nh := h + (q_ph - q_hc + 0.5 * pump_power) * dt_s / float(row.hot_coolant_capacity_j_k)
		var nc := c + (q_hc - q_cr + 0.5 * pump_power) * dt_s / float(row.cold_coolant_capacity_j_k)
		var nr := r + (q_cr - q_amb) * dt_s / float(row.radiator_capacity_j_k)
		for pair in [["plate",np],["hot",nh],["radiator",nr],["cold",nc]]:
			var t := float(pair[1])
			if not is_finite(t) or t < float(row.min_temperature_k) or t > float(row.max_temperature_k):
				return U.failure("COOLING_REFERENCE_NEXT_TEMPERATURE_OUT_OF_DOMAIN", {"lane": lane_index, "node": String(pair[0]), "temperature_k": t})
		next_p.append(np)
		next_h.append(nh)
		next_r.append(nr)
		next_c.append(nc)
		state_delta += float(row.plate_capacity_j_k) * (np - p)
		state_delta += float(row.hot_coolant_capacity_j_k) * (nh - h)
		state_delta += float(row.radiator_capacity_j_k) * (nr - r)
		state_delta += float(row.cold_coolant_capacity_j_k) * (nc - c)
		ambient_exchange_j += q_amb * dt_s
		pump_energy_j += pump_power * dt_s
	var avg_p := 0.0
	var avg_h := 0.0
	var avg_r := 0.0
	var avg_c := 0.0
	for i in range(n):
		avg_p += float(next_p[i])
		avg_h += float(next_h[i])
		avg_r += float(next_r[i])
		avg_c += float(next_c[i])
	avg_p /= float(n)
	avg_h /= float(n)
	avg_r /= float(n)
	avg_c /= float(n)
	return U.success({
		"plate_temperature_k": avg_p,
		"hot_coolant_temperature_k": avg_h,
		"radiator_temperature_k": avg_r,
		"cold_coolant_temperature_k": avg_c,
		"ambient_exchange_j": ambient_exchange_j,
		"pump_hydraulic_energy_j": pump_energy_j,
		"state_energy_delta_j": state_delta,
		"energy_residual_j": state_delta - heat_input_w * dt_s - pump_energy_j + ambient_exchange_j,
		"reynolds_number": max_reynolds,
		"next_state": {
			"plate_temperature_k": next_p,
			"hot_coolant_temperature_k": next_h,
			"radiator_temperature_k": next_r,
			"cold_coolant_temperature_k": next_c,
		},
		"source_thermal_node_traversals": int(plan.source_thermal_node_count),
	})
