extends RefCounted
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const S = preload("res://scripts/research/ecology/v2/organism_state_v1.gd")

static func compile(state: Dictionary, genome: Dictionary) -> Dictionary:
	if not S.validate(state, genome).is_empty():
		return {}
	var stats := {"module_count": state.modules.size(), "collector_area_mm2": 0, "absorber_reach_mm": 0, "material_mg": 0, "height_mm": 0, "below_ground_mm": 0, "support_volume_proxy_mm3": 0}
	var roles := {}
	var children := {}
	for m in state.modules:
		roles[m.role] = int(roles.get(m.role, 0)) + 1
		children[m.parent] = int(children.get(m.parent, 0)) + 1
		stats.material_mg += m.cost.material_mg
		stats.height_mm = maxi(stats.height_mm, m.end_mm[1])
		stats.below_ground_mm = maxi(stats.below_ground_mm, -m.end_mm[1])
		if m.role == "collector":
			stats.collector_area_mm2 += m.area_mm2
		if m.role == "absorber":
			stats.absorber_reach_mm += m.reach_mm
		if m.role in ["support", "transport"]:
			stats.support_volume_proxy_mm3 += m.cost.material_mg
	var branching_nodes := 0
	for id in children:
		if id != "" and children[id] > 1:
			branching_nodes += 1
	stats["branching_nodes"] = branching_nodes
	var geometry := {"schema": "dws.ecology.body-representation.v1", "modules": state.modules.duplicate(true), "attachments": state.attachments.duplicate(true)}
	var result := {"schema": "dws.ecology.phenotype-snapshot.v1", "genome_hash": state.genome_hash, "development_hash": S.biological_hash(state), "body_hash": C.digest(state.modules), "topology_hash": B.topology_signature(state.modules), "statistics": stats, "module_roles": roles, "representation": geometry, "representation_hash": C.digest(geometry), "source_mode": "RESEARCH_BODY_TRUTH", "function_model": "EXPLICIT_TISSUE_COST_AND_ORGAN_EXTENT_PROXIES"}
	result["phenotype_hash"] = C.digest(result)
	return result
