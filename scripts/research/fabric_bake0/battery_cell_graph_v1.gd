extends RefCounted
## Canonical-derived cell topology + material catalog for T3 battery compilation.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/battery_electrochemical_profile_v1.gd")

const SCHEMA := "planet_simulator.fabric_battery_cell_graph.v1"
const FIELDS: Array[String] = [
	"schema", "graph_id", "material_catalog", "profiles",
	"series_group_count", "parallel_slot_count", "cells", "graph_hash", "checksum",
]
const CELL_FIELDS: Array[String] = [
	"cell_id", "series_index", "parallel_index", "profile_id", "case_material_id",
	"active_volume_m3", "case_volume_m3", "electrode_area_m2", "current_path_length_m",
	"case_surface_area_m2", "case_wall_thickness_m", "quality_ratio", "enabled",
]

static func create(
	graph_id: String,
	material_catalog: Dictionary,
	profiles: Array,
	series_group_count: int,
	parallel_slot_count: int,
	cells: Array
) -> Dictionary:
	var ordered_profiles := U.sorted_dicts(profiles, "profile_id")
	var ordered_cells := U.sorted_dicts(cells, "cell_id")
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"material_catalog": material_catalog.duplicate(true),
		"profiles": ordered_profiles,
		"series_group_count": series_group_count,
		"parallel_slot_count": parallel_slot_count,
		"cells": ordered_cells,
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
		return U.failure("UNSUPPORTED_BATTERY_CELL_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_BATTERY_GRAPH_ID")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success", false)):
		return U.failure("INVALID_BATTERY_MATERIAL_CATALOG")
	if not U.is_json_integer(value.get("series_group_count")) or int(value.series_group_count) < 1:
		return U.failure("INVALID_BATTERY_SERIES_GROUP_COUNT")
	if not U.is_json_integer(value.get("parallel_slot_count")) or int(value.parallel_slot_count) < 1:
		return U.failure("INVALID_BATTERY_PARALLEL_SLOT_COUNT")
	if typeof(value.get("profiles")) != TYPE_ARRAY or value.profiles.is_empty():
		return U.failure("INVALID_BATTERY_PROFILES")
	var profile_ids := {}
	var previous_profile := ""
	for index in range(value.profiles.size()):
		var raw = value.profiles[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_BATTERY_PROFILE", {"index": index})
		var profile: Dictionary = raw
		checked = Profile.validate(profile)
		if not checked.success:
			return checked
		var material := MatterCatalog.material_by_id(value.material_catalog, String(profile.active_material_id))
		if material.is_empty():
			return U.failure("BATTERY_PROFILE_MATERIAL_MISSING", {"profile_id": profile.profile_id})
		checked = Profile.validate_against_material(profile, material)
		if not checked.success:
			return checked
		var current_profile := String(profile.profile_id)
		if index > 0 and current_profile <= previous_profile:
			return U.failure("BATTERY_PROFILES_NOT_SORTED_UNIQUE")
		previous_profile = current_profile
		profile_ids[current_profile] = true
	if typeof(value.get("cells")) != TYPE_ARRAY or value.cells.is_empty():
		return U.failure("INVALID_BATTERY_CELLS")
	var slots := {}
	var previous_cell := ""
	for index in range(value.cells.size()):
		var raw_cell = value.cells[index]
		if typeof(raw_cell) != TYPE_DICTIONARY:
			return U.failure("INVALID_BATTERY_CELL", {"index": index})
		var cell: Dictionary = raw_cell
		checked = U.validate_exact_fields(cell, CELL_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(cell.get("cell_id"), 2):
			return U.failure("INVALID_BATTERY_CELL_ID", {"index": index})
		if not U.is_json_integer(cell.get("series_index")) or int(cell.series_index) < 0 or int(cell.series_index) >= int(value.series_group_count):
			return U.failure("INVALID_BATTERY_CELL_SERIES_INDEX", {"index": index})
		if not U.is_json_integer(cell.get("parallel_index")) or int(cell.parallel_index) < 0 or int(cell.parallel_index) >= int(value.parallel_slot_count):
			return U.failure("INVALID_BATTERY_CELL_PARALLEL_INDEX", {"index": index})
		if not profile_ids.has(String(cell.get("profile_id", ""))):
			return U.failure("BATTERY_CELL_PROFILE_MISSING", {"index": index})
		if MatterCatalog.material_by_id(value.material_catalog, String(cell.get("case_material_id", ""))).is_empty():
			return U.failure("BATTERY_CELL_CASE_MATERIAL_MISSING", {"index": index})
		for field in [
			"active_volume_m3", "case_volume_m3", "electrode_area_m2", "current_path_length_m",
			"case_surface_area_m2", "case_wall_thickness_m"
		]:
			if not U.is_positive_number(cell.get(field)):
				return U.failure("INVALID_BATTERY_CELL_GEOMETRY", {"index": index, "field": field})
		if not U.is_positive_number(cell.get("quality_ratio")) or float(cell.quality_ratio) > 1.0:
			return U.failure("INVALID_BATTERY_CELL_QUALITY", {"index": index})
		if typeof(cell.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_BATTERY_CELL_ENABLED", {"index": index})
		var slot := "%d:%d" % [int(cell.series_index), int(cell.parallel_index)]
		if slots.has(slot):
			return U.failure("BATTERY_CELL_SLOT_DUPLICATE", {"slot": slot})
		slots[slot] = true
		var current_cell := String(cell.cell_id)
		if index > 0 and current_cell <= previous_cell:
			return U.failure("BATTERY_CELLS_NOT_SORTED_UNIQUE")
		previous_cell = current_cell
	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("BATTERY_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func profile_by_id(value: Dictionary, profile_id: String) -> Dictionary:
	for profile in value.get("profiles", []):
		if String(profile.get("profile_id", "")) == profile_id:
			return Dictionary(profile).duplicate(true)
	return {}

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id": value.graph_id,
		"material_catalog": value.material_catalog,
		"profiles": value.profiles,
		"series_group_count": value.series_group_count,
		"parallel_slot_count": value.parallel_slot_count,
		"cells": value.cells,
	}
