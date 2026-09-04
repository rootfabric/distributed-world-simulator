extends SceneTree

const Perf = preload("res://scripts/research/fabric_bake0/complex2_perf_scaling_v1.gd")
const Fixture = preload("res://scripts/research/fabric_bake0/complex2_modular_machine_fixture_v1.gd")

var assertions := 0
var failures: Array = []

func _initialize() -> void:
	var matrix := Perf.run_matrix()
	_check(bool(matrix.get("success", false)), "matrix succeeds: %s" % matrix)
	if bool(matrix.get("success", false)):
		var cases: Array = matrix["cases"]
		_check(cases.size() == 3, "three scale cases")
		var expected_counts := {
			500: [160, 60, 80, 80, 120],
			1000: [320, 120, 160, 160, 240],
			2000: [640, 240, 320, 320, 480],
		}
		for case_result in cases:
			var n := int(case_result["part_count"])
			var counts: Dictionary = case_result["region_part_counts"]
			_check(case_result["module_count"] == 25, "%d module count" % n)
			_check(case_result["support_count"] == 29, "%d support count" % n)
			_check(case_result["parts_per_module"] == int(n / 25), "%d parts/module" % n)
			_check(int(counts[Fixture.REGION_STRUCTURAL]) == expected_counts[n][0], "%d structural parts" % n)
			_check(int(counts[Fixture.REGION_FULL]) == expected_counts[n][1], "%d full parts" % n)
			_check(int(counts[Fixture.REGION_CONTACT]) == expected_counts[n][2], "%d contact parts" % n)
			_check(int(counts[Fixture.REGION_DYNAMIC]) == expected_counts[n][3], "%d dynamic parts" % n)
			_check(int(counts[Fixture.REGION_HYBRID]) == expected_counts[n][4], "%d hybrid parts" % n)
			_check(case_result["structural_before_hash"] != case_result["structural_after_hash"], "%d D topology changes" % n)
			_check(case_result["structural_component_count"] == 1, "%d D remains connected" % n)
			_check(int(case_result["settle_step"]) > 0, "%d E settles" % n)
			_check(float(case_result["settled_energy_j"]) <= 0.0025 + 1.0e-12, "%d settled energy" % n)
			_check(float(case_result["reimpact_peak_energy_j"]) > 0.1, "%d reimpact excites machine" % n)
			_check(float(case_result["mixed_full_max_delta"]) <= 1.0e-12, "%d mixed == FULL" % n)
			_check(case_result["local_rebake_regions"] == [Fixture.REGION_DYNAMIC], "%d local rebake one region" % n)
			_check(float(case_result["local_rebake_state_handoff_error"]) == 0.0, "%d local rebake handoff" % n)
			_check(int(case_result["rebake_generation"]) == 7, "%d rebake generation" % n)
			_check(int(case_result["timing_us"]["total"]) > 0, "%d timing captured" % n)
			_check(int(case_result["timing_us"]["total"]) <= int(case_result["budget_us"]), "%d total budget" % n)
			_check(int(case_result["timing_us"]["local_rebake"]) <= Perf.LOCAL_REBAKE_BUDGET_US, "%d local rebake budget" % n)
			print("COMPLEX2-PERF %d parts: total=%dus build=%dus scan=%dus D=%dus E=%dus mixed=%dus rebake=%dus" % [
				n,
				int(case_result["timing_us"]["total"]),
				int(case_result["timing_us"]["build"]),
				int(case_result["timing_us"]["scan"]),
				int(case_result["timing_us"]["structural_failure"]),
				int(case_result["timing_us"]["settle_and_reimpact"]),
				int(case_result["timing_us"]["mixed_runtime"]),
				int(case_result["timing_us"]["local_rebake"]),
			])
		print("COMPLEX2PERF_MATRIX_HASH=%s" % String(matrix["matrix_hash"]))
	_finish()

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("FABRIC COMPLEX2-PERF Scaling Acceptance: PASS (%d assertions) 500/1000/2000" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("COMPLEX2-PERF ASSERTION FAILED: %s" % failure)
	print("FABRIC COMPLEX2-PERF Scaling Acceptance: FAIL (%d/%d failed)" % [failures.size(), assertions])
	quit(1)
