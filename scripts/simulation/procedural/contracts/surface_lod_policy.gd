extends RefCounted

const GeoUtilsScript = preload("res://scripts/simulation/procedural/geo_contract_utils.gd")
const SurfaceCellKeyScript = preload("res://scripts/simulation/procedural/contracts/surface_cell_key.gd")

const SCHEMA: String = "planet_simulator.surface_lod_policy.v1"
const FIELDS: Array[String] = [
	"schema",
	"min_lod",
	"max_lod",
	"refine_ratio",
	"coarsen_ratio",
	"minimum_distance_m",
	"max_leaf_cells",
	"checksum",
]


static func create(
	min_lod: int,
	max_lod: int,
	refine_ratio: float,
	coarsen_ratio: float,
	minimum_distance_m: float,
	max_leaf_cells: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"min_lod": min_lod,
		"max_lod": max_lod,
		"refine_ratio": refine_ratio,
		"coarsen_ratio": coarsen_ratio,
		"minimum_distance_m": minimum_distance_m,
		"max_leaf_cells": max_leaf_cells,
		"checksum": "",
	}
	value["checksum"] = GeoUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = GeoUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return GeoUtilsScript.failure("UNSUPPORTED_SURFACE_LOD_POLICY_SCHEMA")
	for field in ["min_lod", "max_lod", "max_leaf_cells"]:
		if not GeoUtilsScript.is_json_integer(value.get(field)):
			return GeoUtilsScript.failure("INVALID_SURFACE_LOD_POLICY_INTEGER", {"field": field})
	var min_lod: int = int(value["min_lod"])
	var max_lod: int = int(value["max_lod"])
	if min_lod < 0 or max_lod < min_lod or max_lod > SurfaceCellKeyScript.MAX_LOD:
		return GeoUtilsScript.failure("INVALID_SURFACE_LOD_RANGE")
	if not GeoUtilsScript.is_positive_number(value.get("refine_ratio")):
		return GeoUtilsScript.failure("INVALID_SURFACE_LOD_REFINE_RATIO")
	if not GeoUtilsScript.is_positive_number(value.get("coarsen_ratio")):
		return GeoUtilsScript.failure("INVALID_SURFACE_LOD_COARSEN_RATIO")
	if float(value["coarsen_ratio"]) >= float(value["refine_ratio"]):
		return GeoUtilsScript.failure("INVALID_SURFACE_LOD_HYSTERESIS")
	if not GeoUtilsScript.is_positive_number(value.get("minimum_distance_m")):
		return GeoUtilsScript.failure("INVALID_SURFACE_LOD_MINIMUM_DISTANCE")
	var max_leaf_cells: int = int(value["max_leaf_cells"])
	if max_leaf_cells < 6:
		return GeoUtilsScript.failure("INVALID_SURFACE_LOD_LEAF_BUDGET")
	var minimum_required_leaves: int = 6
	for _level in range(min_lod):
		if minimum_required_leaves > max_leaf_cells / 4:
			return GeoUtilsScript.failure("SURFACE_LOD_LEAF_BUDGET_BELOW_MIN_LOD")
		minimum_required_leaves *= 4
	if max_leaf_cells < minimum_required_leaves:
		return GeoUtilsScript.failure("SURFACE_LOD_LEAF_BUDGET_BELOW_MIN_LOD")
	var safe: Dictionary = GeoUtilsScript.validate_json_safe(value, "$.surface_lod_policy")
	if not bool(safe.get("success", false)):
		return safe
	return GeoUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return GeoUtilsScript.normalize(value, validate)
