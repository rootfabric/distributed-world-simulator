extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const Coupling = preload("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd")
const Competition = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_morphology_economics_baseline.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.CAL1-A.1"
const FULL_POOL_CYCLES := 10
const SELECTION_STRENGTH := 0.35
const EPSILON := 0.000000000001

const ENVIRONMENT_ORDER: Array[String] = ["REFERENCE", "SHADE", "SUN", "DRY"]
const STRATEGY_ORDER: Array[String] = [
	"BASE",
	"HEIGHT_LOW",
	"HEIGHT_HIGH",
	"CROWN_NARROW",
	"CROWN_WIDE",
	"BRANCH_LOW",
	"BRANCH_HIGH",
	"GIANT_DENSE",
]
const MORPH_COMPONENT_ORDER: Array[String] = [
	"height_light_access_benefit",
	"crown_light_capture_benefit",
	"branch_light_capture_benefit",
	"structural_cost",
	"branch_maintenance_cost",
	"branch_construction_cost",
	"crown_water_cost",
]
const COST_COMPONENTS: Array[String] = [
	"structural_cost",
	"branch_maintenance_cost",
	"branch_construction_cost",
	"crown_water_cost",
]

static func run() -> Dictionary:
	var environments: Dictionary = PH2Probes.make_environment_samples()
	var strategies: Dictionary = Competition.create_strategy_pool()
	var genome: Dictionary = Genome.create_default()
	if environments.is_empty() or strategies.size() != STRATEGY_ORDER.size() or genome.is_empty():
		return {}

	var pairwise: Dictionary = Competition.run_matrix()
	if pairwise.is_empty() or String(pairwise.get("aggregate_hash", "")).length() != 64:
		return {}

	var environment_results: Dictionary = {}
	var result_tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		EXPERIMENT_REVISION,
		String(pairwise["aggregate_hash"]),
	])
	var total_rows := 0
	var height_low_wins := 0
	var height_low_top2 := 0
	var height_low_beats_height_high := 0

	for environment_name in ENVIRONMENT_ORDER:
		if not environments.has(environment_name):
			return {}
		var environment: Dictionary = environments[environment_name]
		var rows: Array = []
		for strategy_name in STRATEGY_ORDER:
			if not strategies.has(strategy_name):
				return {}
			var row := _evaluate_strategy(strategy_name, strategies[strategy_name], environment_name, environment, genome)
			if row.is_empty():
				return {}
			rows.append(row)

		rows = _sort_rows(rows)
		_assign_ranks(rows)
		_apply_sensitivity(rows)
		_apply_full_pool_shares(rows)
		var summary := _summarize_environment(environment_name, rows)
		if summary.is_empty():
			return {}
		environment_results[environment_name] = {
			"rows": rows,
			"summary": summary,
		}
		total_rows += rows.size()
		height_low_wins += 1 if int(summary["height_low_rank"]) == 1 else 0
		height_low_top2 += 1 if int(summary["height_low_rank"]) <= 2 else 0
		height_low_beats_height_high += 1 if float(summary["height_low_minus_height_high"]) > EPSILON else 0
		result_tokens.append(_environment_token(environment_name, rows, summary))

	var dominance_classification := "HEIGHT_LOW_CONTEXTUAL_OR_PAIRWISE_ONLY"
	if height_low_wins >= 3:
		dominance_classification = "HEIGHT_LOW_BROAD_FULL_POOL_WINNER"
	elif height_low_top2 >= 3 and height_low_beats_height_high == ENVIRONMENT_ORDER.size():
		dominance_classification = "HEIGHT_LOW_BROAD_FULL_POOL_ADVANTAGE"

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"environment_order": ENVIRONMENT_ORDER.duplicate(),
		"strategy_order": STRATEGY_ORDER.duplicate(),
		"row_count": total_rows,
		"environment_results": environment_results,
		"legacy_ph3c_pairwise_hash": String(pairwise["aggregate_hash"]),
		"height_low_win_count": height_low_wins,
		"height_low_top2_count": height_low_top2,
		"height_low_beats_height_high_count": height_low_beats_height_high,
		"dominance_classification": dominance_classification,
	}
	result["baseline_hash"] = "\n".join(result_tokens).sha256_text()
	return result

static func _evaluate_strategy(
	strategy_name: String,
	traits: Dictionary,
	environment_name: String,
	environment: Dictionary,
	genome: Dictionary
) -> Dictionary:
	var envelope: Dictionary = Contract.create_seed_envelope(
		genome,
		traits,
		Competition.PARENT_LINEAGE,
		Competition.REPRODUCTION_EVENT,
		Competition.SEED_INDEX
	)
	if envelope.is_empty():
		return {}
	var phenotype: Dictionary = Plasticity.realize(envelope, traits, environment)
	if phenotype.is_empty():
		return {}
	var coupling: Dictionary = Coupling.evaluate(environment, genome, phenotype)
	if coupling.is_empty():
		return {}
	var realized: Dictionary = phenotype.get("realized_development_traits", {})
	var graph: Dictionary = phenotype.get("growth_graph", {})
	var metrics: Dictionary = graph.get("metrics", {})
	if realized.is_empty() or metrics.is_empty():
		return {}

	var raw_components: Dictionary = {}
	var signed_components: Dictionary = {}
	var reconstructed := float(coupling["base_net_resource_balance"])
	for component_name in MORPH_COMPONENT_ORDER:
		var raw_value := float(coupling[component_name])
		var signed_value := -raw_value if component_name in COST_COMPONENTS else raw_value
		raw_components[component_name] = raw_value
		signed_components[component_name] = signed_value
		reconstructed += signed_value
	var selection_score := float(coupling["coupled_net_resource_balance"])
	if absf(reconstructed - selection_score) > 0.000000001:
		return {}

	return {
		"environment": environment_name,
		"strategy": strategy_name,
		"individual_seed": int(envelope["individual_seed"]),
		"genome_checksum": String(genome["checksum"]),
		"inherited_traits_checksum": String(traits["checksum"]),
		"phenotype_hash": String(phenotype["phenotype_hash"]),
		"growth_graph_hash": String(graph["graph_hash"]),
		"coupling_hash": String(coupling["coupling_hash"]),
		"realized_graph_height_m": float(metrics.get("height_m", 0.0)),
		"realized_max_height_m": float(realized.get("max_height_m", 0.0)),
		"realized_crown_spread_m": float(realized.get("crown_spread_m", 0.0)),
		"realized_branch_probability": float(realized.get("branch_probability", 0.0)),
		"realized_total_length_m": float(metrics.get("total_length_m", 0.0)),
		"base_net_resource_balance": float(coupling["base_net_resource_balance"]),
		"raw_components": raw_components,
		"signed_components": signed_components,
		"morphology_benefit": float(coupling["morphology_benefit"]),
		"morphology_cost": float(coupling["morphology_cost"]),
		"morphology_delta": float(coupling["morphology_delta"]),
		"selection_score": selection_score,
		"rank": 0,
		"margin_to_winner": 0.0,
		"normalized_margin_to_winner": 0.0,
		"sensitivity_component": "",
		"sensitivity_rank_shift": 0,
		"sensitivity_ablated_rank": 0,
		"full_pool_share": 0.0,
	}

static func _sort_rows(rows: Array) -> Array:
	var sorted: Array = []
	for item in rows:
		var row: Dictionary = item
		var inserted := false
		for index in range(sorted.size()):
			var other: Dictionary = sorted[index]
			if _row_is_better(row, other):
				sorted.insert(index, row)
				inserted = true
				break
		if not inserted:
			sorted.append(row)
	return sorted

static func _row_is_better(a: Dictionary, b: Dictionary) -> bool:
	var a_score := float(a["selection_score"])
	var b_score := float(b["selection_score"])
	if a_score > b_score + EPSILON:
		return true
	if b_score > a_score + EPSILON:
		return false
	return String(a["strategy"]) < String(b["strategy"])

static func _assign_ranks(rows: Array) -> void:
	if rows.is_empty():
		return
	var winner_score := float(Dictionary(rows[0])["selection_score"])
	var denominator := maxf(absf(winner_score), EPSILON)
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var margin := winner_score - float(row["selection_score"])
		row["rank"] = index + 1
		row["margin_to_winner"] = margin
		row["normalized_margin_to_winner"] = margin / denominator

static func _apply_sensitivity(rows: Array) -> void:
	for item in rows:
		var row: Dictionary = item
		var baseline_rank := int(row["rank"])
		var best_component := ""
		var best_shift := -1
		var best_magnitude := -1.0
		var best_rank := baseline_rank
		for component_name in MORPH_COMPONENT_ORDER:
			var ablated_rank := _rank_with_component_removed(rows, String(row["strategy"]), component_name)
			var shift := absi(ablated_rank - baseline_rank)
			var magnitude := absf(float(Dictionary(row["signed_components"])[component_name]))
			if shift > best_shift or (shift == best_shift and magnitude > best_magnitude + EPSILON):
				best_component = component_name
				best_shift = shift
				best_magnitude = magnitude
				best_rank = ablated_rank
		row["sensitivity_component"] = best_component
		row["sensitivity_rank_shift"] = best_shift
		row["sensitivity_ablated_rank"] = best_rank

static func _rank_with_component_removed(rows: Array, target_strategy: String, component_name: String) -> int:
	var target_score := 0.0
	for item in rows:
		var row: Dictionary = item
		if String(row["strategy"]) == target_strategy:
			target_score = _ablated_score(row, component_name)
			break
	var rank := 1
	for item in rows:
		var row: Dictionary = item
		var strategy_name := String(row["strategy"])
		if strategy_name == target_strategy:
			continue
		var score := _ablated_score(row, component_name)
		if score > target_score + EPSILON or (absf(score - target_score) <= EPSILON and strategy_name < target_strategy):
			rank += 1
	return rank

static func _ablated_score(row: Dictionary, component_name: String) -> float:
	return float(row["selection_score"]) - float(Dictionary(row["signed_components"])[component_name])

static func _apply_full_pool_shares(rows: Array) -> void:
	var shares: Dictionary = {}
	var initial_share := 1.0 / float(rows.size())
	for item in rows:
		shares[String(Dictionary(item)["strategy"])] = initial_share
	for _cycle in range(FULL_POOL_CYCLES):
		var weights: Dictionary = {}
		var total := 0.0
		for item in rows:
			var row: Dictionary = item
			var strategy_name := String(row["strategy"])
			var weight := float(shares[strategy_name]) * exp(clampf(float(row["selection_score"]) * SELECTION_STRENGTH, -4.0, 4.0))
			weights[strategy_name] = weight
			total += weight
		if total <= 0.0 or not is_finite(total):
			return
		for strategy_name in STRATEGY_ORDER:
			shares[strategy_name] = float(weights[strategy_name]) / total
	for item in rows:
		var row: Dictionary = item
		row["full_pool_share"] = float(shares[String(row["strategy"])])

static func _summarize_environment(environment_name: String, rows: Array) -> Dictionary:
	if rows.size() != STRATEGY_ORDER.size():
		return {}
	var winner: Dictionary = rows[0]
	var runner: Dictionary = rows[1]
	var height_low := _find_row(rows, "HEIGHT_LOW")
	var height_high := _find_row(rows, "HEIGHT_HIGH")
	if height_low.is_empty() or height_high.is_empty():
		return {}
	var winner_driver := _component_delta_summary(winner, runner)
	var height_driver := _component_delta_summary(height_low, height_high)
	return {
		"environment": environment_name,
		"winner": String(winner["strategy"]),
		"runner_up": String(runner["strategy"]),
		"winner_score": float(winner["selection_score"]),
		"runner_up_score": float(runner["selection_score"]),
		"winner_margin": float(winner["selection_score"]) - float(runner["selection_score"]),
		"winner_top_driver": String(winner_driver["top_driver"]),
		"winner_top_driver_delta": float(winner_driver["top_driver_delta"]),
		"winner_top_opposition": String(winner_driver["top_opposition"]),
		"winner_top_opposition_delta": float(winner_driver["top_opposition_delta"]),
		"height_low_rank": int(height_low["rank"]),
		"height_high_rank": int(height_high["rank"]),
		"height_low_score": float(height_low["selection_score"]),
		"height_high_score": float(height_high["selection_score"]),
		"height_low_minus_height_high": float(height_low["selection_score"]) - float(height_high["selection_score"]),
		"height_low_full_pool_share": float(height_low["full_pool_share"]),
		"height_high_full_pool_share": float(height_high["full_pool_share"]),
		"height_low_vs_high_top_driver": String(height_driver["top_driver"]),
		"height_low_vs_high_top_driver_delta": float(height_driver["top_driver_delta"]),
		"height_low_vs_high_top_opposition": String(height_driver["top_opposition"]),
		"height_low_vs_high_top_opposition_delta": float(height_driver["top_opposition_delta"]),
	}

static func _component_delta_summary(a: Dictionary, b: Dictionary) -> Dictionary:
	var top_driver := "base_net_resource_balance"
	var top_driver_delta := float(a["base_net_resource_balance"]) - float(b["base_net_resource_balance"])
	var top_opposition := top_driver
	var top_opposition_delta := top_driver_delta
	for component_name in MORPH_COMPONENT_ORDER:
		var delta := float(Dictionary(a["signed_components"])[component_name]) - float(Dictionary(b["signed_components"])[component_name])
		if delta > top_driver_delta + EPSILON:
			top_driver = component_name
			top_driver_delta = delta
		if delta < top_opposition_delta - EPSILON:
			top_opposition = component_name
			top_opposition_delta = delta
	return {
		"top_driver": top_driver,
		"top_driver_delta": top_driver_delta,
		"top_opposition": top_opposition,
		"top_opposition_delta": top_opposition_delta,
	}

static func _find_row(rows: Array, strategy_name: String) -> Dictionary:
	for item in rows:
		var row: Dictionary = item
		if String(row["strategy"]) == strategy_name:
			return row
	return {}

static func _environment_token(environment_name: String, rows: Array, summary: Dictionary) -> String:
	var tokens := PackedStringArray([environment_name])
	for item in rows:
		var row: Dictionary = item
		var component_tokens := PackedStringArray()
		for component_name in MORPH_COMPONENT_ORDER:
			component_tokens.append("%s=%.12f" % [component_name, float(Dictionary(row["signed_components"])[component_name])])
		tokens.append("|".join(PackedStringArray([
			String(row["strategy"]),
			str(int(row["individual_seed"])),
			String(row["phenotype_hash"]),
			String(row["growth_graph_hash"]),
			String(row["coupling_hash"]),
			"%.12f" % float(row["realized_graph_height_m"]),
			"%.12f" % float(row["realized_crown_spread_m"]),
			"%.12f" % float(row["realized_branch_probability"]),
			"%.12f" % float(row["realized_total_length_m"]),
			"%.12f" % float(row["base_net_resource_balance"]),
			";".join(component_tokens),
			"%.12f" % float(row["morphology_delta"]),
			"%.12f" % float(row["selection_score"]),
			str(int(row["rank"])),
			"%.12f" % float(row["margin_to_winner"]),
			String(row["sensitivity_component"]),
			str(int(row["sensitivity_rank_shift"])),
			str(int(row["sensitivity_ablated_rank"])),
			"%.12f" % float(row["full_pool_share"]),
		])))
	tokens.append("SUMMARY|%s|%s|%.12f|%s|%.12f|%d|%d|%.12f|%s|%.12f" % [
		String(summary["winner"]),
		String(summary["runner_up"]),
		float(summary["winner_margin"]),
		String(summary["winner_top_driver"]),
		float(summary["winner_top_driver_delta"]),
		int(summary["height_low_rank"]),
		int(summary["height_high_rank"]),
		float(summary["height_low_minus_height_high"]),
		String(summary["height_low_vs_high_top_driver"]),
		float(summary["height_low_vs_high_top_driver_delta"]),
	])
	return "\n".join(tokens)
