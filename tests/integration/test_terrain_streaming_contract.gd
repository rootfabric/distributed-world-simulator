extends SceneTree

const TerrainStreamingManagerScript = preload(
	"res://scripts/world/terrain/streaming/terrain_streaming_manager.gd"
)
const MockMoonWorldScript = preload("res://tests/support/mock_moon_world.gd")


func _init() -> void:
	var failures: Array[String] = []
	_check(FileAccess.file_exists("res://config/terrain_streaming.json"), "streaming config missing", failures)
	var config_file := FileAccess.open("res://config/terrain_streaming.json", FileAccess.READ)
	if config_file != null:
		var parsed = JSON.parse_string(config_file.get_as_text())
		_check(parsed is Dictionary, "streaming config is not JSON object", failures)
		if parsed is Dictionary:
			_check(
				String(parsed.get("schema", "")) == "lunar.terrain_streaming_config.v1",
				"unexpected streaming config schema",
				failures
			)
			_check(float(parsed.get("stream_cell_size_m", 0.0)) >= 256.0, "stream cell is too small", failures)
			_check(float(parsed.get("prediction_seconds", 0.0)) > 0.0, "prediction disabled", failures)
			_check(
				float(parsed.get("minimum_predictive_speed_mps", 0.0)) > 0.0,
				"stationary movement hysteresis missing",
				failures
			)
			_check(
				float(parsed.get("stationary_recenter_distance_m", 0.0))
				> float(parsed.get("prefetch_trigger_distance_m", 0.0)),
				"streaming hysteresis ranges are invalid",
				failures
			)
			_check(
				int(parsed.get("collision_triangles_per_tile", 0)) >= 256,
				"tiled collision configuration missing",
				failures
			)
			_check(
				int(parsed.get("recent_surface_cache_capacity", 0)) >= 2,
				"recent surface cache is not configured",
				failures
			)
			_check(
				int(parsed.get("max_pinned_surface_cells", 0)) >= 1,
				"pinned landmark cells are not configured",
				failures
			)
			_check(
				float(parsed.get("pinned_return_trigger_distance_m", 0.0))
				>= float(parsed.get("stream_cell_size_m", 0.0)),
				"pinned return trigger is too small",
				failures
			)

	var mock_world = MockMoonWorldScript.new()
	var manager = TerrainStreamingManagerScript.new()
	manager.setup(mock_world, null, null)
	var direction_a := Vector3(1.0, 0.12, 0.08).normalized()
	var east := Vector3.UP.cross(direction_a).normalized()
	var direction_b := (
		direction_a + east * (900.0 / mock_world.get_moon_radius())
	).normalized()
	var descriptor_a: Dictionary = manager.get_cell_descriptor(direction_a)
	var descriptor_a_scaled: Dictionary = manager.get_cell_descriptor(direction_a * 5.0)
	var descriptor_b: Dictionary = manager.get_cell_descriptor(direction_b)
	_check(
		String(descriptor_a.get("cell_id", "")) == String(descriptor_a_scaled.get("cell_id", "")),
		"terrain cell depends on vector length",
		failures
	)
	_check(
		String(descriptor_a.get("cell_id", "")) != String(descriptor_b.get("cell_id", "")),
		"900 m movement did not cross terrain streaming cell",
		failures
	)
	manager.mark_active_surface(direction_a)
	manager.request_predicted_surface(
		direction_a * mock_world.get_moon_radius(),
		east * 0.4,
		true,
		false,
		"test_stationary_hysteresis"
	)
	var stationary_snapshot: Dictionary = manager.create_snapshot()
	var skip_counts: Dictionary = stationary_snapshot.get("prediction_skip_counts", {})
	_check(
		int(skip_counts.get("stationary_hysteresis", 0)) > 0,
		"low-speed stationary hysteresis did not suppress a request",
		failures
	)
	_check(manager.has_method("request_predicted_surface"), "predictive request method missing", failures)
	_check(manager.has_method("create_snapshot"), "streaming snapshot method missing", failures)
	_check(manager.has_method("run_mini_test"), "runtime mini-test missing", failures)
	_check(manager.has_method("mark_active_surface"), "active surface tracking missing", failures)
	_check(
		manager.has_method("request_predicted_surface"),
		"predictive hysteresis entrypoint missing",
		failures
	)
	_check(
		manager.has_method("set_pinned_surface_directions"),
		"pinned terrain cell API missing",
		failures
	)
	var terrain_script = load("res://scripts/world/terrain/procedural_moon_terrain.gd")
	var terrain_instance = terrain_script.new()
	_check(
		terrain_instance.has_method("streaming_create_collision_root"),
		"tiled collision root API missing",
		failures
	)
	_check(
		terrain_instance.has_method("streaming_add_collision_tile"),
		"tiled collision tile API missing",
		failures
	)
	_check(
		terrain_instance.has_method("register_streaming_actor"),
		"streaming actor reconciliation API missing",
		failures
	)
	_check(
		terrain_instance.has_method("streaming_has_cached_surface"),
		"recent surface cache lookup API missing",
		failures
	)
	_check(
		terrain_instance.has_method("streaming_activate_cached_surface"),
		"recent surface cache activation API missing",
		failures
	)
	_check(
		terrain_instance.has_method("get_recent_surface_cache_snapshot"),
		"recent surface cache diagnostics API missing",
		failures
	)
	terrain_instance.free()
	manager.free()
	mock_world.free()

	if failures.is_empty():
		print("Terrain streaming contract tests: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("Terrain streaming contract tests: FAIL (%d)" % failures.size())
		quit(1)


func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
