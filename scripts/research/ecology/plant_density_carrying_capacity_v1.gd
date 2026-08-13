extends RefCounted

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.p3_2_density_carrying_capacity.v1"
const VERSION := "1.0.0"
const PARENT_P3_1_CANDIDATE_AGGREGATE := "f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a"
const PARENT_EVO1_P2_8_AGGREGATE := Competition.PARENT_EVO1_P2_8_AGGREGATE
const EPSILON := 0.000000000001

const PATCH_FIELDS: Array[String] = [
	"area_m2",
	"reference_capacity_kg_m2",
	"minimum_capacity_fraction",
	"max_recovery_fraction",
	"max_decline_fraction",
]
const RESULT_FIELDS: Array[String] = [
	"schema",
	"version",
	"parent_p3_1_candidate_aggregate",
	"parent_evo1_p2_8_aggregate",
	"competition_result",
	"competition_result_hash",
	"patch",
	"resource_demand_totals",
	"resource_support_ratio",
	"resource_support",
	"resource_pressure",
	"reference_capacity_kg",
	"effective_capacity_fraction",
	"effective_capacity_kg",
	"total_biomass_kg",
	"density_ratio",
	"density_feedback",
	"plant_order",
	"plants",
	"total_next_biomass_kg",
	"result_hash",
]
const PLANT_RESULT_FIELDS: Array[String] = [
	"id",
	"biomass_kg",
	"resource_growth_factor",
	"response_fraction",
	"biomass_delta_kg",
	"next_biomass_kg",
	"record_hash",
]

static func step(competition_result: Dictionary, patch: Dictionary, plants: Array) -> Dictionary:
	if not _safe_competition_shape(competition_result):
		return {}
	if not bool(Competition.validate_result(competition_result).get("success", false)):
		return {}
	var normalized_patch := _normalize_patch(patch)
	if normalized_patch.is_empty():
		return {}
	var normalized_plants := _normalize_plants(plants)
	if normalized_plants.is_empty() and not plants.is_empty():
		return {}

	var competition_order := PackedStringArray(competition_result["plant_order"])
	var input_order := PackedStringArray()
	var plants_by_id := {}
	for plant in normalized_plants:
		var plant_id := String(plant["id"])
		input_order.append(plant_id)
		plants_by_id[plant_id] = plant
	input_order.sort()
	if input_order != competition_order:
		return {}

	var competition_by_id := {}
	var demand_totals := _zero_resource_map()
	for record_variant in Array(competition_result["plants"]):
		var record: Dictionary = record_variant
		var plant_id := String(record["id"])
		var growth_factor_value = record.get("growth_factor")
		if typeof(growth_factor_value) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var growth_factor := float(growth_factor_value)
		if not is_finite(growth_factor) or growth_factor < 0.0 or growth_factor > 1.0:
			return {}
		competition_by_id[plant_id] = record
		var demand: Dictionary = record["demand"]
		for resource in Competition.RESOURCE_ORDER:
			demand_totals[resource] = float(demand_totals[resource]) + float(demand[resource])

	var support_ratio := {}
	var resource_support := 1.0
	var has_demand := false
	var total_uptake: Dictionary = competition_result["total_uptake"]
	for resource in Competition.RESOURCE_ORDER:
		var demand_total := float(demand_totals[resource])
		var ratio := 1.0
		if demand_total > EPSILON:
			has_demand = true
			ratio = clampf(float(total_uptake[resource]) / demand_total, 0.0, 1.0)
			resource_support = minf(resource_support, ratio)
		support_ratio[resource] = ratio
	if not has_demand:
		resource_support = 1.0
	var resource_pressure := 1.0 - resource_support

	var reference_capacity_kg := float(normalized_patch["area_m2"]) * float(normalized_patch["reference_capacity_kg_m2"])
	var minimum_capacity_fraction := float(normalized_patch["minimum_capacity_fraction"])
	var effective_capacity_fraction := minimum_capacity_fraction + (1.0 - minimum_capacity_fraction) * resource_support
	var effective_capacity_kg := reference_capacity_kg * effective_capacity_fraction
	if not is_finite(effective_capacity_kg) or effective_capacity_kg <= EPSILON:
		return {}

	var total_biomass_kg := 0.0
	for plant_id in input_order:
		total_biomass_kg += float(Dictionary(plants_by_id[plant_id])["biomass_kg"])
	var density_ratio := total_biomass_kg / effective_capacity_kg
	if not is_finite(density_ratio) or density_ratio < 0.0:
		return {}
	var density_feedback := _density_feedback(density_ratio)

	var plant_results: Array[Dictionary] = []
	var total_next_biomass_kg := 0.0
	for plant_id in input_order:
		var source: Dictionary = plants_by_id[plant_id]
		var competition_record: Dictionary = competition_by_id[plant_id]
		var biomass_kg := float(source["biomass_kg"])
		var growth_factor := float(competition_record["growth_factor"])
		var response_fraction := 0.0
		if density_feedback > EPSILON:
			response_fraction = float(normalized_patch["max_recovery_fraction"]) * growth_factor * density_feedback
		elif density_feedback < -EPSILON:
			response_fraction = float(normalized_patch["max_decline_fraction"]) * density_feedback
		var biomass_delta_kg := biomass_kg * response_fraction
		var next_biomass_kg := maxf(0.0, biomass_kg + biomass_delta_kg)
		var plant_result := {
			"id": plant_id,
			"biomass_kg": biomass_kg,
			"resource_growth_factor": growth_factor,
			"response_fraction": response_fraction,
			"biomass_delta_kg": biomass_delta_kg,
			"next_biomass_kg": next_biomass_kg,
		}
		plant_result["record_hash"] = _plant_record_hash(plant_result)
		plant_results.append(plant_result)
		total_next_biomass_kg += next_biomass_kg

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_p3_1_candidate_aggregate": PARENT_P3_1_CANDIDATE_AGGREGATE,
		"parent_evo1_p2_8_aggregate": PARENT_EVO1_P2_8_AGGREGATE,
		"competition_result": competition_result.duplicate(true),
		"competition_result_hash": String(competition_result["result_hash"]),
		"patch": normalized_patch,
		"resource_demand_totals": demand_totals,
		"resource_support_ratio": support_ratio,
		"resource_support": resource_support,
		"resource_pressure": resource_pressure,
		"reference_capacity_kg": reference_capacity_kg,
		"effective_capacity_fraction": effective_capacity_fraction,
		"effective_capacity_kg": effective_capacity_kg,
		"total_biomass_kg": total_biomass_kg,
		"density_ratio": density_ratio,
		"density_feedback": density_feedback,
		"plant_order": input_order,
		"plants": plant_results,
		"total_next_biomass_kg": total_next_biomass_kg,
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func validate_result(result: Dictionary) -> Dictionary:
	if not _has_exact_fields(result, RESULT_FIELDS):
		return _failure("ECO_P3_2_RESULT_FIELDS_MISMATCH")
	if String(result.get("schema", "")) != SCHEMA:
		return _failure("ECO_P3_2_SCHEMA_MISMATCH")
	if String(result.get("version", "")) != VERSION:
		return _failure("ECO_P3_2_VERSION_MISMATCH")
	if String(result.get("parent_p3_1_candidate_aggregate", "")) != PARENT_P3_1_CANDIDATE_AGGREGATE:
		return _failure("ECO_P3_2_P3_1_PARENT_MISMATCH")
	if String(result.get("parent_evo1_p2_8_aggregate", "")) != PARENT_EVO1_P2_8_AGGREGATE:
		return _failure("ECO_P3_2_P2_8_PARENT_MISMATCH")
	if typeof(result.get("competition_result")) != TYPE_DICTIONARY:
		return _failure("ECO_P3_2_COMPETITION_RESULT_TYPE_MISMATCH")
	var competition_result: Dictionary = result["competition_result"]
	if not _safe_competition_shape(competition_result):
		return _failure("ECO_P3_2_COMPETITION_RESULT_SHAPE_MISMATCH")
	if not bool(Competition.validate_result(competition_result).get("success", false)):
		return _failure("ECO_P3_2_COMPETITION_RESULT_INVALID")
	if String(result.get("competition_result_hash", "")) != String(competition_result.get("result_hash", "")):
		return _failure("ECO_P3_2_COMPETITION_HASH_MISMATCH")
	if typeof(result.get("patch")) != TYPE_DICTIONARY:
		return _failure("ECO_P3_2_PATCH_TYPE_MISMATCH")
	var patch := _normalize_patch(Dictionary(result["patch"]))
	if patch.is_empty():
		return _failure("ECO_P3_2_PATCH_INVALID")
	if typeof(result.get("plants")) != TYPE_ARRAY or typeof(result.get("plant_order")) != TYPE_PACKED_STRING_ARRAY:
		return _failure("ECO_P3_2_PLANT_CONTAINER_TYPE_MISMATCH")
	var plants: Array = result["plants"]
	var plant_order: PackedStringArray = result["plant_order"]
	if plants.size() != plant_order.size():
		return _failure("ECO_P3_2_PLANT_COUNT_MISMATCH")
	var sorted_order := plant_order.duplicate()
	sorted_order.sort()
	if sorted_order != plant_order:
		return _failure("ECO_P3_2_PLANT_ORDER_NOT_CANONICAL")
	var source_plants: Array[Dictionary] = []
	for index in range(plants.size()):
		if typeof(plants[index]) != TYPE_DICTIONARY:
			return _failure("ECO_P3_2_PLANT_RECORD_TYPE_MISMATCH")
		var plant: Dictionary = plants[index]
		if not _has_exact_fields(plant, PLANT_RESULT_FIELDS):
			return _failure("ECO_P3_2_PLANT_RECORD_FIELDS_MISMATCH")
		if String(plant.get("id", "")) != String(plant_order[index]):
			return _failure("ECO_P3_2_PLANT_ORDER_MISMATCH")
		for field_name in ["biomass_kg", "resource_growth_factor", "response_fraction", "biomass_delta_kg", "next_biomass_kg"]:
			var raw = plant.get(field_name)
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
				return _failure("ECO_P3_2_NON_FINITE_PLANT_FIELD", {"field": field_name})
		if float(plant["biomass_kg"]) < 0.0 or float(plant["next_biomass_kg"]) < 0.0:
			return _failure("ECO_P3_2_NEGATIVE_BIOMASS")
		if float(plant["resource_growth_factor"]) < 0.0 or float(plant["resource_growth_factor"]) > 1.0:
			return _failure("ECO_P3_2_INVALID_GROWTH_FACTOR")
		if String(plant.get("record_hash", "")) != _plant_record_hash(plant):
			return _failure("ECO_P3_2_PLANT_RECORD_HASH_MISMATCH", {"id": String(plant.get("id", ""))})
		source_plants.append({"id": String(plant["id"]), "biomass_kg": float(plant["biomass_kg"])})
	var expected := step(competition_result, patch, source_plants)
	if expected.is_empty():
		return _failure("ECO_P3_2_RECONSTRUCTION_FAILED")
	if String(result.get("result_hash", "")) != compute_result_hash(result):
		return _failure("ECO_P3_2_RESULT_HASH_MISMATCH")
	if String(result.get("result_hash", "")) != String(expected.get("result_hash", "")):
		return _failure("ECO_P3_2_DERIVED_STATE_MISMATCH")
	return _success()

static func compute_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		PARENT_P3_1_CANDIDATE_AGGREGATE,
		PARENT_EVO1_P2_8_AGGREGATE,
		String(result.get("competition_result_hash", "")),
	])
	var patch: Dictionary = result.get("patch", {})
	for field_name in PATCH_FIELDS:
		tokens.append("patch|%s=%.12f" % [field_name, float(patch.get(field_name, 0.0))])
	var demand_totals: Dictionary = result.get("resource_demand_totals", {})
	var support_ratio: Dictionary = result.get("resource_support_ratio", {})
	for resource in Competition.RESOURCE_ORDER:
		tokens.append("resource|%s|demand=%.12f|support=%.12f" % [resource, float(demand_totals.get(resource, 0.0)), float(support_ratio.get(resource, 0.0))])
	tokens.append("resource_support=%.12f" % float(result.get("resource_support", 0.0)))
	tokens.append("resource_pressure=%.12f" % float(result.get("resource_pressure", 0.0)))
	tokens.append("reference_capacity_kg=%.12f" % float(result.get("reference_capacity_kg", 0.0)))
	tokens.append("effective_capacity_fraction=%.12f" % float(result.get("effective_capacity_fraction", 0.0)))
	tokens.append("effective_capacity_kg=%.12f" % float(result.get("effective_capacity_kg", 0.0)))
	tokens.append("total_biomass_kg=%.12f" % float(result.get("total_biomass_kg", 0.0)))
	tokens.append("density_ratio=%.12f" % float(result.get("density_ratio", 0.0)))
	tokens.append("density_feedback=%.12f" % float(result.get("density_feedback", 0.0)))
	var plants: Array = result.get("plants", [])
	for plant_variant in plants:
		if typeof(plant_variant) == TYPE_DICTIONARY:
			var plant: Dictionary = plant_variant
			tokens.append("plant|%s|%s" % [String(plant.get("id", "")), String(plant.get("record_hash", ""))])
	tokens.append("total_next_biomass_kg=%.12f" % float(result.get("total_next_biomass_kg", 0.0)))
	return "\n".join(tokens).sha256_text()

static func _density_feedback(density_ratio: float) -> float:
	if density_ratio <= 1.0:
		return clampf(1.0 - density_ratio, 0.0, 1.0)
	return clampf(1.0 / density_ratio - 1.0, -1.0, 0.0)

static func _normalize_patch(patch: Dictionary) -> Dictionary:
	if not _has_exact_fields(patch, PATCH_FIELDS):
		return {}
	var result := {}
	for field_name in PATCH_FIELDS:
		var raw = patch[field_name]
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var value := float(raw)
		if not is_finite(value):
			return {}
		result[field_name] = value
	if float(result["area_m2"]) <= 0.0 or float(result["reference_capacity_kg_m2"]) <= 0.0:
		return {}
	if float(result["minimum_capacity_fraction"]) <= 0.0 or float(result["minimum_capacity_fraction"]) > 1.0:
		return {}
	for field_name in ["max_recovery_fraction", "max_decline_fraction"]:
		if float(result[field_name]) < 0.0 or float(result[field_name]) > 1.0:
			return {}
	return result

static func _normalize_plants(plants: Array) -> Array[Dictionary]:
	var by_id := {}
	for plant_variant in plants:
		if typeof(plant_variant) != TYPE_DICTIONARY:
			return []
		var plant: Dictionary = plant_variant
		if plant.keys().size() != 2 or not plant.has("id") or not plant.has("biomass_kg"):
			return []
		var plant_id := String(plant["id"])
		if plant_id.is_empty() or by_id.has(plant_id):
			return []
		var raw_biomass = plant["biomass_kg"]
		if typeof(raw_biomass) not in [TYPE_INT, TYPE_FLOAT]:
			return []
		var biomass_kg := float(raw_biomass)
		if not is_finite(biomass_kg) or biomass_kg < 0.0:
			return []
		by_id[plant_id] = {"id": plant_id, "biomass_kg": biomass_kg}
	var ids := PackedStringArray(by_id.keys())
	ids.sort()
	var normalized: Array[Dictionary] = []
	for plant_id in ids:
		normalized.append(Dictionary(by_id[plant_id]))
	return normalized

static func _safe_competition_shape(result: Dictionary) -> bool:
	if typeof(result.get("resource_order")) != TYPE_ARRAY:
		return false
	if typeof(result.get("plant_order")) != TYPE_PACKED_STRING_ARRAY:
		return false
	for field_name in ["supply", "total_uptake", "remaining", "conservation_error"]:
		if typeof(result.get(field_name)) != TYPE_DICTIONARY:
			return false
	if typeof(result.get("plants")) != TYPE_ARRAY:
		return false
	for plant_variant in Array(result["plants"]):
		if typeof(plant_variant) != TYPE_DICTIONARY:
			return false
		var plant: Dictionary = plant_variant
		for field_name in ["demand", "capture_efficiency", "uptake", "uptake_ratio"]:
			if typeof(plant.get(field_name)) != TYPE_DICTIONARY:
				return false
	return true

static func _has_exact_fields(values: Dictionary, fields: Array[String]) -> bool:
	if values.keys().size() != fields.size():
		return false
	for field_name in fields:
		if not values.has(field_name):
			return false
	return true

static func _zero_resource_map() -> Dictionary:
	return {"light": 0.0, "water": 0.0, "nutrients": 0.0}

static func _plant_record_hash(record: Dictionary) -> String:
	return "|".join(PackedStringArray([
		String(record.get("id", "")),
		"biomass=%.12f" % float(record.get("biomass_kg", 0.0)),
		"growth=%.12f" % float(record.get("resource_growth_factor", 0.0)),
		"response=%.12f" % float(record.get("response_fraction", 0.0)),
		"delta=%.12f" % float(record.get("biomass_delta_kg", 0.0)),
		"next=%.12f" % float(record.get("next_biomass_kg", 0.0)),
	])).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
