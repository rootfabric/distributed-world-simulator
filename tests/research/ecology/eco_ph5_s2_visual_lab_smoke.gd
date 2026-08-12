extends SceneTree

var assertions := 0

func _init() -> void:
	var packed := load("res://scenes/labs/ecology/eco_ph5_s2_3d_materialization_lab.tscn") as PackedScene
	_assert(packed != null)
	var instance := packed.instantiate()
	_assert(instance != null)
	root.add_child(instance)
	await process_frame
	await process_frame
	_assert(instance.results.size() == 7)
	_assert(instance.status_label != null)
	_assert(instance.status_label.text.contains("Real 3D Tapered Branch"))
	_assert(instance.status_label.text.contains("growth_graph_hash="))
	_assert(instance.status_label.text.contains("geometry_hash="))
	_assert(instance.plant_root != null)
	_assert(instance.camera != null)
	_assert(instance.plant_root.get_child_count() >= 1)
	instance.profile_index = 0
	instance._refresh()
	await process_frame
	_assert(instance.status_label.text.contains("BRANCH_TUBES"))
	instance.profile_index = 2
	instance._refresh()
	await process_frame
	_assert(instance.status_label.text.contains("FULL_PROCEDURAL"))
	instance.queue_free()
	await process_frame
	print("ECO.PH5-S2 3D Visual Lab Smoke: PASS (%d assertions)" % assertions)
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
