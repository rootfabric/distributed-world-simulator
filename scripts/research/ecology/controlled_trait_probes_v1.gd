extends RefCounted

const PlantGenome = preload("res://scripts/research/ecology/plant_genome_v1.gd")

const BASE := "BASE"
const SHALLOW_ROOT := "SHALLOW_ROOT"
const DEEP_ROOT := "DEEP_ROOT"
const WATER_LOVING := "WATER_LOVING"
const DROUGHT_TOLERANT := "DROUGHT_TOLERANT"
const SHADE_TOLERANT := "SHADE_TOLERANT"
const SUN_FAVORED := "SUN_FAVORED"

const ORDER: Array[String] = [
	BASE,
	SHALLOW_ROOT,
	DEEP_ROOT,
	WATER_LOVING,
	DROUGHT_TOLERANT,
	SHADE_TOLERANT,
	SUN_FAVORED,
]


static func genome(probe_id: String) -> Dictionary:
	var base := PlantGenome.create_default()
	match probe_id:
		BASE:
			return base
		SHALLOW_ROOT:
			return PlantGenome.with_root_depth(base, 0.35, "/probe-shallow-root")
		DEEP_ROOT:
			return PlantGenome.with_root_depth(base, 1.60, "/probe-deep-root")
		WATER_LOVING:
			return PlantGenome.create(
				"plant-probe/p1a-s3-water-loving",
				1.6, 0.65, 0.85, 0.72, 0.22, 0.45, 80, 15.0, 5.0
			)
		DROUGHT_TOLERANT:
			return PlantGenome.create(
				"plant-probe/p1a-s3-drought-tolerant",
				1.3, 0.55, 1.45, 0.36, 0.42, 0.42, 65, 18.0, 6.0
			)
		SHADE_TOLERANT:
			return PlantGenome.create(
				"plant-probe/p1a-s3-shade-tolerant",
				1.6, 0.65, 0.85, 0.58, 0.30, 0.82, 80, 15.0, 5.0
			)
		SUN_FAVORED:
			return PlantGenome.create(
				"plant-probe/p1a-s3-sun-favored",
				1.6, 0.65, 0.85, 0.58, 0.30, 0.08, 80, 15.0, 5.0
			)
	return {}


static func all() -> Dictionary:
	var result := {}
	for probe_id in ORDER:
		result[probe_id] = genome(probe_id)
	return result


static func validate_all() -> Dictionary:
	for probe_id in ORDER:
		var value := genome(probe_id)
		if value.is_empty():
			return {"success": false, "error_code": "ECO_P1A_S3_PROBE_MISSING", "details": {"probe_id": probe_id}}
		var validation := PlantGenome.validate(value)
		if not bool(validation.get("success", false)):
			return {"success": false, "error_code": "ECO_P1A_S3_PROBE_INVALID", "details": {"probe_id": probe_id, "validation": validation}}
	return {"success": true, "error_code": "", "details": {"count": ORDER.size()}}
