extends RefCounted
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Skeleton = preload("res://scripts/research/ecology/plant_growth_graph_skeleton_v1.gd")
const DEFAULT_INDIVIDUAL_SEED := 959597643576420676

static func make_probes() -> Dictionary:
	var base := Traits.create_default()
	return {
		"BASE": base,
		"APICAL_LOW": Traits.with_trait(base, "apical_dominance", 0.05, "/apical-low"),
		"APICAL_HIGH": Traits.with_trait(base, "apical_dominance", 0.95, "/apical-high"),
		"BRANCH_LOW": Traits.with_trait(base, "branch_probability", 0.10, "/branch-low"),
		"BRANCH_HIGH": Traits.with_trait(base, "branch_probability", 0.90, "/branch-high"),
		"ANGLE_NARROW": Traits.with_trait(base, "branch_angle_deg", 15.0, "/angle-narrow"),
		"ANGLE_WIDE": Traits.with_trait(base, "branch_angle_deg", 75.0, "/angle-wide"),
		"INTERNODE_SHORT": Traits.with_trait(base, "internode_length_m", 0.18, "/internode-short"),
		"INTERNODE_LONG": Traits.with_trait(base, "internode_length_m", 0.55, "/internode-long"),
	}

static func run_all(individual_seed: int = DEFAULT_INDIVIDUAL_SEED) -> Dictionary:
	var result := {}
	for name in make_probes().keys():
		result[name] = Skeleton.build(make_probes()[name], individual_seed)
	return result
