extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.plant_genome.v1"
const VERSION := "1.0.0"
const DEFAULT_GENOME_ID := "plant-genome/p1a-s2-baseline"
const FIELD_NAMES: Array[String] = [
	"schema",
	"version",
	"genome_id",
	"height_m",
	"growth_rate",
	"root_depth_m",
	"water_preference",
	"water_tolerance_width",
	"shade_tolerance",
	"seed_count",
	"seed_dispersal_distance_m",
	"lifespan_years",
	"checksum",
]


static func create_default() -> Dictionary:
	return create(
		DEFAULT_GENOME_ID,
		1.6,
		0.65,
		0.85,
		0.58,
		0.30,
		0.45,
		80,
		15.0,
		5.0
	)


static func create(
	genome_id: String,
	height_m: float,
	growth_rate: float,
	root_depth_m: float,
	water_preference: float,
	water_tolerance_width: float,
	shade_tolerance: float,
	seed_count: int,
	seed_dispersal_distance_m: float,
	lifespan_years: float
) -> Dictionary:
	var genome := {
		"schema": SCHEMA,
		"version": VERSION,
		"genome_id": genome_id,
		"height_m": height_m,
		"growth_rate": growth_rate,
		"root_depth_m": root_depth_m,
		"water_preference": water_preference,
		"water_tolerance_width": water_tolerance_width,
		"shade_tolerance": shade_tolerance,
		"seed_count": seed_count,
		"seed_dispersal_distance_m": seed_dispersal_distance_m,
		"lifespan_years": lifespan_years,
	}
	genome["checksum"] = compute_checksum(genome)
	return genome


static func with_root_depth(genome: Dictionary, root_depth_m: float, suffix: String) -> Dictionary:
	return create(
		String(genome.get("genome_id", DEFAULT_GENOME_ID)) + suffix,
		float(genome.get("height_m", 0.0)),
		float(genome.get("growth_rate", 0.0)),
		root_depth_m,
		float(genome.get("water_preference", 0.0)),
		float(genome.get("water_tolerance_width", 0.0)),
		float(genome.get("shade_tolerance", 0.0)),
		int(genome.get("seed_count", 0)),
		float(genome.get("seed_dispersal_distance_m", 0.0)),
		float(genome.get("lifespan_years", 0.0))
	)


static func validate(genome: Dictionary) -> Dictionary:
	if genome.keys().size() != FIELD_NAMES.size():
		return _failure("ECO_PLANT_GENOME_FIELD_COUNT_MISMATCH")
	for field_name in FIELD_NAMES:
		if not genome.has(field_name):
			return _failure("ECO_PLANT_GENOME_MISSING_FIELD", {"field": field_name})
	for field_name in genome.keys():
		if not String(field_name) in FIELD_NAMES:
			return _failure("ECO_PLANT_GENOME_UNEXPECTED_FIELD", {"field": String(field_name)})
	if String(genome.get("schema", "")) != SCHEMA:
		return _failure("ECO_PLANT_GENOME_SCHEMA_MISMATCH")
	if String(genome.get("version", "")) != VERSION:
		return _failure("ECO_PLANT_GENOME_VERSION_MISMATCH")
	var genome_id := String(genome.get("genome_id", ""))
	if genome_id.is_empty() or genome_id != genome_id.strip_edges():
		return _failure("ECO_PLANT_GENOME_INVALID_ID")
	if not _is_range(genome.get("height_m"), 0.05, 50.0):
		return _failure("ECO_PLANT_GENOME_INVALID_HEIGHT")
	if not _is_ratio(genome.get("growth_rate")):
		return _failure("ECO_PLANT_GENOME_INVALID_GROWTH_RATE")
	if not _is_range(genome.get("root_depth_m"), 0.05, 20.0):
		return _failure("ECO_PLANT_GENOME_INVALID_ROOT_DEPTH")
	if not _is_ratio(genome.get("water_preference")):
		return _failure("ECO_PLANT_GENOME_INVALID_WATER_PREFERENCE")
	if not _is_range(genome.get("water_tolerance_width"), 0.02, 1.0):
		return _failure("ECO_PLANT_GENOME_INVALID_WATER_TOLERANCE")
	if not _is_ratio(genome.get("shade_tolerance")):
		return _failure("ECO_PLANT_GENOME_INVALID_SHADE_TOLERANCE")
	if typeof(genome.get("seed_count")) != TYPE_INT or int(genome.get("seed_count")) < 1 or int(genome.get("seed_count")) > 1000000:
		return _failure("ECO_PLANT_GENOME_INVALID_SEED_COUNT")
	if not _is_range(genome.get("seed_dispersal_distance_m"), 0.0, 100000.0):
		return _failure("ECO_PLANT_GENOME_INVALID_DISPERSAL")
	if not _is_range(genome.get("lifespan_years"), 0.1, 10000.0):
		return _failure("ECO_PLANT_GENOME_INVALID_LIFESPAN")
	var checksum := String(genome.get("checksum", ""))
	if not _is_lower_hex_64(checksum):
		return _failure("ECO_PLANT_GENOME_INVALID_CHECKSUM")
	if checksum != compute_checksum(genome):
		return _failure("ECO_PLANT_GENOME_CHECKSUM_MISMATCH")
	return _success()


static func compute_checksum(genome: Dictionary) -> String:
	return "|".join(PackedStringArray([
		SCHEMA,
		VERSION,
		String(genome.get("genome_id", "")),
		_format_float(float(genome.get("height_m", 0.0))),
		_format_float(float(genome.get("growth_rate", 0.0))),
		_format_float(float(genome.get("root_depth_m", 0.0))),
		_format_float(float(genome.get("water_preference", 0.0))),
		_format_float(float(genome.get("water_tolerance_width", 0.0))),
		_format_float(float(genome.get("shade_tolerance", 0.0))),
		str(int(genome.get("seed_count", 0))),
		_format_float(float(genome.get("seed_dispersal_distance_m", 0.0))),
		_format_float(float(genome.get("lifespan_years", 0.0))),
	])).sha256_text()


static func _format_float(value: float) -> String:
	return "%.9f" % value


static func _is_finite_number(value) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _is_ratio(value) -> bool:
	return _is_finite_number(value) and float(value) >= 0.0 and float(value) <= 1.0


static func _is_range(value, minimum: float, maximum: float) -> bool:
	return _is_finite_number(value) and float(value) >= minimum and float(value) <= maximum


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
