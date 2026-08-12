extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.cal1_f_calibration_profile.v1"
const VERSION := "1.0.0"
const PERTURBATION := 0.15

const PROFILE_ORDER: Array[String] = [
	"UNITY",
	"MORPHOLOGY_LOW", "MORPHOLOGY_HIGH",
	"VERTICAL_LOW", "VERTICAL_HIGH",
	"SPATIAL_LOW", "SPATIAL_HIGH",
	"ALL_LOW", "ALL_HIGH",
]

static func create(profile_name: String) -> Dictionary:
	var morphology := 1.0
	var vertical := 1.0
	var crown := 1.0
	var root := 1.0
	match profile_name:
		"UNITY":
			pass
		"MORPHOLOGY_LOW":
			morphology = 1.0 - PERTURBATION
		"MORPHOLOGY_HIGH":
			morphology = 1.0 + PERTURBATION
		"VERTICAL_LOW":
			vertical = 1.0 - PERTURBATION
		"VERTICAL_HIGH":
			vertical = 1.0 + PERTURBATION
		"SPATIAL_LOW":
			crown = 1.0 - PERTURBATION
			root = 1.0 - PERTURBATION
		"SPATIAL_HIGH":
			crown = 1.0 + PERTURBATION
			root = 1.0 + PERTURBATION
		"ALL_LOW":
			morphology = 1.0 - PERTURBATION
			vertical = 1.0 - PERTURBATION
			crown = 1.0 - PERTURBATION
			root = 1.0 - PERTURBATION
		"ALL_HIGH":
			morphology = 1.0 + PERTURBATION
			vertical = 1.0 + PERTURBATION
			crown = 1.0 + PERTURBATION
			root = 1.0 + PERTURBATION
		_:
			return {}
	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"name": profile_name,
		"perturbation_fraction": PERTURBATION,
		"morphology_delta_multiplier": morphology,
		"vertical_light_multiplier": vertical,
		"crown_overlap_loss_multiplier": crown,
		"root_competition_multiplier": root,
		"selection_policy": "UNITY is the neutral calibration baseline; variants are sensitivity probes, never preferred-winner targets",
	}
	result["checksum"] = compute_checksum(result)
	return result

static func validate(profile: Dictionary) -> bool:
	if String(profile.get("schema", "")) != SCHEMA or String(profile.get("version", "")) != VERSION:
		return false
	if not PROFILE_ORDER.has(String(profile.get("name", ""))):
		return false
	for key in ["morphology_delta_multiplier", "vertical_light_multiplier", "crown_overlap_loss_multiplier", "root_competition_multiplier"]:
		var value := float(profile.get(key, -1.0))
		if not is_finite(value) or value <= 0.0:
			return false
	return String(profile.get("checksum", "")) == compute_checksum(profile)

static func compute_checksum(profile: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(profile.get("name", "")),
		"%.12f" % float(profile.get("perturbation_fraction", 0.0)),
		"%.12f" % float(profile.get("morphology_delta_multiplier", 0.0)),
		"%.12f" % float(profile.get("vertical_light_multiplier", 0.0)),
		"%.12f" % float(profile.get("crown_overlap_loss_multiplier", 0.0)),
		"%.12f" % float(profile.get("root_competition_multiplier", 0.0)),
	])).sha256_text()
