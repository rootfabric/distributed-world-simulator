extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")

const EXPECTED_P3_4_SOURCE_HASH := "2651bb4da195af4c1d2ba7f6b09ef9bdc9e459f9206c32ef1e9eb0dbddd6b293"
var assertions := 0
var failed := false

func _init() -> void:
	var environment := _environment()
	_check(bool(EnvGradient.validate_result(environment).get("success", false)), "P3.4 source validates")
	_check(String(environment.get("result_hash", "")) == EXPECTED_P3_4_SOURCE_HASH, "exact P3.4 source fixture pinned")
	var environment_before := environment.duplicate(true)
	var config := _season_config()

	var t0 := Seasonal.evaluate(environment, 0.0, config)
	_check(bool(Seasonal.validate_result(t0).get("success", false)), "P3.5 t0 validates")
	_check(String(t0.get("parent_p3_4_candidate_aggregate", "")) == Seasonal.PARENT_P3_4_CANDIDATE_AGGREGATE, "P3.4 aggregate parent pinned")
	_check(String(t0.get("environment_result_hash", "")) == EXPECTED_P3_4_SOURCE_HASH, "P3.4 source result hash pinned")
	_check(environment == environment_before, "P3.5 does not mutate P3.4 source")
	_check(PackedStringArray(t0["patch_order"]) == PackedStringArray(["A", "B", "C"]), "canonical patch order preserved")
	_near(float(t0["global_phase01"]), 0.0, "t0 global phase")
	_check(int(t0["cycle_index"]) == 0, "t0 cycle index")

	var a0 := _patch(t0, "A")
	var b0 := _patch(t0, "B")
	var c0 := _patch(t0, "C")
	_near(float(a0["local_phase01"]), 0.0, "A phase at t0")
	_near(float(c0["local_phase01"]), 0.25, "C spatial phase shift")
	_near(float(a0["temperature_c"]), 10.0, "A t0 temperature seasonal minimum")
	_near(float(a0["temperature_delta_c"]), -10.0, "A t0 temperature delta")
	_near(float(a0["moisture"]), 0.8, "A t0 moisture phase offset neutral")
	_near(float(a0["light"]), 0.5, "A t0 light opposite phase maximum")
	_near(float(a0["nutrients"]), 0.9, "A t0 nutrient quarter phase neutral")
	_near(float(c0["temperature_c"]), 15.0, "C spatially shifted temperature neutral")
	_near(float(c0["moisture"]), 0.65, "C spatially shifted moisture maximum with clamp-safe value")
	_near(float(c0["light"]), 0.85, "C spatially shifted light neutral")
	_near(float(c0["nutrients"]), 0.4, "C spatially shifted nutrients minimum")
	_near(float(a0["resource_availability"]["light"]), float(a0["light"]), "seasonal light resource bridge")
	_near(float(a0["resource_availability"]["water"]), float(a0["moisture"]), "seasonal moisture to water bridge")
	var base_supply := _resources(2.0)
	var supply_t0 := Seasonal.resource_supply_for_patch(base_supply, a0)
	_near(float(supply_t0["light"]), 1.0, "seasonal supply bridge scales light")
	_near(float(supply_t0["water"]), 1.6, "seasonal supply bridge scales water")
	_near(float(supply_t0["nutrients"]), 1.8, "seasonal supply bridge scales nutrients")

	var t_quarter := Seasonal.evaluate(environment, 0.25, config)
	_check(bool(Seasonal.validate_result(t_quarter).get("success", false)), "P3.5 quarter validates")
	var aq := _patch(t_quarter, "A")
	_near(float(aq["temperature_c"]), 20.0, "quarter temperature returns baseline")
	_near(float(aq["moisture"]), 1.0, "quarter moisture maximum clamped")
	_near(float(aq["light"]), 0.4, "quarter light baseline")
	_near(float(aq["nutrients"]), 0.75, "quarter nutrients minimum")

	var t_half := Seasonal.evaluate(environment, 0.5, config)
	_check(bool(Seasonal.validate_result(t_half).get("success", false)), "P3.5 half validates")
	var ah := _patch(t_half, "A")
	_near(float(ah["temperature_c"]), 30.0, "half temperature maximum")
	_near(float(ah["moisture"]), 0.8, "half moisture neutral")
	_near(float(ah["light"]), 0.3, "half light minimum")
	_near(float(ah["nutrients"]), 0.9, "half nutrients neutral")
	var supply_half := Seasonal.resource_supply_for_patch(base_supply, ah)
	_near(float(supply_half["light"]), 0.6, "seasonal supply changes with phase")
	var response_plant := [{"id":"seasonal_probe","demand":_resources(1.0),"capture_efficiency":_resources(1.0)}]
	var competition_t0 := Competition.compete(supply_t0, response_plant)
	var competition_half := Competition.compete(supply_half, response_plant)
	_near(float(competition_t0["plants"][0]["growth_factor"]), 1.0, "resource-mediated response full at t0")
	_near(float(competition_half["plants"][0]["growth_factor"]), 0.6, "seasonal light limitation propagates into P3.1 response")

	var t1 := Seasonal.evaluate(environment, 1.0, config)
	_check(bool(Seasonal.validate_result(t1).get("success", false)), "P3.5 next cycle validates")
	_near(float(t1["global_phase01"]), 0.0, "period wraps phase")
	_check(int(t1["cycle_index"]) == 1, "period advances cycle index")
	_check(_patch_hashes(t0) == _patch_hashes(t1), "periodic environmental patch state repeats exactly")
	_check(String(t0["result_hash"]) != String(t1["result_hash"]), "absolute time remains part of canonical result identity")

	var negative := Seasonal.evaluate(environment, -0.25, config)
	_check(bool(Seasonal.validate_result(negative).get("success", false)), "negative time valid")
	_near(float(negative["global_phase01"]), 0.75, "negative time wraps phase")
	_check(int(negative["cycle_index"]) == -1, "negative time cycle index")

	Seasonal.evaluate(environment, 0.123456, config)
	var half_repeat := Seasonal.evaluate(environment, 0.5, config)
	_check(String(half_repeat.get("result_hash", "")) == String(t_half.get("result_hash", "")), "direct evaluation has no cumulative seasonal drift")
	var offset_equivalent := config.duplicate(true)
	offset_equivalent["light"]["phase_offset"] = 1.5
	var offset_result := Seasonal.evaluate(environment, 0.0, offset_equivalent)
	_check(String(offset_result.get("result_hash", "")) == String(t0.get("result_hash", "")), "phase offsets canonicalize modulo one cycle")

	var ab0 := _edge(t0, "A", "B")
	var ab_half := _edge(t_half, "A", "B")
	_check(not ab0.is_empty() and not ab_half.is_empty(), "seasonal edge diagnostics present")
	_near(float(ab0["temperature_delta_c"]), -3.0, "same-phase A to B temperature delta retained at t0")
	_near(float(ab_half["temperature_delta_c"]), -3.0, "same-phase A to B temperature delta retained at half")
	var ac0 := _edge(t0, "A", "C")
	_near(float(ac0["temperature_delta_c"]), 5.0, "spatial phase changes A to C seasonal temperature gradient")

	var clamp_config := config.duplicate(true)
	clamp_config["moisture"]["amplitude"] = 1.0
	clamp_config["light"]["amplitude"] = 1.0
	var clamped := Seasonal.evaluate(environment, 0.25, clamp_config)
	var aclamp := _patch(clamped, "A")
	_near(float(aclamp["moisture"]), 1.0, "normalized upper clamp")
	_near(float(aclamp["light"]), 0.4, "light phase at quarter remains baseline despite large amplitude")
	var clamp_half := Seasonal.evaluate(environment, 0.5, clamp_config)
	_near(float(_patch(clamp_half, "A")["light"]), 0.0, "normalized lower clamp")

	var empty_environment := _empty_environment()
	var empty := Seasonal.evaluate(empty_environment, 0.25, config)
	_check(bool(Seasonal.validate_result(empty).get("success", false)), "empty P3.4 system remains valid")
	_check(int(empty["summary"]["patch_count"]) == 0, "empty seasonal summary")

	var bad_config := config.duplicate(true)
	bad_config["cycle"]["period_years"] = 0.0
	_check(Seasonal.evaluate(environment, 0.0, bad_config).is_empty(), "zero period fails closed")
	bad_config = config.duplicate(true)
	bad_config["moisture"]["amplitude"] = -0.1
	_check(Seasonal.evaluate(environment, 0.0, bad_config).is_empty(), "negative amplitude fails closed")
	bad_config = config.duplicate(true)
	bad_config["light"]["amplitude"] = 1.1
	_check(Seasonal.evaluate(environment, 0.0, bad_config).is_empty(), "normalized amplitude above one fails closed")
	bad_config = config.duplicate(true)
	bad_config["cycle"]["phase_y_slope"] = INF
	_check(Seasonal.evaluate(environment, 0.0, bad_config).is_empty(), "non-finite cycle coefficient fails closed")
	bad_config = config.duplicate(true)
	bad_config["extra"] = 1
	_check(Seasonal.evaluate(environment, 0.0, bad_config).is_empty(), "unexpected config field fails closed")
	_check(Seasonal.evaluate(environment, INF, config).is_empty(), "non-finite time fails closed")
	_check(Seasonal.evaluate(environment, 10000000000000000.0, config).is_empty(), "cycle index beyond exact integer range fails closed")
	var bad_supply := base_supply.duplicate(true)
	bad_supply["light"] = -1.0
	_check(Seasonal.resource_supply_for_patch(bad_supply, a0).is_empty(), "negative base supply bridge fails closed")
	var bad_patch_for_supply := a0.duplicate(true)
	bad_patch_for_supply["record_hash"] = "bad"
	_check(Seasonal.resource_supply_for_patch(base_supply, bad_patch_for_supply).is_empty(), "tampered seasonal patch supply bridge fails closed")

	var bad_environment := environment.duplicate(true)
	bad_environment["result_hash"] = "bad"
	_check(Seasonal.evaluate(bad_environment, 0.0, config).is_empty(), "tampered P3.4 parent fails closed")
	var tampered := t0.duplicate(true)
	tampered["patches"][0]["temperature_c"] += 1.0
	_check(not bool(Seasonal.validate_result(tampered).get("success", false)), "tampered seasonal patch rejected")
	tampered = t0.duplicate(true)
	tampered["edge_seasonal_gradients"][0]["temperature_delta_c"] += 1.0
	_check(not bool(Seasonal.validate_result(tampered).get("success", false)), "tampered seasonal edge rejected")
	tampered = t0.duplicate(true)
	tampered["summary"]["light_max"] = 0.0
	_check(not bool(Seasonal.validate_result(tampered).get("success", false)), "tampered seasonal summary rejected")
	tampered = t0.duplicate(true)
	tampered["global_phase01"] = 0.5
	_check(not bool(Seasonal.validate_result(tampered).get("success", false)), "tampered global phase rejected")
	tampered = t0.duplicate(true)
	tampered["cycle_index"] = 99
	_check(not bool(Seasonal.validate_result(tampered).get("success", false)), "tampered cycle index rejected")
	tampered = t0.duplicate(true)
	tampered["parent_p3_4_candidate_aggregate"] = "bad"
	_check(not bool(Seasonal.validate_result(tampered).get("success", false)), "tampered parent aggregate rejected")

	seed(1357911)
	var random_before := randi()
	Seasonal.evaluate(environment, 0.375, config)
	var random_after := randi()
	seed(1357911)
	_check(random_before == randi() and random_after == randi(), "P3.5 consumes no global RNG")

	var aggregate_hash := (String(t0["result_hash"]) + "|" + String(t_quarter["result_hash"]) + "|" + String(t_half["result_hash"]) + "|" + String(empty["result_hash"]) + "|" + Seasonal.PARENT_P3_4_CANDIDATE_AGGREGATE).sha256_text()
	if failed:
		print("ECO.P3.5 Seasonal World: FAIL")
		quit(1)
		return
	print("ECO.P3.5 Seasonal World: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("phase0_hash=" + String(t0["result_hash"]))
	print("quarter_hash=" + String(t_quarter["result_hash"]))
	print("half_hash=" + String(t_half["result_hash"]))
	print("empty_hash=" + String(empty["result_hash"]))
	print("parent_p3_4=" + Seasonal.PARENT_P3_4_CANDIDATE_AGGREGATE)
	print("source_p3_4=" + EXPECTED_P3_4_SOURCE_HASH)
	quit(0)

func _season_config() -> Dictionary:
	return {
		"cycle": {"period_years": 1.0, "epoch_year": 0.0, "phase_x_slope": 0.0, "phase_y_slope": 0.125, "phase_altitude_slope": 0.0},
		"temperature_c": {"amplitude": 10.0, "phase_offset": 0.0},
		"moisture": {"amplitude": 0.2, "phase_offset": 0.25},
		"light": {"amplitude": 0.1, "phase_offset": 0.5},
		"nutrients": {"amplitude": 0.15, "phase_offset": 0.75},
	}

func _environment() -> Dictionary:
	return EnvGradient.apply(_spatial(0.2), [{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}], _environment_config())

func _empty_environment() -> Dictionary:
	var empty_spatial := Dispersal.disperse([], [], {"dispersal_fraction": 0.2})
	return EnvGradient.apply(empty_spatial, [], _environment_config())

func _environment_config() -> Dictionary:
	return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":_channel(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":_channel(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":_channel(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":_channel(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}

func _channel(base: float, x_slope: float, y_slope: float, altitude_slope: float, minimum: float, maximum: float) -> Dictionary:
	return {"base":base,"x_slope":x_slope,"y_slope":y_slope,"altitude_slope":altitude_slope,"min":minimum,"max":maximum}

func _spatial(fraction: float) -> Dictionary:
	var patch_a := _density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0)
	var patch_b := _density([{"id":"beta","biomass_kg":2.0}],2.0)
	var patch_c := _density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":patch_c,"boundary_export_fraction":0.0},{"id":"A","density_result":patch_a,"boundary_export_fraction":0.25},{"id":"B","density_result":patch_b,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":fraction})

func _density(plants: Array, capacity: float) -> Dictionary:
	var competition_plants := []
	for plant in plants:
		competition_plants.append({"id":String(plant["id"]),"demand":_resources(1.0),"capture_efficiency":_resources(1.0)})
	var competition := Competition.compete(_resources(100.0), competition_plants)
	return Density.step(competition,{"area_m2":capacity,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6},plants)

func _resources(value: float) -> Dictionary:
	return {"light":value,"water":value,"nutrients":value}

func _patch(result: Dictionary, patch_id: String) -> Dictionary:
	for patch_value in result.get("patches", []):
		if typeof(patch_value) == TYPE_DICTIONARY and String(patch_value.get("id", "")) == patch_id:
			return patch_value
	return {}

func _edge(result: Dictionary, from_id: String, to_id: String) -> Dictionary:
	for edge_value in result.get("edge_seasonal_gradients", []):
		if typeof(edge_value) == TYPE_DICTIONARY and String(edge_value.get("from", "")) == from_id and String(edge_value.get("to", "")) == to_id:
			return edge_value
	return {}

func _patch_hashes(result: Dictionary) -> PackedStringArray:
	var hashes := PackedStringArray()
	for patch_value in result.get("patches", []):
		hashes.append(String(patch_value.get("record_hash", "")))
	return hashes

func _check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error("FAIL: " + message)
		return
	assertions += 1

func _near(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= 0.000000001, message + " actual=" + str(actual) + " expected=" + str(expected))
