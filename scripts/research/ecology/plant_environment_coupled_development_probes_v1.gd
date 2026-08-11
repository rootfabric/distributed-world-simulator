extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")

const PROBE_ORDER: Array[String] = ["REFERENCE", "SHADE", "SUN", "DRY", "NUTRIENT_POOR", "NUTRIENT_RICH", "FLOODED"]
const PARENT_LINEAGE := "lineage/ph2-controlled"
const REPRODUCTION_EVENT := "germination/ph2-001"
const SEED_INDEX := 0

static func make_environment_samples() -> Dictionary:
	return {
		"REFERENCE": _env(0.55, 0.65, 0.55, 0.05, "reference"),
		"SHADE": _env(0.55, 0.20, 0.55, 0.05, "shade"),
		"SUN": _env(0.55, 0.92, 0.55, 0.05, "sun"),
		"DRY": _env(0.12, 0.65, 0.55, 0.05, "dry"),
		"NUTRIENT_POOR": _env(0.55, 0.65, 0.15, 0.05, "nutrient-poor"),
		"NUTRIENT_RICH": _env(0.55, 0.65, 0.90, 0.05, "nutrient-rich"),
		"FLOODED": _env(0.55, 0.65, 0.55, 0.80, "flooded"),
	}

static func run_all() -> Dictionary:
	var genome := Genome.create_default()
	var inherited_traits := Traits.create_default()
	var envelope := Contract.create_seed_envelope(genome, inherited_traits, PARENT_LINEAGE, REPRODUCTION_EVENT, SEED_INDEX)
	var environments := make_environment_samples()
	var results := {}
	for name in PROBE_ORDER:
		results[name] = Plasticity.realize(envelope, inherited_traits, environments[name])
	return results

static func _env(moisture: float, sunlight: float, nutrients: float, flood: float, label: String) -> Dictionary:
	return EnvironmentSample.create(
		100.0,
		200.0,
		18.0,
		moisture,
		sunlight,
		nutrients,
		flood,
		205201,
		"ECO.PH2.1/" + label
	)
