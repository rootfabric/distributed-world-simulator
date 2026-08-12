extends RefCounted

const Genome = preload("res://scripts/research/ecology/plant_genome_v1.gd")
const Contract = preload("res://scripts/research/ecology/plant_development_contract_v1.gd")
const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const PH2Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
const Plasticity = preload("res://scripts/research/ecology/plant_environment_coupled_development_v1.gd")
const Coupling = preload("res://scripts/research/ecology/plant_morphology_resource_coupling_v1.gd")
const Selection = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")
const VerticalLight = preload("res://scripts/research/ecology/plant_relative_vertical_light_competition_v1.gd")
const Spatial = preload("res://scripts/research/ecology/plant_spatial_crown_root_competition_v1.gd")
const Lifecycle = preload("res://scripts/research/ecology/plant_lifecycle_payoff_v1.gd")
const EExperiment = preload("res://scripts/research/ecology/plant_combined_mechanism_matrix_v1.gd")
const Calibration = preload("res://scripts/research/ecology/plant_cal1_f_calibration_profile_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.cal1_f_full_pool_robustness.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.CAL1-F.1"
const ACCEPTED_CAL1_E_HASH := "6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814"
const EPSILON := 0.000000001

const STRATEGY_ORDER: Array[String] = [
	"BASE", "HEIGHT_LOW", "HEIGHT_HIGH", "CROWN_NARROW",
	"CROWN_WIDE", "BRANCH_LOW", "BRANCH_HIGH", "GIANT_DENSE",
]
const ENVIRONMENT_ORDER: Array[String] = ["REFERENCE", "SHADE", "SUN", "DRY"]
const SEED_IDS: Array[int] = [0, 1, 2, 3, 4]
const ENVIRONMENT_VARIANTS: Array[String] = ["BASE", "MOISTURE_LOW", "MOISTURE_HIGH", "SUN_LOW", "SUN_HIGH"]
const DISTURBANCE_LABELS: Array[String] = ["NONE", "LOW", "MILD", "MID", "SEVERE"]
const DISTURBANCE_SEVERITY := {"NONE": 0.0, "LOW": 0.10, "MILD": 0.20, "MID": 0.50, "SEVERE": 0.90}
const DENSITY_SWEEP := [
	{"label":"DENSE_050", "distance_m":0.50, "local_density":1.00},
	{"label":"DENSE_075", "distance_m":0.75, "local_density":0.90},
	{"label":"MID_100", "distance_m":1.00, "local_density":0.75},
	{"label":"MID_150", "distance_m":1.50, "local_density":0.50},
	{"label":"SPARSE_5000", "distance_m":50.0, "local_density":0.15},
]
const COMMON_STAGE_FRACTION := 0.75
const COMMON_BIOMASS_KG_M2 := 1.0
const COMMON_RESERVE_RESOURCE := 1.0
const MIN_SEED_MULTI_PARETO_FRACTION := 0.75
const MIN_CALIBRATION_PARETO_JACCARD := 0.25
const MIN_MEAN_CALIBRATION_PARETO_JACCARD := 0.50

static func run() -> Dictionary:
	var parent: Dictionary = EExperiment.run()
	if parent.is_empty() or String(parent.get("aggregate_hash", "")) != ACCEPTED_CAL1_E_HASH:
		return {}
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

	var seed_sweep := _run_seed_sweep(environments, strategies, base_genome)
	var environment_sweep := _run_environment_sweep(environments, strategies, base_genome)
	var density_sweep := _run_density_sweep(environments, strategies, base_genome)
	var disturbance_sweep := _run_disturbance_sweep(environments, strategies, base_genome)
	var calibration_sweep := _run_calibration_sweep(parent, environments, strategies, base_genome)
	var pool_sweep := _run_pool_sweep(environments, strategies, base_genome)
	if seed_sweep.is_empty() or environment_sweep.is_empty() or density_sweep.is_empty() or disturbance_sweep.is_empty() or calibration_sweep.is_empty() or pool_sweep.is_empty():
		return {}

	var seed_multi_fraction := float(seed_sweep["multi_member_pareto_contexts"]) / maxf(float(seed_sweep["context_count"]), 1.0)
	var gates := {
		"parent_exact": true,
		"seed_variation_real": int(seed_sweep["distinct_seed_signatures"]) >= 2,
		"seed_multi_pareto": seed_multi_fraction >= MIN_SEED_MULTI_PARETO_FRACTION,
		"environment_context_sensitivity": int(environment_sweep["distinct_pareto_signatures"]) >= 2,
		"density_monotonic": int(density_sweep["monotonic_interaction_violations"]) == 0,
		"disturbance_monotonic": int(disturbance_sweep["survival_violations"]) == 0 and int(disturbance_sweep["post_seed_violations"]) == 0,
		"unity_reproduces_cal1_e": int(calibration_sweep["unity_parent_metric_mismatches"]) == 0,
		"calibration_envelope_stable": float(calibration_sweep["minimum_pareto_jaccard_vs_unity"]) >= MIN_CALIBRATION_PARETO_JACCARD and float(calibration_sweep["mean_pareto_jaccard_vs_unity"]) >= MIN_MEAN_CALIBRATION_PARETO_JACCARD,
		"pool_composition_valid": int(pool_sweep["empty_pareto_contexts"]) == 0,
		"resource_pairwise_consistent": int(pool_sweep["resource_pairwise_contradictions"]) == 0,
	}
	var all_pass := true
	for value in gates.values():
		all_pass = all_pass and bool(value)
	var classification := "ROBUST_UNITY_CALIBRATION" if all_pass else "FRAGILE_REQUIRES_DIAGNOSIS"

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"cal1_e_parent_hash": ACCEPTED_CAL1_E_HASH,
		"selected_calibration_profile": "UNITY",
		"selected_calibration_reason": "No external empirical target justifies coefficient movement; retain accepted unity baseline if the explicit +/-15% envelope is robust.",
		"seed_sweep": seed_sweep,
		"environment_sweep": environment_sweep,
		"density_sweep": density_sweep,
		"disturbance_sweep": disturbance_sweep,
		"calibration_sweep": calibration_sweep,
		"pool_sweep": pool_sweep,
		"seed_multi_pareto_fraction": seed_multi_fraction,
		"gates": gates,
		"classification": classification,
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _run_seed_sweep(environments: Dictionary, strategies: Dictionary, base_genome: Dictionary) -> Dictionary:
	var unity := Calibration.create("UNITY")
	var hashes := PackedStringArray()
	var seed_signatures := {}
	var pareto_signatures := {}
	var contexts := 0
	var rows := 0
	var multi_pareto := 0
	for seed_id in SEED_IDS:
		var seed_tokens := PackedStringArray()
		for environment_name in ENVIRONMENT_ORDER:
			for disturbance_name in ["NONE", "SEVERE"]:
				var context := _evaluate_context(
					environment_name, environments[environment_name], "DENSE", 0.75, 0.90,
					disturbance_name, float(DISTURBANCE_SEVERITY[disturbance_name]), seed_id, unity,
					STRATEGY_ORDER, strategies, base_genome
				)
				if context.is_empty():
					return {}
				contexts += 1
				rows += int(context["row_count"])
				hashes.append(String(context["context_hash"]))
				seed_tokens.append(String(context["context_hash"]))
				var pareto: Array = context["summary"]["pareto_front"]
				if pareto.size() > 1:
					multi_pareto += 1
				pareto_signatures[",".join(PackedStringArray(pareto))] = true
		seed_signatures["\n".join(seed_tokens).sha256_text()] = true
	return {
		"seed_count": SEED_IDS.size(),
		"context_count": contexts,
		"row_count": rows,
		"distinct_seed_signatures": seed_signatures.size(),
		"multi_member_pareto_contexts": multi_pareto,
		"distinct_pareto_signatures": pareto_signatures.size(),
		"aggregate_hash": _tokens_hash("seed", hashes),
	}

static func _run_environment_sweep(environments: Dictionary, strategies: Dictionary, base_genome: Dictionary) -> Dictionary:
	var unity := Calibration.create("UNITY")
	var hashes := PackedStringArray()
	var pareto_signatures := {}
	var resource_signatures := {}
	var contexts := 0
	var rows := 0
	for environment_name in ENVIRONMENT_ORDER:
		for variant in ENVIRONMENT_VARIANTS:
			var environment: Dictionary = _environment_variant(environments[environment_name], variant)
			if environment.is_empty():
				return {}
			var label := environment_name if variant == "BASE" else "%s~%s" % [environment_name, variant]
			var context := _evaluate_context(label, environment, "DENSE", 0.75, 0.90, "NONE", 0.0, 0, unity, STRATEGY_ORDER, strategies, base_genome)
			if context.is_empty():
				return {}
			contexts += 1
			rows += int(context["row_count"])
			hashes.append(String(context["context_hash"]))
			pareto_signatures[",".join(PackedStringArray(context["summary"]["pareto_front"]))] = true
			resource_signatures[",".join(PackedStringArray(context["summary"]["resource_winners"]))] = true
	return {
		"variant_count_per_environment": ENVIRONMENT_VARIANTS.size(),
		"context_count": contexts,
		"row_count": rows,
		"distinct_pareto_signatures": pareto_signatures.size(),
		"distinct_resource_winner_signatures": resource_signatures.size(),
		"aggregate_hash": _tokens_hash("environment", hashes),
	}

static func _run_density_sweep(environments: Dictionary, strategies: Dictionary, base_genome: Dictionary) -> Dictionary:
	var unity := Calibration.create("UNITY")
	var hashes := PackedStringArray()
	var previous := {}
	var violations := 0
	var contexts := 0
	var rows := 0
	for environment_name in ENVIRONMENT_ORDER:
		for point in DENSITY_SWEEP:
			var context := _evaluate_context(
				environment_name, environments[environment_name], String(point["label"]), float(point["distance_m"]), float(point["local_density"]),
				"NONE", 0.0, 0, unity, STRATEGY_ORDER, strategies, base_genome
			)
			if context.is_empty():
				return {}
			contexts += 1
			rows += int(context["row_count"])
			hashes.append(String(context["context_hash"]))
			for row in Array(context["rows"]):
				var key := "%s/%s" % [environment_name, String(row["strategy"])]
				var current := float(row["interaction_abs_sum"])
				if previous.has(key) and current > float(previous[key]) + EPSILON:
					violations += 1
				previous[key] = current
	return {
		"density_point_count": DENSITY_SWEEP.size(),
		"context_count": contexts,
		"row_count": rows,
		"monotonic_interaction_violations": violations,
		"aggregate_hash": _tokens_hash("density", hashes),
	}

static func _run_disturbance_sweep(environments: Dictionary, strategies: Dictionary, base_genome: Dictionary) -> Dictionary:
	var unity := Calibration.create("UNITY")
	var hashes := PackedStringArray()
	var previous_survival := {}
	var previous_seed := {}
	var survival_violations := 0
	var seed_violations := 0
	var contexts := 0
	var rows := 0
	for environment_name in ENVIRONMENT_ORDER:
		for disturbance_name in DISTURBANCE_LABELS:
			var severity := float(DISTURBANCE_SEVERITY[disturbance_name])
			var context := _evaluate_context(environment_name, environments[environment_name], "DENSE", 0.75, 0.90, disturbance_name, severity, 0, unity, STRATEGY_ORDER, strategies, base_genome)
			if context.is_empty():
				return {}
			contexts += 1
			rows += int(context["row_count"])
			hashes.append(String(context["context_hash"]))
			for row in Array(context["rows"]):
				var key := "%s/%s" % [environment_name, String(row["strategy"])]
				var survival := float(row["disturbance_survival_fraction"])
				var seeds := float(row["post_disturbance_seed_potential"])
				if previous_survival.has(key) and survival > float(previous_survival[key]) + EPSILON:
					survival_violations += 1
				if previous_seed.has(key) and seeds > float(previous_seed[key]) + EPSILON:
					seed_violations += 1
				previous_survival[key] = survival
				previous_seed[key] = seeds
	return {
		"severity_count": DISTURBANCE_LABELS.size(),
		"context_count": contexts,
		"row_count": rows,
		"survival_violations": survival_violations,
		"post_seed_violations": seed_violations,
		"aggregate_hash": _tokens_hash("disturbance", hashes),
	}

static func _run_calibration_sweep(parent: Dictionary, environments: Dictionary, strategies: Dictionary, base_genome: Dictionary) -> Dictionary:
	var hashes := PackedStringArray()
	var contexts := 0
	var rows := 0
	var unity_mismatches := 0
	var jaccard_min := 1.0
	var jaccard_sum := 0.0
	var jaccard_count := 0
	var resource_signatures := {}
	var pareto_signatures := {}
	for environment_name in ENVIRONMENT_ORDER:
		for disturbance_name in ["NONE", "SEVERE"]:
			var unity := Calibration.create("UNITY")
			var unity_context := _evaluate_context(environment_name, environments[environment_name], "DENSE", 0.75, 0.90, disturbance_name, float(DISTURBANCE_SEVERITY[disturbance_name]), 0, unity, STRATEGY_ORDER, strategies, base_genome)
			if unity_context.is_empty():
				return {}
			unity_mismatches += _parent_metric_mismatches(parent, "%s/DENSE/%s" % [environment_name, disturbance_name], unity_context)
			var unity_pareto: Array = unity_context["summary"]["pareto_front"]
			for profile_name in Calibration.PROFILE_ORDER:
				var profile := Calibration.create(profile_name)
				if profile.is_empty():
					return {}
				var context := unity_context if profile_name == "UNITY" else _evaluate_context(environment_name, environments[environment_name], "DENSE", 0.75, 0.90, disturbance_name, float(DISTURBANCE_SEVERITY[disturbance_name]), 0, profile, STRATEGY_ORDER, strategies, base_genome)
				if context.is_empty():
					return {}
				contexts += 1
				rows += int(context["row_count"])
				hashes.append("%s|%s" % [profile_name, String(context["context_hash"])])
				var pareto: Array = context["summary"]["pareto_front"]
				pareto_signatures[",".join(PackedStringArray(pareto))] = true
				resource_signatures[",".join(PackedStringArray(context["summary"]["resource_winners"]))] = true
				if profile_name != "UNITY":
					var jaccard := _set_jaccard(unity_pareto, pareto)
					jaccard_min = minf(jaccard_min, jaccard)
					jaccard_sum += jaccard
					jaccard_count += 1
	var mean_jaccard := 1.0 if jaccard_count == 0 else jaccard_sum / float(jaccard_count)
	return {
		"profile_count": Calibration.PROFILE_ORDER.size(),
		"context_count": contexts,
		"row_count": rows,
		"unity_parent_metric_mismatches": unity_mismatches,
		"minimum_pareto_jaccard_vs_unity": jaccard_min,
		"mean_pareto_jaccard_vs_unity": mean_jaccard,
		"distinct_pareto_signatures": pareto_signatures.size(),
		"distinct_resource_winner_signatures": resource_signatures.size(),
		"aggregate_hash": _tokens_hash("calibration", hashes),
	}

static func _run_pool_sweep(environments: Dictionary, strategies: Dictionary, base_genome: Dictionary) -> Dictionary:
	var unity := Calibration.create("UNITY")
	var pool_defs := {
		"FULL_8": STRATEGY_ORDER,
		"NO_HEIGHT_LOW": ["BASE", "HEIGHT_HIGH", "CROWN_NARROW", "CROWN_WIDE", "BRANCH_LOW", "BRANCH_HIGH", "GIANT_DENSE"],
		"NO_GIANT": ["BASE", "HEIGHT_LOW", "HEIGHT_HIGH", "CROWN_NARROW", "CROWN_WIDE", "BRANCH_LOW", "BRANCH_HIGH"],
		"CORE_5": ["BASE", "HEIGHT_LOW", "HEIGHT_HIGH", "CROWN_WIDE", "BRANCH_LOW"],
		"ALTERNATE_5": ["BASE", "CROWN_NARROW", "CROWN_WIDE", "BRANCH_LOW", "BRANCH_HIGH"],
	}
	var hashes := PackedStringArray()
	var contexts := 0
	var rows := 0
	var empty_pareto := 0
	var pairwise_contradictions := 0
	var no_height_low_fallbacks := 0
	for environment_name in ENVIRONMENT_ORDER:
		for pool_name in ["FULL_8", "NO_HEIGHT_LOW", "NO_GIANT", "CORE_5", "ALTERNATE_5"]:
			var pool: Array = pool_defs[pool_name]
			var context := _evaluate_context(environment_name, environments[environment_name], "DENSE", 0.75, 0.90, "NONE", 0.0, 0, unity, pool, strategies, base_genome)
			if context.is_empty():
				return {}
			contexts += 1
			rows += int(context["row_count"])
			hashes.append("%s|%s" % [pool_name, String(context["context_hash"])])
			if Array(context["summary"]["pareto_front"]).is_empty():
				empty_pareto += 1
			if pool_name == "FULL_8":
				pairwise_contradictions += _resource_pairwise_contradictions(context)
			if pool_name == "NO_HEIGHT_LOW" and not Array(context["summary"]["resource_winners"]).is_empty():
				no_height_low_fallbacks += 1
	return {
		"pool_count": pool_defs.size(),
		"context_count": contexts,
		"row_count": rows,
		"empty_pareto_contexts": empty_pareto,
		"resource_pairwise_contradictions": pairwise_contradictions,
		"no_height_low_fallback_contexts": no_height_low_fallbacks,
		"aggregate_hash": _tokens_hash("pool", hashes),
	}

static func _evaluate_context(
	environment_name: String,
	environment: Dictionary,
	density_name: String,
	distance_m: float,
	local_density: float,
	disturbance_name: String,
	severity: float,
	seed_id: int,
	profile: Dictionary,
	pool: Array,
	strategies: Dictionary,
	base_genome: Dictionary
) -> Dictionary:
	if not Calibration.validate(profile) or pool.is_empty():
		return {}
	var neighbour := _realize_strategy("BASE", strategies["BASE"], environment, base_genome, seed_id)
	if neighbour.is_empty():
		return {}
	var context_id := "%s/%s/%s" % [environment_name, density_name, disturbance_name]
	var rows: Array = []
	for strategy_name_value in pool:
		var strategy_name := String(strategy_name_value)
		if not strategies.has(strategy_name):
			return {}
		var focal := _realize_strategy(strategy_name, strategies[strategy_name], environment, base_genome, seed_id)
		if focal.is_empty():
			return {}
		var row := _evaluate_row(context_id, environment_name, density_name, disturbance_name, distance_m, local_density, severity, seed_id, focal, neighbour, strategies[strategy_name], environment, base_genome, profile)
		if row.is_empty():
			return {}
		rows.append(row)
	var summary := _summarize_context(rows)
	if summary.is_empty():
		return {}
	var result := {
		"context_id": context_id,
		"environment": environment_name,
		"environment_checksum": String(environment["checksum"]),
		"density": density_name,
		"distance_m": distance_m,
		"local_density": local_density,
		"disturbance": disturbance_name,
		"disturbance_severity": severity,
		"seed_id": seed_id,
		"calibration_profile": String(profile["name"]),
		"pool": pool.duplicate(),
		"row_count": rows.size(),
		"rows": rows,
		"summary": summary,
	}
	result["context_hash"] = _context_hash(result)
	return result

static func _evaluate_row(
	context_id: String,
	environment_name: String,
	density_name: String,
	disturbance_name: String,
	distance_m: float,
	local_density: float,
	severity: float,
	seed_id: int,
	focal: Dictionary,
	neighbour: Dictionary,
	inherited_traits: Dictionary,
	environment: Dictionary,
	base_genome: Dictionary,
	profile: Dictionary
) -> Dictionary:
	var position_a := Vector2.ZERO
	var position_b := Vector2(distance_m, 0.0)
	var crown := Spatial.evaluate_crown_pair(focal["phenotype"], neighbour["phenotype"], environment, position_a, position_b)
	var root := Spatial.evaluate_root_pair(base_genome, base_genome, environment, position_a, position_b)
	if crown.is_empty() or root.is_empty():
		return {}
	var overlap_scalar := clampf(0.5 * (float(crown["overlap_fraction_a"]) + float(crown["overlap_fraction_b"])), 0.0, 1.0)
	var vertical_context := VerticalLight.create_context(overlap_scalar, local_density, context_id)
	var vertical := VerticalLight.evaluate_pair(environment, focal["phenotype"], neighbour["phenotype"], vertical_context)
	if vertical.is_empty():
		return {}

	var coupling: Dictionary = focal["coupling"]
	var base_resource := float(coupling["base_net_resource_balance"])
	var morphology_delta := float(coupling["morphology_delta"])
	var vertical_delta := float(vertical["a_light_delta"])
	var crown_loss := float(crown["crown_overlap_loss_a"])
	var root_delta := float(root["root_competition_delta_a"])
	var combined_resource := (
		base_resource
		+ morphology_delta * float(profile["morphology_delta_multiplier"])
		+ vertical_delta * float(profile["vertical_light_multiplier"])
		- crown_loss * float(profile["crown_overlap_loss_multiplier"])
		+ root_delta * float(profile["root_competition_multiplier"])
	)

	var graph: Dictionary = focal["phenotype"].get("growth_graph", {})
	var metrics: Dictionary = graph.get("metrics", {})
	if metrics.is_empty():
		return {}
	var adult_height := maxf(float(metrics.get("height_m", 0.0)), 0.05)
	var lifecycle_genome := _lifecycle_projection_genome(base_genome, adult_height, String(focal["strategy"]), environment_name, seed_id)
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

	var result := {
		"context_id": context_id,
		"environment": environment_name,
		"density": density_name,
		"disturbance": disturbance_name,
		"seed_id": seed_id,
		"calibration_profile": String(profile["name"]),
		"strategy": String(focal["strategy"]),
		"inherited_traits_checksum": String(inherited_traits["checksum"]),
		"phenotype_hash": String(focal["phenotype"]["phenotype_hash"]),
		"coupling_hash": String(coupling["coupling_hash"]),
		"base_resource_balance": base_resource,
		"morphology_delta": morphology_delta,
		"vertical_light_delta": vertical_delta,
		"crown_overlap_loss": crown_loss,
		"root_competition_delta": root_delta,
		"combined_resource_balance": combined_resource,
		"interaction_abs_sum": absf(vertical_delta) + absf(crown_loss) + absf(root_delta),
		"adult_height_m": adult_height,
		"maturity_time_index_years": float(lifecycle["maturity_time_index_years"]),
		"post_disturbance_seed_potential": float(lifecycle["post_disturbance_seed_potential"]),
		"effective_seed_dispersal_m": float(lifecycle["effective_seed_dispersal_m"]),
		"disturbance_survival_fraction": float(lifecycle["disturbance_survival_fraction"]),
		"recovery_time_index_years": float(lifecycle["recovery_time_index_years"]),
		"amortized_structural_cost_per_year": float(lifecycle["amortized_structural_cost_per_year"]),
	}
	result["row_hash"] = _row_hash(result)
	return result

static func _realize_strategy(strategy_name: String, traits: Dictionary, environment: Dictionary, genome: Dictionary, seed_id: int) -> Dictionary:
	var event := Selection.REPRODUCTION_EVENT if seed_id == 0 else "competition/cal1f-robust-seed-%d" % seed_id
	var envelope := Contract.create_seed_envelope(genome, traits, Selection.PARENT_LINEAGE, event, Selection.SEED_INDEX)
	if envelope.is_empty():
		return {}
	var phenotype := Plasticity.realize(envelope, traits, environment)
	if phenotype.is_empty():
		return {}
	var coupling := Coupling.evaluate(environment, genome, phenotype)
	if coupling.is_empty():
		return {}
	return {"strategy": strategy_name, "phenotype": phenotype, "coupling": coupling}

static func _lifecycle_projection_genome(base: Dictionary, target_height_m: float, strategy_name: String, environment_name: String, seed_id: int) -> Dictionary:
	return Genome.create(
		"plant-genome/cal1f/%s/%s/s%d" % [strategy_name.to_lower(), environment_name.to_lower(), seed_id],
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

static func _environment_variant(environment: Dictionary, variant: String) -> Dictionary:
	if variant == "BASE":
		return environment
	var moisture := float(environment["soil_moisture"])
	var sunlight := float(environment["sunlight"])
	match variant:
		"MOISTURE_LOW": moisture *= 0.90
		"MOISTURE_HIGH": moisture *= 1.10
		"SUN_LOW": sunlight *= 0.90
		"SUN_HIGH": sunlight *= 1.10
		_: return {}
	return EnvironmentSample.create(
		float(environment["world_x_m"]), float(environment["world_z_m"]), float(environment["temperature_c"]),
		clampf(moisture, 0.0, 1.0), clampf(sunlight, 0.0, 1.0), float(environment["nutrients"]),
		float(environment["flood_frequency"]), int(environment["seed"]), String(environment["environment_revision"]) + "/cal1f-" + variant.to_lower()
	)

static func _summarize_context(rows: Array) -> Dictionary:
	if rows.is_empty():
		return {}
	return {
		"resource_winners": _winner_set(rows, "combined_resource_balance", true),
		"seed_winners": _winner_set(rows, "post_disturbance_seed_potential", true),
		"dispersal_winners": _winner_set(rows, "effective_seed_dispersal_m", true),
		"survival_winners": _winner_set(rows, "disturbance_survival_fraction", true),
		"maturity_winners": _winner_set(rows, "maturity_time_index_years", false),
		"amortization_winners": _winner_set(rows, "amortized_structural_cost_per_year", false),
		"recovery_winners": _winner_set(rows, "recovery_time_index_years", false),
		"pareto_front": _pareto_front(rows),
	}

static func _winner_set(rows: Array, field_name: String, maximize: bool) -> Array[String]:
	var best := -INF if maximize else INF
	for row in rows:
		var value := float(row[field_name])
		best = maxf(best, value) if maximize else minf(best, value)
	var result: Array[String] = []
	for row in rows:
		if absf(float(row[field_name]) - best) <= EPSILON:
			result.append(String(row["strategy"]))
	return result

static func _pareto_front(rows: Array) -> Array[String]:
	var result: Array[String] = []
	for candidate_value in rows:
		var candidate: Dictionary = candidate_value
		var dominated := false
		for challenger_value in rows:
			var challenger: Dictionary = challenger_value
			if String(challenger["strategy"]) == String(candidate["strategy"]):
				continue
			if _dominates(challenger, candidate):
				dominated = true
				break
		if not dominated:
			result.append(String(candidate["strategy"]))
	return result

static func _dominates(a: Dictionary, b: Dictionary) -> bool:
	var maximize_fields := ["combined_resource_balance", "post_disturbance_seed_potential", "effective_seed_dispersal_m", "disturbance_survival_fraction"]
	var minimize_fields := ["maturity_time_index_years", "recovery_time_index_years", "amortized_structural_cost_per_year"]
	var strictly_better := false
	for field_name in maximize_fields:
		var av := float(a[field_name]); var bv := float(b[field_name])
		if av < bv - EPSILON: return false
		if av > bv + EPSILON: strictly_better = true
	for field_name in minimize_fields:
		var av := float(a[field_name]); var bv := float(b[field_name])
		if av > bv + EPSILON: return false
		if av < bv - EPSILON: strictly_better = true
	return strictly_better

static func _parent_metric_mismatches(parent: Dictionary, context_id: String, context: Dictionary) -> int:
	var parent_contexts: Dictionary = parent.get("contexts", {})
	if not parent_contexts.has(context_id):
		return 1000
	var parent_rows := {}
	for row in Array(parent_contexts[context_id]["rows"]):
		parent_rows[String(row["strategy"])] = row
	var mismatches := 0
	for row in Array(context["rows"]):
		var strategy := String(row["strategy"])
		if not parent_rows.has(strategy):
			mismatches += 1
			continue
		var p: Dictionary = parent_rows[strategy]
		if String(p["phenotype_hash"]) != String(row["phenotype_hash"]): mismatches += 1
		for field_name in [
			"combined_resource_balance", "vertical_light_delta", "crown_overlap_loss", "root_competition_delta",
			"maturity_time_index_years", "post_disturbance_seed_potential", "effective_seed_dispersal_m",
			"disturbance_survival_fraction", "recovery_time_index_years", "amortized_structural_cost_per_year"
		]:
			if absf(float(p[field_name]) - float(row[field_name])) > EPSILON:
				mismatches += 1
	return mismatches

static func _resource_pairwise_contradictions(context: Dictionary) -> int:
	var winners: Array = context["summary"]["resource_winners"]
	var rows: Array = context["rows"]
	var by_name := {}
	for row in rows: by_name[String(row["strategy"])] = row
	var contradictions := 0
	for winner_value in winners:
		var winner := String(winner_value)
		for row in rows:
			if float(by_name[winner]["combined_resource_balance"]) < float(row["combined_resource_balance"]) - EPSILON:
				contradictions += 1
	return contradictions

static func _set_jaccard(a: Array, b: Array) -> float:
	var sa := {}; var sb := {}
	for value in a: sa[String(value)] = true
	for value in b: sb[String(value)] = true
	var union := {}; var intersection := 0
	for key in sa.keys(): union[key] = true
	for key in sb.keys():
		if sa.has(key): intersection += 1
		union[key] = true
	return 1.0 if union.is_empty() else float(intersection) / float(union.size())

static func _row_hash(row: Dictionary) -> String:
	var tokens := PackedStringArray([
		String(row["context_id"]), String(row["strategy"]), str(int(row["seed_id"])), String(row["calibration_profile"]),
		String(row["phenotype_hash"]), String(row["coupling_hash"]),
	])
	for field_name in [
		"base_resource_balance", "morphology_delta", "vertical_light_delta", "crown_overlap_loss", "root_competition_delta",
		"combined_resource_balance", "interaction_abs_sum", "adult_height_m", "maturity_time_index_years",
		"post_disturbance_seed_potential", "effective_seed_dispersal_m", "disturbance_survival_fraction",
		"recovery_time_index_years", "amortized_structural_cost_per_year"
	]:
		tokens.append("%.12f" % float(row[field_name]))
	return "|".join(tokens).sha256_text()

static func _context_hash(context: Dictionary) -> String:
	var tokens := PackedStringArray([
		String(context["context_id"]), String(context["environment_checksum"]), String(context["density"]),
		"%.12f" % float(context["distance_m"]), "%.12f" % float(context["local_density"]),
		String(context["disturbance"]), "%.12f" % float(context["disturbance_severity"]), str(int(context["seed_id"])), String(context["calibration_profile"]),
	])
	for row in Array(context["rows"]): tokens.append(String(row["row_hash"]))
	var summary: Dictionary = context["summary"]
	for key in ["resource_winners", "seed_winners", "dispersal_winners", "survival_winners", "maturity_winners", "amortization_winners", "recovery_winners", "pareto_front"]:
		tokens.append("%s=%s" % [key, ",".join(PackedStringArray(summary[key]))])
	return "\n".join(tokens).sha256_text()

static func _tokens_hash(label: String, tokens: PackedStringArray) -> String:
	var all := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, label])
	for token in tokens: all.append(token)
	return "\n".join(all).sha256_text()

static func _aggregate_hash(result: Dictionary) -> String:
	var gates: Dictionary = result["gates"]
	var gate_keys := gates.keys(); gate_keys.sort()
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION, ACCEPTED_CAL1_E_HASH, String(result["selected_calibration_profile"]), String(result["classification"])])
	for sweep_name in ["seed_sweep", "environment_sweep", "density_sweep", "disturbance_sweep", "calibration_sweep", "pool_sweep"]:
		tokens.append("%s=%s" % [sweep_name, String(result[sweep_name]["aggregate_hash"])])
	for key in gate_keys: tokens.append("%s=%s" % [String(key), str(bool(gates[key]))])
	return "\n".join(tokens).sha256_text()
