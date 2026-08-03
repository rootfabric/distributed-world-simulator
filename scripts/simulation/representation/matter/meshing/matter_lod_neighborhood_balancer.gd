extends RefCounted

const RepresentationUtils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const GridProfile = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGrid = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")

const SCHEMA := "planet_simulator.matter_lod_neighborhood_plan.v1"
const MAX_LOD_LEVEL: int = 2
const ENTRY_FIELDS: Array[String] = ["cell_address", "lod_level"]
const FIELDS: Array[String] = ["schema", "entries", "adjustment_count", "checksum"]
const ADJACENCY_TOLERANCE_M: float = 0.000000001


static func balance(entries: Array, grid_profile: Dictionary) -> Dictionary:
	if not bool(GridProfile.validate(grid_profile).get("success", false)):
		return {}
	var normalized: Array = []
	var seen: Dictionary = {}
	var common_level: int = -1
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return {}
		var entry: Dictionary = raw_entry
		if not bool(RepresentationUtils.validate_exact_fields(entry, ENTRY_FIELDS).get("success", false)) \
			or typeof(entry.get("cell_address")) != TYPE_DICTIONARY \
			or not bool(CellGrid.validate_address(grid_profile, entry["cell_address"]).get("success", false)) \
			or not RepresentationUtils.is_json_integer(entry.get("lod_level")):
			return {}
		var lod_level: int = int(entry["lod_level"])
		if lod_level < 0 or lod_level > MAX_LOD_LEVEL:
			return {}
		var cell_address: Dictionary = entry["cell_address"]
		if common_level < 0:
			common_level = int(cell_address["level"])
		elif int(cell_address["level"]) != common_level:
			return {}
		var cell_id: String = String(cell_address["cell_id"])
		if seen.has(cell_id):
			return {}
		seen[cell_id] = true
		normalized.append({"cell_address": cell_address.duplicate(true), "lod_level": lod_level})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["cell_address"]["cell_id"]) < String(b["cell_address"]["cell_id"])
	)
	var adjustment_count: int = 0
	var changed: bool = true
	while changed:
		changed = false
		for first in range(normalized.size()):
			for second in range(first + 1, normalized.size()):
				if not _face_adjacent(
					normalized[first]["cell_address"], normalized[second]["cell_address"], grid_profile
				):
					continue
				var lod_a: int = int(normalized[first]["lod_level"])
				var lod_b: int = int(normalized[second]["lod_level"])
				if absi(lod_a - lod_b) <= 1:
					continue
				if lod_a > lod_b:
					normalized[first]["lod_level"] = lod_b + 1
				else:
					normalized[second]["lod_level"] = lod_a + 1
				adjustment_count += 1
				changed = true
	var value: Dictionary = {
		"schema": SCHEMA,
		"entries": normalized,
		"adjustment_count": adjustment_count,
		"checksum": "",
	}
	value["checksum"] = RepresentationUtils.compute_checksum(value)
	return value if bool(validate(value, grid_profile).get("success", false)) else {}


static func validate(value: Dictionary, grid_profile: Dictionary) -> Dictionary:
	var checked: Dictionary = RepresentationUtils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA or not bool(GridProfile.validate(grid_profile).get("success", false)):
		return RepresentationUtils.failure("INVALID_MATTER_LOD_PLAN_SCHEMA")
	if typeof(value.get("entries")) != TYPE_ARRAY or value["entries"].is_empty():
		return RepresentationUtils.failure("EMPTY_MATTER_LOD_PLAN")
	if not RepresentationUtils.is_json_integer(value.get("adjustment_count")) \
		or int(value["adjustment_count"]) < 0:
		return RepresentationUtils.failure("INVALID_MATTER_LOD_ADJUSTMENT_COUNT")
	var previous_id: String = ""
	var common_level: int = -1
	for index in range(value["entries"].size()):
		var raw_entry = value["entries"][index]
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return RepresentationUtils.failure("INVALID_MATTER_LOD_ENTRY", {"index": index})
		var entry: Dictionary = raw_entry
		checked = RepresentationUtils.validate_exact_fields(entry, ENTRY_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		if typeof(entry.get("cell_address")) != TYPE_DICTIONARY \
			or not bool(CellGrid.validate_address(grid_profile, entry["cell_address"]).get("success", false)):
			return RepresentationUtils.failure("INVALID_MATTER_LOD_CELL", {"index": index})
		if not RepresentationUtils.is_json_integer(entry.get("lod_level")) \
			or int(entry["lod_level"]) < 0 or int(entry["lod_level"]) > MAX_LOD_LEVEL:
			return RepresentationUtils.failure("INVALID_MATTER_LOD_LEVEL", {"index": index})
		var cell_address: Dictionary = entry["cell_address"]
		var cell_id: String = String(cell_address["cell_id"])
		if index > 0 and cell_id <= previous_id:
			return RepresentationUtils.failure("MATTER_LOD_ENTRIES_NOT_SORTED_UNIQUE")
		if common_level < 0:
			common_level = int(cell_address["level"])
		elif int(cell_address["level"]) != common_level:
			return RepresentationUtils.failure("MATTER_LOD_MIXED_CELL_LEVEL")
		previous_id = cell_id
	for first in range(value["entries"].size()):
		for second in range(first + 1, value["entries"].size()):
			var a: Dictionary = value["entries"][first]
			var b: Dictionary = value["entries"][second]
			if _face_adjacent(a["cell_address"], b["cell_address"], grid_profile) \
				and absi(int(a["lod_level"]) - int(b["lod_level"])) > 1:
				return RepresentationUtils.failure("MATTER_LOD_NEIGHBOR_DELTA_EXCEEDED")
	return RepresentationUtils.validate_checksum(value)


static func _face_adjacent(a: Dictionary, b: Dictionary, grid_profile: Dictionary) -> bool:
	var bounds_a: Dictionary = CellGrid.bounds(grid_profile, a)
	var bounds_b: Dictionary = CellGrid.bounds(grid_profile, b)
	if bounds_a.is_empty() or bounds_b.is_empty():
		return false
	var minimum_a := Vector3(float(bounds_a["minimum_m"][0]), float(bounds_a["minimum_m"][1]), float(bounds_a["minimum_m"][2]))
	var maximum_a := Vector3(float(bounds_a["maximum_m"][0]), float(bounds_a["maximum_m"][1]), float(bounds_a["maximum_m"][2]))
	var minimum_b := Vector3(float(bounds_b["minimum_m"][0]), float(bounds_b["minimum_m"][1]), float(bounds_b["minimum_m"][2]))
	var maximum_b := Vector3(float(bounds_b["maximum_m"][0]), float(bounds_b["maximum_m"][1]), float(bounds_b["maximum_m"][2]))
	for axis in range(3):
		var touching: bool = absf(maximum_a[axis] - minimum_b[axis]) <= ADJACENCY_TOLERANCE_M \
			or absf(maximum_b[axis] - minimum_a[axis]) <= ADJACENCY_TOLERANCE_M
		if not touching:
			continue
		var tangent_a: int = (axis + 1) % 3
		var tangent_b: int = (axis + 2) % 3
		var overlap_a: float = minf(maximum_a[tangent_a], maximum_b[tangent_a]) \
			- maxf(minimum_a[tangent_a], minimum_b[tangent_a])
		var overlap_b: float = minf(maximum_a[tangent_b], maximum_b[tangent_b]) \
			- maxf(minimum_a[tangent_b], minimum_b[tangent_b])
		if overlap_a > ADJACENCY_TOLERANCE_M and overlap_b > ADJACENCY_TOLERANCE_M:
			return true
	return false
