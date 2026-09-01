extends SceneTree

const Runtime = preload("res://scripts/labs/fabric_construct0/construct0_lifecycle_runtime.gd")

var _checks := 0
var _failures: Array[String] = []

func _init() -> void:
	var runtime = Runtime.new()
	var ready: Dictionary = runtime.setup()
	_check(bool(ready.get("success", false)), "C0.5 setup")
	if bool(ready.get("success", false)):
		var baseline_hash := String(runtime.state()["metrics"]["artifact_hash"])
		var baseline_generation := int(runtime.state()["metrics"]["build_generation"])
		var rebuilt: Dictionary = runtime.mutate_and_rebuild(false)
		_check(bool(rebuilt.get("success", false)), "mass mutation rebuild succeeds")
		if bool(rebuilt.get("success", false)):
			var state: Dictionary = runtime.state()
			var metrics: Dictionary = state["metrics"]
			_check(String(state["status"]) == "BRIDGE1_REBUILT_BAKE_READY", "fresh bake ready")
			_check(String(metrics["stale_rejection_code"]) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "old artifact execution rejected")
			_check(int(metrics["full_state_count"]) == 500, "reconstruction covers 500 parts")
			_check(String(metrics["full_state_hash"]).length() == 64, "full reconstruction hash visible")
			_check(String(metrics["old_artifact_hash"]) == baseline_hash, "old artifact identity captured")
			_check(String(metrics["new_artifact_hash"]).length() == 64, "new artifact identity captured")
			_check(String(metrics["new_artifact_hash"]) != String(metrics["old_artifact_hash"]), "artifact identity changes")
			_check(int(metrics["old_generation"]) == baseline_generation, "old generation captured")
			_check(int(metrics["new_generation"]) == baseline_generation + 1, "build generation increments")
			_check(float(metrics["handoff_error"]) <= 1.0e-8, "kinematic handoff bounded")
			_check(String(metrics["contact_state_policy"]) == "DISCARD_AND_REDERIVE", "transient contact state discarded")
			_check(not bool(metrics["accepted_previous_contact_impulse"]), "old contact impulse not accepted")
			_check(String(state["effective_representation"]) == "BAKED", "fresh rebuilt bake effective")
			var fresh: Dictionary = runtime.switch_representation("BAKED")
			_check(bool(fresh.get("success", false)), "rebuilt artifact executable")

	var fallback_runtime = Runtime.new()
	var fallback_ready: Dictionary = fallback_runtime.setup()
	_check(bool(fallback_ready.get("success", false)), "FULL fallback setup")
	if bool(fallback_ready.get("success", false)):
		var fallback: Dictionary = fallback_runtime.mutate_and_rebuild(true)
		_check(bool(fallback.get("success", false)), "forced FULL fallback succeeds")
		if bool(fallback.get("success", false)):
			var state2: Dictionary = fallback_runtime.state()
			_check(String(state2["status"]) == "FULL_RECONSTRUCTED", "fallback status FULL_RECONSTRUCTED")
			_check(String(state2["effective_representation"]) == "FULL", "fallback effective FULL")
			_check(int(state2["metrics"]["full_state_count"]) == 500, "fallback reconstructs all parts")
			_check(String(state2["metrics"]["stale_rejection_code"]) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "fallback also rejects stale bake")
			_check(String(state2["metrics"]["contact_state_policy"]) == "DISCARD_AND_REDERIVE", "fallback discards transient contact state")

	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("FABRIC CONSTRUCT0 C0.5 Acceptance: PASS (%d assertions)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error("CONSTRUCT0 C0.5: %s" % failure)
	print("FABRIC CONSTRUCT0 C0.5 Acceptance: FAIL (%d failures / %d assertions)" % [_failures.size(), _checks])
	quit(1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
