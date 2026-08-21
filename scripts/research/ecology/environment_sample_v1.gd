extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.environment_sample.v1"
const VERSION := "1.0.0"
const FIELD_NAMES: Array[String] = [
	"schema",
	"version",
	"environment_revision",
	"seed",
	"world_x_m",
	"world_z_m",
	"temperature_c",
	"soil_moisture",
	"sunlight",
	"nutrients",
	"flood_frequency",
	"checksum",
]
const RATIO_FIELDS: Array[String] = [
	"soil_moisture",
	"sunlight",
	"nutrients",
	"flood_frequency",
]


static func create(
	world_x_m: float,
	world_z_m: float,
	temperature_c: float,
	soil_moisture: float,
	sunlight: float,
	nutrients: float,
	flood_frequency: float,
	seed: int,
	environment_revision: String
) -> Dictionary:
	var sample := {
		"schema": SCHEMA,
		"version": VERSION,
		"environment_revision": environment_revision,
		"seed": seed,
		"world_x_m": world_x_m,
		"world_z_m": world_z_m,
		"temperature_c": temperature_c,
		"soil_moisture": soil_moisture,
		"sunlight": sunlight,
		"nutrients": nutrients,
		"flood_frequency": flood_frequency,
	}
	sample["checksum"] = compute_checksum(sample)
	return sample


static func validate(sample: Dictionary) -> Dictionary:
	if sample.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_ENV_SAMPLE_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not sample.has(field_name):
			return _failure("ECO_ENV_SAMPLE_MISSING_FIELD", {"field": field_name})
	for field_name in sample.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_ENV_SAMPLE_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(sample.get("schema", "")) != SCHEMA:
		return _failure("ECO_ENV_SAMPLE_SCHEMA_MISMATCH")
	if String(sample.get("version", "")) != VERSION:
		return _failure("ECO_ENV_SAMPLE_VERSION_MISMATCH")
	var revision := String(sample.get("environment_revision", ""))
	if revision.is_empty() or revision != revision.strip_edges():
		return _failure("ECO_ENV_SAMPLE_INVALID_REVISION")
	if typeof(sample.get("seed")) != TYPE_INT:
		return _failure("ECO_ENV_SAMPLE_INVALID_SEED")
	for field_name in ["world_x_m", "world_z_m", "temperature_c"]:
		if not _is_finite_number(sample.get(field_name)):
			return _failure("ECO_ENV_SAMPLE_NON_FINITE_NUMBER", {"field": field_name})
	for field_name in RATIO_FIELDS:
		if not _is_ratio(sample.get(field_name)):
			return _failure("ECO_ENV_SAMPLE_INVALID_RATIO", {"field": field_name})
	var checksum := String(sample.get("checksum", ""))
	if not _is_lower_hex_64(checksum):
		return _failure("ECO_ENV_SAMPLE_INVALID_CHECKSUM")
	if checksum != compute_checksum(sample):
		return _failure("ECO_ENV_SAMPLE_CHECKSUM_MISMATCH")
	return _success()


static func compute_checksum(sample: Dictionary) -> String:
	return _canonical_payload(sample).sha256_text()


static func _canonical_payload(sample: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(sample.get("environment_revision", "")),
		str(int(sample.get("seed", 0))),
		_format_float(float(sample.get("world_x_m", 0.0))),
		_format_float(float(sample.get("world_z_m", 0.0))),
		_format_float(float(sample.get("temperature_c", 0.0))),
		_format_float(float(sample.get("soil_moisture", 0.0))),
		_format_float(float(sample.get("sunlight", 0.0))),
		_format_float(float(sample.get("nutrients", 0.0))),
		_format_float(float(sample.get("flood_frequency", 0.0))),
	]))


static func _format_float(value: float) -> String:
	return "%.9f" % value


static func _is_finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_ratio(value) -> bool:
	return _is_finite_number(value) and float(value) >= 0.0 and float(value) <= 1.0


static func _is_lower_hex_64(value: String) -> bool:
	if value.length() != 64 or value != value.to_lower():
		return false
	for character in value:
		if not String(character) in [
			"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
			"a", "b", "c", "d", "e", "f",
		]:
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
