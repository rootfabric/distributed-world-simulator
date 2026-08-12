extends SceneTree

const Robustness = preload("res://scripts/research/ecology/plant_cal1_f_full_pool_robustness_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var result: Dictionary = Robustness.run()
	_check(not result.is_empty(), "CAL1-F robustness result must exist")
	if not result.is_empty():
		_check(String(result.get("cal1_e_parent_hash", "")) == Robustness.ACCEPTED_CAL1_E_HASH, "parent E hash must remain exact")
		_check(String(result.get("selected_calibration_profile", "")) == "UNITY", "selected calibration must remain UNITY")
		_check(String(result.get("classification", "")) == "ROBUST_UNITY_CALIBRATION", "classification must be robust")
		_check(String(result.get("aggregate_hash", "")).length() == 64, "aggregate hash must be sha256")
		print("ECO.CAL1-F Restart Replay Probe: PASS (%d assertions) aggregate_hash=%s classification=%s" % [assertions, String(result["aggregate_hash"]), String(result["classification"])])
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
		push_error("ECO.CAL1-F RESTART ASSERTION FAILED: " + message)
	print("ECO.CAL1-F Restart Replay Probe: FAIL (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(1)
