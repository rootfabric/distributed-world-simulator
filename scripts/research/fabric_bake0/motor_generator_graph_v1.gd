extends RefCounted
## Canonical-derived winding + rigid-rotor graph for T5 motor/generator compilation.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/motor_electromagnetic_profile_v1.gd")

const SCHEMA := "planet_simulator.fabric_motor_generator_graph.v1"
const FIELDS: Array[String] = [
	"schema", "graph_id", "material_catalog", "electromagnetic_profiles",
	"winding_segments", "rotor_sectors", "graph_hash", "checksum",
]
const WINDING_FIELDS: Array[String] = [
	"winding_id", "profile_id", "wire_length_m", "wire_area_m2",
	"active_length_m", "lever_arm_m", "turns", "quality_ratio", "enabled",
]
const ROTOR_FIELDS: Array[String] = [
	"sector_id", "material_id", "volume_m3", "radius_m", "quality_ratio", "enabled",
]

static func create(
	graph_id: String,
	material_catalog: Dictionary,
	electromagnetic_profiles: Array,
	winding_segments: Array,
	rotor_sectors: Array
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"material_catalog": material_catalog.duplicate(true),
		"electromagnetic_profiles": U.sorted_dicts(electromagnetic_profiles, "profile_id"),
		"winding_segments": U.sorted_dicts(winding_segments, "winding_id"),
		"rotor_sectors": U.sorted_dicts(rotor_sectors, "sector_id"),
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
		return U.failure("UNSUPPORTED_MOTOR_GENERATOR_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_MOTOR_GENERATOR_GRAPH_ID")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success", false)):
		return U.failure("INVALID_MOTOR_GENERATOR_MATERIAL_CATALOG")
	if typeof(value.get("electromagnetic_profiles")) != TYPE_ARRAY or value.electromagnetic_profiles.is_empty():
		return U.failure("INVALID_MOTOR_GENERATOR_PROFILES")
	var profile_ids := {}
	var previous_profile := ""
	for index in range(value.electromagnetic_profiles.size()):
		var raw = value.electromagnetic_profiles[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_MOTOR_GENERATOR_PROFILE", {"index": index})
		var profile: Dictionary = raw
		checked = Profile.validate(profile)
		if not checked.success:
			return checked
		var conductor := MatterCatalog.material_by_id(value.material_catalog, String(profile.conductor_material_id))
		var magnet := MatterCatalog.material_by_id(value.material_catalog, String(profile.magnet_material_id))
		if conductor.is_empty() or magnet.is_empty():
			return U.failure("MOTOR_GENERATOR_PROFILE_MATERIAL_MISSING", {"profile_id": profile.profile_id})
		checked = Profile.validate_against_materials(profile, conductor, magnet)
		if not checked.success:
			return checked
		var current := String(profile.profile_id)
		if index > 0 and current <= previous_profile:
			return U.failure("MOTOR_GENERATOR_PROFILES_NOT_SORTED_UNIQUE")
		previous_profile = current
		profile_ids[current] = true

	if typeof(value.get("winding_segments")) != TYPE_ARRAY or value.winding_segments.is_empty():
		return U.failure("INVALID_MOTOR_GENERATOR_WINDINGS")
	var previous_winding := ""
	for index in range(value.winding_segments.size()):
		var raw_winding = value.winding_segments[index]
		if typeof(raw_winding) != TYPE_DICTIONARY:
			return U.failure("INVALID_MOTOR_GENERATOR_WINDING", {"index": index})
		var winding: Dictionary = raw_winding
		checked = U.validate_exact_fields(winding, WINDING_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(winding.get("winding_id"), 2):
			return U.failure("INVALID_MOTOR_WINDING_ID", {"index": index})
		if not profile_ids.has(String(winding.get("profile_id", ""))):
			return U.failure("MOTOR_WINDING_PROFILE_MISSING", {"index": index})
		for field in ["wire_length_m", "wire_area_m2", "active_length_m", "lever_arm_m", "quality_ratio"]:
			if not U.is_positive_number(winding.get(field)):
				return U.failure("INVALID_MOTOR_WINDING_PROPERTY", {"index": index, "field": field})
		if float(winding.quality_ratio) > 1.0:
			return U.failure("INVALID_MOTOR_WINDING_QUALITY", {"index": index})
		if not U.is_json_integer(winding.get("turns")) or int(winding.turns) < 1:
			return U.failure("INVALID_MOTOR_WINDING_TURNS", {"index": index})
		if typeof(winding.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_MOTOR_WINDING_ENABLED", {"index": index})
		var current_winding := String(winding.winding_id)
		if index > 0 and current_winding <= previous_winding:
			return U.failure("MOTOR_WINDINGS_NOT_SORTED_UNIQUE")
		previous_winding = current_winding

	if typeof(value.get("rotor_sectors")) != TYPE_ARRAY or value.rotor_sectors.is_empty():
		return U.failure("INVALID_MOTOR_GENERATOR_ROTOR")
	var previous_sector := ""
	for index in range(value.rotor_sectors.size()):
		var raw_sector = value.rotor_sectors[index]
		if typeof(raw_sector) != TYPE_DICTIONARY:
			return U.failure("INVALID_MOTOR_ROTOR_SECTOR", {"index": index})
		var sector: Dictionary = raw_sector
		checked = U.validate_exact_fields(sector, ROTOR_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(sector.get("sector_id"), 2):
			return U.failure("INVALID_MOTOR_ROTOR_SECTOR_ID", {"index": index})
		if MatterCatalog.material_by_id(value.material_catalog, String(sector.get("material_id", ""))).is_empty():
			return U.failure("MOTOR_ROTOR_MATERIAL_MISSING", {"index": index})
		for field in ["volume_m3", "radius_m", "quality_ratio"]:
			if not U.is_positive_number(sector.get(field)):
				return U.failure("INVALID_MOTOR_ROTOR_PROPERTY", {"index": index, "field": field})
		if float(sector.quality_ratio) > 1.0:
			return U.failure("INVALID_MOTOR_ROTOR_QUALITY", {"index": index})
		if typeof(sector.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_MOTOR_ROTOR_ENABLED", {"index": index})
		var current_sector := String(sector.sector_id)
		if index > 0 and current_sector <= previous_sector:
			return U.failure("MOTOR_ROTOR_SECTORS_NOT_SORTED_UNIQUE")
		previous_sector = current_sector

	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("MOTOR_GENERATOR_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func profile_by_id(value: Dictionary, profile_id: String) -> Dictionary:
	for raw in value.get("electromagnetic_profiles", []):
		if String(raw.get("profile_id", "")) == profile_id:
			return Dictionary(raw).duplicate(true)
	return {}

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id": value.graph_id,
		"material_catalog": value.material_catalog,
		"electromagnetic_profiles": value.electromagnetic_profiles,
		"winding_segments": value.winding_segments,
		"rotor_sectors": value.rotor_sectors,
	}
