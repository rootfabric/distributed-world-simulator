extends SceneTree

const Representation = preload("res://scripts/research/ecology/plant_multiscale_representation_v1.gd")
var assertions := 0

func _init() -> void:
	var packed := load("res://scenes/labs/ecology/eco_ph5_s4_multiscale_lod_lab.tscn") as PackedScene
	_assert(packed != null)
	var instance := packed.instantiate()
	_assert(instance != null)
	root.add_child(instance)
	await process_frame
	await process_frame
	_assert(instance.results.size() == 7)
	_assert(instance.status_label != null)
	_assert(instance.status_label.text.contains("Multi-scale LOD"))
	_assert(instance.plant_root != null)
	_assert(instance.camera != null)
	var first_truth := String(instance.last_truth_hash)
	_assert(first_truth.length() == 64)

	for index in range(Representation.TIER_ORDER.size()):
		instance.tier_index = index
		instance._refresh()
		await process_frame
		var tier: String = Representation.TIER_ORDER[index]
		_assert(instance.status_label.text.contains(tier))
		_assert(String(instance.last_representation.get("tier", "")) == tier)
		_assert(bool(instance.last_materialization.get("success", false)))
		_assert(String(instance.last_materialization.get("ecological_truth_hash", "")) == first_truth)
		if tier == Representation.TIER_2_CANOPY:
			_assert(instance.plant_root.get_child_count() == 1)
			_assert((instance.plant_root.get_child(0) as MeshInstance3D).mesh is SphereMesh)
		elif tier == Representation.TIER_3_IMPOSTOR:
			_assert(instance.plant_root.get_child_count() == 1)
			var mesh := (instance.plant_root.get_child(0) as MeshInstance3D).mesh
			_assert(mesh is QuadMesh)
			_assert(mesh.material is BaseMaterial3D)
			_assert((mesh.material as BaseMaterial3D).billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED)
		elif tier == Representation.TIER_4_POPULATION_ONLY:
			_assert(instance.plant_root.get_child_count() == 0)
			_assert(not bool(instance.last_materialization["individual_node_required"]))
		else:
			_assert(instance.plant_root.get_child_count() >= 1)

	instance.environment_index = 1
	instance.tier_index = 0
	instance._refresh()
	await process_frame
	_assert(String(instance.last_truth_hash).length() == 64)
	_assert(String(instance.last_truth_hash) != first_truth)
	instance.queue_free()
	await process_frame
	print("ECO.PH5-S4 Multiscale Visual Lab Smoke: PASS (%d assertions)" % assertions)
	quit(0)

func _assert(condition: bool) -> void:
	assert(condition)
	assertions += 1
