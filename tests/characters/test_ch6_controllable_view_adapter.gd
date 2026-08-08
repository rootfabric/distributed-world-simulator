extends SceneTree

const ControllableViewAdapter = preload("res://scripts/characters/presentation/controllable_view_adapter.gd")
const DronePresenter = preload("res://tests/fixtures/ch6_test_drone_presenter.gd")

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var host := Node3D.new()
	root.add_child(host)

	var drone = DronePresenter.new()
	drone.name = "ControlledDrone"
	host.add_child(drone)

	var first_person_camera := Camera3D.new()
	first_person_camera.name = "DroneFirstPersonCamera"
	host.add_child(first_person_camera)
	var third_person_camera := Camera3D.new()
	third_person_camera.name = "DroneThirdPersonCamera"
	host.add_child(third_person_camera)

	var adapter = ControllableViewAdapter.new()
	adapter.name = "DroneViewAdapter"
	host.add_child(adapter)
	var bind_result: Dictionary = adapter.bind_presentation(drone)
	_assert(bool(bind_result.get("success", false)), "Drone presentation bind failed")
	adapter.bind_cameras(first_person_camera, third_person_camera)

	var report: Dictionary = adapter.create_report()
	_assert(String(report.get("schema", "")) == "planet_simulator.controllable_view_adapter.v1", "Unexpected generic adapter schema")
	_assert(String(report.get("profile_id", "")) == "test_drone", "Drone profile was not resolved through the presenter contract")
	_assert(String(report.get("entity_kind", "")) == "drone", "Generic adapter assumes a humanoid entity kind")
	_assert(String(report.get("first_person_policy", "")) == "HIDE_WORLD_MODEL", "Drone first-person policy is not camera-layer suppression")
	_assert(int(report.get("world_visual_count", 0)) == 5, "Drone world visuals were not discovered generically")
	_assert(bool(report.get("world_hidden_from_first_person", false)), "First-person camera still renders the drone world body")
	_assert(bool(report.get("world_visible_to_third_person", false)), "Third-person camera lost the drone world body")
	_assert(drone.visible, "Generic adapter disabled the whole controlled entity")

	var world_mask := int(report.get("world_render_layer_mask", 0))
	_assert(world_mask != 0, "World presentation render layer is invalid")
	_assert((first_person_camera.cull_mask & world_mask) == 0, "First-person camera cull mask contains the world body layer")
	_assert((third_person_camera.cull_mask & world_mask) != 0, "Third-person camera cull mask excludes the world body layer")
	for visual in _collect_visuals(drone.get_world_visual_root()):
		_assert(visual.layers == world_mask, "A drone visual was not moved to the dedicated world presentation layer")

	adapter.set_first_person_enabled(true)
	report = adapter.create_report()
	_assert(bool(report.get("first_person_enabled", false)), "Generic first-person state did not enable")
	_assert(drone.visible, "First-person mode hid the drone globally instead of only from its local camera")
	_assert(bool(report.get("world_animation_preserved", false)), "World presentation update contract was disabled in first person")
	_assert(bool(report.get("shadow_caster_preserved", false)), "Hidden world body was not kept as a shadow-capable world presentation")

	adapter.set_first_person_enabled(false)
	_assert(drone.visible, "Third-person restore failed for a non-humanoid presenter")

	var source := FileAccess.get_file_as_string("res://scripts/characters/presentation/controllable_view_adapter.gd")
	_assert(not source.contains("Quaternius"), "Generic adapter depends on a specific asset pack")
	_assert(not source.contains("Skeleton3D"), "Generic adapter depends on a skeleton")
	_assert(not source.contains("head_bone"), "Generic adapter depends on a humanoid head bone")
	_assert(not source.contains("Input."), "Generic presentation adapter gained input ownership")
	_assert(not source.contains("move_and_slide"), "Generic presentation adapter gained movement ownership")

	host.queue_free()
	_finish()


func _collect_visuals(node: Node) -> Array[VisualInstance3D]:
	var result: Array[VisualInstance3D] = []
	_collect_visuals_recursive(node, result)
	return result


func _collect_visuals_recursive(node: Node, output: Array[VisualInstance3D]) -> void:
	if node is VisualInstance3D:
		output.append(node as VisualInstance3D)
	for child in node.get_children():
		_collect_visuals_recursive(child, output)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CH6 controllable view adapter: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CH6 controllable view adapter: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
