extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_render_description_probes_v1.gd")

var assertions := 0

func _init() -> void:
	var results := Probes.run_all()
	_assert(not results.is_empty())
	var reference: Dictionary = results["REFERENCE"]
	var description_hash := String(reference["render_description"]["render_description_hash"])
	var full_hash := String(reference["materializations"]["FULL_PROCEDURAL"]["materialization_hash"])
	var matrix_hash := Probes.compute_profile_matrix_hash(results)
	_assert(description_hash.length() == 64)
	_assert(matrix_hash.length() == 64)
	_assert(full_hash.length() == 64)
	print("ECO.PH5 Restart Replay: PASS (%d assertions) reference_description_hash=%s profile_matrix_hash=%s full_materialization_hash=%s" % [assertions, description_hash, matrix_hash, full_hash])
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
