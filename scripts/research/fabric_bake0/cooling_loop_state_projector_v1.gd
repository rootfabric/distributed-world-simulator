extends RefCounted
## Detailed-lane -> compact four-temperature projection for T8.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/cooling_loop_graph_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/cooling_loop_descriptor_v1.gd")

const REL_TOL := 1.0e-10

static func project(graph: Dictionary, descriptor: Dictionary, detailed_state: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	checked = Descriptor.validate(descriptor)
	if not checked.success:
		return checked
	if String(graph.graph_hash) != String(descriptor.graph_hash):
		return U.failure("COOLING_STATE_PROJECTOR_GRAPH_MISMATCH")
	var n := int(graph.lanes.size())
	var compact := {}
	for field in ["plate_temperature_k", "hot_coolant_temperature_k", "radiator_temperature_k", "cold_coolant_temperature_k"]:
		if typeof(detailed_state.get(field)) != TYPE_ARRAY or detailed_state[field].size() != n:
			return U.failure("COOLING_STATE_PROJECTOR_STATE_INVALID", {"field": field})
		var reference_raw = detailed_state[field][0]
		if not U.is_positive_number(reference_raw):
			return U.failure("COOLING_STATE_PROJECTOR_STATE_INVALID", {"field": field, "lane": 0})
		var reference := float(reference_raw)
		if reference < float(descriptor.min_temperature_k) or reference > float(descriptor.max_temperature_k):
			return U.failure("COOLING_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN", {"field": field, "lane": 0, "temperature_k": reference})
		for lane in range(1, n):
			var actual_raw = detailed_state[field][lane]
			if not U.is_positive_number(actual_raw):
				return U.failure("COOLING_STATE_PROJECTOR_STATE_INVALID", {"field": field, "lane": lane})
			var actual := float(actual_raw)
			if actual < float(descriptor.min_temperature_k) or actual > float(descriptor.max_temperature_k):
				return U.failure("COOLING_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN", {"field": field, "lane": lane, "temperature_k": actual})
			var scale := maxf(1.0, maxf(absf(reference), absf(actual)))
			if absf(actual - reference) > REL_TOL * scale:
				return U.failure("COOLING_STATE_NOT_IN_REDUCTION_MANIFOLD", {"field": field, "lane": lane, "reference_k": reference, "actual_k": actual})
		compact[field] = reference
	return U.success({"projection_kind": "EXACT_SYMMETRY_MANIFOLD", "next_state": compact})
