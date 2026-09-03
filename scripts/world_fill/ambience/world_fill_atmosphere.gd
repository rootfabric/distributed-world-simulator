class_name WorldFillAtmosphere
extends Node3D

## WF0.4 Ambient World Clock / Atmosphere (WORLD FILL train).
##
## Derives a presentation clock and atmosphere from a read-only simulation
## time projection. Owns one WorldEnvironment and one DirectionalLight3D.
##
## Guarantees:
## - PRESENTATION-ONLY: no movement penalties, no canonical temperature, no
##   weather damage, no sleep rules, no authoritative storm state.
## - DETERMINISTIC: same clock input => same preset => same environment.
## - CLOCK-DERIVED SET IS CLOSED: only night/dawn/clear are ever derived
##   from the clock; dust and storm exist only as explicit overrides.
## - FAIL-SOFT: unknown presets fall back to clear and say so in the report.

const SCHEMA := "world_fill.atmosphere_report.v1"

const CLOCK_PRESETS: Array[String] = ["night", "dawn", "clear"]

const PRESETS := {
	"clear": {
		"sun_elevation_deg": -42.0,
		"sun_azimuth_deg": -28.0,
		"sun_energy": 1.7,
		"sun_color": Color(1.0, 0.96, 0.9),
		"ambient_color": Color(0.18, 0.2, 0.26),
		"ambient_energy": 0.45,
		"background_color": Color(0.008, 0.01, 0.018),
		"fog_enabled": false,
		"fog_density": 0.0,
		"fog_color": Color(0.7, 0.7, 0.75),
		"exposure": 1.0,
		"wind_audio": "wind_soft",
	},
	"dust": {
		"sun_elevation_deg": -18.0,
		"sun_azimuth_deg": 15.0,
		"sun_energy": 0.9,
		"sun_color": Color(0.9, 0.75, 0.55),
		"ambient_color": Color(0.35, 0.28, 0.2),
		"ambient_energy": 0.5,
		"background_color": Color(0.09, 0.07, 0.05),
		"fog_enabled": true,
		"fog_density": 0.035,
		"fog_color": Color(0.45, 0.35, 0.24),
		"exposure": 0.9,
		"wind_audio": "wind_dust",
	},
	"storm": {
		"sun_elevation_deg": -25.0,
		"sun_azimuth_deg": 0.0,
		"sun_energy": 0.5,
		"sun_color": Color(0.6, 0.65, 0.7),
		"ambient_color": Color(0.12, 0.13, 0.16),
		"ambient_energy": 0.35,
		"background_color": Color(0.03, 0.035, 0.045),
		"fog_enabled": true,
		"fog_density": 0.06,
		"fog_color": Color(0.25, 0.27, 0.3),
		"exposure": 0.8,
		"wind_audio": "wind_gale",
	},
	"dawn": {
		"sun_elevation_deg": -8.0,
		"sun_azimuth_deg": -75.0,
		"sun_energy": 1.1,
		"sun_color": Color(1.0, 0.7, 0.45),
		"ambient_color": Color(0.3, 0.22, 0.2),
		"ambient_energy": 0.4,
		"background_color": Color(0.05, 0.03, 0.035),
		"fog_enabled": false,
		"fog_density": 0.0,
		"fog_color": Color(0.8, 0.6, 0.5),
		"exposure": 1.0,
		"wind_audio": "wind_soft",
	},
	"night": {
		"sun_elevation_deg": -60.0,
		"sun_azimuth_deg": 40.0,
		"sun_energy": 0.25,
		"sun_color": Color(0.55, 0.62, 0.85),
		"ambient_color": Color(0.05, 0.06, 0.1),
		"ambient_energy": 0.25,
		"background_color": Color(0.002, 0.003, 0.008),
		"fog_enabled": false,
		"fog_density": 0.0,
		"fog_color": Color(0.1, 0.12, 0.18),
		"exposure": 1.1,
		"wind_audio": "wind_night",
	},
}

const DEFAULT_PRESET := "clear"

var _environment_node := WorldEnvironment.new()
var _sun := DirectionalLight3D.new()
var _current_preset := ""
var _fallback_used := false


func apply_preset(preset_name: String) -> Dictionary:
	var preset_key := preset_name
	_fallback_used = false
	if not PRESETS.has(preset_key):
		preset_key = DEFAULT_PRESET
		_fallback_used = preset_name != DEFAULT_PRESET
	var preset: Dictionary = PRESETS[preset_key]
	_current_preset = preset_key

	_environment_node.name = "AtmosphereEnvironment"
	if _environment_node.environment == null:
		_environment_node.environment = Environment.new()
	var environment := _environment_node.environment as Environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = preset["background_color"]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = preset["ambient_color"]
	environment.ambient_light_energy = preset["ambient_energy"]
	environment.fog_enabled = preset["fog_enabled"]
	environment.fog_density = preset["fog_density"]
	environment.fog_light_color = preset["fog_color"]
	environment.tonemap_exposure = preset["exposure"]
	if _environment_node.get_parent() == null:
		add_child(_environment_node)

	_sun.name = "AtmosphereSun"
	_sun.rotation_degrees = Vector3(
		float(preset["sun_elevation_deg"]),
		float(preset["sun_azimuth_deg"]),
		0.0
	)
	_sun.light_energy = preset["sun_energy"]
	_sun.light_color = preset["sun_color"]
	if _sun.get_parent() == null:
		add_child(_sun)

	return report()


func apply_clock(clock: Dictionary) -> Dictionary:
	var day_fraction := float(clock.get("day_fraction", 0.5))
	day_fraction = clampf(day_fraction, 0.0, 1.0)
	var derived := ""
	if day_fraction < 0.2:
		derived = "night"
	elif day_fraction < 0.3:
		derived = "dawn"
	elif day_fraction < 0.85:
		derived = "clear"
	else:
		derived = "night"
	return apply_preset(derived)


func report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"preset": _current_preset,
		"fallback_used": _fallback_used,
		"presentation_only": true,
		"wind_audio": String(PRESETS[_current_preset]["wind_audio"]),
		"sun_energy": float(PRESETS[_current_preset]["sun_energy"]),
		"fog_density": float(PRESETS[_current_preset]["fog_density"]),
	}
