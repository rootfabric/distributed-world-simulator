extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_morphology_aware_selection_competition_v1.gd")

func _init() -> void:
	var first := Competition.run_matrix()
	var second := Competition.run_matrix()
	var checks := 0
	assert(not first.is_empty() and not second.is_empty()); checks += 1
	assert(String(first["aggregate_hash"]) == String(second["aggregate_hash"])); checks += 1
	for key in ["SUN_CROWN/AWARE", "DRY_CROWN/AWARE", "REFERENCE_GIANT/AWARE"]:
		assert(String(first["results"][key]["result_hash"]) == String(second["results"][key]["result_hash"])); checks += 1
	assert(String(first["results"]["SUN_CROWN/RESOURCE_ONLY_CONTROL"]["result_hash"]) == String(second["results"]["SUN_CROWN/RESOURCE_ONLY_CONTROL"]["result_hash"])); checks += 1
	print("ECO.PH3C Restart Replay: PASS (%d assertions) aggregate=%s" % [checks, String(first["aggregate_hash"])])
	quit(0)
