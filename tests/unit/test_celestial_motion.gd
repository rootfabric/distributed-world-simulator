extends SceneTree

const CelestialSystemScript = preload(
	"res://scripts/world/planetary/celestial_system.gd"
)
const SimulationClockScript = preload(
	"res://scripts/simulation/time/simulation_clock.gd"
)

var failures: Array[String] = []


func _init() -> void:
	var clock = SimulationClockScript.new()
	clock.setup({"initial_time_s": 0.0, "paused": true})
	var system = CelestialSystemScript.new()
	_assert(system.setup(["earth"], clock), "Celestial system setup failed.")

	var earth_at_zero: Vector3 = system.get_body_center("earth", 0.0)
	var earth_at_quarter_year: Vector3 = system.get_body_center(
		"earth",
		31558149.7635456 * 0.25
	)
	_assert(
		earth_at_zero.distance_to(earth_at_quarter_year) > 100000000000.0,
		"Earth analytical orbit did not advance."
	)

	var moon_distance_zero: float = system.get_distance_between("earth", "moon", 0.0)
	var moon_distance_later: float = system.get_distance_between(
		"earth",
		"moon",
		2360591.5 * 0.31
	)
	_assert(
		moon_distance_zero > 350000000.0 and moon_distance_zero < 410000000.0,
		"Moon distance at epoch is outside the configured elliptic orbit."
	)
	_assert(
		moon_distance_later > 350000000.0 and moon_distance_later < 410000000.0,
		"Moon distance later is outside the configured elliptic orbit."
	)

	var earth_fixed: String = system.get_body_fixed_frame_id("earth")
	var root_frame: String = system.get_root_frame_id()
	var surface_point := Vector3(1250.0, 6371018.0, -420.0)
	var root_point_later: Vector3 = system.transform_point(
		surface_point,
		earth_fixed,
		root_frame,
		90000.0
	)
	var restored_surface: Vector3 = system.transform_point(
		root_point_later,
		root_frame,
		earth_fixed,
		90000.0
	)
	_assert(
		restored_surface.distance_to(surface_point) < 0.001,
		"Earth surface coordinates changed after root-frame roundtrip."
	)

	var moon_fixed: String = system.get_body_fixed_frame_id("moon")
	var earth_inertial: String = system.get_body_inertial_frame_id("earth")
	var sample_time: float = 123456.0
	var moon_center_earth_frame: Vector3 = system.transform_point(
		Vector3.ZERO,
		system.get_body_inertial_frame_id("moon"),
		earth_inertial,
		sample_time
	)
	var moon_local_x_in_earth_frame: Vector3 = system.transform_direction(
		Vector3.RIGHT,
		moon_fixed,
		earth_inertial,
		sample_time
	).normalized()
	var direction_to_earth: Vector3 = (-moon_center_earth_frame).normalized()
	_assert(
		moon_local_x_in_earth_frame.dot(direction_to_earth) > 0.999999,
		"Tidally locked Moon frame does not face Earth."
	)

	var sampled_ref: Dictionary = system.create_spatial_ref(
		earth_fixed,
		surface_point,
		Basis.IDENTITY,
		Vector3.ZERO,
		Vector3.ZERO,
		90000.0
	)
	clock.set_time(120000.0)
	var sampled_root_ref: Dictionary = system.transform_spatial_ref(
		sampled_ref,
		root_frame
	)
	_assert(
		absf(float(sampled_root_ref.get("sample_time_s", 0.0)) - 90000.0) < 0.000001,
		"SpatialRef default reframe ignored the state sample time."
	)

	var reused_system = CelestialSystemScript.new()
	_assert(reused_system.setup(["earth"]), "Standalone celestial setup failed.")
	var external_clock = SimulationClockScript.new()
	external_clock.setup({"initial_time_s": 10.0})
	_assert(
		reused_system.setup(["earth"], external_clock, "scenario-a"),
		"Celestial system reconfiguration failed."
	)
	reused_system._process(1.0)
	_assert(
		is_equal_approx(external_clock.get_time_seconds(), 10.0),
		"Reconfigured celestial system advanced an externally owned clock."
	)
	_assert(
		String(reused_system.create_snapshot().get("instance_id", "")) == "scenario-a",
		"Celestial system did not propagate the new instance identity."
	)
	reused_system.free()
	system.free()
	if failures.is_empty():
		print("Celestial motion tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Celestial motion tests: FAIL (%d)" % failures.size())
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
