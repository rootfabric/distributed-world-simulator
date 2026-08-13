extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")
const Disturbance = preload("res://scripts/research/ecology/plant_disturbance_succession_v1.gd")

var assertions := 0
var failed := false

func _init() -> void:
	var seasonal := _seasonal(0.0)
	_check(bool(Seasonal.validate_result(seasonal).get("success", false)), "P3.5 source validates")
	var before := seasonal.duplicate(true)
	var traits := _traits()
	var heat := Disturbance.apply(seasonal, _disturbance(0.8, 1.0, 0.0, 0.0), traits, 2.0)
	_check(bool(Disturbance.validate_result(heat).get("success", false)), "heat-like disturbance validates")
	_check(seasonal == before, "P3.6 does not mutate P3.5 source")
	_check(String(heat.get("seasonal_result_hash", "")) == String(seasonal.get("result_hash", "")), "exact P3.5 source hash embedded")
	_check(PackedStringArray(heat["patch_order"]) == PackedStringArray(["A","B","C"]), "patch order preserved")
	var a_heat := _patch(heat, "A")
	var alpha_heat := _plant(a_heat, "alpha")
	var beta_heat := _plant(a_heat, "beta")
	_check(float(alpha_heat["damage_fraction"]) < float(beta_heat["damage_fraction"]), "heat resistance lowers damage without ID winner table")
	_check(float(a_heat["post_disturbance_biomass_kg"]) < float(a_heat["biomass_before_kg"]), "disturbance removes biomass")
	_check(float(a_heat["final_biomass_kg"]) > float(a_heat["post_disturbance_biomass_kg"]), "recovery restores some biomass")
	_check(float(a_heat["final_biomass_kg"]) <= float(a_heat["biomass_before_kg"]) + 1e-9, "recovery does not create biomass above pre-disturbance reference")
	_check(float(beta_heat["recovered_biomass_kg"]) > float(alpha_heat["recovered_biomass_kg"]), "pioneer/recovery traits shift succession allocation")

	var flood := Disturbance.apply(seasonal, _disturbance(0.8, 0.0, 1.0, 0.0), traits, 0.0)
	var a_flood := _patch(flood, "A")
	_check(float(_plant(a_flood,"beta")["damage_fraction"]) < float(_plant(a_flood,"alpha")["damage_fraction"]), "flood resistance reverses relative damage")
	var drought := Disturbance.apply(seasonal, _disturbance(0.8, 0.0, 0.0, 1.0), traits, 0.0)
	var a_drought := _patch(drought, "A")
	_check(float(_plant(a_drought,"beta")["damage_fraction"]) < float(_plant(a_drought,"alpha")["damage_fraction"]), "drought resistance lowers matching disturbance damage")

	var no_recovery := Disturbance.apply(seasonal, _disturbance(0.8, 1.0, 0.0, 0.0), traits, 0.0)
	_near(float(_patch(no_recovery,"A")["final_biomass_kg"]), float(_patch(no_recovery,"A")["post_disturbance_biomass_kg"]), "zero recovery years gives post-disturbance state")
	var longer_recovery := Disturbance.apply(seasonal, _disturbance(0.8, 1.0, 0.0, 0.0), traits, 8.0)
	_check(float(_patch(longer_recovery,"A")["final_biomass_kg"]) > float(a_heat["final_biomass_kg"]), "longer recovery moves closer to pre-disturbance biomass")

	var zero := Disturbance.apply(seasonal, _disturbance(0.0, 1.0, 1.0, 1.0), traits, 5.0)
	_near(float(zero["summary"]["biomass_before_kg"]), float(zero["summary"]["final_biomass_kg"]), "zero severity preserves global biomass")
	_near(float(zero["summary"]["lost_biomass_kg"]), 0.0, "zero severity causes no loss")

	var dry_season := _seasonal(0.5)
	var recovery_wet := Disturbance.apply(seasonal, _disturbance(0.8,1.0,0.0,0.0), traits, 2.0)
	var recovery_dry := Disturbance.apply(dry_season, _disturbance(0.8,1.0,0.0,0.0), traits, 2.0)
	_check(float(_patch(recovery_wet,"A")["resource_support"]) > float(_patch(recovery_dry,"A")["resource_support"]), "seasonal resource support differs")
	_check(float(_patch(recovery_wet,"A")["recovery_pool_kg"]) > float(_patch(recovery_dry,"A")["recovery_pool_kg"]), "resource-poor season slows recovery")

	var permuted := [traits[1], traits[0]]
	var heat_permuted := Disturbance.apply(seasonal, _disturbance(0.8,1.0,0.0,0.0), permuted, 2.0)
	_check(String(heat_permuted.get("result_hash", "")) == String(heat.get("result_hash", "")), "trait input order is non-semantic")
	Disturbance.apply(seasonal, _disturbance(0.2,0.5,0.3,0.2), traits, 1.234)
	var heat_repeat := Disturbance.apply(seasonal, _disturbance(0.8,1.0,0.0,0.0), traits, 2.0)
	_check(String(heat_repeat.get("result_hash", "")) == String(heat.get("result_hash", "")), "direct evaluation has no cumulative succession drift")

	seed(777)
	var rng_before := [randi(), randi(), randi()]
	seed(777)
	Disturbance.apply(seasonal, _disturbance(0.8,1.0,0.0,0.0), traits, 2.0)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "P3.6 consumes no global RNG")

	var bad := _disturbance(1.1,1.0,0.0,0.0)
	_check(Disturbance.apply(seasonal,bad,traits,1.0).is_empty(), "severity above one fails closed")
	bad = _disturbance(0.5,1.0,0.0,0.0); bad["recovery_time_scale_years"] = 0.0
	_check(Disturbance.apply(seasonal,bad,traits,1.0).is_empty(), "zero recovery time scale fails closed")
	_check(Disturbance.apply(seasonal,_disturbance(0.5,1.0,0.0,0.0),traits,-1.0).is_empty(), "negative recovery years fail closed")
	var duplicate_traits := [traits[0], traits[0]]
	_check(Disturbance.apply(seasonal,_disturbance(0.5,1.0,0.0,0.0),duplicate_traits,1.0).is_empty(), "duplicate trait IDs fail closed")
	var missing_traits := [traits[0]]
	_check(Disturbance.apply(seasonal,_disturbance(0.5,1.0,0.0,0.0),missing_traits,1.0).is_empty(), "missing plant trait fails closed")
	var malformed_trait := traits.duplicate(true); malformed_trait[0]["extra"] = 1
	_check(Disturbance.apply(seasonal,_disturbance(0.5,1.0,0.0,0.0),malformed_trait,1.0).is_empty(), "unexpected trait field fails closed")
	var tampered_source := seasonal.duplicate(true); tampered_source["result_hash"] = "bad"
	_check(Disturbance.apply(tampered_source,_disturbance(0.5,1.0,0.0,0.0),traits,1.0).is_empty(), "tampered P3.5 source fails closed")
	var tampered := heat.duplicate(true); tampered["patches"][0]["final_biomass_kg"] += 1.0
	_check(not bool(Disturbance.validate_result(tampered).get("success", false)), "tampered patch rejected")
	tampered = heat.duplicate(true); tampered["summary"]["final_biomass_kg"] += 1.0
	_check(not bool(Disturbance.validate_result(tampered).get("success", false)), "tampered summary rejected")
	tampered = heat.duplicate(true); tampered["traits"][0]["heat_resistance"] = 0.0
	_check(not bool(Disturbance.validate_result(tampered).get("success", false)), "tampered trait/reconstruction rejected")

	var empty := Disturbance.apply(_empty_seasonal(), _disturbance(0.8,1.0,1.0,1.0), [], 2.0)
	_check(bool(Disturbance.validate_result(empty).get("success", false)), "empty seasonal system remains valid")
	_check(int(empty["summary"]["patch_count"]) == 0, "empty disturbance summary")

	var flood_hash := String(flood["result_hash"])
	var drought_hash := String(drought["result_hash"])
	var aggregate := (String(heat["result_hash"]) + "\n" + flood_hash + "\n" + drought_hash + "\n" + String(zero["result_hash"])).sha256_text()
	if failed:
		quit(1)
		return
	print("ECO.P3.6 Disturbance & Succession: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate)
	print("heat_hash=" + String(heat["result_hash"]))
	print("flood_hash=" + flood_hash)
	print("drought_hash=" + drought_hash)
	print("parent_p3_5=" + Disturbance.PARENT_P3_5_CANDIDATE_AGGREGATE)
	print("source_p3_5=" + String(seasonal["result_hash"]))
	quit(0)

func _traits() -> Array:
	return [
		{"id":"alpha","heat_resistance":0.9,"flood_resistance":0.2,"drought_resistance":0.2,"recovery_rate":0.4,"pioneer_capacity":0.2},
		{"id":"beta","heat_resistance":0.2,"flood_resistance":0.8,"drought_resistance":0.8,"recovery_rate":0.9,"pioneer_capacity":0.9},
	]

func _disturbance(severity: float, heat: float, flood: float, drought: float) -> Dictionary:
	return {"severity":severity,"heat_pressure":heat,"flood_pressure":flood,"drought_pressure":drought,"recovery_time_scale_years":2.0}

func _seasonal(time: float) -> Dictionary:
	return Seasonal.evaluate(_environment(), time, _season_config())

func _empty_seasonal() -> Dictionary:
	var spatial := Dispersal.disperse([], [], {"dispersal_fraction":0.2})
	var environment := EnvGradient.apply(spatial, [], _environment_config())
	return Seasonal.evaluate(environment, 0.0, _season_config())

func _season_config() -> Dictionary:
	return {"cycle":{"period_years":1.0,"epoch_year":0.0,"phase_x_slope":0.0,"phase_y_slope":0.125,"phase_altitude_slope":0.0},"temperature_c":{"amplitude":10.0,"phase_offset":0.0},"moisture":{"amplitude":0.2,"phase_offset":0.25},"light":{"amplitude":0.1,"phase_offset":0.5},"nutrients":{"amplitude":0.15,"phase_offset":0.75}}

func _environment() -> Dictionary:
	return EnvGradient.apply(_spatial(0.2), [{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}], _environment_config())

func _environment_config() -> Dictionary:
	return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":_channel(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":_channel(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":_channel(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":_channel(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}

func _channel(base: float, xs: float, ys: float, zs: float, mn: float, mx: float) -> Dictionary:
	return {"base":base,"x_slope":xs,"y_slope":ys,"altitude_slope":zs,"min":mn,"max":mx}

func _spatial(fraction: float) -> Dictionary:
	var a := _density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0)
	var b := _density([{"id":"beta","biomass_kg":2.0}],2.0)
	var c := _density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":c,"boundary_export_fraction":0.0},{"id":"A","density_result":a,"boundary_export_fraction":0.25},{"id":"B","density_result":b,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":fraction})

func _density(plants: Array, capacity: float) -> Dictionary:
	var cp := []; for p in plants: cp.append({"id":String(p["id"]),"demand":_resources(1.0),"capture_efficiency":_resources(1.0)})
	return Density.step(Competition.compete(_resources(100.0),cp),{"area_m2":capacity,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6},plants)

func _resources(v: float) -> Dictionary: return {"light":v,"water":v,"nutrients":v}

func _patch(result: Dictionary, patch_id: String) -> Dictionary:
	for value in result.get("patches", []):
		if typeof(value) == TYPE_DICTIONARY and String(value.get("id", "")) == patch_id: return value
	return {}

func _plant(patch: Dictionary, plant_id: String) -> Dictionary:
	for value in patch.get("plants", []):
		if typeof(value) == TYPE_DICTIONARY and String(value.get("id", "")) == plant_id: return value
	return {}

func _check(condition: bool, message: String) -> void:
	if not condition: failed = true; push_error("FAIL: " + message); return
	assertions += 1
func _near(actual: float, expected: float, message: String) -> void: _check(absf(actual-expected) <= 1e-9, message + " actual=" + str(actual) + " expected=" + str(expected))
