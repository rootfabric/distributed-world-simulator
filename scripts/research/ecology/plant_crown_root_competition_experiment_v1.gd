extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const Competition = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")
const Spatial = preload("res://scripts/research/ecology/plant_spatial_crown_root_competition_v1.gd")
const CAL1BExperiment = preload("res://scripts/research/ecology/plant_vertical_light_competition_experiment_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_c_crown_root_experiment.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.CAL1-C.1"
const EPSILON := 0.000000000001
const EXPECTED_CAL1_B_HASH := "c101ba420aeeeac5f3ee0defa3f8773ad2bf0e9ef24c18f4c7ba6f8ec146e88c"

const CASE_ORDER: Array[String] = [
	"CROWN_NO_OVERLAP",
	"CROWN_EQUAL_CLOSE",
	"CROWN_EQUAL_FAR",
	"CROWN_HIGH_BRANCH_NEIGHBOUR",
	"CROWN_LOW_BRANCH_NEIGHBOUR",
	"CROWN_WIDE_NARROW",
	"CROWN_WIDE_NARROW_SWAP",
	"ROOT_NO_OVERLAP",
	"ROOT_EQUAL_DENSE",
	"ROOT_DEEP_SHALLOW_DENSE",
	"ROOT_DEEP_SHALLOW_SPARSE",
	"ROOT_DRY_DEEP_SHALLOW_DENSE",
	"ROOT_DEEP_SHALLOW_SWAP",
]

static func run() -> Dictionary:
	var environments: Dictionary = PH2Probes.make_environment_samples()
	var strategies: Dictionary = Competition.create_strategy_pool()
	var genome: Dictionary = Genome.create_default()
	if environments.is_empty() or strategies.is_empty() or genome.is_empty():
		return {}
	var parent_b := CAL1BExperiment.run()
	if parent_b.is_empty() or String(parent_b.get("aggregate_hash", "")) != EXPECTED_CAL1_B_HASH:
		return {}

	var reference: Dictionary = environments["REFERENCE"]
	var dry: Dictionary = environments["DRY"]
	var phenotypes := {}
	for strategy_name in ["BASE", "BRANCH_HIGH", "BRANCH_LOW", "CROWN_WIDE", "CROWN_NARROW"]:
		phenotypes[strategy_name] = _realize(strategy_name, strategies[strategy_name], reference, genome)
		if Dictionary(phenotypes[strategy_name]).is_empty():
			return {}

	var cases := {}
	cases["CROWN_NO_OVERLAP"] = _crown_case("CROWN_NO_OVERLAP", phenotypes["BASE"], phenotypes["BASE"], reference, 1.20)
	cases["CROWN_EQUAL_CLOSE"] = _crown_case("CROWN_EQUAL_CLOSE", phenotypes["BASE"], phenotypes["BASE"], reference, 0.20)
	cases["CROWN_EQUAL_FAR"] = _crown_case("CROWN_EQUAL_FAR", phenotypes["BASE"], phenotypes["BASE"], reference, 0.75)
	cases["CROWN_HIGH_BRANCH_NEIGHBOUR"] = _crown_case("CROWN_HIGH_BRANCH_NEIGHBOUR", phenotypes["BASE"], phenotypes["BRANCH_HIGH"], reference, 0.35)
	cases["CROWN_LOW_BRANCH_NEIGHBOUR"] = _crown_case("CROWN_LOW_BRANCH_NEIGHBOUR", phenotypes["BASE"], phenotypes["BRANCH_LOW"], reference, 0.35)
	cases["CROWN_WIDE_NARROW"] = _crown_case("CROWN_WIDE_NARROW", phenotypes["CROWN_WIDE"], phenotypes["CROWN_NARROW"], reference, 0.35)
	cases["CROWN_WIDE_NARROW_SWAP"] = _crown_case("CROWN_WIDE_NARROW_SWAP", phenotypes["CROWN_NARROW"], phenotypes["CROWN_WIDE"], reference, 0.35)

	var deep := Genome.with_root_depth(genome, 1.60, "/cal1c-deep")
	var shallow := Genome.with_root_depth(genome, 0.35, "/cal1c-shallow")
	if deep.is_empty() or shallow.is_empty():
		return {}
	cases["ROOT_NO_OVERLAP"] = _root_case("ROOT_NO_OVERLAP", genome, genome, reference, 1.20)
	cases["ROOT_EQUAL_DENSE"] = _root_case("ROOT_EQUAL_DENSE", genome, genome, reference, 0.10)
	cases["ROOT_DEEP_SHALLOW_DENSE"] = _root_case("ROOT_DEEP_SHALLOW_DENSE", deep, shallow, reference, 0.10)
	cases["ROOT_DEEP_SHALLOW_SPARSE"] = _root_case("ROOT_DEEP_SHALLOW_SPARSE", deep, shallow, reference, 0.90)
	cases["ROOT_DRY_DEEP_SHALLOW_DENSE"] = _root_case("ROOT_DRY_DEEP_SHALLOW_DENSE", deep, shallow, dry, 0.10)
	cases["ROOT_DEEP_SHALLOW_SWAP"] = _root_case("ROOT_DEEP_SHALLOW_SWAP", shallow, deep, reference, 0.10)

	for case_id in CASE_ORDER:
		if not cases.has(case_id) or Dictionary(cases[case_id]).is_empty():
			return {}

	var close_crown: Dictionary = cases["CROWN_EQUAL_CLOSE"]
	var far_crown: Dictionary = cases["CROWN_EQUAL_FAR"]
	var high_neighbour: Dictionary = cases["CROWN_HIGH_BRANCH_NEIGHBOUR"]
	var low_neighbour: Dictionary = cases["CROWN_LOW_BRANCH_NEIGHBOUR"]
	var dense_root: Dictionary = cases["ROOT_DEEP_SHALLOW_DENSE"]
	var sparse_root: Dictionary = cases["ROOT_DEEP_SHALLOW_SPARSE"]
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"parent_cal1_b_hash": String(parent_b["aggregate_hash"]),
		"case_order": CASE_ORDER.duplicate(),
		"cases": cases,
		"crown_close_overlap_m2": float(close_crown["overlap_area_m2"]),
		"crown_far_overlap_m2": float(far_crown["overlap_area_m2"]),
		"crown_close_loss_a": float(close_crown["crown_overlap_loss_a"]),
		"crown_far_loss_a": float(far_crown["crown_overlap_loss_a"]),
		"high_branch_neighbour_loss_a": float(high_neighbour["crown_overlap_loss_a"]),
		"low_branch_neighbour_loss_a": float(low_neighbour["crown_overlap_loss_a"]),
		"root_dense_delta_a": float(dense_root["root_competition_delta_a"]),
		"root_dense_delta_b": float(dense_root["root_competition_delta_b"]),
		"root_sparse_delta_a": float(sparse_root["root_competition_delta_a"]),
		"root_sparse_delta_b": float(sparse_root["root_competition_delta_b"]),
		"root_deep_claim": float(dense_root["shared_claim_a"]),
		"root_shallow_claim": float(dense_root["shared_claim_b"]),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _realize(strategy_name: String, traits: Dictionary, environment: Dictionary, genome: Dictionary) -> Dictionary:
	var envelope := Contract.create_seed_envelope(genome, traits, Competition.PARENT_LINEAGE, Competition.REPRODUCTION_EVENT, Competition.SEED_INDEX)
	if envelope.is_empty():
		return {}
	var phenotype := Plasticity.realize(envelope, traits, environment)
	if phenotype.is_empty():
		return {}
	return {"strategy": strategy_name, "individual_seed": int(envelope["individual_seed"]), "phenotype": phenotype}

static func _crown_case(case_id: String, a: Dictionary, b: Dictionary, environment: Dictionary, separation_factor: float) -> Dictionary:
	var phenotype_a: Dictionary = a["phenotype"]
	var phenotype_b: Dictionary = b["phenotype"]
	var traits_a: Dictionary = phenotype_a["realized_development_traits"]
	var traits_b: Dictionary = phenotype_b["realized_development_traits"]
	var radius_sum := 0.5 * float(traits_a["crown_spread_m"]) + 0.5 * float(traits_b["crown_spread_m"])
	var position_a := Vector2.ZERO
	var position_b := Vector2(radius_sum * separation_factor, 0.0)
	var spatial := Spatial.evaluate_crown_pair(phenotype_a, phenotype_b, environment, position_a, position_b)
	if spatial.is_empty():
		return {}
	var result := spatial.duplicate(true)
	result["case_id"] = case_id
	result["strategy_a"] = String(a["strategy"])
	result["strategy_b"] = String(b["strategy"])
	result["individual_seed_a"] = int(a["individual_seed"])
	result["individual_seed_b"] = int(b["individual_seed"])
	result["separation_factor"] = separation_factor
	result["case_hash"] = _case_hash(result)
	return result

static func _root_case(case_id: String, genome_a: Dictionary, genome_b: Dictionary, environment: Dictionary, separation_factor: float) -> Dictionary:
	var radius_sum := float(genome_a["root_depth_m"]) + float(genome_b["root_depth_m"])
	var position_a := Vector2.ZERO
	var position_b := Vector2(radius_sum * separation_factor, 0.0)
	var spatial := Spatial.evaluate_root_pair(genome_a, genome_b, environment, position_a, position_b)
	if spatial.is_empty():
		return {}
	var result := spatial.duplicate(true)
	result["case_id"] = case_id
	result["separation_factor"] = separation_factor
	result["case_hash"] = _case_hash(result)
	return result

static func _case_hash(result: Dictionary) -> String:
	var keys := result.keys()
	keys.sort()
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, String(result.get("case_id", ""))])
	for key_variant in keys:
		var key := String(key_variant)
		if key in ["case_hash", "position_a", "position_b"]:
			continue
		var value = result[key]
		if typeof(value) == TYPE_FLOAT:
			tokens.append("%s=%.12f" % [key, float(value)])
		elif typeof(value) == TYPE_INT:
			tokens.append("%s=%d" % [key, int(value)])
		elif typeof(value) == TYPE_BOOL:
			tokens.append("%s=%s" % [key, str(bool(value))])
		elif typeof(value) == TYPE_STRING:
			tokens.append("%s=%s" % [key, String(value)])
	for position_key in ["position_a", "position_b"]:
		var p := Vector2(result.get(position_key, Vector2.ZERO))
		tokens.append("%s=%.9f,%.9f" % [position_key, p.x, p.y])
	return "\n".join(tokens).sha256_text()

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, String(result["parent_cal1_b_hash"])])
	var cases: Dictionary = result["cases"]
	for case_id in CASE_ORDER:
		tokens.append("%s|%s" % [case_id, String(cases[case_id]["case_hash"])])
	for name in [
		"crown_close_overlap_m2", "crown_far_overlap_m2", "crown_close_loss_a", "crown_far_loss_a",
		"high_branch_neighbour_loss_a", "low_branch_neighbour_loss_a",
		"root_dense_delta_a", "root_dense_delta_b", "root_sparse_delta_a", "root_sparse_delta_b",
		"root_deep_claim", "root_shallow_claim"
	]:
		tokens.append("%s=%.12f" % [name, float(result.get(name, 0.0))])
	return "\n".join(tokens).sha256_text()
