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
	_check(manager.has_method("request_predicted_surface"), "predictive request method missing", failures)
	_check(manager.has_method("create_snapshot"), "streaming snapshot method missing", failures)
	_check(manager.has_method("run_mini_test"), "runtime mini-test missing", failures)
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
