extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_multiscale_representation.v1"
const VERSION := "1.0.0"

const TIER_0_FULL := "TIER_0_FULL"
const TIER_1_REDUCED := "TIER_1_REDUCED"
const TIER_2_CANOPY := "TIER_2_CANOPY"
const TIER_3_IMPOSTOR := "TIER_3_IMPOSTOR"
const TIER_4_POPULATION_ONLY := "TIER_4_POPULATION_ONLY"

const TIER_ORDER: Array[String] = [
	TIER_0_FULL,
	TIER_1_REDUCED,
	TIER_2_CANOPY,
	TIER_3_IMPOSTOR,
	TIER_4_POPULATION_ONLY,
]

const PROFILE_BY_TIER := {
	TIER_0_FULL: "FULL_PROCEDURAL",
	TIER_1_REDUCED: "BRANCH_LEAF_INSTANCED",
	TIER_2_CANOPY: "CANOPY_APPROXIMATION",
	TIER_3_IMPOSTOR: "IMPOSTOR_BILLBOARD",
	TIER_4_POPULATION_ONLY: "",
}

const MIN_PROJECTED_HEIGHT_PX := {
	TIER_0_FULL: 240.0,
	TIER_1_REDUCED: 96.0,
	TIER_2_CANOPY: 28.0,
	TIER_3_IMPOSTOR: 4.0,
	TIER_4_POPULATION_ONLY: 0.0,
}

const COST_UNITS := {
	TIER_0_FULL: 10000,
	TIER_1_REDUCED: 2500,
	TIER_2_CANOPY: 250,
	TIER_3_IMPOSTOR: 10,
	TIER_4_POPULATION_ONLY: 1,
}

static func select_tier(projected_height_px: float) -> String:
	if not is_finite(projected_height_px) or projected_height_px < 0.0:
		return TIER_4_POPULATION_ONLY
	for tier in TIER_ORDER:
		if projected_height_px >= float(MIN_PROJECTED_HEIGHT_PX[tier]):
			return tier
	return TIER_4_POPULATION_ONLY

static func select_tier_hysteretic(projected_height_px: float, previous_tier: String, margin_ratio: float = 0.12) -> String:
	var base_tier := select_tier(projected_height_px)
	if not previous_tier in TIER_ORDER or not is_finite(projected_height_px) or projected_height_px < 0.0:
		return base_tier
	var margin := clampf(margin_ratio, 0.0, 0.49)
	var index := TIER_ORDER.find(previous_tier)
	var lower := float(MIN_PROJECTED_HEIGHT_PX[previous_tier]) * (1.0 - margin)
	var upper := INF
	if index > 0:
		upper = float(MIN_PROJECTED_HEIGHT_PX[TIER_ORDER[index - 1]]) * (1.0 + margin)
	if projected_height_px >= lower and projected_height_px < upper:
		return previous_tier
	return base_tier

static func build(description: Dictionary, tier: String) -> Dictionary:
	var validation := validate_source(description)
	if not bool(validation["success"]):
		return validation
	if not tier in TIER_ORDER:
		return _failure("ECO_PH5_S3_UNKNOWN_TIER", {"tier": tier})

	var branches: Array = description.get("branches", [])
	var foliage: Array = description.get("foliage_anchors", [])
	var branch_count := 0
	var foliage_count := 0
	var canopy_count := 0
	var impostor_count := 0
	match tier:
		TIER_0_FULL:
			branch_count = branches.size()
			foliage_count = foliage.size()
		TIER_1_REDUCED:
			branch_count = _reduced_count(branches.size(), 0.35)
			foliage_count = _reduced_count(foliage.size(), 0.20)
		TIER_2_CANOPY:
			canopy_count = 1
		TIER_3_IMPOSTOR:
			impostor_count = 1
		TIER_4_POPULATION_ONLY:
			pass

	var result := {
		"success": true,
		"error_code": "",
		"schema": SCHEMA,
		"version": VERSION,
		"derived_representation": true,
		"ecological_truth_hash": String(description["source_graph_hash"]),
		"render_description_hash": String(description["render_description_hash"]),
		"development_traits_checksum": String(description.get("development_traits_checksum", "")),
		"individual_seed": int(description.get("individual_seed", -1)),
		"tier": tier,
		"legacy_profile_id": String(PROFILE_BY_TIER[tier]),
		"individual_materialized": tier != TIER_4_POPULATION_ONLY,
		"branch_primitive_count": branch_count,
		"foliage_instance_count": foliage_count,
		"canopy_primitive_count": canopy_count,
		"impostor_count": impostor_count,
		"cost_units": int(COST_UNITS[tier]),
		"canopy": Dictionary(description.get("canopy", {})).duplicate(true) if tier in [TIER_2_CANOPY, TIER_3_IMPOSTOR] else {},
		"bounds": Dictionary(description.get("bounds", {})).duplicate(true) if tier in [TIER_2_CANOPY, TIER_3_IMPOSTOR] else {},
		"population_projection_required": tier == TIER_4_POPULATION_ONLY,
	}
	result["representation_hash"] = compute_hash(result)
	return result

static func validate_source(description: Dictionary) -> Dictionary:
	var graph_hash := String(description.get("source_graph_hash", ""))
	var render_hash := String(description.get("render_description_hash", ""))
	if not _is_sha256_hex(graph_hash) or not _is_sha256_hex(render_hash):
		return _failure("ECO_PH5_S3_INVALID_TRUTH_HASH")
	if not description.get("branches", []) is Array or not description.get("foliage_anchors", []) is Array:
		return _failure("ECO_PH5_S3_INVALID_ARRAYS")
	for field_name in ["canopy", "bounds"]:
		if not description.get(field_name, {}) is Dictionary:
			return _failure("ECO_PH5_S3_INVALID_DESCRIPTOR", {"field": field_name})
	return _success()

static func compute_hash(representation: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(representation.get("ecological_truth_hash", "")),
		String(representation.get("render_description_hash", "")),
		String(representation.get("tier", "")),
		String(representation.get("legacy_profile_id", "")),
		str(int(representation.get("individual_materialized", false))),
		str(int(representation.get("branch_primitive_count", 0))),
		str(int(representation.get("foliage_instance_count", 0))),
		str(int(representation.get("canopy_primitive_count", 0))),
		str(int(representation.get("impostor_count", 0))),
		str(int(representation.get("cost_units", 0))),
		JSON.stringify(representation.get("canopy", {})),
		JSON.stringify(representation.get("bounds", {})),
	])).sha256_text()

static func _is_sha256_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var decimal := code >= 48 and code <= 57
		var lower_hex := code >= 97 and code <= 102
		var upper_hex := code >= 65 and code <= 70
		if not decimal and not lower_hex and not upper_hex:
			return false
	return true

static func _reduced_count(source_count: int, fraction: float) -> int:
	if source_count <= 0:
		return 0
	return clampi(int(ceil(float(source_count) * fraction)), 1, source_count)

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
