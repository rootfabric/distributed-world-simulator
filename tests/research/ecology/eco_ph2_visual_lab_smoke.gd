extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_environment_coupled_development_probes_v1.gd")
var assertions := 0

func _init() -> void:
	var packed := load("res://scenes/labs/ecology/eco_ph2_plasticity_visual_lab.tscn") as PackedScene
	assert(packed != null); assertions += 1
	var instance := packed.instantiate()
	assert(instance != null); assertions += 1
	root.add_child(instance)
	await process_frame
	assert(instance.results.size() == Probes.PROBE_ORDER.size()); assertions += 1
	assert(instance.status_label != null); assertions += 1
	assert(instance.status_label.text.contains("Same genome + inherited development traits")); assertions += 1
	for name in Probes.PROBE_ORDER:
		assert(not instance.results[name].is_empty()); assertions += 1
	instance.queue_free()
	await process_frame
	print("ECO.PH2 Visual Lab Smoke: PASS (%d assertions)" % assertions)
	quit(0)
