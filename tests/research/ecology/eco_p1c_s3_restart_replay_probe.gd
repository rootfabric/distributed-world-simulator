extends SceneTree
const Diagnostics = preload("res://scripts/research/ecology/plant_niche_cluster_diagnostics_v1.gd")
const EXPECTED_DIAGNOSTIC_HASH := "33de1af8e20e45eea88d9ddc20ee0664b6c53f20282995c593c1738e9105db2d"
const EXPECTED_DYNAMIC_HASH := "3e52c4e93fcdefba64607dd2c935ccbddba78db3f400d6a6ea51b23db766982b"
func _init() -> void:
	var result := Diagnostics.run_seed(Diagnostics.DEFAULT_SEEDS[0], false)
	var assertions := 0
	var failures := 0
	assertions += 1; if result.is_empty(): failures += 1
	assertions += 1; if String(result.get("diagnostic_hash", "")) != EXPECTED_DIAGNOSTIC_HASH: failures += 1
	assertions += 1; if String(result.get("dynamic_result_hash", "")) != EXPECTED_DYNAMIC_HASH: failures += 1
	assertions += 1; if int(result.get("effective_founder_count", 0)) != 19: failures += 1
	assertions += 1; if int(result.get("niche_enriched_cluster_count", 0)) != 3: failures += 1
	if failures == 0:
		print("ECO.P1C-S3 Restart Replay: PASS (%d assertions) diagnostic=%s" % [assertions, String(result["diagnostic_hash"])])
		quit(0)
	else:
		push_error("ECO.P1C-S3 Restart Replay: FAIL (%d/%d)" % [failures, assertions])
		quit(1)
