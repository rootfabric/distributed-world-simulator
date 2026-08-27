extends RefCounted

## ECO.EVO7 LS3.1 — deterministic RAM-only physical environment field.
## Recipes describe physical drivers only; no vegetation class is an input.

const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const SCHEMA := "distributed_world_simulator.ecology.evo7_environment_field.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.1.2"

const RECIPES := {
    "WATER_GRADIENT_STRONG": {
        "rainfall_base": 0.50, "rainfall_gradient_east": 0.46, "rainfall_gradient_north": 0.06,
        "rainfall_noise": 0.09, "micro_relief_m": 5.0, "sand_base": 0.50, "clay_base": 0.20,
        "texture_noise": 0.16, "drainage_gain": 0.58, "light_base": 0.82, "light_noise": 0.09,
        "temperature_offset_c": 0.0, "temperature_noise_c": 0.8,
    },
    "RELIEF_DRAINAGE_STRONG": {
        "rainfall_base": 0.58, "rainfall_gradient_east": 0.08, "rainfall_gradient_north": -0.04,
        "rainfall_noise": 0.12, "micro_relief_m": 24.0, "sand_base": 0.46, "clay_base": 0.24,
        "texture_noise": 0.19, "drainage_gain": 0.92, "light_base": 0.80, "light_noise": 0.13,
        "temperature_offset_c": -0.5, "temperature_noise_c": 1.2,
    },
    "MIXED_PHYSICAL_HETEROGENEITY": {
        "rainfall_base": 0.52, "rainfall_gradient_east": 0.24, "rainfall_gradient_north": -0.18,
        "rainfall_noise": 0.18, "micro_relief_m": 14.0, "sand_base": 0.43, "clay_base": 0.27,
        "texture_noise": 0.24, "drainage_gain": 0.76, "light_base": 0.79, "light_noise": 0.16,
        "temperature_offset_c": 0.7, "temperature_noise_c": 1.8,
    },
}

func recipe_ids() -> Array[String]:
    return ["WATER_GRADIENT_STRONG", "RELIEF_DRAINAGE_STRONG", "MIXED_PHYSICAL_HETEROGENEITY"]

func get_recipe(recipe_id: String) -> Dictionary:
    if not RECIPES.has(recipe_id):
        return {}
    return Dictionary(RECIPES[recipe_id]).duplicate(true)

func generate(patch: Dictionary, recipe_id: String, environment_seed: int) -> Dictionary:
    if patch.is_empty() or not RECIPES.has(recipe_id):
        return {}
    var patch_validator = PlanetPatch.new()
    if not patch_validator.validate_patch(patch):
        return {}
    var grid_size := int(patch["grid_size"])
    var source_cells: Array = patch["cells"]
    var recipe: Dictionary = RECIPES[recipe_id]
    var ordered := _canonical_cells(source_cells, grid_size)
    if ordered.size() != source_cells.size():
        return {}
    var moisture_noise := _noise(environment_seed + 101, 0.115, 4)
    var texture_noise := _noise(environment_seed + 211, 0.085, 4)
    var relief_noise := _noise(environment_seed + 307, 0.065, 5)
    var light_noise := _noise(environment_seed + 401, 0.130, 3)
    var temperature_noise := _noise(environment_seed + 503, 0.055, 3)
    var cells: Array[Dictionary] = []
    for source_value in ordered:
        var source: Dictionary = source_value
        var x := int(source["x"]); var y := int(source["y"])
        var x_norm := float(x) / float(grid_size - 1); var y_norm := float(y) / float(grid_size - 1)
        var nx := float(x) * 0.31; var ny := float(y) * 0.31
        var moisture_n := moisture_noise.get_noise_2d(nx, ny)
        var texture_n := texture_noise.get_noise_2d(nx + 13.0, ny - 7.0)
        var texture_n2 := texture_noise.get_noise_2d(nx - 23.0, ny + 19.0)
        var relief_n := relief_noise.get_noise_2d(nx + 5.0, ny + 31.0)
        var light_n := light_noise.get_noise_2d(nx - 11.0, ny - 17.0)
        var temp_n := temperature_noise.get_noise_2d(nx + 29.0, ny + 3.0)
        var rainfall := clampf(
            float(recipe["rainfall_base"]) + (x_norm - 0.5) * 2.0 * float(recipe["rainfall_gradient_east"])
            + (y_norm - 0.5) * 2.0 * float(recipe["rainfall_gradient_north"])
            + moisture_n * float(recipe["rainfall_noise"]), 0.0, 1.0)
        var micro_relief := relief_n * float(recipe["micro_relief_m"])
        var sand := clampf(float(recipe["sand_base"]) + texture_n * float(recipe["texture_noise"]), 0.04, 0.90)
        var clay := clampf(float(recipe["clay_base"]) - texture_n * float(recipe["texture_noise"]) * 0.45 + texture_n2 * 0.06, 0.04, 0.75)
        if sand + clay > 0.94:
            var scale := 0.94 / (sand + clay); sand *= scale; clay *= scale
        var retention := clampf(0.10 + clay * 0.80 + (1.0 - sand) * 0.24, 0.0, 1.0)
        var slope := clampf(float(source["slope_ratio"]), 0.0, 4.0)
        var positive_relief := maxf(0.0, micro_relief) / maxf(1.0, float(recipe["micro_relief_m"]))
        var drainage := clampf(slope * float(recipe["drainage_gain"]) + sand * 0.42 + positive_relief * 0.20 - clay * 0.16, 0.0, 1.0)
        var surface_water := maxf(float(source["sea_mask"]), maxf(float(source["river_mask"]), float(source["lake_mask"])))
        var soil_moisture := clampf(
            0.05 + float(source["moisture"]) * 0.16 + rainfall * 0.64 + retention * 0.23 + surface_water * 0.28 - drainage * 0.33,
            0.0, 1.0)
        var aspect_light := clampf(-float(source["aspect_north"]) * 0.10 + float(source["aspect_east"]) * 0.04, -0.12, 0.12)
        var incident_light := clampf(float(recipe["light_base"]) + light_n * float(recipe["light_noise"]) + aspect_light - rainfall * 0.05, 0.05, 1.0)
        var temperature := float(source["temperature_c"]) + float(recipe["temperature_offset_c"]) + temp_n * float(recipe["temperature_noise_c"]) - micro_relief * 0.0062
        var elevation := float(source["elevation_m"]) + micro_relief
        if not is_finite(soil_moisture) or not is_finite(temperature) or not is_finite(elevation):
            return {}
        var cell := {
            "index": int(source["index"]), "x": x, "y": y,
            "east_m": float(source["east_m"]), "north_m": float(source["north_m"]),
            "land_mask": float(source["land_mask"]), "surface_water_fraction": clampf(surface_water, 0.0, 1.0),
            "soil_moisture": soil_moisture, "soil_texture_sand": sand, "soil_texture_clay": clay,
            "soil_texture_loam": maxf(0.0, 1.0 - sand - clay), "soil_water_retention": retention,
            "temperature_c": temperature, "incident_light": incident_light, "elevation_m": elevation,
            "local_relief_m": micro_relief, "drainage_index": drainage, "rainfall_forcing": rainfall,
        }
        cell["cell_hash"] = _cell_hash(cell)
        cells.append(cell)
    var result := {
        "schema": SCHEMA, "version": VERSION, "revision": REVISION,
        "source_patch_hash": String(patch["patch_hash"]), "grid_size": grid_size,
        "cell_size_m": float(patch["cell_size_m"]), "recipe_id": recipe_id,
        "environment_seed": environment_seed, "cells": cells,
    }
    result["field_hash"] = _field_hash(result)
    return result

func _canonical_cells(source_cells: Array, grid_size: int) -> Array[Dictionary]:
    var by_index := {}
    var expected_count := grid_size * grid_size
    for value in source_cells:
        if not value is Dictionary:
            return []
        var cell: Dictionary = value
        var index := int(cell.get("index", -1)); var x := int(cell.get("x", -1)); var y := int(cell.get("y", -1))
        if index < 0 or index >= expected_count or by_index.has(index):
            return []
        if x < 0 or x >= grid_size or y < 0 or y >= grid_size or index != y * grid_size + x:
            return []
        by_index[index] = cell
    if by_index.size() != expected_count:
        return []
    var keys: Array = by_index.keys(); keys.sort()
    var result: Array[Dictionary] = []
    for index_value in keys:
        result.append(Dictionary(by_index[index_value]))
    return result

func _noise(seed: int, frequency: float, octaves: int) -> FastNoiseLite:
    var noise := FastNoiseLite.new(); noise.seed = seed; noise.frequency = frequency
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH; noise.fractal_type = FastNoiseLite.FRACTAL_FBM; noise.fractal_octaves = octaves
    return noise

func _cell_hash(cell: Dictionary) -> String:
    var tokens := PackedStringArray([
        str(int(cell["index"])), str(int(cell["x"])), str(int(cell["y"])), _f(float(cell["east_m"])), _f(float(cell["north_m"])),
        _f(float(cell["land_mask"])), _f(float(cell["surface_water_fraction"])), _f(float(cell["soil_moisture"])),
        _f(float(cell["soil_texture_sand"])), _f(float(cell["soil_texture_clay"])), _f(float(cell["soil_texture_loam"])),
        _f(float(cell["soil_water_retention"])), _f(float(cell["temperature_c"])), _f(float(cell["incident_light"])),
        _f(float(cell["elevation_m"])), _f(float(cell["local_relief_m"])), _f(float(cell["drainage_index"])), _f(float(cell["rainfall_forcing"])),
    ])
    return "|".join(tokens).sha256_text()

func _field_hash(field: Dictionary) -> String:
    var tokens := PackedStringArray([
        String(field["schema"]), String(field["version"]), String(field["source_patch_hash"]), String(field["recipe_id"]),
        str(int(field["environment_seed"])), str(int(field["grid_size"])), _f(float(field["cell_size_m"])),
    ])
    for cell_value in field["cells"]:
        tokens.append(String(Dictionary(cell_value)["cell_hash"]))
    return "|".join(tokens).sha256_text()

func _f(value: float) -> String:
    return "%.12f" % value
