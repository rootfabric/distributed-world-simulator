extends RefCounted

const SCHEMA := "distributed_world_simulator.ecology.p3_1_resource_competition.v1"
const VERSION := "1.0.0"
const PARENT_EVO1_P2_8_AGGREGATE := "ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6"
const EPSILON := 0.000000000001
const RESOURCE_ORDER: Array[String] = ["light", "water", "nutrients"]

static func compete(supply: Dictionary, plants: Array) -> Dictionary:
	var normalized_supply := _normalize_resource_map(supply, false)
	if normalized_supply.is_empty():
		return {}
	var normalized_plants := _normalize_plants(plants)
	if normalized_plants.is_empty() and not plants.is_empty():
		return {}

	var plant_ids := PackedStringArray()
	var plants_by_id := {}
	for plant in normalized_plants:
		var plant_id := String(plant["id"])
		plant_ids.append(plant_id)
		plants_by_id[plant_id] = plant
	plant_ids.sort()

	var uptake_by_id := {}
	for plant_id in plant_ids:
		uptake_by_id[plant_id] = _zero_resource_map()

	for resource in RESOURCE_ORDER:
		var allocation := _allocate_resource(float(normalized_supply[resource]), plant_ids, plants_by_id, resource)
		if allocation.is_empty() and not plant_ids.is_empty():
			return {}
		for plant_id in plant_ids:
			uptake_by_id[plant_id][resource] = float(allocation.get(plant_id, 0.0))

	var plant_results: Array[Dictionary] = []
	var total_uptake := _zero_resource_map()
	for plant_id in plant_ids:
		var plant: Dictionary = plants_by_id[plant_id]
		var demand: Dictionary = plant["demand"]
		var efficiency: Dictionary = plant["capture_efficiency"]
		var uptake: Dictionary = uptake_by_id[plant_id]
		var ratios := {}
		var limiting_resource := "NONE"
		var growth_factor := 1.0
		var has_demand := false
		for resource in RESOURCE_ORDER:
			var requested := float(demand[resource])
			var received := float(uptake[resource])
			total_uptake[resource] = float(total_uptake[resource]) + received
			var ratio := 1.0
			if requested > EPSILON:
				has_demand = true
				ratio = clampf(received / requested, 0.0, 1.0)
				if limiting_resource == "NONE" or ratio < growth_factor - EPSILON:
					limiting_resource = resource.to_upper()
					growth_factor = ratio
			ratios[resource] = ratio
		if not has_demand:
			growth_factor = 1.0
		var record := {
			"id": plant_id,
			"demand": demand.duplicate(true),
			"capture_efficiency": efficiency.duplicate(true),
			"uptake": uptake.duplicate(true),
			"uptake_ratio": ratios,
			"limiting_resource": limiting_resource,
			"growth_factor": growth_factor,
		}
		record["record_hash"] = _plant_record_hash(record)
		plant_results.append(record)

	var remaining := {}
	var conservation_error := {}
	for resource in RESOURCE_ORDER:
		var available := float(normalized_supply[resource])
		var used := float(total_uptake[resource])
		var left := maxf(0.0, available - used)
		remaining[resource] = left
		conservation_error[resource] = absf(available - used - left)

	var result := {
		"schema": SCHEMA,
		"version": VERSION,
		"parent_evo1_p2_8_aggregate": PARENT_EVO1_P2_8_AGGREGATE,
		"resource_order": RESOURCE_ORDER.duplicate(),
		"plant_order": plant_ids,
		"supply": normalized_supply,
		"plants": plant_results,
		"total_uptake": total_uptake,
		"remaining": remaining,
		"conservation_error": conservation_error,
	}
	result["result_hash"] = compute_result_hash(result)
	return result

static func validate_result(result: Dictionary) -> Dictionary:
	if String(result.get("schema", "")) != SCHEMA:
		return _failure("ECO_P3_1_SCHEMA_MISMATCH")
	if String(result.get("version", "")) != VERSION:
		return _failure("ECO_P3_1_VERSION_MISMATCH")
	if String(result.get("parent_evo1_p2_8_aggregate", "")) != PARENT_EVO1_P2_8_AGGREGATE:
		return _failure("ECO_P3_1_PARENT_MISMATCH")
	if Array(result.get("resource_order", [])) != RESOURCE_ORDER:
		return _failure("ECO_P3_1_RESOURCE_ORDER_MISMATCH")
	var supply := _normalize_resource_map(Dictionary(result.get("supply", {})), false)
	var total_uptake := _normalize_resource_map(Dictionary(result.get("total_uptake", {})), false)
	var remaining := _normalize_resource_map(Dictionary(result.get("remaining", {})), false)
	var conservation := _normalize_resource_map(Dictionary(result.get("conservation_error", {})), false)
	if supply.is_empty() or total_uptake.is_empty() or remaining.is_empty() or conservation.is_empty():
		return _failure("ECO_P3_1_INVALID_RESOURCE_ACCOUNTING")
	for resource in RESOURCE_ORDER:
		var available := float(supply[resource])
		var used := float(total_uptake[resource])
		var left := float(remaining[resource])
		var error := float(conservation[resource])
		if used > available + EPSILON:
			return _failure("ECO_P3_1_OVERCONSUMPTION", {"resource": resource})
		if absf(available - used - left) > EPSILON or error > EPSILON:
			return _failure("ECO_P3_1_CONSERVATION_MISMATCH", {"resource": resource})
	var plants: Array = result.get("plants", [])
	var plant_order := PackedStringArray(result.get("plant_order", PackedStringArray()))
	if plants.size() != plant_order.size():
		return _failure("ECO_P3_1_PLANT_COUNT_MISMATCH")
	for index in range(plants.size()):
		var plant: Dictionary = plants[index]
		if String(plant.get("id", "")) != String(plant_order[index]):
			return _failure("ECO_P3_1_PLANT_ORDER_MISMATCH")
		if String(plant.get("record_hash", "")) != _plant_record_hash(plant):
			return _failure("ECO_P3_1_PLANT_RECORD_HASH_MISMATCH", {"id": String(plant.get("id", ""))})
	if String(result.get("result_hash", "")) != compute_result_hash(result):
		return _failure("ECO_P3_1_RESULT_HASH_MISMATCH")
	return _success()

static func compute_result_hash(result: Dictionary) -> String:
	var tokens := PackedStringArray([SCHEMA, VERSION, PARENT_EVO1_P2_8_AGGREGATE])
	var supply: Dictionary = result.get("supply", {})
	var total_uptake: Dictionary = result.get("total_uptake", {})
	var remaining: Dictionary = result.get("remaining", {})
	var conservation: Dictionary = result.get("conservation_error", {})
	for resource in RESOURCE_ORDER:
		tokens.append("%s|supply=%.12f|uptake=%.12f|remaining=%.12f|error=%.12f" % [resource, float(supply.get(resource, 0.0)), float(total_uptake.get(resource, 0.0)), float(remaining.get(resource, 0.0)), float(conservation.get(resource, 0.0))])
	var plants: Array = result.get("plants", [])
	for plant_variant in plants:
		var plant: Dictionary = plant_variant
		tokens.append("%s|%s" % [String(plant.get("id", "")), String(plant.get("record_hash", ""))])
	return "\n".join(tokens).sha256_text()

static func _allocate_resource(available: float, plant_ids: PackedStringArray, plants_by_id: Dictionary, resource: String) -> Dictionary:
	var allocation := {}
	var active := PackedStringArray()
	for plant_id in plant_ids:
		allocation[plant_id] = 0.0
		var plant: Dictionary = plants_by_id[plant_id]
		var demand := float(Dictionary(plant["demand"])[resource])
		var efficiency := float(Dictionary(plant["capture_efficiency"])[resource])
		if demand > EPSILON and efficiency > EPSILON:
			active.append(plant_id)

	var remaining_supply := available
	while remaining_supply > EPSILON and not active.is_empty():
		var total_weight := 0.0
		for plant_id in active:
			var plant: Dictionary = plants_by_id[plant_id]
			var demand := float(Dictionary(plant["demand"])[resource])
			var efficiency := float(Dictionary(plant["capture_efficiency"])[resource])
			var unmet := maxf(0.0, demand - float(allocation[plant_id]))
			total_weight += unmet * efficiency
		if total_weight <= EPSILON:
			break

		var round_supply := remaining_supply
		var capped := PackedStringArray()
		for plant_id in active:
			var plant: Dictionary = plants_by_id[plant_id]
			var demand := float(Dictionary(plant["demand"])[resource])
			var efficiency := float(Dictionary(plant["capture_efficiency"])[resource])
			var unmet := maxf(0.0, demand - float(allocation[plant_id]))
			var proposed := round_supply * (unmet * efficiency) / total_weight
			if proposed >= unmet - EPSILON:
				capped.append(plant_id)

		if capped.is_empty():
			for plant_id in active:
				var plant: Dictionary = plants_by_id[plant_id]
				var demand := float(Dictionary(plant["demand"])[resource])
				var efficiency := float(Dictionary(plant["capture_efficiency"])[resource])
				var unmet := maxf(0.0, demand - float(allocation[plant_id]))
				var proposed := round_supply * (unmet * efficiency) / total_weight
				allocation[plant_id] = float(allocation[plant_id]) + minf(unmet, proposed)
			remaining_supply = 0.0
			break

		for plant_id in capped:
			var plant: Dictionary = plants_by_id[plant_id]
			var demand := float(Dictionary(plant["demand"])[resource])
			var unmet := maxf(0.0, demand - float(allocation[plant_id]))
			allocation[plant_id] = float(allocation[plant_id]) + unmet
			remaining_supply = maxf(0.0, remaining_supply - unmet)
			active.remove_at(active.find(plant_id))
	return allocation

static func _normalize_plants(plants: Array) -> Array[Dictionary]:
	var by_id := {}
	for plant_variant in plants:
		if typeof(plant_variant) != TYPE_DICTIONARY:
			return []
		var plant: Dictionary = plant_variant
		if plant.keys().size() != 3 or not plant.has("id") or not plant.has("demand") or not plant.has("capture_efficiency"):
			return []
		var plant_id := String(plant.get("id", ""))
		if plant_id.is_empty() or by_id.has(plant_id):
			return []
		var demand := _normalize_resource_map(Dictionary(plant.get("demand", {})), false)
		var efficiency := _normalize_resource_map(Dictionary(plant.get("capture_efficiency", {})), true)
		if demand.is_empty() or efficiency.is_empty():
			return []
		by_id[plant_id] = {"id": plant_id, "demand": demand, "capture_efficiency": efficiency}
	var ids := PackedStringArray(by_id.keys())
	ids.sort()
	var normalized: Array[Dictionary] = []
	for plant_id in ids:
		normalized.append(Dictionary(by_id[plant_id]))
	return normalized

static func _normalize_resource_map(values: Dictionary, bounded_ratio: bool) -> Dictionary:
	if values.keys().size() != RESOURCE_ORDER.size():
		return {}
	var result := {}
	for resource in RESOURCE_ORDER:
		if not values.has(resource):
			return {}
		var raw = values[resource]
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT]:
			return {}
		var value := float(raw)
		if not is_finite(value) or value < 0.0:
			return {}
		if bounded_ratio and value > 1.0:
			return {}
		result[resource] = value
	return result

static func _zero_resource_map() -> Dictionary:
	return {"light": 0.0, "water": 0.0, "nutrients": 0.0}

static func _plant_record_hash(record: Dictionary) -> String:
	var demand: Dictionary = record.get("demand", {})
	var efficiency: Dictionary = record.get("capture_efficiency", {})
	var uptake: Dictionary = record.get("uptake", {})
	var ratios: Dictionary = record.get("uptake_ratio", {})
	var tokens := PackedStringArray([String(record.get("id", ""))])
	for resource in RESOURCE_ORDER:
		tokens.append("%s|d=%.12f|e=%.12f|u=%.12f|r=%.12f" % [resource, float(demand.get(resource, 0.0)), float(efficiency.get(resource, 0.0)), float(uptake.get(resource, 0.0)), float(ratios.get(resource, 0.0))])
	tokens.append("limiting=%s" % String(record.get("limiting_resource", "")))
	tokens.append("growth=%.12f" % float(record.get("growth_factor", 0.0)))
	return "\n".join(tokens).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}

static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "details": details.duplicate(true)}
