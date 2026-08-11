extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_development_traits.v1"
const VERSION := "1.0.0"
const DEFAULT_TRAITS_ID := "plant-development/ph0-baseline"
const TRAIT_NAMES: Array[String] = [
	"max_height_m",
	"internode_length_m",
	"apical_dominance",
	"branch_probability",
	"branch_angle_deg",
	"branch_length_ratio",
	"branching_depth",
	"crown_spread_m",
]
const FIELD_NAMES: Array[String] = [
	"schema", "version", "traits_id",
	"max_height_m", "internode_length_m", "apical_dominance", "branch_probability",
	"branch_angle_deg", "branch_length_ratio", "branching_depth", "crown_spread_m",
	"checksum",
]
const BOUNDS := {
	"max_height_m": [0.10, 40.0],
	"internode_length_m": [0.02, 4.0],
	"apical_dominance": [0.0, 1.0],
	"branch_probability": [0.0, 1.0],
	"branch_angle_deg": [0.0, 89.0],
	"branch_length_ratio": [0.05, 2.0],
	"branching_depth": [1.0, 8.0],
	"crown_spread_m": [0.05, 30.0],
}

static func create_default() -> Dictionary:
	return create(DEFAULT_TRAITS_ID, 3.2, 0.32, 0.62, 0.48, 42.0, 0.78, 2, 1.8)

static func create(
	traits_id: String,
	max_height_m: float,
	internode_length_m: float,
	apical_dominance: float,
	branch_probability: float,
	branch_angle_deg: float,
	branch_length_ratio: float,
	branching_depth: int,
	crown_spread_m: float
) -> Dictionary:
	var traits := {
		"schema": SCHEMA,
		"version": VERSION,
		"traits_id": traits_id,
		"max_height_m": max_height_m,
		"internode_length_m": internode_length_m,
		"apical_dominance": apical_dominance,
		"branch_probability": branch_probability,
		"branch_angle_deg": branch_angle_deg,
		"branch_length_ratio": branch_length_ratio,
		"branching_depth": branching_depth,
		"crown_spread_m": crown_spread_m,
	}
	traits["checksum"] = compute_checksum(traits)
	return traits

static func with_trait(source: Dictionary, trait_name: String, value, suffix: String = "") -> Dictionary:
	var copy := source.duplicate(true)
	if not trait_name in TRAIT_NAMES:
		return {}
	copy[trait_name] = value
	copy["traits_id"] = String(copy.get("traits_id", DEFAULT_TRAITS_ID)) + suffix
	copy["checksum"] = compute_checksum(copy)
	return copy

static func validate(traits: Dictionary) -> Dictionary:
	if traits.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_DEVELOPMENT_TRAITS_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not traits.has(field_name):
			return _failure("ECO_DEVELOPMENT_TRAITS_MISSING_FIELD", {"field": field_name})
	for field_name in traits.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_DEVELOPMENT_TRAITS_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(traits.get("schema", "")) != SCHEMA or String(traits.get("version", "")) != VERSION:
		return _failure("ECO_DEVELOPMENT_TRAITS_SCHEMA_VERSION_MISMATCH")
	var traits_id := String(traits.get("traits_id", ""))
	if traits_id.is_empty() or traits_id != traits_id.strip_edges():
		return _failure("ECO_DEVELOPMENT_TRAITS_INVALID_ID")
	for name in TRAIT_NAMES:
		var bounds: Array = BOUNDS[name]
		var value = traits.get(name)
		if name == "branching_depth":
			if typeof(value) != TYPE_INT:
				return _failure("ECO_DEVELOPMENT_TRAITS_INVALID_TYPE", {"field": name})
		if not _is_finite_number(value) or float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _failure("ECO_DEVELOPMENT_TRAITS_OUT_OF_RANGE", {"field": name})
	var checksum := String(traits.get("checksum", ""))
	if checksum != compute_checksum(traits):
		return _failure("ECO_DEVELOPMENT_TRAITS_CHECKSUM_MISMATCH")
	return _success()

static func compute_checksum(traits: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(traits.get("traits_id", "")),
		_format_float(float(traits.get("max_height_m", 0.0))),
		_format_float(float(traits.get("internode_length_m", 0.0))),
		_format_float(float(traits.get("apical_dominance", 0.0))),
		_format_float(float(traits.get("branch_probability", 0.0))),
		_format_float(float(traits.get("branch_angle_deg", 0.0))),
		_format_float(float(traits.get("branch_length_ratio", 0.0))),
		str(int(traits.get("branching_depth", 0))),
		_format_float(float(traits.get("crown_spread_m", 0.0))),
	])).sha256_text()

static func _format_float(value: float) -> String:
	return "%.9f" % value

static func _is_finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
