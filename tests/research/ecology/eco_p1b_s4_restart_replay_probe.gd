extends SceneTree
const Gate = preload("res://scripts/research/ecology/plant_local_adaptation_robustness_gate_v1.gd")
const EXPECTED_AGGREGATE_HASH := "2c37160726c73a9b6b479be67a3cedcd34a1247025b219d2b5ebddbec4e18f05"
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
	var result := Gate.run()
	_check(not result.is_empty(), "fresh process result exists")
	_check(String(result.get("aggregate_hash", "")) == EXPECTED_AGGREGATE_HASH, "fresh process aggregate hash exact")
	_check(Array(result.get("runs", [])).size() == Gate.SEEDS.size(), "fresh process seed count exact")
	_check(String(result["neutral"].get("result_hash", "")) == "175bbef1c085d0783bd0d48f23bbc9a865cc438ae09e15785d4e48cdf1cc27bf", "fresh process neutral hash exact")
	_check(String(result["long_run"].get("result_hash", "")) == "7f68ed87e10fa7dd6f9f79c6d50d0a82cf4360e4a416dc481e0e6005bcfb44f3", "fresh process long hash exact")
	if failures.is_empty():
		print("ECO.P1B-S4 Restart Replay: PASS (%d assertions) aggregate=%s" % [assertions, String(result["aggregate_hash"])])
		quit(0)
		return
	for failure in failures:
		push_error("ECO.P1B-S4 RESTART FAIL: %s" % failure)
	quit(1)
func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
