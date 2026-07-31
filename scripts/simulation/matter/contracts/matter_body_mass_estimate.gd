extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

const SCHEMA: String = "planet_simulator.matter_body_mass_estimate.v1"
const FIELDS: Array[String] = [
	"schema",
	"body_id",
	"body_checksum",
	"generator_profile_checksum",
	"feature_catalog_hash",
	"sample_resolution",
	"integration_bounds_radius_m",
	"voxel_edge_m",
	"occupied_sample_count",
	"estimated_volume_m3",
	"estimated_mass_kg",
	"center_of_mass_m",
	"material_masses",
	"checksum",
]
const MATERIAL_MASS_FIELDS: Array[String] = ["material_id", "mass_kg"]
const MAX_SAMPLE_RESOLUTION: int = 256


static func create(data: Dictionary) -> Dictionary:
	var material_masses: Array = []
	for entry in Array(data.get("material_masses", [])):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		material_masses.append({
			"material_id": String(entry.get("material_id", "")).strip_edges().to_lower(),
			"mass_kg": float(entry.get("mass_kg", 0.0)),
		})
	material_masses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("material_id", "")) < String(b.get("material_id", ""))
	)
	var center_raw = data.get("center_of_mass_m", [0.0, 0.0, 0.0])
	var center: Array = []
	if typeof(center_raw) == TYPE_ARRAY:
		for component in center_raw:
			center.append(float(component))
	var value: Dictionary = {
		"schema": SCHEMA,
		"body_id": String(data.get("body_id", "")).strip_edges().to_lower(),
		"body_checksum": String(data.get("body_checksum", "")).strip_edges().to_lower(),
		"generator_profile_checksum": String(data.get("generator_profile_checksum", "")).strip_edges().to_lower(),
		"feature_catalog_hash": String(data.get("feature_catalog_hash", "")).strip_edges().to_lower(),
		"sample_resolution": int(data.get("sample_resolution", 0)),
		"integration_bounds_radius_m": float(data.get("integration_bounds_radius_m", 0.0)),
		"voxel_edge_m": float(data.get("voxel_edge_m", 0.0)),
		"occupied_sample_count": int(data.get("occupied_sample_count", 0)),
		"estimated_volume_m3": float(data.get("estimated_volume_m3", 0.0)),
		"estimated_mass_kg": float(data.get("estimated_mass_kg", 0.0)),
		"center_of_mass_m": center,
		"material_masses": material_masses,
		"checksum": "",
	}
	value["checksum"] = MatterUtilsScript.compute_checksum(value)
	return value


static func validate(value: Dictionary) -> Dictionary:
	var exact: Dictionary = MatterUtilsScript.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)):
		return exact
	if typeof(value.get("schema")) != TYPE_STRING or String(value["schema"]) != SCHEMA:
		return MatterUtilsScript.failure("UNSUPPORTED_MATTER_BODY_MASS_ESTIMATE_SCHEMA")
	if not MatterUtilsScript.is_canonical_id(value.get("body_id"), 2):
		return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_BODY_ID")
	for field in ["body_checksum", "generator_profile_checksum", "feature_catalog_hash"]:
		if not MatterUtilsScript.is_lower_hex_64(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_HASH", {"field": field})
	if not MatterUtilsScript.is_json_integer(value.get("sample_resolution")) \
		or int(value["sample_resolution"]) < 4 \
		or int(value["sample_resolution"]) > MAX_SAMPLE_RESOLUTION:
		return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_RESOLUTION")
	if not MatterUtilsScript.is_positive_number(value.get("integration_bounds_radius_m")) \
		or not MatterUtilsScript.is_positive_number(value.get("voxel_edge_m")):
		return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_GRID")
	var resolution: int = int(value["sample_resolution"])
	var maximum_samples: int = resolution * resolution * resolution
	if not MatterUtilsScript.is_json_integer(value.get("occupied_sample_count")) \
		or int(value["occupied_sample_count"]) <= 0 \
		or int(value["occupied_sample_count"]) > maximum_samples:
		return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_OCCUPANCY")
	for field in ["estimated_volume_m3", "estimated_mass_kg"]:
		if not MatterUtilsScript.is_positive_number(value.get(field)):
			return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_VALUE", {"field": field})
	if not MatterUtilsScript.is_vector3_array(value.get("center_of_mass_m")):
		return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_CENTER")
	if typeof(value.get("material_masses")) != TYPE_ARRAY or value["material_masses"].is_empty():
		return MatterUtilsScript.failure("EMPTY_MASS_ESTIMATE_MATERIALS")
	var previous_id: String = ""
	var material_total: float = 0.0
	for index in range(value["material_masses"].size()):
		var entry = value["material_masses"][index]
		if typeof(entry) != TYPE_DICTIONARY:
			return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_MATERIAL", {"index": index})
		var entry_exact: Dictionary = MatterUtilsScript.validate_exact_fields(entry, MATERIAL_MASS_FIELDS)
		if not bool(entry_exact.get("success", false)):
			return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_MATERIAL_FIELDS", {"index": index})
		var material_id: String = String(entry.get("material_id", ""))
		if not MatterUtilsScript.is_canonical_id(material_id, 2):
			return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_MATERIAL_ID", {"index": index})
		if index > 0 and material_id <= previous_id:
			return MatterUtilsScript.failure("MASS_ESTIMATE_MATERIALS_NOT_SORTED_UNIQUE", {"index": index})
		if not MatterUtilsScript.is_positive_number(entry.get("mass_kg")):
			return MatterUtilsScript.failure("INVALID_MASS_ESTIMATE_MATERIAL_MASS", {"index": index})
		material_total += float(entry["mass_kg"])
		previous_id = material_id
	var total_mass: float = float(value["estimated_mass_kg"])
	var tolerance: float = maxf(0.001, total_mass * 0.000000001)
	if absf(material_total - total_mass) > tolerance:
		return MatterUtilsScript.failure("MASS_ESTIMATE_MATERIAL_BALANCE_MISMATCH", {
			"material_total_kg": material_total,
			"estimated_mass_kg": total_mass,
		})
	var safe: Dictionary = MatterUtilsScript.validate_json_safe(value, "$.matter_body_mass_estimate")
	if not bool(safe.get("success", false)):
		return safe
	return MatterUtilsScript.validate_checksum(value)


static func normalize(value: Dictionary) -> Dictionary:
	return MatterUtilsScript.normalize(value, validate)
