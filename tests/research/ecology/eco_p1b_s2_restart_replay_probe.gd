extends SceneTree
const Selection = preload("res://scripts/research/ecology/plant_spatial_selection_baseline_v1.gd")
const EXPECTED_RESULT_HASH := "a48df039415162a2e2b75fb9badc12ae35fd0cac9f459ae2ba9df88ab1280e80"
const EXPECTED_FIRST_CANDIDATE_POOL_HASH := "9e4b8eba9d7d6bf915de209814e6edba823f30675c6f2aefa6a209fff135f2fd"
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
	var result := Selection.run()
	_check(String(result.get("result_hash", "")) == EXPECTED_RESULT_HASH, "fresh process result hash exact")
	var pool_hashes := {}
	for site_name in Selection.DEFAULT_SITES:
		var hash := String(result["sites"][site_name]["history"][1]["candidate_pool_hash"])
		pool_hashes[hash] = true
		_check(hash == EXPECTED_FIRST_CANDIDATE_POOL_HASH, "fresh process candidate pool exact %s" % site_name)
	_check(pool_hashes.size() == 1, "fresh process common mutation pool preserved")
	if failures.is_empty():
		print("ECO.P1B-S2 Restart Replay: PASS (%d assertions) result=%s pool=%s" % [assertions, EXPECTED_RESULT_HASH, EXPECTED_FIRST_CANDIDATE_POOL_HASH])
		quit(0)
		return
	for failure in failures: push_error("ECO.P1B-S2 RESTART FAIL: %s" % failure)
	quit(1)
func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
