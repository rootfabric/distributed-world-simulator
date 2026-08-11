extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_seed_lifecycle_profile.v1"
const VERSION := "1.0.0"

const FIELD_NAMES: Array[String] = [
	"schema", "version",
	"evaluation_biomass_kg_m2",
	"germination_min_coupled_net",
	"germination_min_stored_energy",
	"germination_energy_cost",
	"juvenile_age_fraction",
	"adult_age_fraction",
	"reproductive_age_fraction",
	"senescent_age_fraction",
	"reproduction_min_coupled_net",
	"offspring_stored_energy",
	"checksum",
]

static func create_default() -> Dictionary:
	var profile := {
		"schema": SCHEMA,
		"version": VERSION,
		"evaluation_biomass_kg_m2": 0.05,
		"germination_min_coupled_net": -0.25,
		"germination_min_stored_energy": 0.25,
		"germination_energy_cost": 0.20,
		"juvenile_age_fraction": 0.08,
		"adult_age_fraction": 0.20,
		"reproductive_age_fraction": 0.30,
		"senescent_age_fraction": 0.90,
		"reproduction_min_coupled_net": 0.0,
		"offspring_stored_energy": 0.80,
	}
	profile["checksum"] = compute_checksum(profile)
	return profile

static func validate(profile: Dictionary) -> Dictionary:
	if profile.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_PH4_PROFILE_FIELD_COUNT_MISMATCH")
	for name in FIELD_NAMES:
		if not profile.has(name):
			return _failure("ECO_PH4_PROFILE_MISSING_FIELD", {"field": name})
	if String(profile.get("schema", "")) != SCHEMA or String(profile.get("version", "")) != VERSION:
		return _failure("ECO_PH4_PROFILE_SCHEMA_VERSION_MISMATCH")
	for name in FIELD_NAMES:
		if name in ["schema", "version", "checksum"]:
			continue
		if typeof(profile.get(name)) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(profile.get(name))):
			return _failure("ECO_PH4_PROFILE_NON_FINITE", {"field": name})
	if float(profile["evaluation_biomass_kg_m2"]) < 0.0:
		return _failure("ECO_PH4_PROFILE_INVALID_BIOMASS")
	if float(profile["germination_min_stored_energy"]) < 0.0 or float(profile["germination_energy_cost"]) < 0.0:
		return _failure("ECO_PH4_PROFILE_INVALID_ENERGY")
	if float(profile["offspring_stored_energy"]) < 0.0:
		return _failure("ECO_PH4_PROFILE_INVALID_OFFSPRING_ENERGY")
	var juvenile := float(profile["juvenile_age_fraction"])
	var adult := float(profile["adult_age_fraction"])
	var reproductive := float(profile["reproductive_age_fraction"])
	var senescent := float(profile["senescent_age_fraction"])
	if juvenile <= 0.0 or juvenile >= adult or adult >= reproductive or reproductive >= senescent or senescent > 1.0:
		return _failure("ECO_PH4_PROFILE_INVALID_STAGE_ORDER")
	var checksum := String(profile.get("checksum", ""))
	if checksum.length() != 64 or checksum != compute_checksum(profile):
		return _failure("ECO_PH4_PROFILE_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(profile: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION])
	for name in FIELD_NAMES:
		if name in ["schema", "version", "checksum"]:
			continue
		tokens.append("%.9f" % float(profile.get(name, 0.0)))
	return "|".join(tokens).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
