extends RefCounted

const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")

## ECO.EVO7 LS4.0 — deterministic seasonal forcing over the accepted LS3.1
## physical environment field.
##
## The provider owns only a research-time forcing transform. It cannot advance
## ecology, mutate population/genomes, write world state, persistence or
## networking. The returned field stays LS3.1-compatible and is validated by
## the LS3.1 single hash implementation before it can reach causal ecology.

const SCHEMA := "distributed_world_simulator.ecology.evo7_ls40_seasonal_forcing.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS4.0.1"
const CYCLE_GENERATIONS := 12
const DEFAULT_PROFILE := "TEMPERATE_SEASONAL"

const PROFILE_IDS: Array[String] = [
	"STATIC_CONTROL",
	"TEMPERATE_SEASONAL",
	"MONSOON_SEASONAL",
]

const PHASE_NAMES: Array[String] = [
	"MID_WINTER",
	"LATE_WINTER",
	"EARLY_SPRING",
	"MID_SPRING",
	"EARLY_SUMMER",
	"MID_SUMMER",
	"LATE_SUMMER",
	"EARLY_AUTUMN",
	"MID_AUTUMN",
	"LATE_AUTUMN",
	"EARLY_WINTER",
	"LATE_WINTER_RETURN",
]

## Explicit lookup tables are used instead of runtime trigonometry so a phase
## has the same forcing coefficients on every supported host.
const THERMAL_WAVE: Array[float] = [
	-1.0, -0.866025403784, -0.5, 0.0, 0.5, 0.866025403784,
	1.0, 0.866025403784, 0.5, 0.0, -0.5, -0.866025403784,
]
const WET_WAVE: Array[float] = [
	0.30, 0.15, 0.00, -0.10, -0.20, -0.10,
	0.05, 0.30, 0.65, 1.00, 0.80, 0.50,
]

const PROFILES := {
	"STATIC_CONTROL": {
		"temperature_amplitude_c": 0.0,
		"light_amplitude": 0.0,
		"rainfall_amplitude": 0.0,
		"moisture_amplitude": 0.0,
		"cloud_dimming": 0.0,
		"wet_phase_offset": 0,
	},
	"TEMPERATE_SEASONAL": {
		"temperature_amplitude_c": 9.0,
		"light_amplitude": 0.14,
		"rainfall_amplitude": 0.08,
		"moisture_amplitude": 0.10,
		"cloud_dimming": 0.04,
		"wet_phase_offset": 0,
	},
	"MONSOON_SEASONAL": {
		"temperature_amplitude_c": 3.0,
		"light_amplitude": 0.08,
		"rainfall_amplitude": 0.30,
		"moisture_amplitude": 0.25,
		"cloud_dimming": 0.16,
		"wet_phase_offset": 0,
	},
}

const ENVIRONMENT_FIELD_KEYS: Array[String] = [
	"schema", "version", "revision", "source_patch_hash", "grid_size",
	"cell_size_m", "recipe_id", "environment_seed", "cells", "field_hash",
]

const ENVIRONMENT_CELL_KEYS: Array[String] = [
	"index", "x", "y", "east_m", "north_m", "land_mask",
	"surface_water_fraction", "soil_moisture", "soil_texture_sand",
	"soil_texture_clay", "soil_texture_loam", "soil_water_retention",
	"temperature_c", "incident_light", "elevation_m", "local_relief_m",
	"drainage_index", "rainfall_forcing", "cell_hash",
]

## LS4 forcing is not allowed to manufacture terrain, water bodies, substrate
## or drainage truth. Only temperature/light/rainfall/soil-moisture vary.
const STATIC_CELL_FIELDS: Array[String] = [
	"index", "x", "y", "east_m", "north_m", "land_mask",
	"surface_water_fraction", "soil_texture_sand", "soil_texture_clay",
	"soil_texture_loam", "soil_water_retention", "elevation_m",
	"local_relief_m", "drainage_index",
]

const AUTHORITY := {
	"world_write": false,
	"terrain_write": false,
	"surface_water_truth_write": false,
	"material_ontology_write": false,
	"ecology_generation_commit": false,
	"population_write": false,
	"genome_write": false,
	"persistence_write": false,
	"network_replication_write": false,
	"production_environment_authority": false,
}

var profile_id := DEFAULT_PROFILE
var last_overlay: Dictionary = {}

func setup(requested_profile_id: String = DEFAULT_PROFILE) -> bool:
	if not requested_profile_id in PROFILE_IDS:
		return false
	profile_id = requested_profile_id
	last_overlay.clear()
	return true

func profile_ids() -> Array[String]:
	return PROFILE_IDS.duplicate()

func get_last_overlay() -> Dictionary:
	return last_overlay.duplicate(true)

func environment_for_generation(generation_value: int, base_environment_field: Dictionary) -> Dictionary:
	last_overlay.clear()
	if generation_value < 1 or not profile_id in PROFILE_IDS:
		return {}
	if not validate_environment_field(base_environment_field):
		return {}

	var phase_index := (generation_value - 1) % CYCLE_GENERATIONS
	var profile: Dictionary = PROFILES[profile_id]
	var result: Dictionary = base_environment_field.duplicate(true)

	if profile_id != "STATIC_CONTROL":
		var thermal := float(THERMAL_WAVE[phase_index])
		var wet_index := (phase_index + int(profile["wet_phase_offset"])) % CYCLE_GENERATIONS
		var wet := float(WET_WAVE[wet_index])
		var cells: Array = result["cells"]
		for index in cells.size():
			var base_cell: Dictionary = Dictionary(Array(base_environment_field["cells"])[index])
			var cell: Dictionary = Dictionary(cells[index])

			var rainfall_delta := wet * float(profile["rainfall_amplitude"])
			cell["temperature_c"] = snappedf(
				float(base_cell["temperature_c"]) + thermal * float(profile["temperature_amplitude_c"]),
				1e-12)
			cell["rainfall_forcing"] = snappedf(clampf(
				float(base_cell["rainfall_forcing"]) + rainfall_delta, 0.0, 1.0), 1e-12)
			cell["soil_moisture"] = snappedf(clampf(
				float(base_cell["soil_moisture"])
				+ wet * float(profile["moisture_amplitude"])
				+ rainfall_delta * 0.35,
				0.0, 1.0), 1e-12)
			cell["incident_light"] = snappedf(clampf(
				float(base_cell["incident_light"])
				+ thermal * float(profile["light_amplitude"])
				- maxf(0.0, wet) * float(profile["cloud_dimming"]),
				0.05, 1.0), 1e-12)

			if not is_finite(float(cell["temperature_c"])) 					or not is_finite(float(cell["rainfall_forcing"])) 					or not is_finite(float(cell["soil_moisture"])) 					or not is_finite(float(cell["incident_light"])):
				return {}
			cell["cell_hash"] = EnvironmentField.new().call("_cell_hash", cell)
			cells[index] = cell
		result["cells"] = cells
		result["field_hash"] = EnvironmentField.new().call("_field_hash", result)

	if not validate_environment_field(result):
		return {}
	if not validate_static_identity(base_environment_field, result):
		return {}

	last_overlay = _overlay_metadata(
		generation_value,
		phase_index,
		String(base_environment_field["field_hash"]),
		String(result["field_hash"])
	)
	return result

func validate_environment_field(value: Dictionary) -> bool:
	if not _exact_keys(value, ENVIRONMENT_FIELD_KEYS):
		return false
	if String(value.get("schema", "")) != EnvironmentField.SCHEMA 			or String(value.get("version", "")) != EnvironmentField.VERSION 			or String(value.get("revision", "")) != EnvironmentField.REVISION:
		return false
	if String(value.get("source_patch_hash", "")).length() != 64:
		return false
	if int(value.get("grid_size", 0)) != 32 or float(value.get("cell_size_m", 0.0)) <= 0.0:
		return false
	if not String(value.get("recipe_id", "")) in EnvironmentField.new().recipe_ids():
		return false
	if typeof(value.get("environment_seed")) != TYPE_INT:
		return false
	var cells_value = value.get("cells")
	if not cells_value is Array or Array(cells_value).size() != 32 * 32:
		return false
	var validator = EnvironmentField.new()
	for index in 32 * 32:
		var cell_value = Array(cells_value)[index]
		if not cell_value is Dictionary:
			return false
		var cell: Dictionary = cell_value
		if not _exact_keys(cell, ENVIRONMENT_CELL_KEYS):
			return false
		if int(cell.get("index", -1)) != index 				or int(cell.get("x", -1)) != index % 32 				or int(cell.get("y", -1)) != index / 32:
			return false
		for field_name in [
			"east_m", "north_m", "land_mask", "surface_water_fraction",
			"soil_moisture", "soil_texture_sand", "soil_texture_clay",
			"soil_texture_loam", "soil_water_retention", "temperature_c",
			"incident_light", "elevation_m", "local_relief_m",
			"drainage_index", "rainfall_forcing",
		]:
			if not is_finite(float(cell.get(field_name, NAN))):
				return false
		if String(cell.get("cell_hash", "")) != String(validator.call("_cell_hash", cell)):
			return false
	return String(value.get("field_hash", "")) == String(validator.call("_field_hash", value))

func validate_static_identity(base_environment_field: Dictionary, derived_environment_field: Dictionary) -> bool:
	if not validate_environment_field(base_environment_field) 			or not validate_environment_field(derived_environment_field):
		return false
	for key in [
		"schema", "version", "revision", "source_patch_hash", "grid_size",
		"cell_size_m", "recipe_id", "environment_seed",
	]:
		if derived_environment_field.get(key) != base_environment_field.get(key):
			return false
	var base_cells: Array = base_environment_field["cells"]
	var derived_cells: Array = derived_environment_field["cells"]
	for index in base_cells.size():
		var base_cell: Dictionary = base_cells[index]
		var derived_cell: Dictionary = derived_cells[index]
		for field_name in STATIC_CELL_FIELDS:
			if derived_cell.get(field_name) != base_cell.get(field_name):
				return false
	return true

func _overlay_metadata(generation_value: int, phase_index: int, base_hash: String, derived_hash: String) -> Dictionary:
	var out := {
		"schema": SCHEMA,
		"version": VERSION,
		"revision": REVISION,
		"shadow_only": true,
		"profile_id": profile_id,
		"generation": generation_value,
		"cycle_generations": CYCLE_GENERATIONS,
		"phase_index": phase_index,
		"phase_name": PHASE_NAMES[phase_index],
		"base_environment_field_hash": base_hash,
		"derived_environment_field_hash": derived_hash,
		"authorities": AUTHORITY.duplicate(true),
	}
	out["overlay_hash"] = _overlay_hash(out)
	return out

func _overlay_hash(value: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA, VERSION, REVISION,
		String(value.get("profile_id", "")),
		str(int(value.get("generation", -1))),
		str(int(value.get("phase_index", -1))),
		String(value.get("phase_name", "")),
		String(value.get("base_environment_field_hash", "")),
		String(value.get("derived_environment_field_hash", "")),
	])).sha256_text()

func _exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.keys().size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true
