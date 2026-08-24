extends SceneTree

## ECO.EVO7 FFF3.1 repair acceptance.
## Proves that light feedback ON/OFF compares the SAME candidates with the SAME
## stochastic realization identities; only environment/light assignment may differ.
const Bridge = preload("res://scripts/research/ecology/evo7_light_feedback_counterfactual_v2.gd")
const Morphology = preload("res://scripts/research/ecology/evo7_morphology_evolution_bridge_v1.gd")
const SEED := 20260824

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	_identity_contract()
	_counterfactual_probe()
	_source_boundaries()
	_finish()

func _identity_contract() -> void:
	var ancestor := Morphology.default_ancestor_bundle(SEED)
	_check(not ancestor.is_empty(), "FFF3.1 ancestor available")
	if ancestor.is_empty(): return
	var tag := Bridge.stable_seed_tag(ancestor)
	_check(tag == "evo7-fff31-eval|%d" % int(ancestor["individual_seed"]), "stable realization tag derives only from candidate identity")
	_check(not tag.contains("sun") and not tag.contains("light") and not tag.contains("environment") and not tag.contains("on") and not tag.contains("off"), "realization tag excludes counterfactual environment/mode")
	var invalid: Dictionary = ancestor.duplicate(true)
	invalid["individual_seed"] = -1
	_check(Bridge.stable_seed_tag(invalid).is_empty(), "invalid candidate identity fails closed")

func _counterfactual_probe() -> void:
	var result := Bridge.run_all(SEED)
	_check(not result.is_empty(), "FFF3.1 counterfactual probe runs")
	if result.is_empty(): return
	var on: Dictionary = result["feedback_on"]
	var off: Dictionary = result["feedback_off"]
	_check(String(result["candidate_pool_hash"]).length() == 64, "one immutable mutation candidate pool exists")
	_check(bool(result["counterfactual_identity_equal"]), "counterfactual identity equality is explicit")
	_check(String(on["realization_seed_hash"]) == String(off["realization_seed_hash"]), "ON/OFF use byte-identical realization seed vector")
	_check(String(on["environment_assignment_hash"]) != String(off["environment_assignment_hash"]), "ON/OFF differ in environment assignment")
	_check(float(on["mean_effective_light"]) < float(off["mean_effective_light"]) - 0.02, "canopy feedback measurably reduces candidate light")
	_check(String(on["score_hash"]) != String(off["score_hash"]), "light-only counterfactual changes fitness scores")
	_check(String(on["selected_population_hash"]) != String(off["selected_population_hash"]), "light-only counterfactual changes selected descendants")
	var replay := Bridge.run_all(SEED)
	_check(not replay.is_empty() and String(replay["result_hash"]) == String(result["result_hash"]), "FFF3.1 deterministic replay is hash-identical")

func _source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/evo7_light_feedback_counterfactual_v2.gd").to_lower()
	for forbidden in ["randf", "randi(", "randomize", "species_class"]:
		_check(not source.contains(forbidden), "FFF3.1 source excludes %s" % forbidden)
	_check(source.contains("stable_seed_tag(bundle)"), "functional realization consumes stable candidate identity")
	_check(not source.contains("stable_seed_tag(bundle, env"), "environment cannot enter stable seed API")
	_check(source.contains("lineageextension.reproduce_bundle"), "single lineage mutation authority retained")
	_check(source.contains("lightfield.compute"), "real canopy/light field drives counterfactual")

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.EVO7 FFF3.1 Counterfactual Identity Repair: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.EVO7 FFF3.1 FAIL: %s" % failure)
	print("ECO.EVO7 FFF3.1 Counterfactual Identity Repair: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
