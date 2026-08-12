extends SceneTree

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
var assertions := 0

func _init() -> void:
	var packed := load("res://scenes/labs/ecology/eco_ph5_s3_multi_scale_representation_lab.tscn") as PackedScene
	_assert(packed != null)
	var instance := packed.instantiate()
	_assert(instance != null)
	root.add_child(instance)
	await process_frame
	await process_frame
	_assert(instance.results.size() == 7)
	_assert(instance.status_label != null)
	_assert(instance.status_label.text.contains("Multi-Scale Plant Representation Lab"))
	_assert(instance.status_label.text.contains("truth_unchanged=true"))
	_assert(instance.plant_root != null)
	_assert(instance.camera != null)
	for index in range(Representation.TIER_ORDER.size()):
		instance.tier_index = index
		instance._refresh()
		await process_frame
		await process_frame
		_assert(instance.status_label.text.contains(instance._friendly_tier(Representation.TIER_ORDER[index])))
		_assert(instance.status_label.text.contains("representation_hash="))
		_assert(instance.status_label.text.contains("truth_unchanged=true"))
		_assert(instance.plant_root.get_child_count() >= 1)
	instance.tier_index = 4
	instance._refresh()
	await process_frame
	await process_frame
	_assert(instance.status_label.text.contains("POPULATION_ONLY"))
	_assert(instance.status_label.text.contains("materialized_growth_graphs=0"))
	instance.queue_free()
	await process_frame
	print("ECO.PH5-S3 Visual Lab Smoke: PASS (%d assertions)" % assertions)
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
