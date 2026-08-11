extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var matrix := Competition.run_matrix()
	_check(not matrix.is_empty(), "PH3C matrix exists")
	_check(int(matrix.get("case_count", 0)) == 5, "PH3C has five causal pair cases")
	_check(String(matrix.get("aggregate_hash", "")).length() == 64, "PH3C aggregate hash exists")
	var results: Dictionary = matrix.get("results", {})
	_check(results.size() == 10, "five aware plus five resource-only controls")

	for definition in Competition.PAIR_CASES:
		var case_id := String(definition["id"])
		var aware: Dictionary = results.get(case_id + "/AWARE", {})
		var control: Dictionary = results.get(case_id + "/RESOURCE_ONLY_CONTROL", {})
		_check(not aware.is_empty(), "%s aware result exists" % case_id)
		_check(not control.is_empty(), "%s control result exists" % case_id)
		if aware.is_empty() or control.is_empty():
			continue
		var aa: Dictionary = aware["strategy_a"]
		var ab: Dictionary = aware["strategy_b"]
		var ca: Dictionary = control["strategy_a"]
		var cb: Dictionary = control["strategy_b"]
		_check(String(aa["genome_checksum"]) == String(ab["genome_checksum"]), "%s same genome across morphology strategies" % case_id)
		_check(int(aa["individual_seed"]) == int(ab["individual_seed"]), "%s common IndividualSeed isolates inherited morphology" % case_id)
		_check(String(aa["resource_balance_checksum"]) == String(ab["resource_balance_checksum"]), "%s accepted P1 resource result identical across strategies" % case_id)
		_check(String(aa["coupling_hash"]) != String(ab["coupling_hash"]), "%s PH3 coupling distinguishes morphology" % case_id)
		_check(absf(float(ca["selection_score"]) - float(cb["selection_score"])) < 0.000000000001, "%s resource-only control has equal selection score" % case_id)
		_check(absf(float(control["final_a_share"]) - 0.5) < 0.000000000001, "%s resource-only A remains 0.5" % case_id)
		_check(absf(float(control["final_b_share"]) - 0.5) < 0.000000000001, "%s resource-only B remains 0.5" % case_id)
		_check(String(control["winner"]) == "TIE", "%s resource-only control remains tie" % case_id)
		_check(absf(float(aware["final_a_share"]) + float(aware["final_b_share"]) - 1.0) < 0.000000001, "%s aware shares conserve one" % case_id)
		_check(absf(float(aware["final_a_share"]) - 0.5) > 0.01, "%s morphology-aware selection diverges from neutral 0.5" % case_id)
		_check(String(aware["result_hash"]).length() == 64, "%s aware result hash" % case_id)
		_check(String(control["result_hash"]).length() == 64, "%s control result hash" % case_id)

	var sun: Dictionary = results["SUN_CROWN/AWARE"]
	var dry: Dictionary = results["DRY_CROWN/AWARE"]
	_check(String(sun["winner"]) == "CROWN_WIDE", "SUN selects wide crown over narrow crown")
	_check(float(sun["final_b_share"]) > 0.60, "SUN wide-crown share exceeds 0.60")
	_check(String(dry["winner"]) == "CROWN_NARROW", "DRY selects narrow crown over wide crown")
	_check(float(dry["final_a_share"]) > 0.60, "DRY narrow-crown share exceeds 0.60")
	_check(String(sun["winner"]) != String(dry["winner"]), "same crown pair reverses winner between SUN and DRY")

	var branch: Dictionary = results["REFERENCE_BRANCH/AWARE"]
	_check(String(branch["winner"]) == "BRANCH_LOW", "branch construction/maintenance cost selects lower branching in reference case")
	_check(float(branch["final_a_share"]) > 0.60, "low-branch share exceeds 0.60")

	var height: Dictionary = results["REFERENCE_HEIGHT/AWARE"]
	_check(String(height["winner"]) == "HEIGHT_LOW", "super-linear structure cost selects low height against extreme height")
	_check(float(height["final_a_share"]) > 0.75, "low-height share exceeds 0.75")

	var giant: Dictionary = results["REFERENCE_GIANT/AWARE"]
	_check(String(giant["winner"]) == "BASE", "balanced morphology defeats giant dense morphology")
	_check(float(giant["final_a_share"]) > 0.95, "balanced morphology exceeds 0.95 share against giant dense")
	_check(float(giant["final_b_share"]) < 0.01, "giant dense morphology falls below 0.01 share")

	_test_source_boundaries()
	print("ECO.PH3C aggregate_hash=%s" % String(matrix["aggregate_hash"]))
	print("ECO.PH3C crown_reversal=%s" % str({
		"sun_wide_share": sun["final_b_share"],
		"dry_wide_share": dry["final_b_share"],
		"sun_winner": sun["winner"],
		"dry_winner": dry["winner"],
	}))
	print("ECO.PH3C selection=%s" % str({
		"branch_low_share": branch["final_a_share"],
		"height_low_share": height["final_a_share"],
		"giant_dense_share": giant["final_b_share"],
	}))
	_finish()

func _test_source_boundaries() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd").to_lower()
	_check(source.contains("plant_resource_model_v1.gd"), "PH3C consumes accepted P1 resource model")
	_check(source.contains("plant_morphology_resource_coupling_v1.gd"), "PH3C consumes accepted PH3 coupling")
	for forbidden in ["meshinstance", "multimesh", "camera", "authority", "network", "persistence", "treegenerator", "bushgenerator", "grassgenerator"]:
		_check(not source.contains(forbidden), "PH3C source excludes %s" % forbidden)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func _finish() -> void:
	if failures.is_empty():
		print("ECO.PH3C Morphology-Aware Selection / Competition: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("ECO.PH3C FAIL: %s" % failure)
	print("ECO.PH3C Morphology-Aware Selection / Competition: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
