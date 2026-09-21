extends RefCounted
## Canonical thermal-pack topology for R5.2/T4 exact stateful-filter reduction.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")

const SCHEMA := "planet_simulator.fabric_thermal_pack_graph.v1"
const FIELDS: Array[String] = [
	"schema", "graph_id", "material_catalog", "layer_count", "lane_count", "cells",
	"interlayer_contact_area_m2", "interlayer_contact_length_m",
	"ambient_surface_area_m2", "ambient_wall_thickness_m", "graph_hash", "checksum",
]
const CELL_FIELDS: Array[String] = [
	"cell_id", "layer_index", "lane_index", "material_id", "volume_m3", "enabled",
]

static func create(
	graph_id: String,
	material_catalog: Dictionary,
	layer_count: int,
	lane_count: int,
	cells: Array,
	interlayer_contact_area_m2: float,
	interlayer_contact_length_m: float,
	ambient_surface_area_m2: float,
	ambient_wall_thickness_m: float
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"material_catalog": material_catalog.duplicate(true),
		"layer_count": layer_count,
		"lane_count": lane_count,
		"cells": U.sorted_dicts(cells, "cell_id"),
		"interlayer_contact_area_m2": interlayer_contact_area_m2,
		"interlayer_contact_length_m": interlayer_contact_length_m,
		"ambient_surface_area_m2": ambient_surface_area_m2,
		"ambient_wall_thickness_m": ambient_wall_thickness_m,
		"graph_hash": "",
		"checksum": "",
	}
	value.graph_hash = U.canonical_hash(_identity(value))
	value.checksum = U.compute_checksum(value)
	return value if validate(value).success else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := U.validate_exact_fields(value, FIELDS)
	if not checked.success:
		return checked
	if value.get("schema") != SCHEMA:
		return U.failure("UNSUPPORTED_THERMAL_PACK_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_THERMAL_PACK_GRAPH_ID")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success", false)):
		return U.failure("INVALID_THERMAL_PACK_MATERIAL_CATALOG")
	for field in ["layer_count", "lane_count"]:
		if not U.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return U.failure("INVALID_THERMAL_PACK_DIMENSION", {"field": field})
	if int(value.layer_count) < 2:
		return U.failure("THERMAL_PACK_REQUIRES_TWO_LAYERS")
	for field in ["interlayer_contact_area_m2", "interlayer_contact_length_m", "ambient_surface_area_m2", "ambient_wall_thickness_m"]:
		if not U.is_positive_number(value.get(field)):
			return U.failure("INVALID_THERMAL_PACK_GEOMETRY", {"field": field})
	if typeof(value.get("cells")) != TYPE_ARRAY:
		return U.failure("INVALID_THERMAL_PACK_CELLS")
	if value.cells.size() != int(value.layer_count) * int(value.lane_count):
		return U.failure("THERMAL_PACK_CELL_COUNT_MISMATCH")
	var slots := {}
	var previous := ""
	for index in range(value.cells.size()):
		var raw = value.cells[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_THERMAL_PACK_CELL", {"index": index})
		var cell: Dictionary = raw
		checked = U.validate_exact_fields(cell, CELL_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(cell.get("cell_id"), 2):
			return U.failure("INVALID_THERMAL_PACK_CELL_ID", {"index": index})
		if not U.is_json_integer(cell.get("layer_index")) or int(cell.layer_index) < 0 or int(cell.layer_index) >= int(value.layer_count):
			return U.failure("INVALID_THERMAL_PACK_LAYER_INDEX", {"index": index})
		if not U.is_json_integer(cell.get("lane_index")) or int(cell.lane_index) < 0 or int(cell.lane_index) >= int(value.lane_count):
			return U.failure("INVALID_THERMAL_PACK_LANE_INDEX", {"index": index})
		if MatterCatalog.material_by_id(value.material_catalog, String(cell.get("material_id", ""))).is_empty():
			return U.failure("THERMAL_PACK_CELL_MATERIAL_MISSING", {"index": index})
		if not U.is_positive_number(cell.get("volume_m3")):
			return U.failure("INVALID_THERMAL_PACK_CELL_VOLUME", {"index": index})
		if typeof(cell.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_THERMAL_PACK_CELL_ENABLED", {"index": index})
		var slot := "%d:%d" % [int(cell.layer_index), int(cell.lane_index)]
		if slots.has(slot):
			return U.failure("THERMAL_PACK_CELL_SLOT_DUPLICATE", {"slot": slot})
		slots[slot] = true
		var current := String(cell.cell_id)
		if index > 0 and current <= previous:
			return U.failure("THERMAL_PACK_CELLS_NOT_SORTED_UNIQUE")
		previous = current
	if slots.size() != int(value.layer_count) * int(value.lane_count):
		return U.failure("THERMAL_PACK_SLOT_COVERAGE_INCOMPLETE")
	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("THERMAL_PACK_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func cell_by_slot(value: Dictionary, layer_index: int, lane_index: int) -> Dictionary:
	for raw in value.get("cells", []):
		var cell: Dictionary = raw
		if int(cell.layer_index) == layer_index and int(cell.lane_index) == lane_index:
			return cell.duplicate(true)
	return {}

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id": value.graph_id,
		"material_catalog": value.material_catalog,
		"layer_count": value.layer_count,
		"lane_count": value.lane_count,
		"cells": value.cells,
		"interlayer_contact_area_m2": value.interlayer_contact_area_m2,
		"interlayer_contact_length_m": value.interlayer_contact_length_m,
		"ambient_surface_area_m2": value.ambient_surface_area_m2,
		"ambient_wall_thickness_m": value.ambient_wall_thickness_m,
	}
