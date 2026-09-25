extends SceneTree

# ECO ARCH2 A10.5 / ECO-POLYGON-1 — P11 Batch runner + comparison tests.
# Runner: Godot headless --script.
#
# Coverage (work order P11, brief §22):
#   a) small batch 2 variations x 2 seeds x horizon 8: ALL 4 results are in
#      the report (no filtering / "beautiful seed" selection); every result
#      carries variation_name/manifest_hash/seed/final_state_hash/metrics/
#      events; deterministic order (variation order, seeds ascending).
#   b) determinism: a repeated run_batch of the SAME plan produces the
#      IDENTICAL canonical report text.
#   c) different fixed seeds -> different final state hashes (diverging
#      dynamics), same seed -> identical hash.
#   d) mutation_on_off helper: mutation event metrics differ between on/off
#      (or both statuses are correctly recorded COMPLETED).
#   e) profile SOFT/NMS -> canonical DEVELOPMENT_BIAS runs, all kept in
#      the report, canonical state untouched (FREE run hash == plain
#      controller run hash for the same seed).
#   f) batch report round-trip: saved canonical text decodes back and
#      contains every result.
#   g) experiment_comparison_v1 accepts batch results directly -> correct
#      diff (seed / manifest / final hash unequal, metric deltas present).

const P = preload("res://scripts/research/ecology/v2/development_program_v1.gd")
const Fixtures = preload("res://scripts/research/ecology/v2/body_program_fixtures_v1.gd")
const Protocol = preload("res://scripts/research/ecology/v2/observatory_protocol_v1.gd")
const C = preload("res://scripts/research/ecology/v2/canonical_value_v1.gd")
const Controller = preload("res://scripts/ecology/workbench/experiment_controller_v1.gd")
const Manifest = preload("res://scripts/ecology/workbench/experiment_manifest_v1.gd")
const Comparison = preload("res://scripts/ecology/workbench/experiment_comparison_v1.gd")
const Batch = preload("res://scripts/ecology/workbench/batch_runner_v1.gd")
const Profile = preload("res://scripts/ecology/workbench/organization_profile_v1.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("A10_5_P11_FAIL " + message)

func _base_manifest(seed: int) -> Dictionary:
	return {
		"schema": Manifest.SCHEMA,
		"experiment_id": "eco-polygon/exp-p11-batch-%d" % seed,
		"seed": seed,
		"horizon_ticks": 32,
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
		"checkpoint": {"interval_ticks": 4},
		"mode": "LAB",
	}

func _small_plan() -> Dictionary:
	# 2 variations x 2 seeds x horizon 8 (fixed diverging seeds).
	return Batch.plan(_base_manifest(1001), [
		{"name": "alpha", "seed_range": [1001, 1002]},
		{"name": "beta", "seed_range": [2001, 2002]},
	], 8)

func _test_small_batch() -> Dictionary:
	var runner := Batch.new()
	var batch: Dictionary = runner.run_batch(_small_plan())
	_check(bool(batch.get("success", false)), "small batch run succeeds")
	var results: Array = batch.results
	_check(results.size() == 4, "all 4 results reported (2 variations x 2 seeds), got %d" % results.size())
	_check(int(batch.run_count) == 4, "run_count == 4")
	# Deterministic order: variation plan order, seeds ascending.
	_check(String(results[0].variation_name) == "alpha" and int(results[0].seed) == 1001, "result 0 = alpha/1001")
	_check(String(results[1].variation_name) == "alpha" and int(results[1].seed) == 1002, "result 1 = alpha/1002")
	_check(String(results[2].variation_name) == "beta" and int(results[2].seed) == 2001, "result 2 = beta/2001")
	_check(String(results[3].variation_name) == "beta" and int(results[3].seed) == 2002, "result 3 = beta/2002")
	for index in results.size():
		var result: Dictionary = results[index]
		_check(String(result.status) == "COMPLETED", "result %d COMPLETED (no filtering)" % index)
		_check(not String(result.manifest_hash).is_empty(), "result %d carries manifest_hash" % index)
		_check(not String(result.initial_state_hash).is_empty(), "result %d carries initial_state_hash (tick 0)" % index)
		_check(not String(result.final_state_hash).is_empty(), "result %d carries final_state_hash" % index)
		_check(result.metrics is Dictionary and not result.metrics.is_empty(), "result %d carries metrics summary" % index)
		_check(result.metrics.has("final") and result.metrics.has("event_counts"), "result %d metrics summary shape" % index)
		_check(result.events is Dictionary and result.events.has("birth"), "result %d carries event counts by kind" % index)
		_check(int(result.ticks_run) == 8, "result %d ran the full horizon 8" % index)
		_check(result.checkpoint_ref is Dictionary and int(result.checkpoint_ref.get("tick", -1)) == 8,
			"result %d carries the last checkpoint ref (interval 4)" % index)
	return batch

func _test_determinism(batch_a: Dictionary) -> void:
	var runner := Batch.new()
	var batch_b: Dictionary = runner.run_batch(_small_plan())
	var text_a: String = runner.build_report(batch_a.results)
	var text_b: String = runner.build_report(batch_b.results)
	_check(not text_a.is_empty() and text_a == text_b, "repeated run_batch of the same plan -> identical canonical report text")
	_check(String(batch_a.report_hash) == String(batch_b.report_hash), "repeated run_batch -> identical report hash")

func _test_seed_divergence(batch: Dictionary) -> void:
	var results: Array = batch.results
	# Fixed diverging seeds: alpha/1001 vs alpha/1002 differ; beta pair too.
	_check(String(results[0].final_state_hash) != String(results[1].final_state_hash),
		"alpha seeds 1001 vs 1002 -> different final hashes")
	_check(String(results[2].final_state_hash) != String(results[3].final_state_hash),
		"beta seeds 2001 vs 2002 -> different final hashes")
	_check(String(results[0].manifest_hash) != String(results[1].manifest_hash),
		"different seeds -> different manifest hashes (seed is manifest input)")
	# Same seed re-run determinism (through the batch path).
	var runner := Batch.new()
	var repeat: Dictionary = runner.run_batch(Batch.plan(_base_manifest(1001), [
		{"name": "alpha", "seed": 1001},
	], 8))
	_check(bool(repeat.get("success", false)) and String(repeat.results[0].final_state_hash) == String(results[0].final_state_hash),
		"same variation+seed re-run -> identical final hash")

func _test_mutation_on_off() -> void:
	var runner := Batch.new()
	var plan := Batch.mutation_on_off(_base_manifest(1001), [1001, 1002])
	plan.horizon_ticks = 16
	var batch: Dictionary = runner.run_batch(plan)
	_check(bool(batch.get("success", false)), "mutation_on_off batch succeeds")
	var results: Array = batch.results
	_check(results.size() == 4, "mutation_on_off: 2 variations x 2 seeds all reported")
	var on_events := 0
	var off_events := 0
	for result in results:
		_check(String(result.status) == "COMPLETED", "mutation variation %s COMPLETED" % String(result.variation_name))
		if String(result.variation_name) == "mutation-on":
			on_events += int(result.metrics.final.get("mutation_events_total", 0))
		else:
			off_events += int(result.metrics.final.get("mutation_events_total", 0))
	_check(on_events >= off_events, "mutation-on events (%d) >= mutation-off events (%d)" % [on_events, off_events])
	_check(on_events > off_events or (on_events == 0 and off_events == 0),
		"mutation metrics differ or both runs correctly recorded zero (on=%d off=%d)" % [on_events, off_events])

func _test_profile_bias() -> void:
	var runner := Batch.new()
	var plan := Batch.profile_free_vs_visual(_base_manifest(1001), [1001])
	plan.horizon_ticks = 8
	var batch: Dictionary = runner.run_batch(plan)
	_check(bool(batch.get("success", false)), "profile_free_vs_visual batch succeeds")
	var results: Array = batch.results
	_check(results.size() == 3, "profile batch: FREE + SOFT + NMS_LIKE all reported")
	var by_name := {}
	for result in results:
		by_name[String(result.variation_name)] = result
	for name in ["profile-free", "profile-soft", "profile-nms-like"]:
		var row: Dictionary = by_name[name]
		_check(String(row.status) == "COMPLETED", "%s executes as a canonical batch run" % name)
		_check(not String(row.initial_state_hash).is_empty() and not String(row.final_state_hash).is_empty(), "%s carries canonical state hashes" % name)
	# FREE batch result must still equal a direct run of its exact derived manifest.
	var free_result: Dictionary = by_name["profile-free"]
	var derived: Dictionary = runner.derive_manifest(_base_manifest(1001),
		{"name": "profile-free", "organization_profile": "FREE"}, 1001, 8)
	_check(bool(derived.get("success", false)), "derive_manifest succeeds for FREE")
	var plain := Controller.new()
	plain.initialize(derived.manifest)
	plain.run(8)
	_check(String(free_result.final_state_hash) == String(plain.get_snapshot().canonical_state_hash),
		"FREE batch run hash == plain controller run of the derived manifest")
	# Biased runs have distinct manifest identities because the profile name and
	# profile semantic version are part of the manifest hash.
	_check(String(by_name["profile-soft"].manifest_hash) != String(free_result.manifest_hash), "SOFT bias has distinct manifest identity")
	_check(String(by_name["profile-nms-like"].manifest_hash) != String(free_result.manifest_hash), "NMS_LIKE bias has distinct manifest identity")

func _test_report_round_trip(batch: Dictionary) -> void:
	var runner := Batch.new()
	var saved: Dictionary = runner.save_batch_report(batch.results, "user://test_batch_report_p11.json")
	_check(bool(saved.get("success", false)), "save_batch_report succeeds (user:// path)")
	var text: String = saved.text
	_check(not text.is_empty() and String(text.sha256_text()) == String(saved.report_hash), "report hash matches text")
	var decoded: Dictionary = C.decode(text)
	_check(bool(decoded.get("success", false)), "saved canonical report decodes back")
	var envelope: Dictionary = decoded.value
	_check(String(envelope.schema) == Batch.REPORT_SCHEMA, "report envelope schema")
	_check(int(envelope.result_count) == 4 and envelope.results.size() == 4, "decoded report contains all 4 results")
	for index in envelope.results.size():
		var result: Dictionary = envelope.results[index]
		_check(result.has_all(["variation_name", "seed", "manifest_hash", "final_state_hash", "metrics", "events"]),
			"decoded result %d carries all required fields" % index)
		_check(String(result.variation_name) == String(batch.results[index].variation_name),
			"decoded result %d order preserved" % index)
	var on_disk := FileAccess.get_file_as_string("user://test_batch_report_p11.json")
	_check(on_disk == text, "file on disk matches the canonical report text")
	# Absolute path save also works.
	var abs_path := ProjectSettings.globalize_path("user://") + "test_batch_report_p11_abs.json"
	var saved_abs: Dictionary = runner.save_batch_report(batch.results, abs_path)
	_check(bool(saved_abs.get("success", false)), "save_batch_report succeeds (absolute path)")
	_check(FileAccess.get_file_as_string(abs_path) == text, "absolute-path report identical (deterministic text)")

func _test_comparison(batch: Dictionary) -> void:
	var results: Array = batch.results
	var compared: Dictionary = Comparison.compare(results[0], results[1])
	_check(String(compared.schema) == Comparison.SCHEMA, "comparison accepts batch results directly")
	_check(not bool(compared.seed.equal), "comparison detects different seeds")
	_check(not bool(compared.manifest_hash.equal), "comparison detects different manifest hashes")
	_check(not bool(compared.final_state_hash.equal), "comparison detects different final hashes")
	var diffs: Dictionary = compared.metric_diffs
	_check(diffs.has("tick") and bool(diffs.tick.equal) and int(diffs.tick.a) == 8, "both batch results reached tick 8")
	_check(diffs.has("population") and diffs.population.has("delta"), "population diff carries delta")
	_check(compared.event_counts.a.has("birth") and compared.event_counts.b.has("birth"), "event counts carried for both sides")
	var same: Dictionary = Comparison.compare(results[0], results[0])
	_check(bool(same.final_state_hash.equal) and bool(same.seed.equal), "self-comparison equal")

func _test_helpers_and_validation() -> void:
	var base := _base_manifest(1001)
	# Helper plans validate.
	for helper in [
		Batch.same_genome_different_environment(base, {"schema": "dws.ecology.workbench.environment-patch.v1", "zones": {"dry": {"water_mg": 400000}}}, {"schema": "dws.ecology.workbench.environment-patch.v1", "zones": {"dry": {"water_mg": 50000}}}, [7]),
		Batch.different_genome_same_environment(base, {"founder/b": Fixtures.make(2)}, [7]),
		Batch.feedback_on_off(base, [7]),
		Batch.seeds_1_to_n(base, 3),
	]:
		_check(Batch.new().validate_plan(helper).is_empty(), "helper plan validates")
	var runner := Batch.new()
	var env_batch: Dictionary = runner.run_batch(Batch.same_genome_different_environment(base,
		{"schema": "dws.ecology.workbench.environment-patch.v1", "zones": {"wet": {"water_mg": 60000}}},
		{"schema": "dws.ecology.workbench.environment-patch.v1", "zones": {"wet": {"water_mg": 500000}}},
		[1001]))
	_check(bool(env_batch.get("success", false)) and env_batch.results.size() == 2, "same_genome_different_environment runs 2 results")
	if bool(env_batch.get("success", false)):
		_check(String(env_batch.results[0].manifest_hash) != String(env_batch.results[1].manifest_hash),
			"env patches produce different manifest hashes")
		_check(String(env_batch.results[0].final_state_hash) != String(env_batch.results[1].final_state_hash),
			"same genome + different environment -> different final hashes")
	var seeds_plan := Batch.seeds_1_to_n(base, 3)
	seeds_plan.horizon_ticks = 8
	var seeds_batch: Dictionary = runner.run_batch(seeds_plan)
	_check(bool(seeds_batch.get("success", false)) and seeds_batch.results.size() == 3, "seeds_1_to_n(3) -> 3 results, none selected away")
	# Plan validation rejects garbage.
	_check(not Batch.new().validate_plan({"schema": "wrong"}).is_empty(), "invalid plan schema rejected")
	var bad_seed := _small_plan()
	bad_seed.variations[0].seed_range = [10, 5]
	_check(not Batch.new().validate_plan(bad_seed).is_empty(), "inverted seed_range rejected")
	var bad_horizon := _small_plan()
	bad_horizon.horizon_ticks = 100000
	_check(not Batch.new().validate_plan(bad_horizon).is_empty(), "horizon above MAX_HORIZON rejected")
	# Default horizon cap: no horizon_ticks -> min(base, 32).
	var capped := Batch.plan(_base_manifest(1001), [{"name": "cap"}])
	capped.erase("horizon_ticks")
	var capped_batch: Dictionary = runner.run_batch(capped)
	_check(bool(capped_batch.get("success", false)) and int(capped_batch.horizon_ticks) == 32,
		"default batch horizon capped at 32 (A6 O(steps^2) guard)")

func _run() -> void:
	var batch := _test_small_batch()
	_test_determinism(batch)
	_test_seed_divergence(batch)
	_test_mutation_on_off()
	_test_profile_bias()
	_test_report_round_trip(batch)
	_test_comparison(batch)
	_test_helpers_and_validation()
	_finish()

func _finish() -> void:
	print("EVO_ARCH2_A10_5_BATCH_P11 checks=%d failed=%d" % [checks, failures.size()])
	if failures.is_empty():
		print("EVO_ARCH2_A10_5_BATCH_P11 PASS")
		quit(0)
	else:
		for failure in failures:
			print("A10_5_P11_FAILURE " + failure)
		quit(1)
