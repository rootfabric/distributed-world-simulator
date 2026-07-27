extends SceneTree

const GravityMath = preload(
	"res://scripts/simulation/gravity/gravity_math.gd"
)
const GravityField = preload(
	"res://scripts/simulation/gravity/gravity_field.gd"
)
const GravityTrajectoryIntegrator = preload(
	"res://scripts/simulation/gravity/gravity_trajectory_integrator.gd"
)
const CelestialSystem = preload(
	"res://scripts/world/planetary/celestial_system.gd"
)

const EARTH_RADIUS_M: float = 6_371_000.0
const EARTH_MU_M3_S2: float = 398_048_402_912_650.0
const MOON_RADIUS_M: float = 1_737_400.0
const MOON_MU_M3_S2: float = 4_890_065_191_200.0

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_inverse_square_and_interior_model()
	_test_superposition_and_dominant_source()
	_test_celestial_reference_frame_compensation()
	_test_test_particle_orbit_integrator()
	_finish()


func _test_inverse_square_and_interior_model() -> void:
	var field = GravityField.new()
	_assert(
		field.setup_static_sources([{
			"id": "moon",
			"radius_m": MOON_RADIUS_M,
			"gravitational_parameter_m3_s2": MOON_MU_M3_S2,
			"center_m": [0.0, 0.0, 0.0],
			"interior_model": "uniform_sphere",
		}], "moon/inertial"),
		"Static Moon gravity field must initialize"
	)
	var surface: Vector3 = field.get_acceleration_at_position(
		Vector3(MOON_RADIUS_M, 0.0, 0.0),
		"moon/inertial"
	)
	_assert_vector_close(
		surface,
		Vector3(-1.62, 0.0, 0.0),
		0.000001,
		"Moon surface acceleration must point to the centre"
	)
	var double_radius: Vector3 = field.get_acceleration_at_position(
		Vector3(MOON_RADIUS_M * 2.0, 0.0, 0.0),
		"moon/inertial"
	)
	_assert_close(
		double_radius.length(),
		0.405,
		0.000001,
		"Gravity at two radii must be one quarter of surface gravity"
	)
	var half_radius: Vector3 = field.get_acceleration_at_position(
		Vector3(MOON_RADIUS_M * 0.5, 0.0, 0.0),
		"moon/inertial"
	)
	_assert_close(
		half_radius.length(),
		0.81,
		0.000001,
		"Uniform-sphere interior field must decrease linearly toward the centre"
	)
	_assert(
		field.get_acceleration_at_position(Vector3.ZERO, "moon/inertial").is_zero_approx(),
		"Gravity must be finite and zero at the exact centre"
	)
	_assert_close(
		field.get_escape_speed_mps("moon", MOON_RADIUS_M),
		field.get_circular_orbit_speed_mps("moon", MOON_RADIUS_M) * sqrt(2.0),
		0.000001,
		"Escape speed must be sqrt(2) times circular speed at the same radius"
	)


func _test_superposition_and_dominant_source() -> void:
	var field = GravityField.new()
	_assert(
		field.setup_static_sources([
			{
				"id": "left",
				"radius_m": 10.0,
				"gravitational_parameter_m3_s2": 100_000.0,
				"center_m": [-1000.0, 0.0, 0.0],
			},
			{
				"id": "right",
				"radius_m": 10.0,
				"gravitational_parameter_m3_s2": 100_000.0,
				"center_m": [1000.0, 0.0, 0.0],
			},
		], "test/root"),
		"Two-source field must initialize"
	)
	_assert_vector_close(
		field.get_acceleration_at_position(Vector3.ZERO, "test/root"),
		Vector3.ZERO,
		0.000000001,
		"Equal opposite sources must cancel at the midpoint"
	)
	_assert(
		field.get_dominant_source_id_at_position(
			Vector3(900.0, 0.0, 0.0),
			"test/root"
		) == "right",
		"Nearest strong source must dominate the local field"
	)
	var contributions: Array = field.get_contributions_at_position(
		Vector3(900.0, 0.0, 0.0),
		"test/root"
	)
	_assert(contributions.size() == 2, "Gravity diagnostics must expose every source contribution")
	_assert(
		field.create_snapshot().get("superposition", false),
		"Gravity snapshot must declare superposition"
	)


func _test_celestial_reference_frame_compensation() -> void:
	var system = CelestialSystem.new()
	get_root().add_child(system)
	_assert(
		system.setup(["earth", "moon"]),
		"Celestial system with gravity field must initialize"
	)
	var earth_frame: String = system.get_body_inertial_frame_id("earth")
	var earth_surface: Vector3 = system.get_gravity_acceleration_at_position(
		Vector3(EARTH_RADIUS_M, 0.0, 0.0),
		earth_frame,
		0.0
	)
	_assert_close(
		earth_surface.length(),
		9.80665,
		0.0002,
		"Earth-relative surface field must preserve configured gravity"
	)
	_assert(
		earth_surface.x < -9.80,
		"Earth surface acceleration must point toward the Earth centre"
	)
	var earth_center_relative: Vector3 = system.get_gravity_acceleration_at_position(
		Vector3.ZERO,
		earth_frame,
		0.0
	)
	_assert(
		earth_center_relative.length() < 0.000000001,
		"External common acceleration must cancel at the reference body centre"
	)
	var earth_center_root: Vector3 = system.get_body_center("earth", 0.0)
	var earth_center_absolute: Vector3 = system.get_gravity_acceleration_at_position(
		earth_center_root,
		system.get_root_frame_id(),
		0.0
	)
	_assert(
		earth_center_absolute.length() > 0.001,
		"Absolute barycentric field at Earth must retain solar acceleration"
	)
	_assert(
		system.get_gravity_field().get_dominant_source_id_at_position(
			Vector3(EARTH_RADIUS_M + 1000.0, 0.0, 0.0),
			earth_frame,
			0.0
		) == "earth",
		"Earth must dominate its near-surface gravity well"
	)
	var snapshot: Dictionary = system.create_snapshot()
	_assert(
		Dictionary(snapshot.get("gravity_field", {})).get("source_count", 0) == 3,
		"Celestial runtime snapshot must include Sun, Earth and Moon gravity sources"
	)
	var observer_snapshot: Dictionary = system.get_space_snapshot(earth_center_root)
	_assert(
		String(observer_snapshot.get("gravity_dominant_source_id", "")) == "sun",
		"Barycentric observer snapshot at Earth centre must report the dominant absolute source"
	)
	_assert(
		Array(observer_snapshot.get("gravity_acceleration_root_mps2", [])).size() == 3,
		"Observer snapshot must expose the absolute gravity vector"
	)

	var dynamic_integrator = GravityTrajectoryIntegrator.new()
	_assert(
		dynamic_integrator.setup(system.get_gravity_field()),
		"Celestial gravity field must be usable by the generic trajectory integrator"
	)
	var orbital_radius_m: float = EARTH_RADIUS_M + 400_000.0
	var circular_speed_mps: float = system.get_gravity_field().get_circular_orbit_speed_mps(
		"earth",
		orbital_radius_m
	)
	var orbital_period_s: float = TAU * orbital_radius_m / circular_speed_mps
	var delta_s: float = 10.0
	var dynamic_result: Dictionary = dynamic_integrator.propagate(
		Vector3(orbital_radius_m, 0.0, 0.0),
		Vector3(0.0, 0.0, circular_speed_mps),
		delta_s,
		int(round(orbital_period_s / delta_s)),
		earth_frame,
		0.0,
		"earth"
	)
	_assert(
		bool(dynamic_result.get("success", false)),
		"A test particle must propagate in the moving Earth reference frame"
	)
	var dynamic_final_position: Vector3 = _array_to_vector(
		dynamic_result.get("position_m", [])
	)
	_assert(
		absf(dynamic_final_position.length() - orbital_radius_m) < 80_000.0,
		"Earth gravity well must retain a natural satellite while Sun and Moon move"
	)
	system.free()


func _test_test_particle_orbit_integrator() -> void:
	var field = GravityField.new()
	_assert(
		field.setup_static_sources([{
			"id": "earth",
			"radius_m": EARTH_RADIUS_M,
			"gravitational_parameter_m3_s2": EARTH_MU_M3_S2,
			"center_m": [0.0, 0.0, 0.0],
		}], "earth/inertial"),
		"Isolated Earth field must initialize"
	)
	var orbital_radius_m: float = EARTH_RADIUS_M + 400_000.0
	var circular_speed_mps: float = field.get_circular_orbit_speed_mps(
		"earth",
		orbital_radius_m
	)
	var orbital_period_s: float = TAU * orbital_radius_m / circular_speed_mps
	var delta_s: float = 5.0
	var step_count: int = int(round(orbital_period_s / delta_s))
	var integrator = GravityTrajectoryIntegrator.new()
	_assert(integrator.setup(field), "Gravity trajectory integrator must accept a field")
	var result: Dictionary = integrator.propagate(
		Vector3(orbital_radius_m, 0.0, 0.0),
		Vector3(0.0, 0.0, circular_speed_mps),
		delta_s,
		step_count,
		"earth/inertial"
	)
	_assert(bool(result.get("success", false)), "Circular test-particle propagation must succeed")
	var final_position: Vector3 = _array_to_vector(result.get("position_m", []))
	var relative_radius_error: float = absf(final_position.length() - orbital_radius_m) / orbital_radius_m
	_assert(
		relative_radius_error < 0.0001,
		"Velocity-Verlet orbit must preserve radius over approximately one revolution; error=%s"
		% relative_radius_error
	)
	_assert(
		final_position.distance_to(Vector3(orbital_radius_m, 0.0, 0.0)) < 80_000.0,
		"Test particle must return near its initial orbital position after one period"
	)


func _array_to_vector(value) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _assert_vector_close(
	actual: Vector3,
	expected: Vector3,
	tolerance: float,
	message: String
) -> void:
	_assert(
		actual.distance_to(expected) <= tolerance,
		"%s; actual=%s expected=%s" % [message, actual, expected]
	)


func _assert_close(
	actual: float,
	expected: float,
	tolerance: float,
	message: String
) -> void:
	_assert(
		absf(actual - expected) <= tolerance,
		"%s; actual=%s expected=%s" % [message, actual, expected]
	)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("Gravity field and trajectory: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"Gravity field and trajectory: FAIL (%d failures, %d assertions)"
		% [failures.size(), assertions]
	)
	quit(1)
