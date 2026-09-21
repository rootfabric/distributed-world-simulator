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
		var reference := float(detailed_state[field][0])
		if not is_finite(reference):
			return U.failure("COOLING_STATE_PROJECTOR_STATE_INVALID", {"field": field})
		for lane in range(1, n):
			var actual := float(detailed_state[field][lane])
			if not is_finite(actual):
				return U.failure("COOLING_STATE_PROJECTOR_STATE_INVALID", {"field": field, "lane": lane})
			var scale := maxf(1.0, maxf(absf(reference), absf(actual)))
			if absf(actual - reference) > REL_TOL * scale:
				return U.failure("COOLING_STATE_NOT_IN_REDUCTION_MANIFOLD", {"field": field, "lane": lane, "reference_k": reference, "actual_k": actual})
		compact[field] = reference
	return U.success({"projection_kind": "EXACT_SYMMETRY_MANIFOLD", "next_state": compact})
