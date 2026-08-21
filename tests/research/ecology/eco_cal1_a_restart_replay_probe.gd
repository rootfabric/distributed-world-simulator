extends SceneTree

const Baseline = preload("res://scripts/research/ecology/plant_morphology_economics_baseline_v1.gd")

func _init() -> void:
	var result: Dictionary = Baseline.run()
	var checks := 0
	assert(not result.is_empty()); checks += 1
	assert(String(result.get("baseline_hash", "")).length() == 64); checks += 1
	assert(String(result.get("legacy_ph3c_pairwise_hash", "")).length() == 64); checks += 1
	assert(int(result.get("row_count", 0)) == 32); checks += 1
	assert(int(result.get("height_low_beats_height_high_count", 0)) == 4); checks += 1
	print("ECO.CAL1-A Restart Replay Probe: PASS (%d assertions) baseline_hash=%s legacy_ph3c_pairwise_hash=%s classification=%s" % [
		checks,
		String(result["baseline_hash"]),
		String(result["legacy_ph3c_pairwise_hash"]),
		String(result["dominance_classification"]),
	])
	quit(0)
