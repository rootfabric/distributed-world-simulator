extends RefCounted

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")

const SCHEMA := "distributed_world_simulator.ecology.obs1_snapshot.v1"
const VERSION := "1.0.0"
const EPSILON := 0.000000000001
const SNAPSHOT_FIELDS: Array[String] = [
	"schema",
	"version",
	"step_index",
	"year",
	"source_schema",
	"source_result_hash",
	"parent_p3_1_aggregate",
	"parent_evo1_p2_8_aggregate",
	"resource_support_ratio",
	"resource_support",
	"resource_pressure",
	"limiting_resource",
	"effective_capacity_kg",
	"total_biomass_kg",
	"total_next_biomass_kg",
	"density_ratio",
	"density_feedback",
	"active_plant_count",
	"plant_order",
	"plants",
	"snapshot_hash",
]
const PLANT_FIELDS: Array[String] = [
	"id",
	"biomass_kg",
	"next_biomass_kg",
	"resource_growth_factor",
	"limiting_resource",
]

static func from_p3_2(result: Dictionary, step_index: int, year: float) -> Dictionary:
	if step_index < 0 or not is_finite(year) or year < 0.0:
		return {}
	if not bool(Density.validate_result(result).get("success", false)):
		return {}
	var source_hash := String(result.get("result_hash", ""))
	if source_hash.length() != 64:
		return {}
	var support_ratio := _copy_resource_map(Dictionary(result.get("resource_support_ratio", {})))
	if support_ratio.is_empty():
		return {}
	var competition_result: Dictionary = result.get("competition_result", {})
	if not bool(Competition.validate_result(competition_result).get("success", false)):
		return {}
	var competition_by_id := {}
	for record_value in Array(competition_result.get("plants", [])):
		if typeof(record_value) != TYPE_DICTIONARY:
			return {}
		var record: Dictionary = record_value
		competition_by_id[String(record.get("id", ""))] = record
	var plant_order := PackedStringArray(result.get("plant_order", PackedStringArray()))
	var plants: Array[Dictionary] = []
	var active_count := 0
	for plant_value in Array(result.get("plants", [])):
		if typeof(plant_value) != TYPE_DICTIONARY:
			return {}
		var plant: Dictionary = plant_value
		var plant_id := String(plant.get("id", ""))
		if not competition_by_id.has(plant_id):
			return {}
		var competition_record: Dictionary = competition_by_id[plant_id]
		var biomass := float(plant.get("biomass_kg", 0.0))
		if biomass > EPSILON:
			active_count += 1
		plants.append({
			"id": plant_id,
			"biomass_kg": biomass,
			"next_biomass_kg": float(plant.get("next_biomass_kg", 0.0)),
			"resource_growth_factor": float(plant.get("resource_growth_factor", 0.0)),
			"limiting_resource": String(competition_record.get("limiting_resource", "NONE")),
		})
	var snapshot := {
		"schema": SCHEMA,
		"version": VERSION,
		"step_index": step_index,
		"year": year,
		"source_schema": String(result.get("schema", "")),
		"source_result_hash": source_hash,
		"parent_p3_1_aggregate": String(result.get("parent_p3_1_candidate_aggregate", "")),
		"parent_evo1_p2_8_aggregate": String(result.get("parent_evo1_p2_8_aggregate", "")),
		"resource_support_ratio": support_ratio,
		"resource_support": float(result.get("resource_support", 0.0)),
		"resource_pressure": float(result.get("resource_pressure", 0.0)),
		"limiting_resource": _limiting_resource(support_ratio),
		"effective_capacity_kg": float(result.get("effective_capacity_kg", 0.0)),
		"total_biomass_kg": float(result.get("total_biomass_kg", 0.0)),
		"total_next_biomass_kg": float(result.get("total_next_biomass_kg", 0.0)),
		"density_ratio": float(result.get("density_ratio", 0.0)),
		"density_feedback": float(result.get("density_feedback", 0.0)),
		"active_plant_count": active_count,
		"plant_order": plant_order.duplicate(),
		"plants": plants,
	}
	snapshot["snapshot_hash"] = compute_hash(snapshot)
	if String(result.get("result_hash", "")) != source_hash:
		return {}
	return snapshot

static func validate(snapshot: Dictionary) -> Dictionary:
	if not _has_exact_fields(snapshot, SNAPSHOT_FIELDS):
		return _failure("ECO_OBS1_SNAPSHOT_FIELDS_MISMATCH")
	if String(snapshot.get("schema", "")) != SCHEMA:
		return _failure("ECO_OBS1_SCHEMA_MISMATCH")
	if String(snapshot.get("version", "")) != VERSION:
		return _failure("ECO_OBS1_VERSION_MISMATCH")
	if String(snapshot.get("source_schema", "")) != Density.SCHEMA:
		return _failure("ECO_OBS1_SOURCE_SCHEMA_MISMATCH")
	if String(snapshot.get("parent_p3_1_aggregate", "")) != Density.PARENT_P3_1_CANDIDATE_AGGREGATE:
		return _failure("ECO_OBS1_P3_1_PARENT_MISMATCH")
	if String(snapshot.get("parent_evo1_p2_8_aggregate", "")) != Density.PARENT_EVO1_P2_8_AGGREGATE:
		return _failure("ECO_OBS1_P2_8_PARENT_MISMATCH")
	if int(snapshot.get("step_index", -1)) < 0:
		return _failure("ECO_OBS1_INVALID_STEP_INDEX")
	var year_value = snapshot.get("year")
	if typeof(year_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(year_value)) or float(year_value) < 0.0:
		return _failure("ECO_OBS1_INVALID_YEAR")
	for field_name in ["resource_support", "resource_pressure", "effective_capacity_kg", "total_biomass_kg", "total_next_biomass_kg", "density_ratio", "density_feedback"]:
		var raw = snapshot.get(field_name)
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
			return _failure("ECO_OBS1_NON_FINITE_FIELD", {"field": field_name})
	if float(snapshot["resource_support"]) < 0.0 or float(snapshot["resource_support"]) > 1.0:
		return _failure("ECO_OBS1_INVALID_RESOURCE_SUPPORT")
	if float(snapshot["effective_capacity_kg"]) <= EPSILON:
		return _failure("ECO_OBS1_INVALID_EFFECTIVE_CAPACITY")
	if float(snapshot["total_biomass_kg"]) < 0.0 or float(snapshot["total_next_biomass_kg"]) < 0.0:
		return _failure("ECO_OBS1_NEGATIVE_TOTAL_BIOMASS")
	if float(snapshot["density_ratio"]) < 0.0 or float(snapshot["density_feedback"]) < -1.0 or float(snapshot["density_feedback"]) > 1.0:
		return _failure("ECO_OBS1_INVALID_DENSITY_STATE")
	if absf(float(snapshot["density_ratio"]) - float(snapshot["total_biomass_kg"]) / float(snapshot["effective_capacity_kg"])) > EPSILON:
		return _failure("ECO_OBS1_DENSITY_RATIO_MISMATCH")
	if float(snapshot["resource_pressure"]) < 0.0 or float(snapshot["resource_pressure"]) > 1.0:
		return _failure("ECO_OBS1_INVALID_RESOURCE_PRESSURE")
	if absf(float(snapshot["resource_pressure"]) - (1.0 - float(snapshot["resource_support"]))) > EPSILON:
		return _failure("ECO_OBS1_RESOURCE_PRESSURE_MISMATCH")
	var support_ratio := _copy_resource_map(Dictionary(snapshot.get("resource_support_ratio", {})))
	if support_ratio.is_empty():
		return _failure("ECO_OBS1_INVALID_RESOURCE_SUPPORT_MAP")
	if String(snapshot.get("limiting_resource", "")) != _limiting_resource(support_ratio):
		return _failure("ECO_OBS1_LIMITING_RESOURCE_MISMATCH")
	if typeof(snapshot.get("plant_order")) != TYPE_PACKED_STRING_ARRAY or typeof(snapshot.get("plants")) != TYPE_ARRAY:
		return _failure("ECO_OBS1_PLANT_CONTAINER_TYPE_MISMATCH")
	var order: PackedStringArray = snapshot["plant_order"]
	var sorted_order := order.duplicate()
	sorted_order.sort()
	if sorted_order != order:
		return _failure("ECO_OBS1_PLANT_ORDER_NOT_CANONICAL")
	var plants: Array = snapshot["plants"]
	if plants.size() != order.size():
		return _failure("ECO_OBS1_PLANT_COUNT_MISMATCH")
	var active_count := 0
	for index in range(plants.size()):
		if typeof(plants[index]) != TYPE_DICTIONARY:
			return _failure("ECO_OBS1_PLANT_RECORD_TYPE_MISMATCH")
		var plant: Dictionary = plants[index]
		if not _has_exact_fields(plant, PLANT_FIELDS):
			return _failure("ECO_OBS1_PLANT_FIELDS_MISMATCH")
		if String(plant.get("id", "")) != String(order[index]):
			return _failure("ECO_OBS1_PLANT_ORDER_MISMATCH")
		for field_name in ["biomass_kg", "next_biomass_kg", "resource_growth_factor"]:
			var raw = plant.get(field_name)
			if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)):
				return _failure("ECO_OBS1_NON_FINITE_PLANT_FIELD", {"field": field_name})
		if float(plant["biomass_kg"]) < 0.0 or float(plant["next_biomass_kg"]) < 0.0:
			return _failure("ECO_OBS1_NEGATIVE_PLANT_BIOMASS")
		if float(plant["resource_growth_factor"]) < 0.0 or float(plant["resource_growth_factor"]) > 1.0:
			return _failure("ECO_OBS1_INVALID_PLANT_GROWTH_FACTOR")
		if not String(plant["limiting_resource"]) in ["LIGHT", "WATER", "NUTRIENTS", "NONE"]:
			return _failure("ECO_OBS1_INVALID_PLANT_LIMITING_RESOURCE")
		if float(plant["biomass_kg"]) > EPSILON:
			active_count += 1
	if int(snapshot.get("active_plant_count", -1)) != active_count:
		return _failure("ECO_OBS1_ACTIVE_COUNT_MISMATCH")
	if String(snapshot.get("source_result_hash", "")).length() != 64:
		return _failure("ECO_OBS1_INVALID_SOURCE_HASH")
	if String(snapshot.get("snapshot_hash", "")) != compute_hash(snapshot):
		return _failure("ECO_OBS1_SNAPSHOT_HASH_MISMATCH")
	return _success()

static func compute_hash(snapshot: Dictionary) -> String:
	var tokens := PackedStringArray([
		SCHEMA,
		VERSION,
		"step=%d" % int(snapshot.get("step_index", 0)),
		"year=%.12f" % float(snapshot.get("year", 0.0)),
		"source=%s" % String(snapshot.get("source_result_hash", "")),
		"parent_p3_1=%s" % String(snapshot.get("parent_p3_1_aggregate", "")),
		"parent_p2_8=%s" % String(snapshot.get("parent_evo1_p2_8_aggregate", "")),
	])
	var support_ratio: Dictionary = snapshot.get("resource_support_ratio", {})
	for resource in Competition.RESOURCE_ORDER:
		tokens.append("%s=%.12f" % [resource, float(support_ratio.get(resource, 0.0))])
	for field_name in ["resource_support", "resource_pressure", "effective_capacity_kg", "total_biomass_kg", "total_next_biomass_kg", "density_ratio", "density_feedback"]:
		tokens.append("%s=%.12f" % [field_name, float(snapshot.get(field_name, 0.0))])
	tokens.append("limiting=%s" % String(snapshot.get("limiting_resource", "")))
	tokens.append("active=%d" % int(snapshot.get("active_plant_count", 0)))
	for plant_value in Array(snapshot.get("plants", [])):
		if typeof(plant_value) != TYPE_DICTIONARY:
			continue
		var plant: Dictionary = plant_value
		tokens.append("plant|%s|%.12f|%.12f|%.12f|%s" % [
			String(plant.get("id", "")),
			float(plant.get("biomass_kg", 0.0)),
			float(plant.get("next_biomass_kg", 0.0)),
			float(plant.get("resource_growth_factor", 0.0)),
			String(plant.get("limiting_resource", "")),
		])
	return "\n".join(tokens).sha256_text()

static func _copy_resource_map(values: Dictionary) -> Dictionary:
	if values.keys().size() != Competition.RESOURCE_ORDER.size():
		return {}
	var result := {}
	for resource in Competition.RESOURCE_ORDER:
		if not values.has(resource):
			return {}
		var raw = values[resource]
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var value := float(raw)
		if not is_finite(value) or value < 0.0 or value > 1.0:
			return {}
		result[resource] = value
	return result

static func _limiting_resource(support_ratio: Dictionary) -> String:
	var best_resource := String(Competition.RESOURCE_ORDER[0])
	var best_value := float(support_ratio.get(best_resource, 1.0))
	for resource in Competition.RESOURCE_ORDER:
		var value := float(support_ratio.get(resource, 1.0))
		if value < best_value - EPSILON:
			best_resource = resource
			best_value = value
	return best_resource.to_upper()

static func _has_exact_fields(value: Dictionary, fields: Array[String]) -> bool:
	if value.keys().size() != fields.size():
		return false
	for field_name in fields:
		if not value.has(field_name):
			return false
	return true

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
