extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const EPSILON := 0.000000001
var assertion_count := 0

func _init() -> void:
	var failure := _run()
	if failure.is_empty():
		return
	push_error(failure)
	quit(1)

func _run() -> String:
	var constrained_plants := [
		_plant("oak", 8.0, 8.0, 4.0, 1.0, 1.0, 1.0),
		_plant("fern", 8.0, 8.0, 4.0, 0.5, 0.5, 0.5),
	]
	var constrained_supply := _resources(6.0, 6.0, 3.0)
	var constrained := Competition.compete(constrained_supply, constrained_plants)
	var failure := _assert(not constrained.is_empty(), "constrained result must exist")
	if not failure.is_empty(): return failure
	failure = _assert(bool(Competition.validate_result(constrained).get("success", false)), "constrained result validates")
	if not failure.is_empty(): return failure
	failure = _assert(String(constrained["parent_evo1_p2_8_aggregate"]) == Competition.PARENT_EVO1_P2_8_AGGREGATE, "P2.8 parent is pinned")
	if not failure.is_empty(): return failure
	failure = _assert(Array(constrained["plant_order"]) == ["fern", "oak"], "plant order is canonical")
	if not failure.is_empty(): return failure
	var fern := _record(constrained, "fern")
	var oak := _record(constrained, "oak")
	failure = _near(float(oak["uptake"]["light"]), 4.0, "high-efficiency light share")
	if not failure.is_empty(): return failure
	failure = _near(float(fern["uptake"]["light"]), 2.0, "low-efficiency light share")
	if not failure.is_empty(): return failure
	failure = _near(float(oak["uptake"]["water"]), 4.0, "high-efficiency water share")
	if not failure.is_empty(): return failure
	failure = _near(float(fern["uptake"]["water"]), 2.0, "low-efficiency water share")
	if not failure.is_empty(): return failure
	failure = _near(float(oak["uptake"]["nutrients"]), 2.0, "high-efficiency nutrient share")
	if not failure.is_empty(): return failure
	failure = _near(float(fern["uptake"]["nutrients"]), 1.0, "low-efficiency nutrient share")
	if not failure.is_empty(): return failure
	for resource in Competition.RESOURCE_ORDER:
		failure = _near(float(constrained["total_uptake"][resource]), float(constrained_supply[resource]), "constrained pool consumed: " + resource)
		if not failure.is_empty(): return failure
		failure = _near(float(constrained["remaining"][resource]), 0.0, "constrained pool remaining zero: " + resource)
		if not failure.is_empty(): return failure
		failure = _assert(float(constrained["conservation_error"][resource]) <= Competition.EPSILON, "conservation: " + resource)
		if not failure.is_empty(): return failure

	var permuted := Competition.compete(constrained_supply, [constrained_plants[1], constrained_plants[0]])
	failure = _assert(String(permuted.get("result_hash", "")) == String(constrained["result_hash"]), "input permutation does not change result hash")
	if not failure.is_empty(): return failure
	failure = _assert(Array(permuted.get("plant_order", [])) == Array(constrained["plant_order"]), "permutation keeps canonical output order")
	if not failure.is_empty(): return failure
	var repeat_a := Competition.compete(constrained_supply, constrained_plants)
	var repeat_b := Competition.compete(constrained_supply, constrained_plants)
	failure = _assert(String(repeat_a["result_hash"]) == String(repeat_b["result_hash"]), "repeat determinism")
	if not failure.is_empty(): return failure

	var abundant := Competition.compete(_resources(100.0, 100.0, 100.0), [
		_plant("a", 2.0, 3.0, 4.0, 0.1, 0.2, 0.3),
		_plant("b", 5.0, 7.0, 11.0, 1.0, 1.0, 1.0),
	])
	failure = _assert(bool(Competition.validate_result(abundant).get("success", false)), "abundant result validates")
	if not failure.is_empty(): return failure
	for resource in Competition.RESOURCE_ORDER:
		var expected := float(_record(abundant, "a")["demand"][resource]) + float(_record(abundant, "b")["demand"][resource])
		failure = _near(float(abundant["total_uptake"][resource]), expected, "abundant fulfills all demand: " + resource)
		if not failure.is_empty(): return failure
	failure = _near(float(_record(abundant, "a")["growth_factor"]), 1.0, "abundant resources permit full growth")
	if not failure.is_empty(): return failure
	failure = _assert(String(_record(abundant, "a")["limiting_resource"]) == "LIGHT", "all-full demanded resources use deterministic LIGHT tie-break")
	if not failure.is_empty(): return failure

	var water_limited := Competition.compete(_resources(10.0, 1.0, 10.0), [_plant("single", 2.0, 4.0, 1.0, 1.0, 1.0, 1.0)])
	var single := _record(water_limited, "single")
	failure = _near(float(single["uptake_ratio"]["light"]), 1.0, "single light fulfilled")
	if not failure.is_empty(): return failure
	failure = _near(float(single["uptake_ratio"]["water"]), 0.25, "single water ratio")
	if not failure.is_empty(): return failure
	failure = _near(float(single["uptake_ratio"]["nutrients"]), 1.0, "single nutrients fulfilled")
	if not failure.is_empty(): return failure
	failure = _near(float(single["growth_factor"]), 0.25, "Liebig growth follows limiting resource")
	if not failure.is_empty(): return failure
	failure = _assert(String(single["limiting_resource"]) == "WATER", "water is limiting")
	if not failure.is_empty(): return failure

	var zero := Competition.compete(_resources(0.0, 0.0, 0.0), [_plant("zero", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)])
	failure = _assert(bool(Competition.validate_result(zero).get("success", false)), "zero-supply result validates")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(zero, "zero")["growth_factor"]), 0.0, "zero supply yields zero growth")
	if not failure.is_empty(): return failure
	for resource in Competition.RESOURCE_ORDER:
		failure = _near(float(zero["total_uptake"][resource]), 0.0, "zero uptake: " + resource)
		if not failure.is_empty(): return failure

	var empty_population := Competition.compete(_resources(2.0, 3.0, 4.0), [])
	failure = _assert(bool(Competition.validate_result(empty_population).get("success", false)), "empty population conserves pool")
	if not failure.is_empty(): return failure
	failure = _near(float(empty_population["remaining"]["light"]), 2.0, "empty population keeps light")
	if not failure.is_empty(): return failure
	failure = _near(float(empty_population["remaining"]["water"]), 3.0, "empty population keeps water")
	if not failure.is_empty(): return failure
	failure = _near(float(empty_population["remaining"]["nutrients"]), 4.0, "empty population keeps nutrients")
	if not failure.is_empty(): return failure

	failure = _assert(Competition.compete(_resources(-1.0, 1.0, 1.0), constrained_plants).is_empty(), "negative supply fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Competition.compete(_resources(1.0, 1.0, 1.0), [_plant("dup", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0), _plant("dup", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)]).is_empty(), "duplicate IDs fail closed")
	if not failure.is_empty(): return failure
	var invalid_eff := _plant("bad", 1.0, 1.0, 1.0, 1.1, 1.0, 1.0)
	failure = _assert(Competition.compete(_resources(1.0, 1.0, 1.0), [invalid_eff]).is_empty(), "efficiency above one fails closed")
	if not failure.is_empty(): return failure
	var invalid_shape := _plant("shape", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
	invalid_shape["unexpected"] = true
	failure = _assert(Competition.compete(_resources(1.0, 1.0, 1.0), [invalid_shape]).is_empty(), "unexpected plant field fails closed")
	if not failure.is_empty(): return failure

	var tampered := constrained.duplicate(true)
	tampered["plants"][0]["growth_factor"] = 0.123
	failure = _assert(not bool(Competition.validate_result(tampered).get("success", false)), "tampered result fails validation")
	if not failure.is_empty(): return failure

	var aggregate := "\n".join(PackedStringArray([
		Competition.PARENT_EVO1_P2_8_AGGREGATE,
		String(constrained["result_hash"]),
		String(permuted["result_hash"]),
		String(abundant["result_hash"]),
		String(water_limited["result_hash"]),
		String(zero["result_hash"]),
		String(empty_population["result_hash"]),
	])).sha256_text()
	print("ECO.P3.1 Resource Competition: PASS (%d assertions)" % assertion_count)
	print("aggregate_hash=%s" % aggregate)
	print("constrained_hash=%s" % String(constrained["result_hash"]))
	print("abundant_hash=%s" % String(abundant["result_hash"]))
	print("water_limited_hash=%s" % String(water_limited["result_hash"]))
	print("parent_p2_8=%s" % Competition.PARENT_EVO1_P2_8_AGGREGATE)
	quit(0)
	return ""

func _plant(id: String, light_demand: float, water_demand: float, nutrient_demand: float, light_efficiency: float, water_efficiency: float, nutrient_efficiency: float) -> Dictionary:
	return {"id": id, "demand": _resources(light_demand, water_demand, nutrient_demand), "capture_efficiency": _resources(light_efficiency, water_efficiency, nutrient_efficiency)}

func _resources(light: float, water: float, nutrients: float) -> Dictionary:
	return {"light": light, "water": water, "nutrients": nutrients}

func _record(result: Dictionary, id: String) -> Dictionary:
	for record_variant in Array(result.get("plants", [])):
		var record: Dictionary = record_variant
		if String(record.get("id", "")) == id:
			return record
	return {}

func _assert(condition: bool, message: String) -> String:
	assertion_count += 1
	if condition:
		return ""
	return "ASSERTION FAILED: " + message

func _near(actual: float, expected: float, message: String) -> String:
	return _assert(absf(actual - expected) <= EPSILON, "%s actual=%.12f expected=%.12f" % [message, actual, expected])
