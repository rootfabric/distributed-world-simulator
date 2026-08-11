extends SceneTree

const LabScript = preload("res://scripts/labs/ecology/eco_ph3_morphology_resource_visual_lab.gd")
var assertions := 0

func _init() -> void:
	var packed := load("res://scenes/labs/ecology/eco_ph3_morphology_resource_visual_lab.tscn") as PackedScene
	assert(packed != null); assertions += 1
	var instance := packed.instantiate()
	assert(instance != null); assertions += 1
	root.add_child(instance)
	await process_frame
	assert(instance.suite.size() == 32); assertions += 1
	assert(instance.status_label != null); assertions += 1
	assert(instance.status_label.text.contains("Morphology-to-Resource Coupling")); assertions += 1
	assert(instance.status_label.text.contains("morphology_delta")); assertions += 1
	assert(LabScript.CASE_ORDER.size() == 10); assertions += 1
	for key in LabScript.CASE_ORDER:
		assert(instance.suite.has(key)); assertions += 1
	instance.queue_free()
	await process_frame
	print("ECO.PH3 Visual Lab Smoke: PASS (%d assertions)" % assertions)
	quit(0)
