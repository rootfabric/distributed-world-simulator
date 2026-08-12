extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const Coupling = preload("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd")
const Selection = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")
const VerticalLight = preload("res://scripts/research/ecology/plant_relative_vertical_light_competition_v1.gd")
const Spatial = preload("res://scripts/research/ecology/plant_spatial_crown_root_competition_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_lifecycle_payoff_v1.gd")
const DExperiment = preload("res://scripts/research/ecology/plant_lifecycle_payoff_experiment_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_e_combined_mechanism_matrix.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.CAL1-E.1"
const ACCEPTED_CAL1_D_HASH := "c295da316e42fdf2f1073f8853709482191818a23763e9991d473cb5064992b6"
const EPSILON := 0.000000000001

const STRATEGY_ORDER: Array[String] = [
	"BASE", "HEIGHT_LOW", "HEIGHT_HIGH", "CROWN_NARROW",
	"CROWN_WIDE", "BRANCH_LOW", "BRANCH_HIGH", "GIANT_DENSE",
]
const ENVIRONMENT_ORDER: Array[String] = ["REFERENCE", "SHADE", "SUN", "DRY"]
const DENSITY_ORDER: Array[String] = ["SPARSE", "DENSE"]
const DISTURBANCE_ORDER: Array[String] = ["NONE", "MILD", "SEVERE"]
const DENSITY_DISTANCE_M := {"SPARSE": 50.0, "DENSE": 0.75}
const DENSITY_LOCAL := {"SPARSE": 0.15, "DENSE": 0.90}
const DISTURBANCE_SEVERITY := {"NONE": 0.0, "MILD": 0.20, "SEVERE": 0.90}
const COMMON_STAGE_FRACTION := 0.75
const COMMON_BIOMASS_KG_M2 := 1.0
const COMMON_RESERVE_RESOURCE := 1.0

static func run() -> Dictionary:
	var environments: Dictionary = PH2Probes.make_environment_samples()
	var strategies: Dictionary = Selection.create_strategy_pool()
	var base_genome: Dictionary = Genome.create_default()
	if environments.is_empty() or strategies.is_empty() or base_genome.is_empty():
		return {}
	for name in ENVIRONMENT_ORDER:
		if not environments.has(name):
			return {}
	for name in STRATEGY_ORDER:
		if not strategies.has(name):
			return {}

	var parent: Dictionary = DExperiment.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_CAL1_D_HASH:
		return {}

	var contexts := {}
	var aggregate_tokens := PackedStringArray([
		SCHEMA, VERSION, EXPERIMENT_REVISION, ACCEPTED_CAL1_D_HASH,
		"stage=%.12f" % COMMON_STAGE_FRACTION,
		"biomass=%.12f" % COMMON_BIOMASS_KG_M2,
		"reserve=%.12f" % COMMON_RESERVE_RESOURCE,
	])
	var row_count := 0
	var dense_nonzero_interaction_rows := 0
	var sparse_nonzero_interaction_rows := 0
	var multiobjective_contexts := 0
	var multi_member_pareto_contexts := 0
	var pareto_signatures := {}

	for environment_name in ENVIRONMENT_ORDER:
		var environment: Dictionary = environments[environment_name]
		var neighbour := _realize_strategy("BASE", strategies["BASE"], environment, base_genome)
		if neighbour.is_empty():
			return {}
		for density_name in DENSITY_ORDER:
			for disturbance_name in DISTURBANCE_ORDER:
				var context_id := "%s/%s/%s" % [environment_name, density_name, disturbance_name]
				var rows: Array = []
				for strategy_name in STRATEGY_ORDER:
					var focal := _realize_strategy(strategy_name, strategies[strategy_name], environment, base_genome)
					if focal.is_empty():
						return {}
					var row := _evaluate_row(
						context_id, environment_name, density_name, disturbance_name,
						focal, neighbour, strategies[strategy_name], environment, base_genome
					)
					if row.is_empty():
						return {}
					rows.append(row)
					row_count += 1
					var interaction_abs := float(row["interaction_abs_sum"])
					if density_name == "DENSE" and interaction_abs > EPSILON:
						dense_nonzero_interaction_rows += 1
					if density_name == "SPARSE" and interaction_abs > EPSILON:
						sparse_nonzero_interaction_rows += 1
				var summary := _summarize_context(rows)
				if summary.is_empty():
					return {}
				if int(summary["distinct_metric_winner_count"]) > 1:
					multiobjective_contexts += 1
				if Array(summary["pareto_front"]).size() > 1:
					multi_member_pareto_contexts += 1
				var pareto_signature := ",".join(PackedStringArray(summary["pareto_front"]))
				pareto_signatures[pareto_signature] = true
				var context := {
					"context_id": context_id,
					"environment": environment_name,
					"density": density_name,
					"disturbance": disturbance_name,
					"distance_m": float(DENSITY_DISTANCE_M[density_name]),
					"local_density": float(DENSITY_LOCAL[density_name]),
					"disturbance_severity": float(DISTURBANCE_SEVERITY[disturbance_name]),
					"rows": rows,
					"summary": summary,
				}
				context["context_hash"] = _context_hash(context)
				contexts[context_id] = context
				aggregate_tokens.append("%s|%s" % [context_id, String(context["context_hash"])])

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"cal1_d_parent_hash": ACCEPTED_CAL1_D_HASH,
		"strategy_order": STRATEGY_ORDER.duplicate(),
		"environment_order": ENVIRONMENT_ORDER.duplicate(),
		"density_order": DENSITY_ORDER.duplicate(),
		"disturbance_order": DISTURBANCE_ORDER.duplicate(),
		"common_stage_fraction": COMMON_STAGE_FRACTION,
		"common_biomass_kg_m2": COMMON_BIOMASS_KG_M2,
		"common_reserve_resource": COMMON_RESERVE_RESOURCE,
		"context_count": contexts.size(),
		"row_count": row_count,
		"dense_nonzero_interaction_rows": dense_nonzero_interaction_rows,
		"sparse_nonzero_interaction_rows": sparse_nonzero_interaction_rows,
		"multiobjective_contexts": multiobjective_contexts,
		"multi_member_pareto_contexts": multi_member_pareto_contexts,
		"distinct_pareto_signatures": pareto_signatures.size(),
		"contexts": contexts,
	}
	for field_name in [
		"context_count", "row_count", "dense_nonzero_interaction_rows", "sparse_nonzero_interaction_rows",
		"multiobjective_contexts", "multi_member_pareto_contexts", "distinct_pareto_signatures"
	]:
		aggregate_tokens.append("%s=%d" % [field_name, int(result[field_name])])
	result["aggregate_hash"] = "\n".join(aggregate_tokens).sha256_text()
	return result

static func _evaluate_row(
	context_id: String,
	environment_name: String,
	density_name: String,
	disturbance_name: String,
	focal: Dictionary,
	neighbour: Dictionary,
	inherited_traits: Dictionary,
	environment: Dictionary,
	base_genome: Dictionary
) -> Dictionary:
	var distance := float(DENSITY_DISTANCE_M[density_name])
	var local_density := float(DENSITY_LOCAL[density_name])
	var severity := float(DISTURBANCE_SEVERITY[disturbance_name])
	var position_a := Vector2.ZERO
	var position_b := Vector2(distance, 0.0)

	var crown := Spatial.evaluate_crown_pair(focal["phenotype"], neighbour["phenotype"], environment, position_a, position_b)
	var root := Spatial.evaluate_root_pair(base_genome, base_genome, environment, position_a, position_b)
	if crown.is_empty() or root.is_empty():
		return {}
	var overlap_scalar := clampf(0.5 * (float(crown["overlap_fraction_a"]) + float(crown["overlap_fraction_b"])), 0.0, 1.0)
	var vertical_context := VerticalLight.create_context(overlap_scalar, local_density, context_id)
	var vertical := VerticalLight.evaluate_pair(environment, focal["phenotype"], neighbour["phenotype"], vertical_context)
	if vertical.is_empty():
		return {}

	var coupled_resource := float(focal["coupling"]["coupled_net_resource_balance"])
	var vertical_delta := float(vertical["a_light_delta"])
	var crown_loss := float(crown["crown_overlap_loss_a"])
	var root_delta := float(root["root_competition_delta_a"])
	var combined_resource := coupled_resource + vertical_delta - crown_loss + root_delta

	var realized_traits: Dictionary = focal["phenotype"].get("realized_development_traits", {})
	var graph: Dictionary = focal["phenotype"].get("growth_graph", {})
	var metrics: Dictionary = graph.get("metrics", {})
	if realized_traits.is_empty() or metrics.is_empty():
		return {}
	var adult_height := maxf(float(metrics.get("height_m", 0.0)), 0.05)
	var lifecycle_genome := _lifecycle_projection_genome(base_genome, adult_height, String(focal["strategy"]), environment_name)
	if lifecycle_genome.is_empty():
		return {}
	var stage_height := adult_height * COMMON_STAGE_FRACTION
	var maturity_time := adult_height / maxf(float(lifecycle_genome["growth_rate"]), EPSILON)
	var years_alive := maturity_time * COMMON_STAGE_FRACTION
	var state := Lifecycle.create_state(stage_height, COMMON_BIOMASS_KG_M2, COMMON_RESERVE_RESOURCE, years_alive)
	var disturbance := Lifecycle.create_disturbance(severity)
	var lifecycle := Lifecycle.evaluate(lifecycle_genome, environment, state, disturbance)
	if lifecycle.is_empty():
		return {}

	var interaction_abs_sum := absf(vertical_delta) + absf(crown_loss) + absf(root_delta)
	var result := {
		"context_id": context_id,
		"environment": environment_name,
		"density": density_name,
		"disturbance": disturbance_name,
		"strategy": String(focal["strategy"]),
		"inherited_traits_checksum": String(inherited_traits["checksum"]),
		"phenotype_hash": String(focal["phenotype"]["phenotype_hash"]),
		"coupling_hash": String(focal["coupling"]["coupling_hash"]),
		"vertical_hash": String(vertical["result_hash"]),
		"crown_hash": String(crown["result_hash"]),
		"root_hash": String(root["result_hash"]),
		"lifecycle_hash": String(lifecycle["result_hash"]),
		"adult_height_m": adult_height,
		"crown_spread_m": float(realized_traits.get("crown_spread_m", 0.0)),
		"branch_probability": float(realized_traits.get("branch_probability", 0.0)),
		"coupled_resource_balance": coupled_resource,
		"vertical_light_delta": vertical_delta,
		"crown_overlap_loss": crown_loss,
		"root_competition_delta": root_delta,
		"combined_resource_balance": combined_resource,
		"interaction_abs_sum": interaction_abs_sum,
		"maturity_time_index_years": float(lifecycle["maturity_time_index_years"]),
		"post_disturbance_seed_potential": float(lifecycle["post_disturbance_seed_potential"]),
		"effective_seed_dispersal_m": float(lifecycle["effective_seed_dispersal_m"]),
		"disturbance_survival_fraction": float(lifecycle["disturbance_survival_fraction"]),
		"recovery_time_index_years": float(lifecycle["recovery_time_index_years"]),
		"amortized_structural_cost_per_year": float(lifecycle["amortized_structural_cost_per_year"]),
	}
	result["row_hash"] = _row_hash(result)
	return result

static func _realize_strategy(strategy_name: String, traits: Dictionary, environment: Dictionary, genome: Dictionary) -> Dictionary:
	var envelope := Contract.create_seed_envelope(
		genome, traits, Selection.PARENT_LINEAGE, Selection.REPRODUCTION_EVENT, Selection.SEED_INDEX
	)
	if envelope.is_empty():
		return {}
	var phenotype := Plasticity.realize(envelope, traits, environment)
	if phenotype.is_empty():
		return {}
	var coupling := Coupling.evaluate(environment, genome, phenotype)
	if coupling.is_empty():
		return {}
	return {"strategy": strategy_name, "phenotype": phenotype, "coupling": coupling}

static func _lifecycle_projection_genome(base: Dictionary, target_height_m: float, strategy_name: String, environment_name: String) -> Dictionary:
	return Genome.create(
		"plant-genome/cal1e/%s/%s" % [strategy_name.to_lower(), environment_name.to_lower()],
		target_height_m,
		float(base["growth_rate"]),
		float(base["root_depth_m"]),
		float(base["water_preference"]),
		float(base["water_tolerance_width"]),
		float(base["shade_tolerance"]),
		int(base["seed_count"]),
		float(base["seed_dispersal_distance_m"]),
		float(base["lifespan_years"])
	)

static func _summarize_context(rows: Array) -> Dictionary:
	if rows.size() != STRATEGY_ORDER.size():
		return {}
	var resource_winners := _winner_set(rows, "combined_resource_balance", true)
	var seed_winners := _winner_set(rows, "post_disturbance_seed_potential", true)
	var dispersal_winners := _winner_set(rows, "effective_seed_dispersal_m", true)
	var survival_winners := _winner_set(rows, "disturbance_survival_fraction", true)
	var maturity_winners := _winner_set(rows, "maturity_time_index_years", false)
	var amortization_winners := _winner_set(rows, "amortized_structural_cost_per_year", false)
	var recovery_winners := _winner_set(rows, "recovery_time_index_years", false)
	var pareto := _pareto_front(rows)
	var union := {}
	for winners in [resource_winners, seed_winners, dispersal_winners, survival_winners, maturity_winners, amortization_winners, recovery_winners]:
		for name in winners:
			union[String(name)] = true
	return {
		"resource_winners": resource_winners,
		"seed_winners": seed_winners,
		"dispersal_winners": dispersal_winners,
		"survival_winners": survival_winners,
		"maturity_winners": maturity_winners,
		"amortization_winners": amortization_winners,
		"recovery_winners": recovery_winners,
		"distinct_metric_winner_count": union.size(),
		"pareto_front": pareto,
	}

static func _winner_set(rows: Array, field_name: String, maximize: bool) -> Array[String]:
	var best := -INF if maximize else INF
	for row_value in rows:
		var row: Dictionary = row_value
		var value := float(row[field_name])
		if maximize:
			best = maxf(best, value)
		else:
			best = minf(best, value)
	var winners: Array[String] = []
	for row_value in rows:
		var row: Dictionary = row_value
		if absf(float(row[field_name]) - best) <= EPSILON:
			winners.append(String(row["strategy"]))
	return winners

static func _pareto_front(rows: Array) -> Array[String]:
	var front: Array[String] = []
	for i in range(rows.size()):
		var dominated := false
		for j in range(rows.size()):
			if i == j:
				continue
			if _dominates(Dictionary(rows[j]), Dictionary(rows[i])):
				dominated = true
				break
		if not dominated:
			front.append(String(Dictionary(rows[i])["strategy"]))
	return front

static func _dominates(a: Dictionary, b: Dictionary) -> bool:
	var strictly_better := false
	for field_name in ["combined_resource_balance", "post_disturbance_seed_potential", "effective_seed_dispersal_m", "disturbance_survival_fraction"]:
		var av := float(a[field_name]); var bv := float(b[field_name])
		if av < bv - EPSILON:
			return false
		if av > bv + EPSILON:
			strictly_better = true
	for field_name in ["maturity_time_index_years", "recovery_time_index_years", "amortized_structural_cost_per_year"]:
		var av := float(a[field_name]); var bv := float(b[field_name])
		if av > bv + EPSILON:
			return false
		if av < bv - EPSILON:
			strictly_better = true
	return strictly_better

static func _row_hash(row: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, EXPERIMENT_REVISION,
		String(row.get("context_id", "")), String(row.get("strategy", "")),
		String(row.get("inherited_traits_checksum", "")), String(row.get("phenotype_hash", "")),
		String(row.get("coupling_hash", "")), String(row.get("vertical_hash", "")),
		String(row.get("crown_hash", "")), String(row.get("root_hash", "")), String(row.get("lifecycle_hash", "")),
	])
	for field_name in [
		"adult_height_m", "crown_spread_m", "branch_probability",
		"coupled_resource_balance", "vertical_light_delta", "crown_overlap_loss", "root_competition_delta",
		"combined_resource_balance", "interaction_abs_sum", "maturity_time_index_years",
		"post_disturbance_seed_potential", "effective_seed_dispersal_m", "disturbance_survival_fraction",
		"recovery_time_index_years", "amortized_structural_cost_per_year"
	]:
		tokens.append("%.12f" % float(row.get(field_name, 0.0)))
	return "|".join(tokens).sha256_text()

static func _context_hash(context: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA, VERSION, EXPERIMENT_REVISION,
		String(context.get("context_id", "")),
		"%.12f" % float(context.get("distance_m", 0.0)),
		"%.12f" % float(context.get("local_density", 0.0)),
		"%.12f" % float(context.get("disturbance_severity", 0.0)),
	])
	for row_value in Array(context.get("rows", [])):
		var row: Dictionary = row_value
		tokens.append("%s|%s" % [String(row["strategy"]), String(row["row_hash"])])
	var summary: Dictionary = context.get("summary", {})
	for name in ["resource_winners", "seed_winners", "dispersal_winners", "survival_winners", "maturity_winners", "amortization_winners", "recovery_winners", "pareto_front"]:
		tokens.append("%s=%s" % [name, ",".join(PackedStringArray(summary.get(name, [])))])
	tokens.append("distinct=%d" % int(summary.get("distinct_metric_winner_count", 0)))
	return "\n".join(tokens).sha256_text()
