extends RefCounted
## Detailed T4 thermal reference. Traverses every source cell on every execute.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/thermal_pack_graph_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var layers := int(graph.layer_count)
	var lanes := int(graph.lane_count)
	var count := layers * lanes
	var capacity: Array = []
	var conductivity: Array = []
	capacity.resize(count)
	conductivity.resize(count)
	var max_temperature := INF
	for layer in range(layers):
		for lane in range(lanes):
			var cell := Graph.cell_by_slot(graph, layer, lane)
			if cell.is_empty() or not bool(cell.enabled):
				return U.failure("THERMAL_REFERENCE_CELL_DISABLED_OR_MISSING", {"layer": layer, "lane": lane})
			var material := MatterCatalog.material_by_id(graph.material_catalog, String(cell.material_id))
			if material.is_empty():
				return U.failure("THERMAL_REFERENCE_MATERIAL_MISSING")
			var index := layer * lanes + lane
			var mass := float(material.density_kg_m3) * float(cell.volume_m3)
			capacity[index] = mass * float(material.heat_capacity_j_kg_k)
			conductivity[index] = float(material.thermal_conductivity_w_m_k)
			max_temperature = minf(max_temperature, float(material.melting_temperature_k))
	var links: Array = []
	links.resize((layers - 1) * lanes)
	for layer in range(layers - 1):
		for lane in range(lanes):
			var a := layer * lanes + lane
			var b := (layer + 1) * lanes + lane
			var k_a := float(conductivity[a])
			var k_b := float(conductivity[b])
			var k_eff := 2.0 * k_a * k_b / (k_a + k_b)
			links[layer * lanes + lane] = k_eff * float(graph.interlayer_contact_area_m2) / float(graph.interlayer_contact_length_m)
	var ambient: Array = []
	ambient.resize(lanes)
	for lane in range(lanes):
		var index := (layers - 1) * lanes + lane
		ambient[lane] = float(conductivity[index]) * float(graph.ambient_surface_area_m2) / float(graph.ambient_wall_thickness_m)
	return U.success({
		"graph_hash": graph.graph_hash,
		"layer_count": layers,
		"lane_count": lanes,
		"capacity_j_k": capacity,
		"link_conductance_w_k": links,
		"ambient_conductance_w_k": ambient,
		"min_temperature_k": 1.0,
		"max_temperature_k": max_temperature,
		"source_cell_count": count,
	})

static func initial_state(plan: Dictionary, temperature_k: float) -> Dictionary:
	if not U.is_positive_number(temperature_k):
		return {}
	if temperature_k < float(plan.min_temperature_k) or temperature_k > float(plan.max_temperature_k):
		return {}
	var values: Array = []
	for _i in range(int(plan.source_cell_count)):
		values.append(temperature_k)
	return {"cell_temperature_k": values}

static func execute(plan: Dictionary, state: Dictionary, heat_input_w: float, dt_s: float, ambient_temperature_k: float) -> Dictionary:
	var layers := int(plan.layer_count)
	var lanes := int(plan.lane_count)
	var count := int(plan.source_cell_count)
	if typeof(state.get("cell_temperature_k")) != TYPE_ARRAY or state.cell_temperature_k.size() != count:
		return U.failure("THERMAL_REFERENCE_STATE_INVALID")
	if not U.is_non_negative_number(heat_input_w) or not U.is_positive_number(dt_s) or not U.is_positive_number(ambient_temperature_k):
		return U.failure("THERMAL_REFERENCE_STEP_INVALID")
	var net_power: Array = []
	net_power.resize(count)
	for i in range(count):
		net_power[i] = 0.0
	var per_lane_input := heat_input_w / float(lanes)
	for lane in range(lanes):
		net_power[lane] = per_lane_input
	for layer in range(layers - 1):
		for lane in range(lanes):
			var a := layer * lanes + lane
			var b := (layer + 1) * lanes + lane
			var flow := float(plan.link_conductance_w_k[layer * lanes + lane]) * (float(state.cell_temperature_k[a]) - float(state.cell_temperature_k[b]))
			net_power[a] = float(net_power[a]) - flow
			net_power[b] = float(net_power[b]) + flow
	var ambient_exchange_w := 0.0
	for lane in range(lanes):
		var index := (layers - 1) * lanes + lane
		var flow := float(plan.ambient_conductance_w_k[lane]) * (float(state.cell_temperature_k[index]) - ambient_temperature_k)
		net_power[index] = float(net_power[index]) - flow
		ambient_exchange_w += flow
	var next_values: Array = []
	var state_energy_delta := 0.0
	for i in range(count):
		var old_t := float(state.cell_temperature_k[i])
		var next_t := old_t + float(net_power[i]) * dt_s / float(plan.capacity_j_k[i])
		if next_t < float(plan.min_temperature_k) or next_t > float(plan.max_temperature_k):
			return U.failure("THERMAL_REFERENCE_NEXT_TEMPERATURE_OUT_OF_DOMAIN", {"cell_index": i, "temperature_k": next_t})
		next_values.append(next_t)
		state_energy_delta += float(plan.capacity_j_k[i]) * (next_t - old_t)
	var output_temperature := 0.0
	for lane in range(lanes):
		output_temperature += float(next_values[(layers - 1) * lanes + lane])
	output_temperature /= float(lanes)
	var ambient_exchange_j := ambient_exchange_w * dt_s
	var input_energy := heat_input_w * dt_s
	return U.success({
		"output_temperature_k": output_temperature,
		"ambient_exchange_j": ambient_exchange_j,
		"state_energy_delta_j": state_energy_delta,
		"energy_residual_j": state_energy_delta - input_energy + ambient_exchange_j,
		"next_state": {"cell_temperature_k": next_values},
		"source_cell_traversals": count,
	})
