extends RefCounted
## Four-bank H-bridge source topology for R5.2/T6 power-stage compilation.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Profile = preload("res://scripts/research/fabric_bake0/power_stage_semiconductor_profile_v1.gd")

const SCHEMA := "planet_simulator.fabric_power_stage_graph.v1"
const BANK_COUNT := 4
const FIELDS: Array[String] = [
	"schema", "graph_id", "material_catalog", "semiconductor_profiles",
	"switch_dies", "graph_hash", "checksum",
]
const DIE_FIELDS: Array[String] = [
	"die_id", "bank_index", "profile_id", "current_path_length_m",
	"active_area_m2", "quality_ratio", "enabled",
]

static func create(
	graph_id: String,
	material_catalog: Dictionary,
	semiconductor_profiles: Array,
	switch_dies: Array
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"graph_id": graph_id,
		"material_catalog": material_catalog.duplicate(true),
		"semiconductor_profiles": U.sorted_dicts(semiconductor_profiles, "profile_id"),
		"switch_dies": U.sorted_dicts(switch_dies, "die_id"),
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
		return U.failure("UNSUPPORTED_POWER_STAGE_GRAPH_SCHEMA")
	if not U.is_canonical_id(value.get("graph_id"), 2):
		return U.failure("INVALID_POWER_STAGE_GRAPH_ID")
	if typeof(value.get("material_catalog")) != TYPE_DICTIONARY or not bool(MatterCatalog.validate(value.material_catalog).get("success", false)):
		return U.failure("INVALID_POWER_STAGE_MATERIAL_CATALOG")
	if typeof(value.get("semiconductor_profiles")) != TYPE_ARRAY or value.semiconductor_profiles.is_empty():
		return U.failure("INVALID_POWER_STAGE_PROFILES")
	var profile_ids := {}
	var previous_profile := ""
	for index in range(value.semiconductor_profiles.size()):
		var raw = value.semiconductor_profiles[index]
		if typeof(raw) != TYPE_DICTIONARY:
			return U.failure("INVALID_POWER_STAGE_PROFILE", {"index": index})
		var profile: Dictionary = raw
		checked = Profile.validate(profile)
		if not checked.success:
			return checked
		var material := MatterCatalog.material_by_id(value.material_catalog, String(profile.semiconductor_material_id))
		if material.is_empty():
			return U.failure("POWER_STAGE_PROFILE_MATERIAL_MISSING", {"profile_id": profile.profile_id})
		checked = Profile.validate_against_material(profile, material)
		if not checked.success:
			return checked
		var current := String(profile.profile_id)
		if index > 0 and current <= previous_profile:
			return U.failure("POWER_STAGE_PROFILES_NOT_SORTED_UNIQUE")
		previous_profile = current
		profile_ids[current] = true

	if typeof(value.get("switch_dies")) != TYPE_ARRAY or value.switch_dies.is_empty():
		return U.failure("INVALID_POWER_STAGE_SWITCH_DIES")
	var previous_die := ""
	var bank_counts := [0, 0, 0, 0]
	for index in range(value.switch_dies.size()):
		var raw_die = value.switch_dies[index]
		if typeof(raw_die) != TYPE_DICTIONARY:
			return U.failure("INVALID_POWER_STAGE_SWITCH_DIE", {"index": index})
		var die: Dictionary = raw_die
		checked = U.validate_exact_fields(die, DIE_FIELDS)
		if not checked.success:
			return checked
		if not U.is_canonical_id(die.get("die_id"), 2):
			return U.failure("INVALID_POWER_STAGE_DIE_ID", {"index": index})
		if not U.is_json_integer(die.get("bank_index")) or int(die.bank_index) < 0 or int(die.bank_index) >= BANK_COUNT:
			return U.failure("INVALID_POWER_STAGE_BANK_INDEX", {"index": index})
		if not profile_ids.has(String(die.get("profile_id", ""))):
			return U.failure("POWER_STAGE_DIE_PROFILE_MISSING", {"index": index})
		for field in ["current_path_length_m", "active_area_m2", "quality_ratio"]:
			if not U.is_positive_number(die.get(field)):
				return U.failure("INVALID_POWER_STAGE_DIE_PROPERTY", {"index": index, "field": field})
		if float(die.quality_ratio) > 1.0:
			return U.failure("INVALID_POWER_STAGE_DIE_QUALITY", {"index": index})
		if typeof(die.get("enabled")) != TYPE_BOOL:
			return U.failure("INVALID_POWER_STAGE_DIE_ENABLED", {"index": index})
		bank_counts[int(die.bank_index)] += 1
		var current_die := String(die.die_id)
		if index > 0 and current_die <= previous_die:
			return U.failure("POWER_STAGE_DIES_NOT_SORTED_UNIQUE")
		previous_die = current_die
	for bank_index in range(BANK_COUNT):
		if int(bank_counts[bank_index]) < 1:
			return U.failure("POWER_STAGE_BANK_MISSING", {"bank_index": bank_index})
	if not U.is_lower_hex_64(value.get("graph_hash")) or String(value.graph_hash) != U.canonical_hash(_identity(value)):
		return U.failure("POWER_STAGE_GRAPH_HASH_MISMATCH")
	return U.validate_checksum(value)

static func profile_by_id(value: Dictionary, profile_id: String) -> Dictionary:
	for raw in value.get("semiconductor_profiles", []):
		if String(raw.get("profile_id", "")) == profile_id:
			return Dictionary(raw).duplicate(true)
	return {}

static func _identity(value: Dictionary) -> Dictionary:
	return {
		"graph_id": value.graph_id,
		"material_catalog": value.material_catalog,
		"semiconductor_profiles": value.semiconductor_profiles,
		"switch_dies": value.switch_dies,
	}
