extends "res://scripts/labs/ecology/eco_environment_provider.gd"

const EnvironmentSample = preload("res://scripts/research/ecology/environment_sample_v1.gd")
const DEFAULT_SEED := 73191
const ENVIRONMENT_REVISION := "eco-vis1.1-lab-environment-v1"
const TERRAIN_HALF_M := 250.0

var _seed: int
var _seed_phase: float

func _init(seed: int = DEFAULT_SEED) -> void:
	_seed = seed
	_seed_phase = TAU * float(posmod(seed, 10007)) / 10007.0

func sample(position: Vector3) -> Dictionary:
	var nx := clampf(position.x / TERRAIN_HALF_M, -1.0, 1.0)
	var nz := clampf(position.z / TERRAIN_HALF_M, -1.0, 1.0)
	var water_availability := sample_water_availability(position.x, position.z)
	var altitude01 := clampf(inverse_lerp(-20.0, 30.0, position.y), 0.0, 1.0)
	var micro := 0.5 + 0.5 * sin(nx * 5.1 + _seed_phase) * cos(nz * 4.3 - _seed_phase * 0.73)
	var moisture := clampf(0.12 + 0.68 * water_availability + 0.15 * (1.0 - altitude01) + 0.08 * micro, 0.0, 1.0)
	var temperature := 18.8 - 0.055 * position.y - 1.9 * nz + 0.35 * sin(nx * 2.3 + _seed_phase * 0.15)
	var sunlight := clampf(0.72 + 0.12 * cos(nx * 2.0 + nz * 1.4) + 0.08 * altitude01 - 0.08 * water_availability, 0.0, 1.0)
	var fertility_basin := exp(-pow((nx + 0.10) * 1.55, 2.0) - pow((nz - 0.02) * 1.25, 2.0))
	var nutrient_depletion := exp(-pow((nx + 0.68) * 3.2, 2.0) - pow((nz - 0.55) * 2.8, 2.0))
	var nutrients := clampf(0.20 + 0.33 * moisture + 0.31 * fertility_basin - 0.32 * nutrient_depletion, 0.0, 1.0)
	var flood_frequency := clampf((water_availability - 0.48) / 0.52, 0.0, 1.0) * clampf(1.05 - 0.52 * altitude01, 0.0, 1.0)
	return EnvironmentSample.create(position.x, position.z, temperature, moisture, sunlight, nutrients, flood_frequency, _seed, ENVIRONMENT_REVISION)

func sample_context(position: Vector3, slope_degrees: float = 0.0) -> Dictionary:
	var context := super.sample_context(position, slope_degrees)
	context["water_distance_m"] = sample_water_distance_m(position.x, position.z)
	context["water_availability"] = sample_water_availability(position.x, position.z)
	return context

func sample_water_center_z(x: float) -> float:
	return 32.0 + 46.0 * sin(x / 92.0 + 0.15 * sin(_seed_phase)) + 11.0 * sin(x / 31.0 - 0.08 * _seed_phase)

func sample_water_distance_m(x: float, z: float) -> float:
	return absf(z - sample_water_center_z(x))

func sample_water_availability(x: float, z: float) -> float:
	var distance := sample_water_distance_m(x, z)
	return exp(-pow(distance / 42.0, 2.0))

func get_environment_revision() -> String:
	return ENVIRONMENT_REVISION

func get_seed() -> int:
	return _seed
