extends SceneTree

const Harness = preload("res://scripts/research/ecology/eco_p1a_s4_sensitivity_harness_v1.gd")

const EXPECTED_BASELINE_SUMMARY_HASH := "327d211d24f8f74251e02f0ced22323b4120c18d9b42a9cfcf99974cf9accc5a"
const EXPECTED_BASELINE_RESULT_HASH := "cb1641a6b49dfa2be3f64c94f2ebc3240327eaca559d025d34e72ba74c0aa11e"
const EXPECTED_BIOMASS_SERIES_HASH := "7c621f1a8c302fdd10f60fd4e576b7688a3bd1065f84c84b7c391e5031f05e0c"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var summary := Harness.sensitivity_summary(Harness.baseline_config(), 17)
	var full := Harness.run(Harness.baseline_config(), 9, 24)
	_check(not summary.is_empty(), "restart summary builds")
	_check(not full.is_empty(), "restart full run builds")
	_check(String(summary.get("summary_hash", "")) == EXPECTED_BASELINE_SUMMARY_HASH, "restart summary hash exact")
	_check(String(full.get("result_hash", "")) == EXPECTED_BASELINE_RESULT_HASH, "restart result hash exact")
	_check(String(full.get("total_biomass_series_hash", "")) == EXPECTED_BIOMASS_SERIES_HASH, "restart biomass series hash exact")
	if failures.is_empty():
		print("ECO.P1A-S4 Restart Replay: PASS (%d assertions) summary=%s result=%s series=%s" % [assertions, EXPECTED_BASELINE_SUMMARY_HASH, EXPECTED_BASELINE_RESULT_HASH, EXPECTED_BIOMASS_SERIES_HASH])
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1A-S4 RESTART FAIL: %s" % failure)
	quit(1)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
