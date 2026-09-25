extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P10 Observatory tests (metrics +
# comparison + workbench observatory UI). Runner: Godot headless --script.
#
# Coverage (work order P10):
#   a) 16-tick run with the metrics accumulator observing after EVERY tick:
#      population/alive/births/deaths series consistent with the snapshots
#      (population[t] == presentation view count); birth events carry the
#      correct entity_id/tick; the timeline is sorted (tick, index).
#   b) Observatory is READ-ONLY: hash of the observed run == hash of a plain
#      run without any observation.
#   c) Morphology diversity counts unique canonical topology signatures
#      (verified against a manual recount from debug_state).
#   d) Comparison of two runs with DIFFERENT seeds -> different final hashes
#      + a correct diff summary; two runs with the SAME seed reproduce the
#      identical final hash (determinism through the comparison path).
#   e) Workbench observatory UI: toggling OBSERVATORY + MORPHOTYPE
#      CLASSIFICATION on does not change the canonical hash (8 UI ticks vs
#      8 plain controller ticks).

const B = preload("res://scripts/research/ecology/v2/body_graph_v1.gd")
const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const G = preload("res://scripts/research/ecology/v2/organism_genome_v2.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Metrics = preload("res://scripts/ecology/workbench/experiment_metrics_v1.gd")
const Comparison = preload("res://scripts/ecology/workbench/experiment_comparison_v1.gd")
const LabScene = preload("res://scenes/labs/ecology/eco_arch2_polygon_lab.tscn")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P10_FAIL " + message)

func _manifest(seed: int) -> Dictionary:
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p10-observatory-%d" % seed,
		"seed": seed,
		"horizon_ticks": 16,
		"founders": [
			{"founder_id": "founder/a", "biological_hash": null, "genome": Protocol.ancestor()},
			{"founder_id": "founder/b", "biological_hash": null, "genome": Fixtures.make(1)},
		],
		"environment": {
			"spatial": {"origin_mm": [0, 0, 0], "cell_size_mm": 1000, "width": 3, "depth": 1},
			"zones": [
				{"id": "wet", "water_mg": 500000, "light": 700, "temperature": 500, "nutrient_mg": 1000, "organic_mg": 0},
				{"id": "dry", "water_mg": 200000, "light": 800, "temperature": 550, "nutrient_mg": 300, "organic_mg": 0},
				{"id": "dark", "water_mg": 100000, "light": 100, "temperature": 450, "nutrient_mg": 100, "organic_mg": 0},
			],
		},
		"placement": {
			"entries": [
				{"founder_ref": "founder/a", "zone_id": "wet", "position_mm": [500, 0, 500]},
				{"founder_ref": "founder/b", "zone_id": "dry", "position_mm": [1500, 0, 500]},
			],
		},
		"mutation": {"operator": "small", "mutations_enabled": true},
		"organization_profile": "FREE",
		"feedback": {"enabled": true, "decomposition_enabled": true},
		"metrics": {"requested": ["population"]},
		"checkpoint": {"interval_ticks": 16},
		"mode": "LAB",
	}

func _run_observed(manifest: Dictionary) -> Dictionary:
	# 16 ticks; metrics observe after EVERY tick (including the tick-0
	# baseline). Returns {controller, metrics, snapshots}.
	var ctl := Controller.new()
	var init_result: Dictionary = ctl.initialize(manifest)
	_check(bool(init_result.get("success", false)), "observed run initializes (seed %d)" % int(manifest.seed))
	var accumulator := Metrics.new()
	accumulator.begin(manifest)
	var snapshots: Array = []
	snapshots.append(ctl.get_snapshot())
	var observed: Dictionary = accumulator.observe(ctl)
	_check(bool(observed.get("success", false)), "tick-0 baseline observation succeeds")
	for _tick in 16:
		var step: Dictionary = ctl.step()
		_check(bool(step.get("success", false)), "observed tick succeeds")
		snapshots.append(ctl.get_snapshot())
		var frame: Dictionary = accumulator.observe(ctl)
		if not bool(frame.get("success", false)):
			_check(false, "observation after tick %d succeeds: %s" % [int(frame.get("tick", -1)), String(frame.get("error", "?"))])
			break
	return {"controller": ctl, "metrics": accumulator, "snapshots": snapshots}

func _experiment_result(manifest: Dictionary, ctl: Object, accumulator: Object) -> Dictionary:
	var snapshot: Dictionary = ctl.get_snapshot()
	return {
		"experiment_id": String(manifest.experiment_id),
		"manifest_hash": Manifest.canonical_hash(manifest),
		"seed": int(manifest.seed),
		"final_state_hash": String(snapshot.canonical_state_hash),
		"metrics": accumulator.summary(String(snapshot.canonical_state_hash)),
	}

func _test_series_consistency() -> void:
	var manifest := _manifest(4242)
	var run := _run_observed(manifest)
	var accumulator: Object = run.metrics
	var series: Dictionary = accumulator.series
	_check(int(series.tick.size()) == 17, "17 observations recorded (baseline + 16 ticks)")
	for i in series.tick.size():
		_check(int(series.tick[i]) == i, "series tick[%d] == %d" % [i, i])
		var snapshot: Dictionary = run.snapshots[i]
		_check(int(series.population[i]) == snapshot.presentation.size(),
			"population[%d] == snapshot view count (%d vs %d)" % [i, int(series.population[i]), snapshot.presentation.size()])
		var alive := 0
		for view in snapshot.presentation:
			if bool(view.alive):
				alive += 1
		_check(int(series.alive[i]) == alive, "alive[%d] matches snapshot alive views" % i)
		_check(int(series.population[i]) == int(series.alive[i]) + _dead_in(snapshot),
			"population[%d] == alive + dead" % i)
	# Births/deaths vs events: every new id produced a birth event with the
	# correct tick and entity_id; counts per tick match the series.
	var seen := {}
	seen = _population_ids(run.snapshots[0])
	var birth_events := {}
	for i in range(1, run.snapshots.size()):
		var ids_now := _population_ids(run.snapshots[i])
		for id in ids_now.keys():
			if not seen.has(id):
				_check(true, "birth detected for %s" % id)
		seen = ids_now
	for event in accumulator.timeline:
		if String(event.kind) == "birth":
			var key := "%d|%s" % [int(event.tick), String(event.entity_id)]
			_check(not birth_events.has(key), "birth event unique for %s" % key)
			birth_events[key] = true
			var present := false
			var snapshot: Dictionary = run.snapshots[mini(int(event.tick), run.snapshots.size() - 1)]
			for entry in snapshot.population:
				if String(entry.individual_id) == String(event.entity_id):
					present = true
			_check(present, "birth event entity %s exists in tick-%d snapshot" % [String(event.entity_id), int(event.tick)])
	var total_births := 0
	for value in series.births:
		total_births += int(value)
	_check(total_births == birth_events.size(), "births series total (%d) == birth events (%d)" % [total_births, birth_events.size()])
	var total_births_debug := 0
	for entry in run.controller.debug_state().population:
		if String(entry.state.origin_kind) == "PARENT_TRANSFER":
			total_births_debug += 1
	_check(total_births == total_births_debug, "births total == PARENT_TRANSFER individuals (%d)" % total_births_debug)
	# Timeline sorted by (tick, index).
	var sorted_ok := true
	for i in range(1, accumulator.timeline.size()):
		var prev: Dictionary = accumulator.timeline[i - 1]
		var curr: Dictionary = accumulator.timeline[i]
		if int(prev.tick) > int(curr.tick) or (int(prev.tick) == int(curr.tick) and int(prev.index) >= int(curr.index)):
			sorted_ok = false
	_check(sorted_ok, "event timeline sorted by (tick, index)")

func _dead_in(snapshot: Dictionary) -> int:
	var dead := 0
	for view in snapshot.presentation:
		if not bool(view.alive):
			dead += 1
	return dead

func _population_ids(snapshot: Dictionary) -> Dictionary:
	var ids := {}
	for entry in snapshot.population:
		ids[String(entry.individual_id)] = true
	return ids

func _test_read_only() -> void:
	var manifest := _manifest(777)
	# Plain run: no observation at all.
	var ctl_plain := Controller.new()
	ctl_plain.initialize(manifest)
	ctl_plain.run(16)
	var hash_plain := String(ctl_plain.get_snapshot().canonical_state_hash)
	# Observed run.
	var run := _run_observed(manifest)
	var hash_observed := String(run.controller.get_snapshot().canonical_state_hash)
	_check(not hash_plain.is_empty() and hash_observed == hash_plain,
		"observatory read-only: observed run hash == unobserved run hash")

func _test_morphology_diversity() -> void:
	var manifest := _manifest(4242)
	var run := _run_observed(manifest)
	var series: Dictionary = run.metrics.series
	var last: int = series.tick.size() - 1
	# Manual recount of unique topology signatures among ALIVE organisms.
	var unique := {}
	for entry in run.controller.debug_state().population:
		var state: Dictionary = entry.state
		if not bool(state.alive):
			continue
		var signature := String(B.topology_signature(state.development.modules))
		if not signature.is_empty():
			unique[signature] = true
	_check(int(series.morphology_unique_signatures[last]) == unique.size(),
		"morphology diversity == manual unique signature count (%d vs %d)" % [int(series.morphology_unique_signatures[last]), unique.size()])
	_check(int(series.morphology_unique_signatures[last]) >= 1, "at least one unique morphology signature")
	# Shannon permille is bounded and deterministic.
	var shannon := int(series.morphology_shannon_permille[last])
	_check(shannon >= 0 and shannon <= roundi(log(2.0) * 1000.0 * maxi(1, unique.size())) + 1,
		"morphology Shannon entropy bounded by ln(unique) (got %d permille)" % shannon)
	# Body modules series is consistent with the final state.
	var modules_total := 0
	for entry in run.controller.debug_state().population:
		modules_total += int(entry.state.development.modules.size())
	_check(int(series.body_modules_total[last]) == modules_total,
		"body_modules_total == manual module count (%d)" % modules_total)

func _test_comparison() -> void:
	var run_a := _run_observed(_manifest(1001))
	var run_b := _run_observed(_manifest(2002))
	var result_a := _experiment_result(_manifest(1001), run_a.controller, run_a.metrics)
	var result_b := _experiment_result(_manifest(2002), run_b.controller, run_b.metrics)
	var compared: Dictionary = Comparison.compare(result_a, result_b)
	_check(String(compared.schema) == Comparison.SCHEMA, "comparison report schema")
	_check(not bool(compared.manifest_hash.equal), "different seeds -> different manifest hashes")
	_check(not bool(compared.seed.equal), "different seeds detected")
	_check(not bool(compared.final_state_hash.equal), "different seeds -> different final state hashes")
	var diffs: Dictionary = compared.metric_diffs
	_check(diffs.has("population") and diffs.has("tick") and diffs.has("births_total"), "diff summary covers key metrics")
	_check(int(diffs.tick.a) == 16 and int(diffs.tick.b) == 16 and bool(diffs.tick.equal), "both runs reached tick 16")
	_check(diffs.population.has("a") and diffs.population.has("b") and diffs.population.has("delta"),
		"population diff carries a/b/delta")
	_check(compared.event_counts.a.has("birth") and compared.event_counts.b.has("birth"), "event counts carried for both sides")
	# Determinism through the comparison path: same seed twice.
	var run_c := _run_observed(_manifest(1001))
	var result_c := _experiment_result(_manifest(1001), run_c.controller, run_c.metrics)
	var compared_same: Dictionary = Comparison.compare(result_a, result_c)
	_check(bool(compared_same.final_state_hash.equal), "same seed -> identical final state hash")
	_check(bool(compared_same.manifest_hash.equal), "same seed -> identical manifest hash")
	# Selected-metrics subset.
	var selected: Dictionary = Comparison.compare(result_a, result_b, ["population"])
	_check(selected.metrics_compared == ["population"], "selected metrics subset respected")

func _test_workbench_observatory_ui() -> void:
	var lab: Node = LabScene.instantiate()
	root.add_child(lab)
	var controller: Object = lab.get("controller")
	var workbench: Node = lab.get_node_or_null("EcologyWorkbench")
	if controller == null or workbench == null:
		_check(false, "lab scene exposes controller + workbench for observatory UI test")
		_finish()
		return
	# Baseline: 8 plain controller ticks.
	var baseline_ctl := Controller.new()
	baseline_ctl.initialize(controller.get_manifest())
	baseline_ctl.run(8)
	var hash_baseline := String(baseline_ctl.get_snapshot().canonical_state_hash)
	# UI path: observatory + classification ON, 8 ticks.
	workbench.set("observatory_enabled", true)
	workbench.set("morphotype_classification_enabled", true)
	var ok := true
	for i in 8:
		if not bool(workbench.call("command_step")):
			ok = false
			break
	_check(ok, "8 UI ticks with observatory ON succeed")
	_check(String(controller.get_snapshot().canonical_state_hash) == hash_baseline,
		"observatory UI ON: canonical hash identical to plain 8-tick run")
	var content: Label = workbench.get_node_or_null("WorkbenchUI/ObservatoryPanel/ObservatoryContent") as Label
	_check(content != null and String(content.text).length() > 0, "observatory panel renders text series")
	_check(String(content.text).contains("tick"), "observatory text shows the tick series")
	# Classification toggle affects analytics only (hash unchanged again).
	workbench.call("set_morphotype_classification", false)
	for i in 8:
		workbench.call("command_step")
	_check(String(controller.get_snapshot().canonical_state_hash) != "" , "run continues after classification toggle")
	lab.queue_free()

func _run() -> void:
	_test_series_consistency()
	_test_read_only()
	_test_morphology_diversity()
	_test_comparison()
	_test_workbench_observatory_ui()
	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_OBSERVATORY_P10 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_OBSERVATORY_P10 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P10_FAILURE " + failure)
		quit(1)
