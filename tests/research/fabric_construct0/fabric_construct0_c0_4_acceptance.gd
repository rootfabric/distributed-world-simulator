extends SceneTree

const Runtime = preload("res://scripts/labs/fabric_construct0/construct0_lifecycle_runtime.gd")

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var runtime = Runtime.new()
	var ready: Dictionary = runtime.setup()
	_check(bool(ready.get("success", false)), "C0.4 setup")
	if bool(ready.get("success", false)):
		var auto: Dictionary = runtime.state()
		_check(String(auto["requested_representation"]) == "AUTO", "AUTO requested")
		_check(String(auto["effective_representation"]) == "BAKED", "AUTO chooses certified BAKED")
		_check(int(auto["metrics"]["canonical_part_count"]) == 500, "canonical 500 parts")
		_check(int(auto["metrics"]["full_dof"]) == 6500, "FULL complexity 6500 DOF")
		_check(int(auto["metrics"]["current_dof"]) == 13, "BAKED complexity 13 DOF")
		_check(absf(float(auto["metrics"]["reduction_ratio"]) - 500.0) <= 1.0e-12, "BAKED reduction 500x")
		_check(float(auto["metrics"]["boundary_anchor_error"]) <= 1.0e-9, "AUTO boundary anchors match FULL")
		_check(float(auto["metrics"]["minimum_guard_margin"]) > 0.0, "BAKED guard margin visible")
		_check(String(auto["metrics"]["artifact_hash"]).length() == 64, "BAKED artifact hash visible")
		var frontier := String(auto["metrics"]["source_frontier_hash"])

		var full_result: Dictionary = runtime.switch_representation("FULL")
		_check(bool(full_result.get("success", false)), "FORCE FULL succeeds")
		var full: Dictionary = runtime.state()
		_check(String(full["effective_representation"]) == "FULL", "effective FULL")
		_check(int(full["metrics"]["current_dof"]) == 6500, "FULL current complexity 6500")
		_check(absf(float(full["metrics"]["reduction_ratio"]) - 1.0) <= 1.0e-12, "FULL reduction ratio 1")
		_check(float(full["metrics"]["boundary_anchor_error"]) <= 1.0e-9, "FULL boundary anchors match BAKED")
		_check(String(full["metrics"]["source_frontier_hash"]) == frontier, "representation switch does not mutate canonical frontier")

		var baked_result: Dictionary = runtime.switch_representation("BAKED")
		_check(bool(baked_result.get("success", false)), "FORCE BAKED succeeds")
		var baked: Dictionary = runtime.state()
		_check(String(baked["effective_representation"]) == "BAKED", "effective BAKED")
		_check(int(baked["metrics"]["current_dof"]) == 13, "BAKED returns to 13 DOF")
		_check(String(baked["metrics"]["source_frontier_hash"]) == frontier, "BAKED forcing leaves source unchanged")

		var no_safe: Dictionary = runtime.probe_no_safe_bake()
		_check(bool(no_safe.get("success", false)), "NO_SAFE_BAKE probe succeeds")
		_check(String(no_safe.get("reason", "")) == "NO_SAFE_BOUNDED_LOCAL_UNBAKE_LIMIT", "NO_SAFE reason exact")
		var visible: Dictionary = runtime.state()["no_safe_bake"]
		_check(bool(visible["visible"]), "NO_SAFE_BAKE is visible")
		_check(String(visible["policy"]) == "FAIL_CLOSED_OR_FULL", "NO_SAFE policy fail-closed/full")

	var second = Runtime.new()
	var second_ready: Dictionary = second.setup()
	_check(bool(second_ready.get("success", false)), "repeat C0.4 setup")
	if bool(second_ready.get("success", false)) and bool(ready.get("success", false)):
		_check(JSON.stringify(second.state()["metrics"]) == JSON.stringify(ready["state"]["metrics"]), "AUTO representation deterministic")

	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC CONSTRUCT0 C0.4 Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("CONSTRUCT0 C0.4: %s" % failure)
	print("FABRIC CONSTRUCT0 C0.4 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
