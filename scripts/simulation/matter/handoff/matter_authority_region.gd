extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const RegionScript = preload("res://scripts/simulation/matter/interest/matter_interest_region.gd")

const SCHEMA: String = "planet_simulator.matter_authority_region.v1"
const MAX_RADIUS_CELLS: int = 8
const FIELDS: Array[String] = [
	"schema", "region_id", "body_id", "cell_level", "center_cell_address",
	"radius_cells", "checksum",
]


static func create(
	region_id: String,
	body_id: String,
	cell_level: int,
	center_cell_address: Dictionary,
	radius_cells: int
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"region_id": region_id.strip_edges().to_lower(),
		"body_id": body_id.strip_edges().to_lower(),
		"cell_level": cell_level,
		"center_cell_address": center_cell_address.duplicate(true),
		"radius_cells": radius_cells,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if String(value.get("schema", "")) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_AUTHORITY_REGION_SCHEMA")
	for field in ["region_id", "body_id"]:
		if not MatterUtilsScript.is_canonical_id(value.get(field), 2):
			return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_REGION_ID", {"field": field})
	if not MatterUtilsScript.is_json_integer(value.get("cell_level")) \
			or not MatterUtilsScript.is_json_integer(value.get("radius_cells")):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_REGION_INTEGER")
	if int(value["cell_level"]) < 0 or int(value["radius_cells"]) < 0 \
			or int(value["radius_cells"]) > MAX_RADIUS_CELLS:
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_REGION_BOUNDS")
	if typeof(value.get("center_cell_address")) != TYPE_DICTIONARY:
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_REGION_CENTER")
	if int(value["center_cell_address"].get("level", -1)) != int(value["cell_level"]):
		return MatterUtilsScript.failure("MATTER_AUTHORITY_REGION_CENTER_LEVEL_MISMATCH")
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_authority_region")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func validate_for_grid(grid_profile: Dictionary, value: Dictionary) -> Dictionary:
	var validation: Dictionary = validate(value)
	if not bool(validation.get("success", false)):
		return validation
	if not bool(GridProfileScript.validate(grid_profile).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_AUTHORITY_REGION_GRID")
	if String(value["body_id"]) != String(grid_profile["body_id"]):
		return MatterUtilsScript.failure("MATTER_AUTHORITY_REGION_BODY_MISMATCH")
	if int(value["cell_level"]) > int(grid_profile["max_level"]):
		return MatterUtilsScript.failure("MATTER_AUTHORITY_REGION_LEVEL_EXCEEDS_GRID")
	var center_validation: Dictionary = CellGridScript.validate_address(
		grid_profile, value["center_cell_address"]
	)
	if not bool(center_validation.get("success", false)):
		return MatterUtilsScript.failure("MATTER_AUTHORITY_REGION_CENTER_GRID_MISMATCH")
	return MatterUtilsScript.success()


static func contains_cell_address(
	grid_profile: Dictionary,
	region: Dictionary,
	cell_address: Dictionary
) -> bool:
	if not bool(validate_for_grid(grid_profile, region).get("success", false)) \
			or not bool(CellGridScript.validate_address(grid_profile, cell_address).get("success", false)) \
			or int(cell_address["level"]) != int(region["cell_level"]):
		return false
	var center_indices: Array = RegionScript.indices_for_cell(region["center_cell_address"])
	var target_indices: Array = RegionScript.indices_for_cell(cell_address)
	if center_indices.size() != 3 or target_indices.size() != 3:
		return false
	var radius: int = int(region["radius_cells"])
	return absi(int(target_indices[0]) - int(center_indices[0])) <= radius \
		and absi(int(target_indices[1]) - int(center_indices[1])) <= radius \
		and absi(int(target_indices[2]) - int(center_indices[2])) <= radius


static func contains_brick_address(
	grid_profile: Dictionary,
	region: Dictionary,
	brick_address: Dictionary
) -> bool:
	if typeof(brick_address.get("cell_address")) != TYPE_DICTIONARY:
		return false
	return contains_cell_address(grid_profile, region, brick_address["cell_address"])


static func contains_snapshot(
	grid_profile: Dictionary,
	region: Dictionary,
	snapshot: Dictionary
) -> bool:
	return typeof(snapshot.get("address")) == TYPE_DICTIONARY \
		and contains_brick_address(grid_profile, region, snapshot["address"])


static func cell_ids(grid_profile: Dictionary, region: Dictionary) -> Array:
	if not bool(validate_for_grid(grid_profile, region).get("success", false)):
		return []
	var center_indices: Array = RegionScript.indices_for_cell(region["center_cell_address"])
	if center_indices.size() != 3:
		return []
	var level: int = int(region["cell_level"])
	var radius: int = int(region["radius_cells"])
	var axis_count: int = 1 << level
	var result: Array = []
	for z in range(maxi(0, int(center_indices[2]) - radius), mini(axis_count - 1, int(center_indices[2]) + radius) + 1):
		for y in range(maxi(0, int(center_indices[1]) - radius), mini(axis_count - 1, int(center_indices[1]) + radius) + 1):
			for x in range(maxi(0, int(center_indices[0]) - radius), mini(axis_count - 1, int(center_indices[0]) + radius) + 1):
				var address: Dictionary = RegionScript.cell_for_indices(grid_profile, level, x, y, z)
				if not address.is_empty():
					result.append(String(address["cell_id"]))
	result.sort()
	return result


static func overlaps(grid_profile: Dictionary, left: Dictionary, right: Dictionary) -> bool:
	if not bool(validate_for_grid(grid_profile, left).get("success", false)) \
			or not bool(validate_for_grid(grid_profile, right).get("success", false)) \
			or int(left["cell_level"]) != int(right["cell_level"]):
		return false
	var left_ids: Dictionary = {}
	for cell_id in cell_ids(grid_profile, left):
		left_ids[String(cell_id)] = true
	for cell_id in cell_ids(grid_profile, right):
		if left_ids.has(String(cell_id)):
			return true
	return false
