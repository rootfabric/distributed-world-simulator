extends RefCounted

const Field = preload("res://scripts/research/ecology/plant_regional_population_field_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p1b_local_adaptation_robustness_gate.v1"
const VERSION := "1.0.0"
const EXPERIMENT_REVISION := "ECO.P1B-S4.1"
const GRID_SIZE := 5
const GENERATIONS := 9
const LONG_GENERATIONS := 12
const POPULATION_SIZE := 4
const OFFSPRING_PER_PARENT := 2
const SEEDS: Array[int] = [918221, 918222, 918223]
const NEUTRAL_SEED := 918221
const LONG_SEED := 918221

static func run() -> Dictionary:
	var runs: Array = []
	for seed in SEEDS:
		var result := Field.run(GRID_SIZE, GENERATIONS, POPULATION_SIZE, OFFSPRING_PER_PARENT, seed, false)
		if result.is_empty():
			return {}
		runs.append(_summarize_run(result))
	var neutral := Field.run(GRID_SIZE, GENERATIONS, POPULATION_SIZE, OFFSPRING_PER_PARENT, NEUTRAL_SEED, true)
	if neutral.is_empty():
		return {}
	var long_run := Field.run(GRID_SIZE, LONG_GENERATIONS, POPULATION_SIZE, OFFSPRING_PER_PARENT, LONG_SEED, false)
	if long_run.is_empty():
		return {}
	var aggregate := _aggregate(runs)
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"experiment_revision": EXPERIMENT_REVISION,
		"grid_size": GRID_SIZE,
		"generations": GENERATIONS,
		"long_generations": LONG_GENERATIONS,
		"population_size": POPULATION_SIZE,
		"offspring_per_parent": OFFSPRING_PER_PARENT,
		"seeds": SEEDS.duplicate(),
		"runs": runs,
		"aggregate": aggregate,
		"neutral": _summarize_run(neutral),
		"long_run": _summarize_run(long_run),
	}
	result["aggregate_hash"] = _aggregate_hash(result)
	return result

static func _summarize_run(result: Dictionary) -> Dictionary:
	var regions: Dictionary = result["regional_stats"]
	return {
		"lineage_seed": int(result["lineage_seed"]),
		"neutral_control": bool(result["neutral_control"]),
		"result_hash": String(result["result_hash"]),
		"initial_average_net": float(result["initial_field"]["average_net_resource_balance"]),
		"final_average_net": float(result["final_field"]["average_net_resource_balance"]),
		"water_preference_vs_moisture": float(result["correlations"]["water_preference_vs_moisture"]),
		"root_depth_vs_moisture": float(result["correlations"]["root_depth_vs_moisture"]),
		"shade_tolerance_vs_sunlight": float(result["correlations"]["shade_tolerance_vs_sunlight"]),
		"wet_minus_dry_water_preference": float(regions["WET"]["traits"]["water_preference"]["mean"]) - float(regions["DRY"]["traits"]["water_preference"]["mean"]),
		"dry_minus_wet_root_depth_m": float(regions["DRY"]["traits"]["root_depth_m"]["mean"]) - float(regions["WET"]["traits"]["root_depth_m"]["mean"]),
		"shaded_minus_sunlit_shade_tolerance": float(regions["SHADED"]["traits"]["shade_tolerance"]["mean"]) - float(regions["SUNLIT"]["traits"]["shade_tolerance"]["mean"]),
		"final_trait_means": Dictionary(result["final_field"]["trait_means"]).duplicate(true),
	}

static func _aggregate(runs: Array) -> Dictionary:
	var sums := {
		"final_average_net": 0.0,
		"water_preference_vs_moisture": 0.0,
		"root_depth_vs_moisture": 0.0,
		"shade_tolerance_vs_sunlight": 0.0,
		"wet_minus_dry_water_preference": 0.0,
		"dry_minus_wet_root_depth_m": 0.0,
		"shaded_minus_sunlit_shade_tolerance": 0.0,
	}
	var minimums := {
		"final_average_net": INF,
		"water_preference_vs_moisture": INF,
		"dry_minus_wet_root_depth_m": INF,
		"wet_minus_dry_water_preference": INF,
		"shaded_minus_sunlit_shade_tolerance": INF,
	}
	var maximum_root_corr := -INF
	var maximum_shade_corr := -INF
	for run in runs:
		for key in sums.keys():
			sums[key] = float(sums[key]) + float(run[key])
		for key in minimums.keys():
			minimums[key] = minf(float(minimums[key]), float(run[key]))
		maximum_root_corr = maxf(maximum_root_corr, float(run["root_depth_vs_moisture"]))
		maximum_shade_corr = maxf(maximum_shade_corr, float(run["shade_tolerance_vs_sunlight"]))
	var means := {}
	for key in sums.keys():
		means[key] = float(sums[key]) / float(runs.size())
	return {
		"seed_count": runs.size(),
		"means": means,
		"minimums": minimums,
		"maximum_root_depth_vs_moisture": maximum_root_corr,
		"maximum_shade_tolerance_vs_sunlight": maximum_shade_corr,
	}

static func _aggregate_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, EXPERIMENT_REVISION])
	for run in Array(result["runs"]):
		tokens.append(_run_token(run))
	tokens.append("NEUTRAL|" + _run_token(result["neutral"]))
	tokens.append("LONG|" + _run_token(result["long_run"]))
	return "\n".join(tokens).sha256_text()

static func _run_token(run: Dictionary) -> String:
	return "|".join(PackedStringArray([
		str(int(run["lineage_seed"])),
		"1" if bool(run["neutral_control"]) else "0",
		String(run["result_hash"]),
		_fmt(float(run["initial_average_net"])),
		_fmt(float(run["final_average_net"])),
		_fmt(float(run["water_preference_vs_moisture"])),
		_fmt(float(run["root_depth_vs_moisture"])),
		_fmt(float(run["shade_tolerance_vs_sunlight"])),
		_fmt(float(run["wet_minus_dry_water_preference"])),
		_fmt(float(run["dry_minus_wet_root_depth_m"])),
		_fmt(float(run["shaded_minus_sunlit_shade_tolerance"])),
	]))

static func _fmt(value: float) -> String:
	return "%.12f" % value
