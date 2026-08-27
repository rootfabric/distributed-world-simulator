extends RefCounted

## ECO.EVO7 LS3.0 — contiguous read-only physical patch over a planet source.
## Only whitelisted physical fields are copied from the source pipeline.

const SCHEMA := "distributed_world_simulator.ecology.evo7_planet_patch.v1"
const VERSION := "1.0.0"
const REVISION := "ECO.EVO7-LS3.0.4"
const EARTH_EAST_FALLBACK_LENGTH_SQUARED := 0.000001
const BASIS_EPS := 1e-10
const COORD_EPS_M := 1e-9
const DIRECTION_EPS := 1e-10
const DEFAULT_GRID_SIZE := 32
const DEFAULT_CELL_SIZE_M := 16.0
const DEFAULT_PLANET_RADIUS_M := 6_371_000.0
const MIN_GRID_SIZE := 2
const MAX_GRID_SIZE := 128
const MIN_CELL_SIZE_M := 0.25
const MAX_CELL_SIZE_M := 10_000.0
const REQUIRED_SOURCE_FIELDS := [
    "base_elevation_m", "land_mask", "water_kind", "sea_mask", "river_mask",
    "lake_mask", "channel_depth_m", "lake_depth_m", "shore_mask",
    "temperature_c", "moisture", "aridity",
]
const REQUIRED_CELL_FIELDS := [
    "index", "x", "y", "east_m", "north_m", "direction", "elevation_m",
    "base_elevation_m", "land_mask", "water_kind", "sea_mask", "river_mask",
    "lake_mask", "channel_depth_m", "lake_depth_m", "shore_mask",
    "temperature_c", "moisture", "aridity", "slope_ratio", "slope_rad",
    "aspect_east", "aspect_north", "cell_hash",
]

func build(
    planet_source,
    center_direction: Vector3 = Vector3.ZERO,
    grid_size: int = DEFAULT_GRID_SIZE,
    cell_size_m: float = DEFAULT_CELL_SIZE_M
) -> Dictionary:
    if planet_source == null or planet_source.get("pipeline") == null:
        return {}
    if grid_size < MIN_GRID_SIZE or grid_size > MAX_GRID_SIZE:
        return {}
    if not is_finite(cell_size_m) or cell_size_m < MIN_CELL_SIZE_M or cell_size_m > MAX_CELL_SIZE_M:
        return {}
    var center := _resolve_center(planet_source, center_direction)
    if not _finite_direction(center) or center.length_squared() < 0.5:
        return {}
    center = center.normalized()
    var basis := _tangent_basis(center)
    var east: Vector3 = basis["east"]
    var north: Vector3 = basis["north"]
    var radius := _planet_radius(planet_source)
    if not is_finite(radius) or radius < 1000.0:
        return {}
    var cells: Array[Dictionary] = []
    var half_index := float(grid_size - 1) * 0.5
    for y in grid_size:
        for x in grid_size:
            var east_m := (float(x) - half_index) * cell_size_m
            var north_m := (float(y) - half_index) * cell_size_m
            var direction := _offset_direction(center, east, north, east_m, north_m, radius)
            var state: Dictionary = planet_source.pipeline.sample(direction, 0)
            if not _valid_source_state(state):
                return {}
            var physical_cell := _physical_cell(x, y, grid_size, east_m, north_m, direction, state)
            if physical_cell.is_empty():
                return {}
            cells.append(physical_cell)
    _compute_surface_derivatives(cells, grid_size, cell_size_m)
    for i in cells.size():
        cells[i]["cell_hash"] = _cell_hash(cells[i])
    var patch := {
        "schema": SCHEMA,
        "version": VERSION,
        "revision": REVISION,
        "grid_size": grid_size,
        "cell_size_m": cell_size_m,
        "patch_width_m": float(grid_size) * cell_size_m,
        "planet_radius_m": radius,
        "center_direction": center,
        "east": east,
        "north": north,
        "cells": cells,
    }
    patch["patch_hash"] = _patch_hash(patch)
    if not validate_patch(patch):
        return {}
    return patch

func validate_patch(patch: Dictionary) -> bool:
    if patch.is_empty() or String(patch.get("schema", "")) != SCHEMA or String(patch.get("version", "")) != VERSION:
        return false
    var grid_size := int(patch.get("grid_size", 0))
    var cell_size_m := float(patch.get("cell_size_m", NAN))
    var radius := float(patch.get("planet_radius_m", NAN))
    if grid_size < MIN_GRID_SIZE or grid_size > MAX_GRID_SIZE:
        return false
    if not is_finite(cell_size_m) or cell_size_m < MIN_CELL_SIZE_M or cell_size_m > MAX_CELL_SIZE_M:
        return false
    if not is_finite(radius) or radius < 1000.0:
        return false
    if not is_finite(float(patch.get("patch_width_m", NAN))) or absf(float(patch["patch_width_m"]) - float(grid_size) * cell_size_m) > COORD_EPS_M:
        return false

    var center_value = patch.get("center_direction")
    var east_value = patch.get("east")
    var north_value = patch.get("north")
    if not center_value is Vector3 or not east_value is Vector3 or not north_value is Vector3:
        return false
    var center: Vector3 = center_value
    var east: Vector3 = east_value
    var north: Vector3 = north_value
    for basis_vector in [center, east, north]:
        if not _finite_direction(basis_vector) or absf(basis_vector.length_squared() - 1.0) > BASIS_EPS:
            return false
    if absf(center.dot(east)) > BASIS_EPS or absf(center.dot(north)) > BASIS_EPS or absf(east.dot(north)) > BASIS_EPS:
        return false
    var canonical_basis := _tangent_basis(center)
    if east.distance_to(Vector3(canonical_basis["east"])) > BASIS_EPS or north.distance_to(Vector3(canonical_basis["north"])) > BASIS_EPS:
        return false

    var cells_value = patch.get("cells")
    if not cells_value is Array:
        return false
    var cells: Array = cells_value
    if cells.size() != grid_size * grid_size:
        return false
    var seen := {}
    var half_index := float(grid_size - 1) * 0.5
    for value in cells:
        if not value is Dictionary:
            return false
        var cell: Dictionary = value
        for required in REQUIRED_CELL_FIELDS:
            if not cell.has(required):
                return false
        var index := int(cell["index"])
        var x := int(cell["x"])
        var y := int(cell["y"])
        if index < 0 or index >= grid_size * grid_size or seen.has(index):
            return false
        if x < 0 or x >= grid_size or y < 0 or y >= grid_size or index != y * grid_size + x:
            return false
        seen[index] = true

        for numeric_field in [
            "east_m", "north_m", "elevation_m", "base_elevation_m", "land_mask",
            "sea_mask", "river_mask", "lake_mask", "channel_depth_m", "lake_depth_m",
            "shore_mask", "temperature_c", "moisture", "aridity", "slope_ratio",
            "slope_rad", "aspect_east", "aspect_north",
        ]:
            if not is_finite(float(cell[numeric_field])):
                return false
        var expected_east_m := (float(x) - half_index) * cell_size_m
        var expected_north_m := (float(y) - half_index) * cell_size_m
        if absf(float(cell["east_m"]) - expected_east_m) > COORD_EPS_M or absf(float(cell["north_m"]) - expected_north_m) > COORD_EPS_M:
            return false

        var direction_value = cell["direction"]
        if not direction_value is Vector3:
            return false
        var direction: Vector3 = direction_value
        if not _finite_direction(direction) or absf(direction.length_squared() - 1.0) > DIRECTION_EPS:
            return false
        var expected_direction := _offset_direction(center, east, north, expected_east_m, expected_north_m, radius)
        if direction.distance_to(expected_direction) > DIRECTION_EPS:
            return false

        for unit_field in ["land_mask", "sea_mask", "river_mask", "lake_mask", "shore_mask", "moisture", "aridity"]:
            var unit_value := float(cell[unit_field])
            if unit_value < 0.0 or unit_value > 1.0:
                return false
        if int(cell["water_kind"]) < 0 or int(cell["water_kind"]) > 3:
            return false
        if float(cell["channel_depth_m"]) < 0.0 or float(cell["lake_depth_m"]) < 0.0 or float(cell["slope_ratio"]) < 0.0:
            return false
        if absf(float(cell["aspect_east"])) > 1.0000001 or absf(float(cell["aspect_north"])) > 1.0000001:
            return false
        var expected_cell_hash := _cell_hash(cell)
        if expected_cell_hash.is_empty() or String(cell["cell_hash"]) != expected_cell_hash:
            return false
    var expected_patch_hash := _patch_hash(patch)
    return not expected_patch_hash.is_empty() and String(patch.get("patch_hash", "")) == expected_patch_hash

func _resolve_center(planet_source, requested: Vector3) -> Vector3:
    if _finite_direction(requested) and requested.length_squared() >= 0.5:
        return requested.normalized()
    var from_property = planet_source.get("surface_center_direction")
    if from_property is Vector3 and _finite_direction(Vector3(from_property)) and Vector3(from_property).length_squared() >= 0.5:
        return Vector3(from_property).normalized()
    if planet_source.has_method("get_canonical_spawn_direction"):
        var spawn = planet_source.call("get_canonical_spawn_direction")
        if spawn is Vector3 and _finite_direction(Vector3(spawn)) and Vector3(spawn).length_squared() >= 0.5:
            return Vector3(spawn).normalized()
    return Vector3.ZERO

func _planet_radius(planet_source) -> float:
    var value = planet_source.get("planet_radius_m")
    if value != null:
        return float(value)
    if planet_source.has_method("get_planet_radius"):
        return float(planet_source.call("get_planet_radius"))
    return DEFAULT_PLANET_RADIUS_M

func _tangent_basis(center: Vector3) -> Dictionary:
    var east := Vector3.UP.cross(center)
    if east.length_squared() < EARTH_EAST_FALLBACK_LENGTH_SQUARED:
        east = Vector3.RIGHT.cross(center)
    east = east.normalized()
    var north := east.cross(center).normalized()
    return {"east": east, "north": north}

func _offset_direction(center: Vector3, east: Vector3, north: Vector3, east_m: float, north_m: float, radius_m: float) -> Vector3:
    var tangent := east * east_m + north * north_m
    var distance_m := tangent.length()
    if distance_m <= 1e-12:
        return center
    var angle := distance_m / radius_m
    return (center * cos(angle) + tangent.normalized() * sin(angle)).normalized()

func _valid_source_state(state: Dictionary) -> bool:
    if state.is_empty():
        return false
    for field in REQUIRED_SOURCE_FIELDS:
        if not state.has(field):
            return false
    for field in REQUIRED_SOURCE_FIELDS:
        if field == "water_kind":
            continue
        if not is_finite(float(state[field])):
            return false
    var water_kind := int(state["water_kind"])
    return water_kind >= 0 and water_kind <= 3

func _physical_cell(x: int, y: int, grid_size: int, east_m: float, north_m: float, direction: Vector3, state: Dictionary) -> Dictionary:
    if not _valid_source_state(state) or not _finite_direction(direction):
        return {}
    var base_elevation := float(state["base_elevation_m"])
    var river_mask := clampf(float(state["river_mask"]), 0.0, 1.0)
    var lake_mask := clampf(float(state["lake_mask"]), 0.0, 1.0)
    var channel_depth := maxf(0.0, float(state["channel_depth_m"]))
    var lake_depth := maxf(0.0, float(state["lake_depth_m"]))
    var elevation := base_elevation - channel_depth * river_mask - lake_depth * lake_mask
    if not is_finite(elevation):
        return {}
    return {
        "index": y * grid_size + x, "x": x, "y": y, "east_m": east_m, "north_m": north_m,
        "direction": direction, "elevation_m": elevation, "base_elevation_m": base_elevation,
        "land_mask": clampf(float(state["land_mask"]), 0.0, 1.0), "water_kind": int(state["water_kind"]),
        "sea_mask": clampf(float(state["sea_mask"]), 0.0, 1.0), "river_mask": river_mask,
        "lake_mask": lake_mask, "channel_depth_m": channel_depth, "lake_depth_m": lake_depth,
        "shore_mask": clampf(float(state["shore_mask"]), 0.0, 1.0), "temperature_c": float(state["temperature_c"]),
        "moisture": clampf(float(state["moisture"]), 0.0, 1.0), "aridity": clampf(float(state["aridity"]), 0.0, 1.0),
        "slope_ratio": 0.0, "slope_rad": 0.0, "aspect_east": 0.0, "aspect_north": 0.0,
    }

func _compute_surface_derivatives(cells: Array[Dictionary], grid_size: int, cell_size_m: float) -> void:
    for y in grid_size:
        for x in grid_size:
            var index := y * grid_size + x
            var west_x := maxi(0, x - 1); var east_x := mini(grid_size - 1, x + 1)
            var south_y := maxi(0, y - 1); var north_y := mini(grid_size - 1, y + 1)
            var west_elev := float(cells[y * grid_size + west_x]["elevation_m"])
            var east_elev := float(cells[y * grid_size + east_x]["elevation_m"])
            var south_elev := float(cells[south_y * grid_size + x]["elevation_m"])
            var north_elev := float(cells[north_y * grid_size + x]["elevation_m"])
            var east_span := float(east_x - west_x) * cell_size_m
            var north_span := float(north_y - south_y) * cell_size_m
            var dz_east := 0.0 if east_span <= 0.0 else (east_elev - west_elev) / east_span
            var dz_north := 0.0 if north_span <= 0.0 else (north_elev - south_elev) / north_span
            var slope_ratio := sqrt(dz_east * dz_east + dz_north * dz_north)
            cells[index]["slope_ratio"] = slope_ratio; cells[index]["slope_rad"] = atan(slope_ratio)
            if slope_ratio > 1e-12:
                cells[index]["aspect_east"] = dz_east / slope_ratio
                cells[index]["aspect_north"] = dz_north / slope_ratio

func _cell_hash(cell: Dictionary) -> String:
    var d: Vector3 = cell["direction"]
    var tokens := PackedStringArray([
        str(int(cell["index"])), str(int(cell["x"])), str(int(cell["y"])), _f(float(cell["east_m"])), _f(float(cell["north_m"])),
        _f(d.x), _f(d.y), _f(d.z), _f(float(cell["elevation_m"])), _f(float(cell["base_elevation_m"])),
        _f(float(cell["land_mask"])), str(int(cell["water_kind"])), _f(float(cell["sea_mask"])), _f(float(cell["river_mask"])),
        _f(float(cell["lake_mask"])), _f(float(cell["channel_depth_m"])), _f(float(cell["lake_depth_m"])), _f(float(cell["shore_mask"])),
        _f(float(cell["temperature_c"])), _f(float(cell["moisture"])), _f(float(cell["aridity"])), _f(float(cell["slope_ratio"])),
        _f(float(cell["slope_rad"])), _f(float(cell["aspect_east"])), _f(float(cell["aspect_north"])),
    ])
    return "|".join(tokens).sha256_text()

func _patch_hash(patch: Dictionary) -> String:
    var center_value = patch.get("center_direction")
    var east_value = patch.get("east")
    var north_value = patch.get("north")
    if not center_value is Vector3 or not east_value is Vector3 or not north_value is Vector3:
        return ""
    var center: Vector3 = center_value
    var east: Vector3 = east_value
    var north: Vector3 = north_value
    if not _finite_direction(center) or not _finite_direction(east) or not _finite_direction(north):
        return ""
    var tokens := PackedStringArray([
        String(patch["schema"]), String(patch["version"]), str(int(patch["grid_size"])), _f(float(patch["cell_size_m"])), _f(float(patch["planet_radius_m"])),
        _f(center.x), _f(center.y), _f(center.z),
        _f(east.x), _f(east.y), _f(east.z),
        _f(north.x), _f(north.y), _f(north.z),
    ])
    var by_index := {}
    for cell_value in Array(patch.get("cells", [])):
        if not cell_value is Dictionary:
            return ""
        var cell: Dictionary = cell_value
        var index := int(cell.get("index", -1))
        if index < 0 or by_index.has(index):
            return ""
        by_index[index] = String(cell.get("cell_hash", ""))
    var indexes: Array = by_index.keys(); indexes.sort()
    for index_value in indexes:
        tokens.append(String(by_index[index_value]))
    return "|".join(tokens).sha256_text()

func _finite_direction(value: Vector3) -> bool:
    return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _f(value: float) -> String:
    return "%.12f" % value
