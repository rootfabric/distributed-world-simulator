extends SceneTree
const Dynamic = preload("res://scripts/research/ecology/plant_dynamic_abundance_competition_v1.gd")
const EXPECTED_RESULT_HASH := "3e52c4e93fcdefba64607dd2c935ccbddba78db3f400d6a6ea51b23db766982b"
const EXPECTED_FOUNDER_POOL_HASH := "77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38"
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
	var result := Dynamic.run()
	_check(not result.is_empty(), "restart result exists")
	_check(String(result.get("result_hash", "")) == EXPECTED_RESULT_HASH, "restart result hash exact")
	_check(String(result.get("founder_pool_hash", "")) == EXPECTED_FOUNDER_POOL_HASH, "restart founder pool exact")
	_check(int(result.get("cycles", 0)) == Dynamic.DEFAULT_CYCLES, "restart cycles exact")
	_check(float(result.get("global_abundance", {}).get("top1_biomass_share", 1.0)) < 0.30, "restart preserves non-monopoly result")
	if failures.is_empty():
		print("ECO.P1C-S2 Restart Replay: PASS (%d assertions) result=%s" % [assertions, String(result.get("result_hash", ""))])
		quit(0)
		return
	for failure in failures: push_error("ECO.P1C-S2 RESTART FAIL: %s" % failure)
	quit(1)
func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
