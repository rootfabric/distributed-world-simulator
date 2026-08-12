extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const Coupling = preload("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd")
const Competition = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")
const VerticalLight = preload("res://scripts/research/ecology/plant_relative_vertical_light_competition_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_b_vertical_light_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.CAL1-B.1"
const EPSILON := 0.000000000001

const CASE_ORDER: Array[String] = [
	"NO_NEIGHBOURS",
	"EQUAL_HEIGHT_DENSE",
	"TALL_SHORT_DENSE",
	"TALL_SHORT_SPARSE",
	"DRY_TALL_SHORT_DENSE",
	"TALL_SHORT_DENSE_SWAP",
]

static func run() -> Dictionary:
	var environments: Dictionary = PH2Probes.make_environment_samples()
	var strategies: Dictionary = Competition.create_strategy_pool()
	var genome: Dictionary = Genome.create_default()
	if environments.is_empty() or strategies.is_empty() or genome.is_empty():
		return {}

	var cases := {
		"NO_NEIGHBOURS": _run_case("NO_NEIGHBOURS", "REFERENCE", "HEIGHT_HIGH", "HEIGHT_LOW", 0.0, 0.0, environments, strategies, genome),
		"EQUAL_HEIGHT_DENSE": _run_case("EQUAL_HEIGHT_DENSE", "REFERENCE", "BASE", "BASE", 0.90, 0.90, environments, strategies, genome),
		"TALL_SHORT_DENSE": _run_case("TALL_SHORT_DENSE", "REFERENCE", "HEIGHT_HIGH", "HEIGHT_LOW", 0.90, 0.90, environments, strategies, genome),
		"TALL_SHORT_SPARSE": _run_case("TALL_SHORT_SPARSE", "REFERENCE", "HEIGHT_HIGH", "HEIGHT_LOW", 0.15, 0.15, environments, strategies, genome),
		"DRY_TALL_SHORT_DENSE": _run_case("DRY_TALL_SHORT_DENSE", "DRY", "HEIGHT_HIGH", "HEIGHT_LOW", 0.90, 0.90, environments, strategies, genome),
		"TALL_SHORT_DENSE_SWAP": _run_case("TALL_SHORT_DENSE_SWAP", "REFERENCE", "HEIGHT_LOW", "HEIGHT_HIGH", 0.90, 0.90, environments, strategies, genome),
	}
	for case_id in CASE_ORDER:
		if not cases.has(case_id) or Dictionary(cases[case_id]).is_empty():
			return {}

	var dense: Dictionary = cases["TALL_SHORT_DENSE"]
	var sparse: Dictionary = cases["TALL_SHORT_SPARSE"]
	var dry: Dictionary = cases["DRY_TALL_SHORT_DENSE"]
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"case_order": CASE_ORDER.duplicate(),
		"cases": cases,
		"dense_to_sparse_delta_ratio": absf(float(dense["a_light_delta"])) / maxf(absf(float(sparse["a_light_delta"])), EPSILON),
		"reference_dense_baseline_gap_a_minus_b": float(dense["baseline_score_a"]) - float(dense["baseline_score_b"]),
		"reference_dense_adjusted_gap_a_minus_b": float(dense["adjusted_score_a"]) - float(dense["adjusted_score_b"]),
		"dry_dense_baseline_gap_a_minus_b": float(dry["baseline_score_a"]) - float(dry["baseline_score_b"]),
		"dry_dense_adjusted_gap_a_minus_b": float(dry["adjusted_score_a"]) - float(dry["adjusted_score_b"]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _run_case(
	case_id: String,
	environment_name: String,
	strategy_a_name: String,
	strategy_b_name: String,
	canopy_overlap: float,
	local_density: float,
	environments: Dictionary,
	strategies: Dictionary,
	genome: Dictionary
) -> Dictionary:
	if not environments.has(environment_name) or not strategies.has(strategy_a_name) or not strategies.has(strategy_b_name):
		return {}
	var environment: Dictionary = environments[environment_name]
	var a := _realize_strategy(strategy_a_name, strategies[strategy_a_name], environment, genome)
	var b := _realize_strategy(strategy_b_name, strategies[strategy_b_name], environment, genome)
	if a.is_empty() or b.is_empty():
		return {}
	var context := VerticalLight.create_context(canopy_overlap, local_density, case_id)
	if context.is_empty():
		return {}
	var light := VerticalLight.evaluate_pair(environment, a["phenotype"], b["phenotype"], context)
	if light.is_empty():
		return {}
	var baseline_a := float(a["coupling"]["coupled_net_resource_balance"])
	var baseline_b := float(b["coupling"]["coupled_net_resource_balance"])
	var adjusted_a := baseline_a + float(light["a_light_delta"])
	var adjusted_b := baseline_b + float(light["b_light_delta"])
	var result := {
		"case_id": case_id,
		"environment": environment_name,
		"strategy_a": strategy_a_name,
		"strategy_b": strategy_b_name,
		"individual_seed_a": int(a["individual_seed"]),
		"individual_seed_b": int(b["individual_seed"]),
		"phenotype_a_hash": String(a["phenotype"]["phenotype_hash"]),
		"phenotype_b_hash": String(b["phenotype"]["phenotype_hash"]),
		"coupling_a_hash": String(a["coupling"]["coupling_hash"]),
		"coupling_b_hash": String(b["coupling"]["coupling_hash"]),
		"vertical_light_hash": String(light["result_hash"]),
		"height_a_m": float(light["height_a_m"]),
		"height_b_m": float(light["height_b_m"]),
		"competition_intensity": float(light["competition_intensity"]),
		"contested_light_pool": float(light["contested_light_pool"]),
		"relative_height_bias": float(light["relative_height_bias"]),
		"a_relative_access_share": float(light["a_relative_access_share"]),
		"b_relative_access_share": float(light["b_relative_access_share"]),
		"a_light_delta": float(light["a_light_delta"]),
		"b_light_delta": float(light["b_light_delta"]),
		"conservation_error": float(light["conservation_error"]),
		"baseline_score_a": baseline_a,
		"baseline_score_b": baseline_b,
		"adjusted_score_a": adjusted_a,
		"adjusted_score_b": adjusted_b,
		"baseline_winner": _winner(strategy_a_name, baseline_a, strategy_b_name, baseline_b),
		"adjusted_winner": _winner(strategy_a_name, adjusted_a, strategy_b_name, adjusted_b),
	}
	result["case_hash"] = _case_hash(result)
	return result

static func _realize_strategy(strategy_name: String, traits: Dictionary, environment: Dictionary, genome: Dictionary) -> Dictionary:
	var envelope := Contract.create_seed_envelope(
		genome,
		traits,
		Competition.PARENT_LINEAGE,
		Competition.REPRODUCTION_EVENT,
		Competition.SEED_INDEX
	)
	if envelope.is_empty():
		return {}
	var phenotype := Plasticity.realize(envelope, traits, environment)
	if phenotype.is_empty():
		return {}
	var coupling := Coupling.evaluate(environment, genome, phenotype)
	if coupling.is_empty():
		return {}
	return {
		"strategy": strategy_name,
		"individual_seed": int(envelope["individual_seed"]),
		"phenotype": phenotype,
		"coupling": coupling,
	}

static func _winner(a_name: String, a_score: float, b_name: String, b_score: float) -> String:
	if a_score > b_score + EPSILON:
		return a_name
	if b_score > a_score + EPSILON:
		return b_name
	return "TIE"

static func _case_hash(result: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("case_id", "")),
		String(result.get("environment", "")),
		String(result.get("strategy_a", "")),
		String(result.get("strategy_b", "")),
		str(int(result.get("individual_seed_a", -1))),
		str(int(result.get("individual_seed_b", -1))),
		String(result.get("phenotype_a_hash", "")),
		String(result.get("phenotype_b_hash", "")),
		String(result.get("coupling_a_hash", "")),
		String(result.get("coupling_b_hash", "")),
		String(result.get("vertical_light_hash", "")),
		"%.12f" % float(result.get("a_light_delta", 0.0)),
		"%.12f" % float(result.get("b_light_delta", 0.0)),
		"%.12f" % float(result.get("baseline_score_a", 0.0)),
		"%.12f" % float(result.get("baseline_score_b", 0.0)),
		"%.12f" % float(result.get("adjusted_score_a", 0.0)),
		"%.12f" % float(result.get("adjusted_score_b", 0.0)),
		String(result.get("baseline_winner", "")),
		String(result.get("adjusted_winner", "")),
	])).sha256_text()

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION])
	var cases: Dictionary = result["cases"]
	for case_id in CASE_ORDER:
		tokens.append("%s|%s" % [case_id, String(cases[case_id]["case_hash"])])
	for name in [
		"dense_to_sparse_delta_ratio",
		"reference_dense_baseline_gap_a_minus_b",
		"reference_dense_adjusted_gap_a_minus_b",
		"dry_dense_baseline_gap_a_minus_b",
		"dry_dense_adjusted_gap_a_minus_b"
	]:
		tokens.append("%.12f" % float(result.get(name, 0.0)))
	return "\n".join(tokens).sha256_text()
