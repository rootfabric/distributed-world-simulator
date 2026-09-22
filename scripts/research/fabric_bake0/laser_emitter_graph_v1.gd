extends RefCounted
## Common-cavity gain-cell array for R5.2/T9.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/laser_emitter_photonic_profile_v1.gd")

const SCHEMA := "planet_simulator.fabric_laser_emitter_graph.v1"
const FIELDS: Array[String] = [
	"schema", "graph_id", "material_catalog", "photonic_profiles", "gain_cells",
	"graph_hash", "checksum",
]
const CELL_FIELDS: Array[String] = [
	"cell_id", "profile_id", "active_area_m2", "current_path_length_m",
	"quality_ratio", "enabled",
]

static func create(
	graph_id: String,
	material_catalog: Dictionary,
	photonic_profiles: Array,
	gain_cells: Array
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"material_catalog": material_catalog.duplicate(true),
		"photonic_profiles": U.sorted_dicts(photonic_profiles, "profile_id"),
		"gain_cells": U.sorted_dicts(gain_cells, "cell_id"),
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
		return U.failure("UNSUPPORTED_LASER_EMITTER_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_LASER_EMITTER_GRAPH_ID")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success", false)):
		return U.failure("INVALID_LASER_EMITTER_MATERIAL_CATALOG")
	if typeof(value.get("photonic_profiles")) != TYPE_ARRAY or value.photonic_profiles.is_empty():
		return U.failure("INVALID_LASER_EMITTER_PROFILES")
	var profile_ids := {}
	var previous_profile := ""
	for index in range(value.photonic_profiles.size()):
		var raw = value.photonic_profiles[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_LASER_EMITTER_PROFILE", {"index": index})
		var profile: Dictionary = raw
		checked = Profile.validate(profile)
		if not checked.success:
			return checked
		var material := MatterCatalog.material_by_id(value.material_catalog, String(profile.active_material_id))
		if material.is_empty():
			return U.failure("LASER_EMITTER_PROFILE_MATERIAL_MISSING", {"profile_id": profile.profile_id})
		checked = Profile.validate_against_material(profile, material)
		if not checked.success:
			return checked
		var pid := String(profile.profile_id)
		if index > 0 and pid <= previous_profile:
			return U.failure("LASER_EMITTER_PROFILES_NOT_SORTED_UNIQUE")
		previous_profile = pid
		profile_ids[pid] = true

	if typeof(value.get("gain_cells")) != TYPE_ARRAY or value.gain_cells.is_empty():
		return U.failure("INVALID_LASER_EMITTER_GAIN_CELLS")
	var previous_cell := ""
	for index in range(value.gain_cells.size()):
		var raw_cell = value.gain_cells[index]
		if typeof(raw_cell) != TYPE_DICTIONARY:
			return U.failure("INVALID_LASER_GAIN_CELL", {"index": index})
		var cell: Dictionary = raw_cell
		checked = U.validate_exact_fields(cell, CELL_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(cell.get("cell_id"), 2):
			return U.failure("INVALID_LASER_GAIN_CELL_ID", {"index": index})
		if not profile_ids.has(String(cell.get("profile_id", ""))):
			return U.failure("LASER_GAIN_CELL_PROFILE_MISSING", {"index": index})
		for field in ["active_area_m2", "current_path_length_m", "quality_ratio"]:
			if not U.is_positive_number(cell.get(field)):
				return U.failure("INVALID_LASER_GAIN_CELL_PROPERTY", {"index": index, "field": field})
		if float(cell.quality_ratio) > 1.0:
			return U.failure("INVALID_LASER_GAIN_CELL_QUALITY", {"index": index})
		if typeof(cell.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_LASER_GAIN_CELL_ENABLED", {"index": index})
		var cid := String(cell.cell_id)
		if index > 0 and cid <= previous_cell:
			return U.failure("LASER_GAIN_CELLS_NOT_SORTED_UNIQUE")
		previous_cell = cid

	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("LASER_EMITTER_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func profile_by_id(value: Dictionary, profile_id: String) -> Dictionary:
	for raw in value.get("photonic_profiles", []):
		if String(raw.get("profile_id", "")) == profile_id:
			return Dictionary(raw).duplicate(true)
	return {}

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id": value.graph_id,
		"material_catalog": value.material_catalog,
		"photonic_profiles": value.photonic_profiles,
		"gain_cells": value.gain_cells,
	}
