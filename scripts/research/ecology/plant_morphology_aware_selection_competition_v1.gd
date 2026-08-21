extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Traits = preload("res://scripts/research/ecology/plant_development_traits_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const ResourceModel = preload("res://scripts/research/ecology/plant_resource_model_v1.gd")
const Coupling = preload("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.plant_morphology_aware_selection_competition.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.PH3C.1"
const DEFAULT_CYCLES := 10
const SELECTION_STRENGTH := 0.35
const PARENT_LINEAGE := "lineage/ph3c-controlled"
const REPRODUCTION_EVENT := "competition/ph3c-common"
const SEED_INDEX := 0
const PAIR_CASES := [
	{"id":"SUN_CROWN", "environment":"SUN", "a":"CROWN_NARROW", "b":"CROWN_WIDE"},
	{"id":"DRY_CROWN", "environment":"DRY", "a":"CROWN_NARROW", "b":"CROWN_WIDE"},
	{"id":"REFERENCE_BRANCH", "environment":"REFERENCE", "a":"BRANCH_LOW", "b":"BRANCH_HIGH"},
	{"id":"REFERENCE_HEIGHT", "environment":"REFERENCE", "a":"HEIGHT_LOW", "b":"HEIGHT_HIGH"},
	{"id":"REFERENCE_GIANT", "environment":"REFERENCE", "a":"BASE", "b":"GIANT_DENSE"},
]

static func create_strategy_pool() -> Dictionary:
	var base := Traits.create_default()
	var giant := Traits.with_trait(base, "max_height_m", 12.0, "/giant")
	giant = Traits.with_trait(giant, "crown_spread_m", 7.0, "/wide")
	giant = Traits.with_trait(giant, "branch_probability", 0.98, "/dense")
	giant = Traits.with_trait(giant, "branch_length_ratio", 1.15, "/long-branch")
	giant = Traits.with_trait(giant, "branching_depth", 4, "/deep-branch")
	return {
		"BASE": base,
		"HEIGHT_LOW": Traits.with_trait(base, "max_height_m", 1.8, "/height-low"),
		"HEIGHT_HIGH": Traits.with_trait(base, "max_height_m", 7.0, "/height-high"),
		"CROWN_NARROW": Traits.with_trait(base, "crown_spread_m", 0.75, "/crown-narrow"),
		"CROWN_WIDE": Traits.with_trait(base, "crown_spread_m", 4.2, "/crown-wide"),
		"BRANCH_LOW": Traits.with_trait(base, "branch_probability", 0.18, "/branch-low"),
		"BRANCH_HIGH": Traits.with_trait(base, "branch_probability", 0.90, "/branch-high"),
		"GIANT_DENSE": giant,
	}

static func run_pair(case_id: String, morphology_aware: bool = true, cycles: int = DEFAULT_CYCLES) -> Dictionary:
	if cycles <= 0:
		return {}
	var definition := _pair_definition(case_id)
	if definition.is_empty():
		return {}
	var environments := PH2Probes.make_environment_samples()
	var environment_name := String(definition["environment"])
	if not environments.has(environment_name):
		return {}
	var environment: Dictionary = environments[environment_name]
	var strategies := create_strategy_pool()
	var a_name := String(definition["a"])
	var b_name := String(definition["b"])
	if not strategies.has(a_name) or not strategies.has(b_name):
		return {}
	var genome := Genome.create_default()
	var a := _evaluate_strategy(a_name, strategies[a_name], environment, genome, morphology_aware)
	var b := _evaluate_strategy(b_name, strategies[b_name], environment, genome, morphology_aware)
	if a.is_empty() or b.is_empty():
		return {}

	var a_share := 0.5
	var b_share := 0.5
	var history: Array = [{"cycle":0, "a_share":a_share, "b_share":b_share}]
	for cycle in range(1, cycles + 1):
		var a_weight := a_share * exp(clampf(float(a["selection_score"]) * SELECTION_STRENGTH, -4.0, 4.0))
		var b_weight := b_share * exp(clampf(float(b["selection_score"]) * SELECTION_STRENGTH, -4.0, 4.0))
		var total := a_weight + b_weight
		if total <= 0.0 or not is_finite(total):
			return {}
		a_share = a_weight / total
		b_share = b_weight / total
		history.append({"cycle":cycle, "a_share":a_share, "b_share":b_share})

	var winner := "TIE"
	if a_share > b_share + 0.000000001:
		winner = a_name
	elif b_share > a_share + 0.000000001:
		winner = b_name
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"case_id": case_id,
		"environment": environment_name,
		"morphology_aware": morphology_aware,
		"cycles": cycles,
		"selection_strength": SELECTION_STRENGTH,
		"strategy_a": a,
		"strategy_b": b,
		"history": history,
		"final_a_share": a_share,
		"final_b_share": b_share,
		"winner": winner,
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func run_matrix(cycles: int = DEFAULT_CYCLES) -> Dictionary:
	var results := {}
	var tokens := PackedStringArray()
	for definition in PAIR_CASES:
		var case_id := String(definition["id"])
		var aware := run_pair(case_id, true, cycles)
		var control := run_pair(case_id, false, cycles)
		if aware.is_empty() or control.is_empty():
			return {}
		results[case_id + "/AWARE"] = aware
		results[case_id + "/RESOURCE_ONLY_CONTROL"] = control
		tokens.append("%s|AWARE|%s" % [case_id, String(aware["result_hash"])])
		tokens.append("%s|RESOURCE_ONLY_CONTROL|%s" % [case_id, String(control["result_hash"])])
	return {
		"schema": SCHEMA + ".matrix",
		"version": VERSION,
		"cycles": cycles,
		"case_count": PAIR_CASES.size(),
		"results": results,
		"aggregate_hash": "\n".join(tokens).sha256_text(),
	}

static func compute_result_hash(result: Dictionary) -> String:
	var a: Dictionary = result.get("strategy_a", {})
	var b: Dictionary = result.get("strategy_b", {})
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(result.get("case_id", "")),
		String(result.get("environment", "")),
		str(bool(result.get("morphology_aware", false))),
		str(int(result.get("cycles", 0))),
		"%.9f" % float(result.get("selection_strength", 0.0)),
		_strategy_token(a),
		_strategy_token(b),
	])
	for row in Array(result.get("history", [])):
		var h: Dictionary = row
		tokens.append("%d|%.9f|%.9f" % [int(h["cycle"]), float(h["a_share"]), float(h["b_share"])])
	tokens.append("%.9f|%.9f|%s" % [float(result.get("final_a_share", 0.0)), float(result.get("final_b_share", 0.0)), String(result.get("winner", ""))])
	return "\n".join(tokens).sha256_text()

static func _evaluate_strategy(name: String, traits: Dictionary, environment: Dictionary, genome: Dictionary, morphology_aware: bool) -> Dictionary:
	var envelope := Contract.create_seed_envelope(genome, traits, PARENT_LINEAGE, REPRODUCTION_EVENT, SEED_INDEX)
	if envelope.is_empty():
		return {}
	var phenotype := Plasticity.realize(envelope, traits, environment)
	if phenotype.is_empty():
		return {}
	var resource := ResourceModel.evaluate(environment, genome)
	var coupling := Coupling.evaluate(environment, genome, phenotype)
	if resource.is_empty() or coupling.is_empty():
		return {}
	var base_score := float(resource["net_resource_balance"])
	var coupled_score := float(coupling["coupled_net_resource_balance"])
	return {
		"name": name,
		"genome_checksum": String(genome["checksum"]),
		"inherited_traits_checksum": String(traits["checksum"]),
		"individual_seed": int(envelope["individual_seed"]),
		"phenotype_hash": String(phenotype["phenotype_hash"]),
		"growth_graph_hash": String(phenotype["growth_graph"]["graph_hash"]),
		"resource_balance_checksum": String(resource["checksum"]),
		"coupling_hash": String(coupling["coupling_hash"]),
		"base_net_resource_balance": base_score,
		"morphology_delta": float(coupling["morphology_delta"]),
		"coupled_net_resource_balance": coupled_score,
		"selection_score": coupled_score if morphology_aware else base_score,
	}

static func _pair_definition(case_id: String) -> Dictionary:
	for definition in PAIR_CASES:
		if String(definition["id"]) == case_id:
			var copy := {}
			for key in definition.keys():
				copy[key] = definition[key]
			return copy
	return {}

static func _strategy_token(strategy: Dictionary) -> String:
	return "%s|%s|%s|%d|%s|%s|%s|%.9f|%.9f|%.9f|%.9f" % [
		String(strategy.get("name", "")),
		String(strategy.get("genome_checksum", "")),
		String(strategy.get("inherited_traits_checksum", "")),
		int(strategy.get("individual_seed", -1)),
		String(strategy.get("phenotype_hash", "")),
		String(strategy.get("growth_graph_hash", "")),
		String(strategy.get("coupling_hash", "")),
		float(strategy.get("base_net_resource_balance", 0.0)),
		float(strategy.get("morphology_delta", 0.0)),
		float(strategy.get("coupled_net_resource_balance", 0.0)),
		float(strategy.get("selection_score", 0.0)),
	]
