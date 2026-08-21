extends SceneTree

const Competition = preload("res://scripts/research/ecology/plant_resource_competition_v1.gd")
const Density = preload("res://scripts/research/ecology/plant_density_carrying_capacity_v1.gd")
const Dispersal = preload("res://scripts/research/ecology/plant_spatial_dispersal_v1.gd")
const EnvGradient = preload("res://scripts/research/ecology/plant_environmental_gradient_v1.gd")
const Seasonal = preload("res://scripts/research/ecology/plant_seasonal_world_v1.gd")
const Disturbance = preload("res://scripts/research/ecology/plant_disturbance_succession_v1.gd")
const Coexistence = preload("res://scripts/research/ecology/plant_multi_niche_coexistence_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_ecosystem_persistence_v1.gd")
const RegionState = preload("res://scripts/ecology/production/ecology_region_state_v1.gd")

const EXPECTED_P3_8_INITIAL_STATE := "6070494e77828f4e25a00eed9695de9e87fdf94e472f5018d660a7c20b15d7fb"
const EXPECTED_P3_8_CUT_STATE := "07f6ecaa00d508b87042948a23cf4e0eaa600d79a8229e16b859c461dada509d"
const EXPECTED_REGION_ZERO_HASH := "2d7fc8f595dbe5e55e29a0dca1256a9f4ccebe4176ec8d53c9bf66671ac3b7b4"
const EXPECTED_REGION_CUT_HASH := "fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c"
const EXPECTED_OTHER_REGION_HASH := "d4f0cd4890678747ef2f2399bcfd500282a3840af43ea37913ee78c39b17c3e5"
const EXPECTED_AGGREGATE := "1acb55e1e825872943eac438303f03b979f33778a87c227d9819f74bff44b717"

var assertions := 0
var failed := false

func _init() -> void:
	var initial_result := _initial_p3_7_result()
	_check(bool(Coexistence.validate_result(initial_result).get("success", false)), "P3.7 fixture validates")
	var p3_initial := Persistence.initialize(initial_result)
	_check(bool(Persistence.validate_state(p3_initial).get("success", false)), "accepted P3.8 parent state validates")
	_check(String(p3_initial.get("state_hash", "")) == EXPECTED_P3_8_INITIAL_STATE, "frozen P3.8 initial state identity reproduced")
	var p3_source_before := p3_initial.duplicate(true)

	var region := RegionState.create_region_state("planet-01:region_0007", 42.5, p3_initial)
	_check(bool(RegionState.validate_region_state(region).get("success", false)), "P4.1 region state validates")
	_check(p3_initial == p3_source_before, "P4.1 create does not mutate P3 source")
	_check(String(region.get("schema", "")) == RegionState.SCHEMA, "P4.1 schema exact")
	_check(String(region.get("version", "")) == RegionState.VERSION, "P4.1 version exact")
	_check(String(region.get("parent_p3_8_accepted_aggregate", "")) == RegionState.PARENT_P3_8_ACCEPTED_AGGREGATE, "accepted P3.8 aggregate pinned")
	_check(String(region.get("region_id", "")) == "planet-01:region_0007", "region identity retained")
	_check(int(region.get("ecology_generation", -1)) == 0, "generation mirrors P3 state")
	_check(typeof(region.get("last_simulated_world_time")) == TYPE_FLOAT and is_equal_approx(float(region.get("last_simulated_world_time")), 42.5), "world time stored as canonical finite float")
	_check(String(region.get("p3_state_hash", "")) == EXPECTED_P3_8_INITIAL_STATE, "P3 state hash pinned")
	_check(String(region.get("region_state_hash", "")) == EXPECTED_REGION_ZERO_HASH, "frozen region-zero hash exact")

	var same_from_int_time := RegionState.create_region_state("planet-01:region_0007", 42, p3_initial)
	var same_from_float_time := RegionState.create_region_state("planet-01:region_0007", 42.0, p3_initial)
	_check(String(same_from_int_time.get("region_state_hash", "")) == String(same_from_float_time.get("region_state_hash", "")), "integer and float world time normalize canonically")

	var wrapped_before := region.duplicate(true)
	p3_initial["state_hash"] = "0".repeat(64)
	_check(region == wrapped_before, "caller P3 mutation cannot alias stored region state")

	var extracted := RegionState.extract_p3_state(region)
	_check(extracted == p3_source_before, "P3 extraction returns exact semantic state")
	extracted["state_hash"] = "0".repeat(64)
	_check(bool(RegionState.validate_region_state(region).get("success", false)), "mutating extracted P3 copy cannot corrupt region state")

	var reordered := {}
	for key in ["region_state_hash","p3_state_hash","p3_state","parent_p3_8_accepted_aggregate","last_simulated_world_time","ecology_generation","region_id","version","schema"]:
		reordered[key] = region[key]
	_check(bool(RegionState.validate_region_state(reordered).get("success", false)), "top-level dictionary insertion order does not alter validation")
	_check(String(RegionState.compute_region_state_hash(reordered)) == EXPECTED_REGION_ZERO_HASH, "region hash independent of top-level insertion order")

	var other_region := RegionState.create_region_state("planet-01:region_0008", 42.5, p3_source_before)
	_check(String(other_region.get("p3_state_hash", "")) == String(region.get("p3_state_hash", "")), "same P3 state may be wrapped by a different region identity")
	_check(String(other_region.get("region_state_hash", "")) == EXPECTED_OTHER_REGION_HASH, "other region identity hash exact")
	_check(String(other_region.get("region_state_hash", "")) != String(region.get("region_state_hash", "")), "region identity participates in region hash")

	var later_time := RegionState.create_region_state("planet-01:region_0007", 43.0, p3_source_before)
	_check(String(later_time.get("region_state_hash", "")) != String(region.get("region_state_hash", "")), "world time participates in region hash")
	_check(String(later_time.get("p3_state_hash", "")) == String(region.get("p3_state_hash", "")), "world time does not rewrite embedded P3 identity")

	var p3_cut := Persistence.advance(p3_source_before, 5)
	_check(bool(Persistence.validate_state(p3_cut).get("success", false)), "P3.8 generation-five fixture validates")
	_check(String(p3_cut.get("state_hash", "")) == EXPECTED_P3_8_CUT_STATE, "frozen P3.8 generation-five state identity reproduced")
	var cut_region := RegionState.create_region_state("planet-01:region_0007", 47.5, p3_cut)
	_check(bool(RegionState.validate_region_state(cut_region).get("success", false)), "generation-five region state validates")
	_check(int(cut_region.get("ecology_generation", -1)) == 5, "region generation mirrors P3 generation-five state")
	_check(String(cut_region.get("p3_state_hash", "")) == EXPECTED_P3_8_CUT_STATE, "generation-five P3 state hash retained")
	_check(String(cut_region.get("region_state_hash", "")) == EXPECTED_REGION_CUT_HASH, "frozen generation-five region hash exact")

	_check(RegionState.create_region_state("", 0.0, p3_source_before).is_empty(), "empty region id rejected")
	_check(RegionState.create_region_state(" region", 0.0, p3_source_before).is_empty(), "leading whitespace region id rejected")
	_check(RegionState.create_region_state("region/7", 0.0, p3_source_before).is_empty(), "path-like region id rejected")
	_check(RegionState.create_region_state("регион", 0.0, p3_source_before).is_empty(), "non-canonical region id rejected")
	_check(RegionState.create_region_state(7, 0.0, p3_source_before).is_empty(), "non-string region id rejected")
	_check(RegionState.create_region_state("region-7", -1.0, p3_source_before).is_empty(), "negative world time rejected")
	_check(RegionState.create_region_state("region-7", NAN, p3_source_before).is_empty(), "NaN world time rejected")
	_check(RegionState.create_region_state("region-7", INF, p3_source_before).is_empty(), "infinite world time rejected")
	_check(RegionState.create_region_state("region-7", "1.0", p3_source_before).is_empty(), "non-numeric world time rejected")
	_check(RegionState.create_region_state("region-7", 1.0, []).is_empty(), "non-dictionary P3 state rejected")

	var tampered := region.duplicate(true)
	tampered["ecology_generation"] = 1
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "generation/P3 mismatch rejected")
	tampered = region.duplicate(true)
	tampered["ecology_generation"] = 0.0
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "non-integer generation rejected")
	tampered = region.duplicate(true)
	tampered["last_simulated_world_time"] = 42
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "stored world time requires canonical float type")
	tampered = region.duplicate(true)
	tampered["parent_p3_8_accepted_aggregate"] = "0".repeat(64)
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "wrong accepted P3.8 aggregate rejected")
	tampered = region.duplicate(true)
	tampered["p3_state_hash"] = "0".repeat(64)
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "tampered P3 state hash rejected")
	tampered = region.duplicate(true)
	tampered["p3_state"]["state_hash"] = "0".repeat(64)
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "tampered embedded P3 state rejected")
	tampered = region.duplicate(true)
	tampered["region_state_hash"] = "0".repeat(64)
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "tampered region state hash rejected")
	tampered = region.duplicate(true)
	tampered["unexpected"] = true
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "extra state field rejected")
	tampered = region.duplicate(true)
	tampered.erase("region_id")
	_check(not bool(RegionState.validate_region_state(tampered).get("success", false)), "missing state field rejected")
	_check(RegionState.extract_p3_state(tampered).is_empty(), "invalid region state cannot expose P3 state")

	seed(97531)
	var rng_before := [randi(), randi(), randi()]
	seed(97531)
	var rng_region := RegionState.create_region_state("rng-region", 100.0, p3_cut)
	RegionState.validate_region_state(rng_region)
	RegionState.extract_p3_state(rng_region)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "P4.1 region adapter consumes no global RNG")

	var aggregate_hash := (String(region.get("region_state_hash", "")) + "\n" + String(cut_region.get("region_state_hash", "")) + "\n" + String(other_region.get("region_state_hash", "")) + "\n" + RegionState.PARENT_P3_8_ACCEPTED_AGGREGATE).sha256_text()
	_check(aggregate_hash == EXPECTED_AGGREGATE, "P4.1 frozen aggregate exact")

	if failed:
		quit(1)
		return
	print("ECO.P4.1 Production Ecology Region Contract: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("region_zero_hash=" + String(region.get("region_state_hash", "")))
	print("region_cut_hash=" + String(cut_region.get("region_state_hash", "")))
	print("other_region_hash=" + String(other_region.get("region_state_hash", "")))
	print("parent_p3_8=" + RegionState.PARENT_P3_8_ACCEPTED_AGGREGATE)
	quit(0)

func _initial_p3_7_result() -> Dictionary:
	var parent := _disturbance_result()
	var niches := _niches()
	var community := Coexistence.community_from_parent(parent, niches)
	var skewed := _skew_community(community, 0.05, 0.95)
	return Coexistence.step(parent, skewed, niches, {"stabilization_fraction": 0.5})

func _niches() -> Array:
	return [{"id":"alpha","temperature_optimum_c":10.0,"temperature_breadth_c":12.0,"moisture_optimum":0.8,"moisture_breadth":0.5,"light_optimum":0.5,"light_breadth":0.5,"nutrients_optimum":0.9,"nutrients_breadth":0.7},{"id":"beta","temperature_optimum_c":15.0,"temperature_breadth_c":12.0,"moisture_optimum":0.65,"moisture_breadth":0.5,"light_optimum":0.85,"light_breadth":0.5,"nutrients_optimum":0.4,"nutrients_breadth":0.7}]

func _skew_community(base: Array, alpha_share: float, beta_share: float) -> Array:
	var out := []
	for patch_value in base:
		var patch: Dictionary = patch_value
		var total := 0.0
		for plant_value in patch["plants"]:
			total += float(plant_value["biomass_kg"])
		out.append({"id":String(patch["id"]),"plant_order":PackedStringArray(["alpha","beta"]),"plants":[{"id":"alpha","biomass_kg":total*alpha_share},{"id":"beta","biomass_kg":total*beta_share}]})
	return out

func _disturbance_result() -> Dictionary:
	return Disturbance.apply(_seasonal(0.0), _disturbance(0.8, 1.0, 0.0, 0.0), _traits(), 2.0)

func _traits() -> Array:
	return [{"id":"alpha","heat_resistance":0.9,"flood_resistance":0.2,"drought_resistance":0.2,"recovery_rate":0.4,"pioneer_capacity":0.2},{"id":"beta","heat_resistance":0.2,"flood_resistance":0.8,"drought_resistance":0.8,"recovery_rate":0.9,"pioneer_capacity":0.9}]

func _disturbance(s: float, h: float, f: float, d: float) -> Dictionary:
	return {"severity":s,"heat_pressure":h,"flood_pressure":f,"drought_pressure":d,"recovery_time_scale_years":2.0}

func _seasonal(t: float) -> Dictionary:
	return Seasonal.evaluate(_environment(), t, _season_config())

func _season_config() -> Dictionary:
	return {"cycle":{"period_years":1.0,"epoch_year":0.0,"phase_x_slope":0.0,"phase_y_slope":0.125,"phase_altitude_slope":0.0},"temperature_c":{"amplitude":10.0,"phase_offset":0.0},"moisture":{"amplitude":0.2,"phase_offset":0.25},"light":{"amplitude":0.1,"phase_offset":0.5},"nutrients":{"amplitude":0.15,"phase_offset":0.75}}

func _environment() -> Dictionary:
	return EnvGradient.apply(_spatial(0.2), [{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}], _environment_config())

func _environment_config() -> Dictionary:
	return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":_channel(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":_channel(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":_channel(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":_channel(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}

func _channel(b: float, x: float, y: float, z: float, mn: float, mx: float) -> Dictionary:
	return {"base":b,"x_slope":x,"y_slope":y,"altitude_slope":z,"min":mn,"max":mx}

func _spatial(fraction: float) -> Dictionary:
	var a := _density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0)
	var b := _density([{"id":"beta","biomass_kg":2.0}],2.0)
	var c := _density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":c,"boundary_export_fraction":0.0},{"id":"A","density_result":a,"boundary_export_fraction":0.25},{"id":"B","density_result":b,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":fraction})

func _density(plants: Array, capacity: float) -> Dictionary:
	var competitors := []
	for plant in plants:
		competitors.append({"id":String(plant["id"]),"demand":_resources(1.0),"capture_efficiency":_resources(1.0)})
	return Density.step(Competition.compete(_resources(100.0), competitors), {"area_m2":capacity,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6}, plants)

func _resources(value: float) -> Dictionary:
	return {"light":value,"water":value,"nutrients":value}

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		return
	failed = true
	push_error("ECO.P4.1 FAIL: " + message)
