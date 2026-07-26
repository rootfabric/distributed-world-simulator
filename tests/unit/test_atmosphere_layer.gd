extends SceneTree

const CelestialSystemScript = preload(
	"res://scripts/world/planetary/celestial_system.gd"
)
const PlanetAtmosphereScript = preload(
	"res://scripts/world/atmosphere/planet_atmosphere.gd"
)

var failures: Array[String] = []


func _init() -> void:
	var system = CelestialSystemScript.new()
	root.add_child(system)
	_assert(system.setup(), "Celestial system config failed to load.")
	_assert(
		system.get_atmosphere_config_path("earth") == "res://config/atmospheres/earth.json",
		"Earth atmosphere is not registered on the celestial body contract."
	)
	_assert(
		system.get_atmosphere_config_path("moon").is_empty(),
		"Moon unexpectedly received an atmosphere."
	)

	var atmosphere = PlanetAtmosphereScript.new()
	root.add_child(atmosphere)
	_assert(
		atmosphere.setup(
			"res://config/atmospheres/earth.json",
			system,
			null,
			null
		),
		"Earth atmosphere setup failed."
	)
	_assert(
		atmosphere.get_plugin_ids() == ["earth_low_clouds"],
		"Cloud layer was not loaded as an atmosphere plugin."
	)

	var earth_radius: float = system.get_body_radius("earth")
	var earth_center: Vector3 = system.get_body_center("earth")
	var near_surface_state: Dictionary = atmosphere.update_for_observer(
		earth_center + Vector3(earth_radius + 1000.0, 0.0, 0.0),
		null,
		0.016
	)
	_assert(bool(near_surface_state.get("active", false)), "Atmosphere is inactive at 1 km.")
	_assert(
		float(near_surface_state.get("intensity", 0.0)) > 0.95,
		"Atmosphere intensity is unexpectedly weak near the surface."
	)

	var upper_state: Dictionary = atmosphere.update_for_observer(
		earth_center + Vector3(earth_radius + 85000.0, 0.0, 0.0),
		null,
		0.016
	)
	_assert(bool(upper_state.get("active", false)), "Atmosphere should still fade at 85 km.")
	_assert(
		float(upper_state.get("intensity", 1.0)) < 0.72,
		"Upper-atmosphere intensity does not decrease with altitude."
	)

	var space_state: Dictionary = atmosphere.update_for_observer(
		earth_center + Vector3(earth_radius + 120000.0, 0.0, 0.0),
		null,
		0.016
	)
	_assert(not bool(space_state.get("active", true)), "Atmosphere remains active above 100 km.")

	var cloud_config: Dictionary = _load_json(
		"res://config/atmosphere_plugins/earth_low_clouds.json"
	)
	_assert(
		is_equal_approx(float(cloud_config.get("altitude_m", 0.0)), 4000.0),
		"Earth cloud layer is not configured at 4 km."
	)

	if failures.is_empty():
		print("Atmosphere architecture tests: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("Atmosphere architecture tests: FAIL (%d)" % failures.size())
	quit(1)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
