extends RefCounted
## Conservative detailed->lumped state projection for T4.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/thermal_pack_graph_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/thermal_filter_descriptor_v1.gd")

const REL_TOL := 1.0e-10

static func project(graph: Dictionary, descriptor: Dictionary, detailed_state: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	checked = Descriptor.validate(descriptor)
	if not checked.success:
		return checked
	if String(graph.graph_hash) != String(descriptor.graph_hash):
		return U.failure("THERMAL_STATE_PROJECTOR_GRAPH_MISMATCH")
	var layers := int(graph.layer_count)
	var lanes := int(graph.lane_count)
	if typeof(detailed_state.get("cell_temperature_k")) != TYPE_ARRAY or detailed_state.cell_temperature_k.size() != layers * lanes:
		return U.failure("THERMAL_STATE_PROJECTOR_STATE_INVALID")
	var layer_temperatures: Array = []
	for layer in range(layers):
		var reference_raw = detailed_state.cell_temperature_k[layer * lanes]
		if not U.is_positive_number(reference_raw):
			return U.failure("THERMAL_STATE_PROJECTOR_STATE_INVALID", {"layer": layer, "lane": 0})
		var reference := float(reference_raw)
		if reference < float(descriptor.min_temperature_k) or reference > float(descriptor.max_temperature_k):
			return U.failure("THERMAL_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN", {"layer": layer, "lane": 0, "temperature_k": reference})
		for lane in range(1, lanes):
			var actual_raw = detailed_state.cell_temperature_k[layer * lanes + lane]
			if not U.is_positive_number(actual_raw):
				return U.failure("THERMAL_STATE_PROJECTOR_STATE_INVALID", {"layer": layer, "lane": lane})
			var actual := float(actual_raw)
			if actual < float(descriptor.min_temperature_k) or actual > float(descriptor.max_temperature_k):
				return U.failure("THERMAL_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN", {"layer": layer, "lane": lane, "temperature_k": actual})
			var scale := maxf(1.0, maxf(absf(reference), absf(actual)))
			if absf(actual - reference) > REL_TOL * scale:
				return U.failure("THERMAL_STATE_NOT_IN_REDUCTION_MANIFOLD", {"layer": layer, "lane": lane, "reference_k": reference, "actual_k": actual})
		layer_temperatures.append(reference)
	return U.success({
		"projection_kind": "EXACT_SYMMETRY_MANIFOLD",
		"next_state": {"layer_temperature_k": layer_temperatures},
	})
