extends SceneTree

const Robustness = preload("res://scripts/research/ecology/plant_cal1_f_full_pool_robustness_v1.gd")
const Calibration = preload("res://scripts/research/ecology/plant_cal1_f_calibration_profile_v1.gd")

const EXPECTED_PARENT_E := "6214b8348b16acd005979c3e8ea88eca202acac0ffe835fc899cef27fbe50814"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	for profile_name in Calibration.PROFILE_ORDER:
		var profile: Dictionary = Calibration.create(profile_name)
		_check(not profile.is_empty(), "calibration profile must exist: %s" % profile_name)
		if not profile.is_empty():
			_check(Calibration.validate(profile), "calibration profile must validate: %s" % profile_name)
	var unity := Calibration.create("UNITY")
	_check(float(unity.get("morphology_delta_multiplier", 0.0)) == 1.0, "UNITY morphology multiplier must be 1")
	_check(float(unity.get("vertical_light_multiplier", 0.0)) == 1.0, "UNITY vertical multiplier must be 1")
	_check(float(unity.get("crown_overlap_loss_multiplier", 0.0)) == 1.0, "UNITY crown multiplier must be 1")
	_check(float(unity.get("root_competition_multiplier", 0.0)) == 1.0, "UNITY root multiplier must be 1")

	var result: Dictionary = Robustness.run()
	_check(not result.is_empty(), "CAL1-F result must exist")
	if result.is_empty():
		_finish()
		return
	_check(String(result.get("cal1_e_parent_hash", "")) == EXPECTED_PARENT_E, "accepted CAL1-E parent hash must remain exact")
	_check(String(result.get("selected_calibration_profile", "")) == "UNITY", "without empirical target CAL1-F must retain unity calibration if robust")
	_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash must be sha256")

	var seed: Dictionary = result["seed_sweep"]
	_check(int(seed["seed_count"]) == 5, "seed sweep must use five deterministic phenotype seeds")
	_check(int(seed["context_count"]) == 40, "seed sweep must cover 40 contexts")
	_check(int(seed["row_count"]) == 320, "seed sweep must cover 320 full-pool rows")
	_check(int(seed["distinct_seed_signatures"]) >= 2, "different deterministic seeds must actually change the realized experiment")
	_check(float(result["seed_multi_pareto_fraction"]) >= Robustness.MIN_SEED_MULTI_PARETO_FRACTION, "most seed contexts must retain multi-member Pareto fronts")

	var environment: Dictionary = result["environment_sweep"]
	_check(int(environment["context_count"]) == 20, "environment sweep must cover 20 contexts")
	_check(int(environment["row_count"]) == 160, "environment sweep must cover 160 rows")
	_check(int(environment["distinct_pareto_signatures"]) >= 2, "environment perturbations must preserve observable ecological differentiation")

	var density: Dictionary = result["density_sweep"]
	_check(int(density["context_count"]) == 20, "density sweep must cover 20 contexts")
	_check(int(density["row_count"]) == 160, "density sweep must cover 160 rows")
	_check(int(density["monotonic_interaction_violations"]) == 0, "neighbour interaction cannot grow as controlled distance increases and density falls")

	var disturbance: Dictionary = result["disturbance_sweep"]
	_check(int(disturbance["context_count"]) == 20, "disturbance sweep must cover 20 contexts")
	_check(int(disturbance["row_count"]) == 160, "disturbance sweep must cover 160 rows")
	_check(int(disturbance["survival_violations"]) == 0, "increasing disturbance cannot improve survival in matched rows")
	_check(int(disturbance["post_seed_violations"]) == 0, "increasing disturbance cannot improve post-disturbance seed potential in matched rows")

	var calibration: Dictionary = result["calibration_sweep"]
	_check(int(calibration["profile_count"]) == Calibration.PROFILE_ORDER.size(), "all explicit calibration profiles must run")
	_check(int(calibration["context_count"]) == Calibration.PROFILE_ORDER.size() * 8, "calibration sweep must cover eight representative contexts per profile")
	_check(int(calibration["unity_parent_metric_mismatches"]) == 0, "UNITY recomposition must numerically reproduce accepted CAL1-E metrics")
	_check(float(calibration["minimum_pareto_jaccard_vs_unity"]) >= Robustness.MIN_CALIBRATION_PARETO_JACCARD, "no +/-15% calibration perturbation may create a disjoint Pareto regime")
	_check(float(calibration["mean_pareto_jaccard_vs_unity"]) >= Robustness.MIN_MEAN_CALIBRATION_PARETO_JACCARD, "Pareto structure must remain substantially stable across calibration envelope")

	var pool: Dictionary = result["pool_sweep"]
	_check(int(pool["pool_count"]) == 5, "strategy-pool sweep must include five pool compositions")
	_check(int(pool["context_count"]) == 20, "strategy-pool sweep must cover four environments x five pools")
	_check(int(pool["empty_pareto_contexts"]) == 0, "every restricted pool must retain a valid Pareto front")
	_check(int(pool["resource_pairwise_contradictions"]) == 0, "full-pool resource winner must be pairwise-consistent on the same scalar ledger")
	_check(int(pool["no_height_low_fallback_contexts"]) == 4, "removing HEIGHT_LOW must produce a deterministic fallback winner in all four environments")

	var gates: Dictionary = result["gates"]
	for gate_name in gates.keys():
		_check(bool(gates[gate_name]), "robustness gate must pass: %s" % String(gate_name))
	_check(String(result.get("classification", "")) == "ROBUST_UNITY_CALIBRATION", "CAL1-F classification must be robust before CAL1 closure")

	var repeat: Dictionary = Robustness.run()
	_check(not repeat.is_empty(), "same-process repeat must exist")
	if not repeat.is_empty():
		_check(String(repeat.get("aggregate_hash", "")) == String(result.get("aggregate_hash", "")), "same-process aggregate must be deterministic")

	print("ECO.CAL1-F seeds=%d seed_signatures=%d seed_multi_pareto=%.6f env_pareto_signatures=%d" % [
		int(seed["seed_count"]), int(seed["distinct_seed_signatures"]), float(result["seed_multi_pareto_fraction"]), int(environment["distinct_pareto_signatures"])
	])
	print("ECO.CAL1-F density_violations=%d disturbance_survival_violations=%d disturbance_seed_violations=%d" % [
		int(density["monotonic_interaction_violations"]), int(disturbance["survival_violations"]), int(disturbance["post_seed_violations"])
	])
	print("ECO.CAL1-F calibration_min_jaccard=%.12f calibration_mean_jaccard=%.12f calibration_pareto_signatures=%d resource_signatures=%d" % [
		float(calibration["minimum_pareto_jaccard_vs_unity"]), float(calibration["mean_pareto_jaccard_vs_unity"]),
		int(calibration["distinct_pareto_signatures"]), int(calibration["distinct_resource_winner_signatures"])
	])
	print("ECO.CAL1-F pool_contexts=%d pairwise_contradictions=%d classification=%s" % [
		int(pool["context_count"]), int(pool["resource_pairwise_contradictions"]), String(result["classification"])
	])
	print("ECO.CAL1-F Calibration + Full-Pool Robustness: PASS (%d assertions) aggregate_hash=%s cal1_e=%s" % [assertions, String(result["aggregate_hash"]), String(result["cal1_e_parent_hash"])])
	_finish()

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		quit(0)
		return
	for message in failures:
		push_error("ECO.CAL1-F ASSERTION FAILED: " + message)
	print("ECO.CAL1-F Calibration + Full-Pool Robustness: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
