extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_lifecycle_payoff_v1.gd")
const CExperiment = preload("res://scripts/research/ecology/plant_crown_root_competition_experiment_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_d_lifecycle_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.CAL1-D.1"
const ACCEPTED_CAL1_C_HASH := "d48919f42e2da92d32b3cbb8b344cb4ba0a2357411707781725a6873f40c3f1a"
const EPSILON := 0.000000000001

const CASE_ORDER: Array[String] = [
	"IMMATURE_CONTROL",
	"MATURE_CONTROL",
	"MATURE_LOW_RESERVE",
	"MATURE_HIGH_RESERVE",
	"RELEASE_LOW",
	"RELEASE_HIGH",
	"FAST_GROWTH",
	"SLOW_GROWTH",
	"SHORT_LIFE",
	"LONG_LIFE",
	"NO_DISTURBANCE",
	"DISTURBANCE_SHALLOW_ROOT",
	"DISTURBANCE_DEEP_ROOT",
	"DISTURBANCE_FAST_RECOVERY",
	"DISTURBANCE_SLOW_RECOVERY",
	"DISTURBANCE_MILD",
	"DISTURBANCE_SEVERE",
]

static func run() -> Dictionary:
	var environments: Dictionary = PH2Probes.make_environment_samples()
	if environments.is_empty() or not environments.has("REFERENCE"):
		return {}
	var environment: Dictionary = environments["REFERENCE"]
	var default_genome: Dictionary = Genome.create_default()
	if default_genome.is_empty():
		return {}

	var fast := _genome("fast", 2.0, 0.80, 1.0, 80, 15.0, 20.0)
	var slow := _genome("slow", 2.0, 0.25, 1.0, 80, 15.0, 20.0)
	var short_life := _genome("short-life", 2.0, 0.80, 1.0, 80, 15.0, 5.0)
	var long_life := _genome("long-life", 2.0, 0.80, 1.0, 80, 15.0, 30.0)
	var shallow := _genome("shallow", 3.0, 0.50, 0.5, 80, 15.0, 20.0)
	var deep := _genome("deep", 3.0, 0.50, 3.0, 80, 15.0, 20.0)
	var recovery_fast := _genome("recovery-fast", 3.0, 0.80, 1.2, 80, 15.0, 20.0)
	var recovery_slow := _genome("recovery-slow", 3.0, 0.25, 1.2, 80, 15.0, 20.0)
	for genome in [fast, slow, short_life, long_life, shallow, deep, recovery_fast, recovery_slow]:
		if Dictionary(genome).is_empty():
			return {}

	var cases := {
		"IMMATURE_CONTROL": _case(default_genome, environment, 0.4, 1.0, 1.0, 0.5, 0.0),
		"MATURE_CONTROL": _case(default_genome, environment, 1.6, 1.0, 1.0, 3.0, 0.0),
		"MATURE_LOW_RESERVE": _case(default_genome, environment, 1.6, 1.0, 0.25, 3.0, 0.0),
		"MATURE_HIGH_RESERVE": _case(default_genome, environment, 1.6, 1.0, 2.0, 3.0, 0.0),
		"RELEASE_LOW": _case(default_genome, environment, 0.4, 1.0, 1.0, 0.5, 0.0),
		"RELEASE_HIGH": _case(default_genome, environment, 1.6, 1.0, 1.0, 3.0, 0.0),
		"FAST_GROWTH": _case(fast, environment, 2.0, 1.0, 1.0, 4.0, 0.0),
		"SLOW_GROWTH": _case(slow, environment, 2.0, 1.0, 1.0, 9.0, 0.0),
		"SHORT_LIFE": _case(short_life, environment, 2.0, 1.0, 1.0, 3.0, 0.0),
		"LONG_LIFE": _case(long_life, environment, 2.0, 1.0, 1.0, 3.0, 0.0),
		"NO_DISTURBANCE": _case(recovery_fast, environment, 3.0, 1.0, 1.0, 5.0, 0.0),
		"DISTURBANCE_SHALLOW_ROOT": _case(shallow, environment, 3.0, 1.0, 1.0, 7.0, 0.8),
		"DISTURBANCE_DEEP_ROOT": _case(deep, environment, 3.0, 1.0, 1.0, 7.0, 0.8),
		"DISTURBANCE_FAST_RECOVERY": _case(recovery_fast, environment, 3.0, 1.0, 1.0, 7.0, 0.7),
		"DISTURBANCE_SLOW_RECOVERY": _case(recovery_slow, environment, 3.0, 1.0, 1.0, 13.0, 0.7),
		"DISTURBANCE_MILD": _case(recovery_fast, environment, 3.0, 1.0, 1.0, 7.0, 0.2),
		"DISTURBANCE_SEVERE": _case(recovery_fast, environment, 3.0, 1.0, 1.0, 7.0, 0.9),
	}
	for case_id in CASE_ORDER:
		if not cases.has(case_id) or Dictionary(cases[case_id]).is_empty():
			return {}

	var parent: Dictionary = CExperiment.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_CAL1_C_HASH:
		return {}

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"case_order": CASE_ORDER.duplicate(),
		"cases": cases,
		"cal1_c_parent_hash": String(parent["aggregate_hash"]),
		"mature_to_immature_seed_ratio": _ratio(cases["MATURE_CONTROL"]["realized_seed_output_per_year"], cases["IMMATURE_CONTROL"]["realized_seed_output_per_year"]),
		"high_to_low_reserve_seed_ratio": _ratio(cases["MATURE_HIGH_RESERVE"]["realized_seed_output_per_year"], cases["MATURE_LOW_RESERVE"]["realized_seed_output_per_year"]),
		"high_to_low_release_distance_ratio": _ratio(cases["RELEASE_HIGH"]["effective_seed_dispersal_m"], cases["RELEASE_LOW"]["effective_seed_dispersal_m"]),
		"fast_maturity_time": float(cases["FAST_GROWTH"]["maturity_time_index_years"]),
		"slow_maturity_time": float(cases["SLOW_GROWTH"]["maturity_time_index_years"]),
		"short_life_amortized_structure": float(cases["SHORT_LIFE"]["amortized_structural_cost_per_year"]),
		"long_life_amortized_structure": float(cases["LONG_LIFE"]["amortized_structural_cost_per_year"]),
		"shallow_survival": float(cases["DISTURBANCE_SHALLOW_ROOT"]["disturbance_survival_fraction"]),
		"deep_survival": float(cases["DISTURBANCE_DEEP_ROOT"]["disturbance_survival_fraction"]),
		"fast_recovery_time": float(cases["DISTURBANCE_FAST_RECOVERY"]["recovery_time_index_years"]),
		"slow_recovery_time": float(cases["DISTURBANCE_SLOW_RECOVERY"]["recovery_time_index_years"]),
		"mild_post_seed_potential": float(cases["DISTURBANCE_MILD"]["post_disturbance_seed_potential"]),
		"severe_post_seed_potential": float(cases["DISTURBANCE_SEVERE"]["post_disturbance_seed_potential"]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _genome(id_suffix: String, height: float, growth: float, root_depth: float, seeds: int, dispersal: float, lifespan: float) -> Dictionary:
	return Genome.create(
		"plant-genome/cal1d/" + id_suffix,
		height,
		growth,
		root_depth,
		0.58,
		0.30,
		0.45,
		seeds,
		dispersal,
		lifespan
	)

static func _case(genome: Dictionary, environment: Dictionary, height: float, biomass: float, reserve: float, age: float, severity: float) -> Dictionary:
	var state := Lifecycle.create_state(height, biomass, reserve, age)
	var disturbance := Lifecycle.create_disturbance(severity)
	return Lifecycle.evaluate(genome, environment, state, disturbance)

static func _ratio(a, b) -> float:
	return float(a) / maxf(absf(float(b)), EPSILON)

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, String(result.get("cal1_c_parent_hash", ""))])
	var cases: Dictionary = result["cases"]
	for case_id in CASE_ORDER:
		tokens.append("%s|%s" % [case_id, String(cases[case_id]["result_hash"])])
	for field_name in [
		"mature_to_immature_seed_ratio", "high_to_low_reserve_seed_ratio", "high_to_low_release_distance_ratio",
		"fast_maturity_time", "slow_maturity_time", "short_life_amortized_structure", "long_life_amortized_structure",
		"shallow_survival", "deep_survival", "fast_recovery_time", "slow_recovery_time",
		"mild_post_seed_potential", "severe_post_seed_potential"
	]:
		tokens.append("%.12f" % float(result.get(field_name, 0.0)))
	return "\n".join(tokens).sha256_text()
