extends SceneTree

const ObservatoryPanel = preload("res://scripts/labs/ecology/eco_vis2_2_observatory_panel.gd")

const FORK_GENERATION := 20
const REPLICATES := 4

var _assertions := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_summary := _make_summary()
	var source_before := source_summary.duplicate(true)
	var panel = ObservatoryPanel.new()
	panel.name = "VIS22CObservatoryPanel"
	panel.size = Vector2(560.0, 360.0)
	get_root().add_child(panel)
	await process_frame

	_check(panel.mouse_filter == Control.MOUSE_FILTER_IGNORE, "panel ignores mouse input")
	_check(panel.set_observatory_data(source_summary, 2), "panel accepts valid aggregate summary")
	await process_frame
	await process_frame
	_check(source_summary == source_before, "binding cannot mutate source aggregate summary")
	_check(panel.get_observatory_summary() == source_before, "panel stores byte-identical deep copy")

	var state_r2 := panel.get_presentation_state()
	_check(bool(state_r2.get("success", false)), "presentation state successful")
	_check(String(state_r2.get("stage", "")) == ObservatoryPanel.STAGE, "presentation stage")
	_check(int(state_r2.get("replicate_count", 0)) == REPLICATES, "presentation replicate count")
	_check(int(state_r2.get("selected_replicate", -1)) == 2, "initial selected replicate")
	_check(int(state_r2.get("point_count", 0)) == 8, "presentation point count")
	_check(int(state_r2.get("oldest_generation", -1)) == FORK_GENERATION, "presentation oldest generation")
	_check(int(state_r2.get("latest_generation", -1)) == FORK_GENERATION + 7, "presentation latest generation")
	_check(String(state_r2.get("aggregate_series_hash", "")) == String(source_summary.get("series_hash", "")), "aggregate hash exposed unchanged")
	_check(int(state_r2.get("selected_population_delta", 99)) == 1, "selected R2 population delta")
	_check(_approx(float(state_r2.get("selected_fitness_delta", 99.0)), 0.01), "selected R2 fitness delta")
	_check(_approx(float(state_r2.get("aggregate_mean_population_delta", 99.0)), 0.5), "aggregate population mean shown")
	_check(_approx(float(state_r2.get("aggregate_mean_fitness_delta", 99.0)), 0.005), "aggregate fitness mean shown")
	_check(int(state_r2.get("population_positive_count", 0)) == 2 and int(state_r2.get("population_zero_count", 0)) == 1 and int(state_r2.get("population_negative_count", 0)) == 1, "population sign counts shown")
	_check(String(state_r2.get("population_effect_direction", "")) == "POSITIVE", "population direction shown")
	_check(String(state_r2.get("fitness_effect_direction", "")) == "MIXED", "fitness direction shown")

	var aggregate_hash := String(state_r2.get("aggregate_series_hash", ""))
	var aggregate_copy_before_selection := panel.get_observatory_summary()
	_check(panel.select_replicate(3), "select R3")
	await process_frame
	var state_r3 := panel.get_presentation_state()
	_check(int(state_r3.get("selected_replicate", -1)) == 3, "R3 selected")
	_check(int(state_r3.get("selected_population_delta", 0)) == 3, "R3 population delta")
	_check(_approx(float(state_r3.get("selected_fitness_delta", 0.0)), 0.06), "R3 fitness delta")
	_check(String(state_r3.get("aggregate_series_hash", "")) == aggregate_hash, "selected replicate cannot change aggregate hash")
	_check(panel.get_observatory_summary() == aggregate_copy_before_selection, "selected replicate cannot mutate aggregate points")
	_check(source_summary == source_before, "selected replicate cannot mutate caller data")

	_check(panel.select_replicate(0), "select R0")
	_check(panel.select_replicate(1), "select R1")
	var state_r1 := panel.get_presentation_state()
	_check(int(state_r1.get("selected_replicate", -1)) == 1, "R1 selected")
	_check(int(state_r1.get("selected_population_delta", 99)) == 0, "R1 population delta")
	_check(String(state_r1.get("aggregate_series_hash", "")) == aggregate_hash, "multiple selections preserve aggregate hash")

	var state_before_invalid_selection := panel.get_presentation_state()
	_check(not panel.select_replicate(-1), "negative replicate selection rejected")
	_check(not panel.select_replicate(REPLICATES), "out-of-range replicate selection rejected")
	_check(panel.get_presentation_state() == state_before_invalid_selection, "invalid selection leaves presentation unchanged")

	var bad_stage := source_summary.duplicate(true)
	bad_stage["stage"] = "WRONG"
	var before_bad_summary := panel.get_observatory_summary()
	_check(not panel.set_observatory_data(bad_stage, 0), "wrong aggregate stage rejected")
	_check(panel.get_observatory_summary() == before_bad_summary, "invalid summary cannot replace good data")

	var bad_hash := source_summary.duplicate(true)
	bad_hash["series_hash"] = "bad"
	_check(not panel.set_observatory_data(bad_hash, 0), "invalid aggregate hash rejected")
	_check(panel.get_observatory_summary() == before_bad_summary, "invalid hash cannot mutate panel data")

	var unbounded := source_summary.duplicate(true)
	var too_many: Array = []
	for index in range(65):
		var point := Dictionary(Array(source_summary.get("points", []))[index % 8]).duplicate(true)
		point["generation"] = FORK_GENERATION + index
		too_many.append(point)
	unbounded["points"] = too_many
	unbounded["point_count"] = too_many.size()
	_check(not panel.set_observatory_data(unbounded, 0), "unbounded aggregate history rejected")
	_check(panel.get_observatory_summary() == before_bad_summary, "unbounded input cannot mutate panel data")

	var exported := panel.get_observatory_summary()
	exported["series_hash"] = "caller-mutated"
	_check(String(panel.get_observatory_summary().get("series_hash", "")) == aggregate_hash, "returned summary is deep copy")

	panel.size = Vector2(720.0, 420.0)
	panel.queue_redraw()
	await process_frame
	await process_frame
	_check(panel.get_presentation_state() == state_before_invalid_selection, "redraw/resize cannot mutate presentation data")

	panel.free()
	await process_frame
	_finish()


func _make_summary() -> Dictionary:
	var points: Array[Dictionary] = []
	for offset in range(8):
		var generation := FORK_GENERATION + offset
		var at_fork := offset == 0
		points.append(_make_point(generation, at_fork))
	return {
		"success": true,
		"stage": "ECO.VIS2.2-B",
		"mode": "REPLICATED_CAUSAL_EFFECT_AGGREGATE",
		"fork_generation": FORK_GENERATION,
		"replicate_count": REPLICATES,
		"point_count": points.size(),
		"oldest_generation": FORK_GENERATION,
		"latest_generation": FORK_GENERATION + points.size() - 1,
		"series_window": 64,
		"hash_precision_decimals": 12,
		"points": points,
		"series_hash": "VIS22C|aggregate-series".sha256_text(),
	}


func _make_point(generation: int, at_fork: bool) -> Dictionary:
	var pop_values := [0, 0, 0, 0] if at_fork else [-2, 0, 1, 3]
	var fit_values := [0.0, 0.0, 0.0, 0.0] if at_fork else [-0.04, -0.01, 0.01, 0.06]
	var identities: Array[Dictionary] = []
	for replicate_index in range(REPLICATES):
		identities.append({
			"replicate_index": replicate_index,
			"root": ("VIS22C|root=%d" % replicate_index).sha256_text(),
			"pair_hash": ("VIS22C|pair=G%d|R%d" % [generation, replicate_index]).sha256_text(),
			"control_field_hash": ("VIS22C|control=G%d|R%d" % [generation, replicate_index]).sha256_text(),
			"treatment_field_hash": ("VIS22C|treatment=G%d|R%d" % [generation, replicate_index]).sha256_text(),
			"control_environment_revision": "ENV-BASE",
			"treatment_environment_revision": "ENV-BASE" if at_fork else "ENV-DROUGHT",
			"control_experiment_id": "BASELINE",
			"treatment_experiment_id": "BASELINE" if at_fork else "DROUGHT",
			"delta_population": int(pop_values[replicate_index]),
			"delta_mean_fitness": float(fit_values[replicate_index]),
			"delta_unique_genomes": int(pop_values[replicate_index]),
			"delta_births": 0 if at_fork else replicate_index - 1,
			"delta_deaths": 0 if at_fork else 2 - replicate_index,
			"delta_survivors": int(pop_values[replicate_index]),
			"delta_represented_biomass_kg": 0.0 if at_fork else float(pop_values[replicate_index]) * 0.2,
			"delta_alpha_share": 0.0 if at_fork else float(replicate_index - 1) * 0.01,
		})
	var point := {
		"stage": "ECO.VIS2.2-B",
		"mode": "REPLICATED_CAUSAL_EFFECT_AGGREGATE",
		"generation": generation,
		"fork_generation": FORK_GENERATION,
		"replicate_count": REPLICATES,
		"treatment_experiment_id": "BASELINE" if at_fork else "DROUGHT",
		"mean_population_delta": 0.0 if at_fork else 0.5,
		"median_population_delta": 0.0 if at_fork else 0.5,
		"min_population_delta": 0 if at_fork else -2,
		"max_population_delta": 0 if at_fork else 3,
		"mean_fitness_delta": 0.0 if at_fork else 0.005,
		"median_fitness_delta": 0.0,
		"min_fitness_delta": 0.0 if at_fork else -0.04,
		"max_fitness_delta": 0.0 if at_fork else 0.06,
		"mean_unique_genomes_delta": 0.0 if at_fork else 0.5,
		"mean_birth_delta": 0.0 if at_fork else 0.5,
		"mean_death_delta": 0.0 if at_fork else 0.5,
		"mean_survivor_delta": 0.0 if at_fork else 0.5,
		"mean_represented_biomass_delta": 0.0 if at_fork else 0.1,
		"mean_alpha_share_delta": 0.0 if at_fork else 0.005,
		"population_positive_count": 0 if at_fork else 2,
		"population_zero_count": REPLICATES if at_fork else 1,
		"population_negative_count": 0 if at_fork else 1,
		"population_effect_direction": "ZERO" if at_fork else "POSITIVE",
		"population_consensus_fraction": 1.0 if at_fork else 0.5,
		"fitness_positive_count": 0 if at_fork else 2,
		"fitness_zero_count": REPLICATES if at_fork else 0,
		"fitness_negative_count": 0 if at_fork else 2,
		"fitness_effect_direction": "ZERO" if at_fork else "MIXED",
		"fitness_consensus_fraction": 1.0 if at_fork else 0.5,
		"replicate_identities": identities,
	}
	point["point_hash"] = ("VIS22C|point=G%d" % generation).sha256_text()
	return point


func _approx(actual: float, expected: float, epsilon: float = 0.0000001) -> bool:
	return absf(actual - expected) <= epsilon


func _check(condition: bool, label: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	push_error("ECO.VIS2.2-C assertion failed: %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("ECO.VIS2.2-C observatory panel: PASS (%d assertions)" % _assertions)
		quit(0)
	else:
		push_error("ECO.VIS2.2-C observatory panel: FAIL (%d failures / %d assertions)" % [_failures, _assertions])
		quit(1)
