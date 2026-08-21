extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const EPSILON := 0.000000001
var assertion_count := 0

func _init() -> void:
	var failure := _run()
	if failure.is_empty():
		return
	push_error(failure)
	quit(1)

func _run() -> String:
	var full_competition := Competition.compete(_resources(10.0, 10.0, 10.0), [
		_competitor("b", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0),
		_competitor("a", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0),
	])
	var failure := _assert(bool(Competition.validate_result(full_competition).get("success", false)), "full-resource P3.1 parent validates")
	if not failure.is_empty(): return failure

	var patch := _patch(10.0, 1.0, 0.25, 0.25, 0.60)
	var under := Density.step(full_competition, patch, [_biomass("b", 1.0), _biomass("a", 1.0)])
	failure = _assert(not under.is_empty(), "under-capacity result exists")
	if not failure.is_empty(): return failure
	failure = _assert(bool(Density.validate_result(under).get("success", false)), "under-capacity result validates")
	if not failure.is_empty(): return failure
	failure = _assert(String(under["parent_p3_1_candidate_aggregate"]) == Density.PARENT_P3_1_CANDIDATE_AGGREGATE, "P3.1 candidate parent is pinned")
	if not failure.is_empty(): return failure
	failure = _assert(String(under["parent_evo1_p2_8_aggregate"]) == Density.PARENT_EVO1_P2_8_AGGREGATE, "P2.8 frozen ancestor is pinned")
	if not failure.is_empty(): return failure
	failure = _assert(Array(under["plant_order"]) == ["a", "b"], "plant order is canonical")
	if not failure.is_empty(): return failure
	failure = _near(float(under["resource_support"]), 1.0, "full resources have full patch support")
	if not failure.is_empty(): return failure
	failure = _near(float(under["resource_pressure"]), 0.0, "full resources have zero pressure")
	if not failure.is_empty(): return failure
	failure = _near(float(under["reference_capacity_kg"]), 10.0, "reference K")
	if not failure.is_empty(): return failure
	failure = _near(float(under["effective_capacity_kg"]), 10.0, "full-resource effective K")
	if not failure.is_empty(): return failure
	failure = _near(float(under["density_ratio"]), 0.2, "under-capacity density ratio")
	if not failure.is_empty(): return failure
	failure = _near(float(under["density_feedback"]), 0.8, "under-capacity recovery feedback")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(under, "a")["response_fraction"]), 0.2, "bounded recovery response")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(under, "a")["next_biomass_kg"]), 1.2, "a recovers below K")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(under, "b")["next_biomass_kg"]), 1.2, "b recovers below K")
	if not failure.is_empty(): return failure
	failure = _near(float(under["total_next_biomass_kg"]), 2.4, "under-capacity next total")
	if not failure.is_empty(): return failure

	var permuted := Density.step(full_competition, patch, [_biomass("a", 1.0), _biomass("b", 1.0)])
	failure = _assert(String(permuted.get("result_hash", "")) == String(under["result_hash"]), "input permutation leaves P3.2 hash unchanged")
	if not failure.is_empty(): return failure
	failure = _assert(Array(permuted.get("plant_order", [])) == Array(under["plant_order"]), "input permutation leaves canonical order unchanged")
	if not failure.is_empty(): return failure
	var repeat := Density.step(full_competition, patch, [_biomass("b", 1.0), _biomass("a", 1.0)])
	failure = _assert(String(repeat.get("result_hash", "")) == String(under["result_hash"]), "same input repeats deterministically")
	if not failure.is_empty(): return failure

	var at_capacity := Density.step(full_competition, patch, [_biomass("a", 5.0), _biomass("b", 5.0)])
	failure = _assert(bool(Density.validate_result(at_capacity).get("success", false)), "at-capacity result validates")
	if not failure.is_empty(): return failure
	failure = _near(float(at_capacity["density_ratio"]), 1.0, "at-capacity ratio is one")
	if not failure.is_empty(): return failure
	failure = _near(float(at_capacity["density_feedback"]), 0.0, "at-capacity feedback is zero")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(at_capacity, "a")["next_biomass_kg"]), 5.0, "at K biomass is stationary")
	if not failure.is_empty(): return failure

	var over := Density.step(full_competition, patch, [_biomass("a", 7.0), _biomass("b", 5.0)])
	failure = _assert(bool(Density.validate_result(over).get("success", false)), "over-capacity result validates")
	if not failure.is_empty(): return failure
	failure = _near(float(over["density_ratio"]), 1.2, "over-capacity ratio")
	if not failure.is_empty(): return failure
	failure = _near(float(over["density_feedback"]), -1.0 / 6.0, "bounded over-capacity feedback")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(over, "a")["response_fraction"]), -0.1, "shared decline response")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(over, "a")["next_biomass_kg"]), 6.3, "a declines softly")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(over, "b")["next_biomass_kg"]), 4.5, "b declines softly")
	if not failure.is_empty(): return failure
	failure = _near(float(over["total_next_biomass_kg"]), 10.8, "soft response total")
	if not failure.is_empty(): return failure
	failure = _assert(float(over["total_next_biomass_kg"]) > float(over["effective_capacity_kg"]), "P3.2 does not hard-clip to carrying capacity")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(over, "a")["biomass_kg"]) / float(over["total_biomass_kg"]), float(_record(over, "a")["next_biomass_kg"]) / float(over["total_next_biomass_kg"]), "shared over-capacity pressure preserves composition")
	if not failure.is_empty(): return failure

	var convergence_plants := [_biomass("a", 7.0), _biomass("b", 5.0)]
	var previous_total := 12.0
	for step_index in range(10):
		var convergence := Density.step(full_competition, patch, convergence_plants)
		failure = _assert(bool(Density.validate_result(convergence).get("success", false)), "convergence step validates %d" % step_index)
		if not failure.is_empty(): return failure
		var next_total := float(convergence["total_next_biomass_kg"])
		failure = _assert(next_total < previous_total and next_total > float(convergence["effective_capacity_kg"]), "over-capacity trajectory approaches K without crossing %d" % step_index)
		if not failure.is_empty(): return failure
		previous_total = next_total
		convergence_plants = _next_biomass(convergence)
	failure = _assert(previous_total < 10.001, "soft decline converges close to K")
	if not failure.is_empty(): return failure

	var limited_competition := Competition.compete(_resources(10.0, 1.0, 10.0), [
		_competitor("a", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0),
		_competitor("b", 1.0, 1.0, 1.0, 1.0, 1.0, 1.0),
	])
	var limited := Density.step(limited_competition, patch, [_biomass("a", 1.0), _biomass("b", 1.0)])
	failure = _assert(bool(Density.validate_result(limited).get("success", false)), "resource-limited result validates")
	if not failure.is_empty(): return failure
	failure = _near(float(limited["resource_support_ratio"]["water"]), 0.5, "water support ratio")
	if not failure.is_empty(): return failure
	failure = _near(float(limited["resource_support"]), 0.5, "patch support follows limiting resource")
	if not failure.is_empty(): return failure
	failure = _near(float(limited["resource_pressure"]), 0.5, "resource pressure")
	if not failure.is_empty(): return failure
	failure = _near(float(limited["effective_capacity_fraction"]), 0.625, "resource pressure lowers capacity fraction")
	if not failure.is_empty(): return failure
	failure = _near(float(limited["effective_capacity_kg"]), 6.25, "resource pressure lowers K")
	if not failure.is_empty(): return failure
	failure = _near(float(limited["density_ratio"]), 0.32, "limited density ratio uses effective K")
	if not failure.is_empty(): return failure
	failure = _near(float(limited["density_feedback"]), 0.68, "limited density feedback")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(limited, "a")["resource_growth_factor"]), 0.5, "P3.1 growth factor propagates")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(limited, "a")["response_fraction"]), 0.085, "resource scarcity slows recovery")
	if not failure.is_empty(): return failure
	failure = _near(float(_record(limited, "a")["next_biomass_kg"]), 1.085, "limited recovery biomass")
	if not failure.is_empty(): return failure
	failure = _assert(float(_record(limited, "a")["next_biomass_kg"]) < float(_record(under, "a")["next_biomass_kg"]), "limited resources recover slower than full resources")
	if not failure.is_empty(): return failure

	var empty_competition := Competition.compete(_resources(3.0, 3.0, 3.0), [])
	var empty_population := Density.step(empty_competition, patch, [])
	failure = _assert(bool(Density.validate_result(empty_population).get("success", false)), "empty population is valid")
	if not failure.is_empty(): return failure
	failure = _near(float(empty_population["resource_support"]), 1.0, "no demand has neutral resource support")
	if not failure.is_empty(): return failure
	failure = _near(float(empty_population["density_feedback"]), 1.0, "empty patch has maximum recovery potential")
	if not failure.is_empty(): return failure
	failure = _near(float(empty_population["total_next_biomass_kg"]), 0.0, "P3.2 does not create biomass/recruitment")
	if not failure.is_empty(): return failure

	var invalid_patch := patch.duplicate(true)
	invalid_patch["area_m2"] = -1.0
	failure = _assert(Density.step(full_competition, invalid_patch, [_biomass("a", 1.0), _biomass("b", 1.0)]).is_empty(), "negative area fails closed")
	if not failure.is_empty(): return failure
	invalid_patch = patch.duplicate(true)
	invalid_patch["minimum_capacity_fraction"] = 0.0
	failure = _assert(Density.step(full_competition, invalid_patch, [_biomass("a", 1.0), _biomass("b", 1.0)]).is_empty(), "zero minimum capacity fraction fails closed")
	if not failure.is_empty(): return failure
	invalid_patch = patch.duplicate(true)
	invalid_patch["max_decline_fraction"] = 1.01
	failure = _assert(Density.step(full_competition, invalid_patch, [_biomass("a", 1.0), _biomass("b", 1.0)]).is_empty(), "decline fraction above one fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Density.step(full_competition, patch, [_biomass("a", -0.1), _biomass("b", 1.0)]).is_empty(), "negative biomass fails closed")
	if not failure.is_empty(): return failure
	failure = _assert(Density.step(full_competition, patch, [_biomass("a", 1.0), _biomass("a", 1.0)]).is_empty(), "duplicate plant IDs fail closed")
	if not failure.is_empty(): return failure
	failure = _assert(Density.step(full_competition, patch, [_biomass("a", 1.0), _biomass("missing", 1.0)]).is_empty(), "P3.1/P3.2 plant-set mismatch fails closed")
	if not failure.is_empty(): return failure
	var unexpected_plant := _biomass("a", 1.0)
	unexpected_plant["unexpected"] = true
	failure = _assert(Density.step(full_competition, patch, [unexpected_plant, _biomass("b", 1.0)]).is_empty(), "unexpected input plant field fails closed")
	if not failure.is_empty(): return failure
	var malformed_parent := full_competition.duplicate(true)
	malformed_parent["plant_order"] = ["a", "b"]
	failure = _assert(Density.step(malformed_parent, patch, [_biomass("a", 1.0), _biomass("b", 1.0)]).is_empty(), "malformed P3.1 container type fails closed")
	if not failure.is_empty(): return failure

	var tampered_feedback := under.duplicate(true)
	tampered_feedback["density_feedback"] = 0.123
	failure = _assert(not bool(Density.validate_result(tampered_feedback).get("success", false)), "tampered density feedback fails validation")
	if not failure.is_empty(): return failure
	var tampered_plant := under.duplicate(true)
	tampered_plant["plants"][0]["next_biomass_kg"] = 9.0
	failure = _assert(not bool(Density.validate_result(tampered_plant).get("success", false)), "tampered plant record fails validation")
	if not failure.is_empty(): return failure

	var aggregate := "\n".join(PackedStringArray([
		Density.PARENT_P3_1_CANDIDATE_AGGREGATE,
		String(under["result_hash"]),
		String(permuted["result_hash"]),
		String(at_capacity["result_hash"]),
		String(over["result_hash"]),
		String(limited["result_hash"]),
		String(empty_population["result_hash"]),
	])).sha256_text()
	print("ECO.P3.2 Density & Carrying Capacity: PASS (%d assertions)" % assertion_count)
	print("aggregate_hash=%s" % aggregate)
	print("under_capacity_hash=%s" % String(under["result_hash"]))
	print("over_capacity_hash=%s" % String(over["result_hash"]))
	print("resource_limited_hash=%s" % String(limited["result_hash"]))
	print("parent_p3_1=%s" % Density.PARENT_P3_1_CANDIDATE_AGGREGATE)
	quit(0)
	return ""

func _competitor(id: String, light_demand: float, water_demand: float, nutrient_demand: float, light_efficiency: float, water_efficiency: float, nutrient_efficiency: float) -> Dictionary:
	return {"id": id, "demand": _resources(light_demand, water_demand, nutrient_demand), "capture_efficiency": _resources(light_efficiency, water_efficiency, nutrient_efficiency)}

func _resources(light: float, water: float, nutrients: float) -> Dictionary:
	return {"light": light, "water": water, "nutrients": nutrients}

func _patch(area_m2: float, reference_capacity_kg_m2: float, minimum_capacity_fraction: float, max_recovery_fraction: float, max_decline_fraction: float) -> Dictionary:
	return {
		"area_m2": area_m2,
		"reference_capacity_kg_m2": reference_capacity_kg_m2,
		"minimum_capacity_fraction": minimum_capacity_fraction,
		"max_recovery_fraction": max_recovery_fraction,
		"max_decline_fraction": max_decline_fraction,
	}

func _biomass(id: String, biomass_kg: float) -> Dictionary:
	return {"id": id, "biomass_kg": biomass_kg}

func _next_biomass(result: Dictionary) -> Array:
	var values: Array = []
	for record_variant in Array(result.get("plants", [])):
		var record: Dictionary = record_variant
		values.append(_biomass(String(record["id"]), float(record["next_biomass_kg"])))
	return values

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
