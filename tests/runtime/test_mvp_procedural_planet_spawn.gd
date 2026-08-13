extends SceneTree

const EarthWorldScript = preload("res://scripts/world/earth/procedural_earth_world.gd")
const EarthAppScript = preload("res://scripts/app/earth_app.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world = EarthWorldScript.new()
	get_root().add_child(world)
	_assert(world.setup(), "Procedural Earth setup failed.")
	if not world.initialized:
		_finish(world)
		return

	var first_direction: Vector3 = world.get_canonical_spawn_direction()
	var second_direction: Vector3 = world.get_canonical_spawn_direction()
	var altitude_m: float = world.get_canonical_spawn_altitude_m()
	var snapshot: Dictionary = world.get_canonical_spawn_snapshot()
	var surface: Vector3 = world.get_surface_point(first_direction)
	var spawn_position: Vector3 = surface + first_direction * altitude_m

	_assert(first_direction.length_squared() > 0.999, "Canonical spawn direction is not normalized.")
	_assert(first_direction.distance_to(second_direction) < 0.000001, "Canonical spawn direction is not deterministic.")
	_assert(String(snapshot.get("id", "")) == "earth-default-spawn", "Canonical spawn id drifted.")
	_assert(is_equal_approx(float(snapshot.get("latitude_deg", -1.0)), 45.0), "Canonical spawn latitude drifted.")
	_assert(is_equal_approx(float(snapshot.get("longitude_deg", -1.0)), 25.0), "Canonical spawn longitude drifted.")
	_assert(is_equal_approx(altitude_m, 450.0), "Canonical spawn altitude drifted.")
	_assert(absf(world.get_altitude(spawn_position) - altitude_m) < 0.01, "Spawn altitude is not above the procedural surface.")
	_assert(
		spawn_position.distance_to(surface) > 449.99,
		"Spawn position does not preserve configured clearance above the procedural surface."
	)

	world.queue_free()
	var app = EarthAppScript.new()
	get_root().add_child(app)
	var app_explorer = app.get("earth_explorer")
	if app_explorer != null:
		app_explorer.set_physics_process(false)
		app_explorer.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	var app_snapshot: Dictionary = app.create_runtime_snapshot()
	var app_spawn: Dictionary = Dictionary(app_snapshot.get("canonical_spawn", {}))
	var app_test: Dictionary = app.call("_test_earth_canonical_spawn")
	_assert(bool(app.get("initialized")), "Earth runtime did not initialize.")
	_assert(String(app_spawn.get("id", "")) == "earth-default-spawn", "Earth runtime did not expose canonical spawn.")
	_assert(bool(app_test.get("passed", false)), "Earth runtime did not start at canonical spawn.")
	app.queue_free()
	_finish(null)


func _finish(world) -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	if failures.is_empty():
		print("MVP procedural planet spawn: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MVP procedural planet spawn: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
