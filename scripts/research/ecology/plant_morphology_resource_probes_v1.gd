extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Coupling = preload("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd")

const PARENT_LINEAGE := "lineage/ph3-controlled"
const REPRODUCTION_EVENT := "germination/ph3-001"
const SEED_INDEX := 0

static func run_suite() -> Dictionary:
	var environments := PH2Probes.make_environment_samples()
	var base := Traits.create_default()
	var variants := {
		"BASE": base,
		"HEIGHT_LOW": Traits.with_trait(base, "max_height_m", 1.8, "/height-low"),
		"HEIGHT_HIGH": Traits.with_trait(base, "max_height_m", 7.0, "/height-high"),
		"CROWN_NARROW": Traits.with_trait(base, "crown_spread_m", 0.75, "/crown-narrow"),
		"CROWN_WIDE": Traits.with_trait(base, "crown_spread_m", 4.2, "/crown-wide"),
		"BRANCH_LOW": Traits.with_trait(base, "branch_probability", 0.18, "/branch-low"),
		"BRANCH_HIGH": Traits.with_trait(base, "branch_probability", 0.90, "/branch-high"),
		"GIANT_DENSE": _giant_dense(base),
	}
	var cases := {}
	for environment_name in ["REFERENCE", "SHADE", "SUN", "DRY"]:
		for variant_name in variants.keys():
			var key := "%s/%s" % [environment_name, variant_name]
			cases[key] = _case(environments[environment_name], variants[variant_name], key)
	return cases

static func _case(environment: Dictionary, development_traits: Dictionary, event_suffix: String) -> Dictionary:
	var genome := Genome.create_default()
	var envelope := Contract.create_seed_envelope(genome, development_traits, PARENT_LINEAGE, REPRODUCTION_EVENT + "/" + event_suffix, SEED_INDEX)
	var phenotype := Plasticity.realize(envelope, development_traits, environment)
	var coupling := Coupling.evaluate(environment, genome, phenotype)
	return {"environment": environment, "traits": development_traits, "phenotype": phenotype, "coupling": coupling}

static func _giant_dense(base: Dictionary) -> Dictionary:
	var value := Traits.with_trait(base, "max_height_m", 12.0, "/giant")
	value = Traits.with_trait(value, "crown_spread_m", 7.0, "/wide")
	value = Traits.with_trait(value, "branch_probability", 0.98, "/dense")
	value = Traits.with_trait(value, "branch_length_ratio", 1.15, "/long-branch")
	value = Traits.with_trait(value, "branching_depth", 4, "/deep-branch")
	return value
