extends SceneTree

const PlanetPatch = preload("res://scripts/ecology/shadow/eco_evo7_ls30_planet_patch_v1.gd")
const EnvironmentField = preload("res://scripts/ecology/shadow/eco_evo7_ls31_environment_field_v1.gd")

var checks := 0
var failures: Array[String] = []

class FakePipeline:
    extends RefCounted
    func sample(direction: Vector3, _lod: int = 0) -> Dictionary:
        var d := direction.normalized()
        var moisture := clampf(0.52 + d.z * 0.12 - d.x * 0.08, 0.0, 1.0)
        var river := clampf(0.12 + sin(d.x * 91.0) * 0.06, 0.0, 1.0)
        var lake := clampf(0.06 + cos(d.z * 67.0) * 0.03, 0.0, 1.0)
        return {
            "base_elevation_m": 240.0 + d.x * 500.0 + d.z * 260.0,
            "land_mask": 1.0,
            "water_kind": 0,
            "sea_mask": 0.0,
            "river_mask": river,
            "lake_mask": lake,
            "channel_depth_m": 14.0 * river,
            "lake_depth_m": 28.0 * lake,
            "shore_mask": 0.0,
            "temperature_c": 18.0,
            "moisture": moisture,
            "aridity": 1.0 - moisture,
            "biome_code": 4,
            "tree_density": 0.9,
        }

class FakeEarth:
    extends RefCounted
    var pipeline = FakePipeline.new()
    var planet_radius_m := 6_371_000.0
    var surface_center_direction := Vector3(0.41, 0.71, 0.57).normalized()

func _init() -> void:
    var builder = PlanetPatch.new()
    var earth = FakeEarth.new()
    var patch := builder.build(earth, earth.surface_center_direction, 32, 16.0)
    _check(not patch.is_empty(), "valid patch builds")
    _check(builder.validate_patch(patch), "valid patch validates")

    var reordered: Dictionary = patch.duplicate(true)
    var reordered_cells: Array = reordered["cells"]
    reordered_cells.reverse()
    reordered["cells"] = reordered_cells
    _check(builder.validate_patch(reordered), "validation is cell-order invariant")

    var generator = EnvironmentField.new()
    var field := generator.generate(patch, "WATER_GRADIENT_STRONG", 20260831)
    _check(not field.is_empty(), "valid patch generates environment")
    var reordered_field := generator.generate(reordered, "WATER_GRADIENT_STRONG", 20260831)
    _check(not reordered_field.is_empty() and String(reordered_field["field_hash"]) == String(field["field_hash"]), "reordered valid patch produces same field")

    var stale: Dictionary = patch.duplicate(true)
    stale["cells"][0]["moisture"] = 0.123456
    _check(not builder.validate_patch(stale), "stale cell hash fails validation")
    _check(generator.generate(stale, "WATER_GRADIENT_STRONG", 20260831).is_empty(), "environment rejects stale patch identity")

    var bad_index: Dictionary = patch.duplicate(true)
    bad_index["cells"][0]["index"] = 2048
    bad_index["cells"][0]["cell_hash"] = builder.call("_cell_hash", bad_index["cells"][0])
    bad_index["patch_hash"] = builder.call("_patch_hash", bad_index)
    _check(not builder.validate_patch(bad_index), "out-of-range index rejected even with recomputed hashes")
    _check(generator.generate(bad_index, "WATER_GRADIENT_STRONG", 20260831).is_empty(), "environment rejects out-of-range topology")

    var bad_xy: Dictionary = patch.duplicate(true)
    bad_xy["cells"][0]["x"] = 7
    bad_xy["cells"][0]["cell_hash"] = builder.call("_cell_hash", bad_xy["cells"][0])
    bad_xy["patch_hash"] = builder.call("_patch_hash", bad_xy)
    _check(not builder.validate_patch(bad_xy), "index-to-coordinate mismatch rejected")

    var nonfinite: Dictionary = patch.duplicate(true)
    nonfinite["cells"][0]["elevation_m"] = NAN
    nonfinite["cells"][0]["cell_hash"] = builder.call("_cell_hash", nonfinite["cells"][0])
    nonfinite["patch_hash"] = builder.call("_patch_hash", nonfinite)
    _check(not builder.validate_patch(nonfinite), "NaN physical cell rejected")
    _check(generator.generate(nonfinite, "WATER_GRADIENT_STRONG", 20260831).is_empty(), "environment rejects non-finite patch")

    var flipped_basis: Dictionary = patch.duplicate(true)
    flipped_basis["north"] = -Vector3(flipped_basis["north"])
    flipped_basis["patch_hash"] = builder.call("_patch_hash", flipped_basis)
    _check(String(flipped_basis["patch_hash"]) != String(patch["patch_hash"]), "basis is bound into patch hash")
    _check(not builder.validate_patch(flipped_basis), "flipped north basis rejected after rehash")
    _check(generator.generate(flipped_basis, "WATER_GRADIENT_STRONG", 20260831).is_empty(), "environment rejects flipped basis")

    var skewed_basis: Dictionary = patch.duplicate(true)
    skewed_basis["north"] = (Vector3(skewed_basis["north"]) + Vector3(skewed_basis["east"]) * 0.1).normalized()
    skewed_basis["patch_hash"] = builder.call("_patch_hash", skewed_basis)
    _check(not builder.validate_patch(skewed_basis), "non-orthogonal basis rejected after rehash")

    var bad_east_m: Dictionary = patch.duplicate(true)
    bad_east_m["cells"][0]["east_m"] = float(bad_east_m["cells"][0]["east_m"]) + 1.0
    bad_east_m["cells"][0]["cell_hash"] = builder.call("_cell_hash", bad_east_m["cells"][0])
    bad_east_m["patch_hash"] = builder.call("_patch_hash", bad_east_m)
    _check(not builder.validate_patch(bad_east_m), "east_m topology tamper rejected after rehash")
    _check(generator.generate(bad_east_m, "WATER_GRADIENT_STRONG", 20260831).is_empty(), "environment rejects east_m topology tamper")

    var bad_north_m: Dictionary = patch.duplicate(true)
    bad_north_m["cells"][0]["north_m"] = float(bad_north_m["cells"][0]["north_m"]) - 1.0
    bad_north_m["cells"][0]["cell_hash"] = builder.call("_cell_hash", bad_north_m["cells"][0])
    bad_north_m["patch_hash"] = builder.call("_patch_hash", bad_north_m)
    _check(not builder.validate_patch(bad_north_m), "north_m topology tamper rejected after rehash")

    var bad_direction: Dictionary = patch.duplicate(true)
    bad_direction["cells"][0]["direction"] = (Vector3(bad_direction["cells"][0]["direction"]) + Vector3(patch["east"]) * 0.0001).normalized()
    bad_direction["cells"][0]["cell_hash"] = builder.call("_cell_hash", bad_direction["cells"][0])
    bad_direction["patch_hash"] = builder.call("_patch_hash", bad_direction)
    _check(not builder.validate_patch(bad_direction), "direction topology tamper rejected after rehash")
    _check(generator.generate(bad_direction, "WATER_GRADIENT_STRONG", 20260831).is_empty(), "environment rejects direction topology tamper")

    var nonunit_direction: Dictionary = patch.duplicate(true)
    nonunit_direction["cells"][0]["direction"] = Vector3(nonunit_direction["cells"][0]["direction"]) * 2.0
    nonunit_direction["cells"][0]["cell_hash"] = builder.call("_cell_hash", nonunit_direction["cells"][0])
    nonunit_direction["patch_hash"] = builder.call("_patch_hash", nonunit_direction)
    _check(not builder.validate_patch(nonunit_direction), "non-unit direction rejected after rehash")

    var raw_state: Dictionary = earth.pipeline.sample(earth.surface_center_direction, 0)
    raw_state["base_elevation_m"] = NAN
    var bad_physical: Dictionary = builder.call("_physical_cell", 0, 0, 32, 0.0, 0.0, earth.surface_center_direction, raw_state)
    _check(bad_physical.is_empty(), "non-finite source state fails closed before patch materialization")

    var missing_state: Dictionary = earth.pipeline.sample(earth.surface_center_direction, 0)
    missing_state.erase("temperature_c")
    var missing_physical: Dictionary = builder.call("_physical_cell", 0, 0, 32, 0.0, 0.0, earth.surface_center_direction, missing_state)
    _check(missing_physical.is_empty(), "missing required physical source field fails closed")

    if failures.is_empty():
        print("ECO.EVO7 LS3.0/LS3.1 fail-closed hardening: PASS (%d checks) patch=%s field=%s" % [checks, String(patch["patch_hash"]).substr(0,16), String(field["field_hash"]).substr(0,16)])
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        print("ECO.EVO7 LS3.0/LS3.1 fail-closed hardening: FAIL %d/%d" % [failures.size(), checks])
        quit(1)

func _check(condition: bool, label: String) -> void:
    checks += 1
    if not condition:
        failures.append(label)
