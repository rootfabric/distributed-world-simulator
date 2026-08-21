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
const EcologyClock = preload("res://scripts/ecology/production/ecology_clock_v1.gd")

const EXPECTED_P3_8_INITIAL_STATE := "6070494e77828f4e25a00eed9695de9e87fdf94e472f5018d660a7c20b15d7fb"
const EXPECTED_CLOCK_HASH := "f62815a7be67d7db2aeaa809915924ba2eb0437521ef6c908239642ba6909899"
const EXPECTED_GENERATION_5_REGION_HASH := "fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c"
const EXPECTED_DECIMAL_GENERATION_100_REGION_HASH := "6b291c025ec6f2eb5904741b1c09959942f1bd10ef10a5e5b14886bf63a62692"
const EXPECTED_AGGREGATE := "607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e"

var assertions := 0
var failed := false

func _init() -> void:
	var p3_initial := Persistence.initialize(_initial_p3_7_result())
	_check(bool(Persistence.validate_state(p3_initial).get("success", false)), "P3.8 initial fixture validates")
	_check(String(p3_initial.get("state_hash", "")) == EXPECTED_P3_8_INITIAL_STATE, "P3.8 initial identity exact")
	var region := RegionState.create_region_state("planet-01:region_0007", 42.5, p3_initial)
	_check(bool(RegionState.validate_region_state(region).get("success", false)), "accepted P4.1 region fixture validates")
	var region_before := region.duplicate(true)

	var clock := EcologyClock.create_clock(region, 1.0)
	_check(bool(EcologyClock.validate_clock(clock).get("success", false)), "P4.2 clock validates")
	_check(region == region_before, "clock creation does not mutate region")
	_check(String(clock.get("parent_p4_1_accepted_aggregate", "")) == EcologyClock.PARENT_P4_1_ACCEPTED_AGGREGATE, "accepted P4.1 aggregate pinned")
	_check(int(clock.get("origin_generation", -1)) == 0, "clock origin generation derives from region")
	_check(is_equal_approx(float(clock.get("origin_world_time", NAN)), 42.5), "clock origin world time derives from region")
	_check(is_equal_approx(float(clock.get("step_interval_world_time", NAN)), 1.0), "clock interval canonical float")
	_check(bool(EcologyClock.validate_bound_region(region, clock).get("success", false)), "origin region bound to clock")
	_check(String(clock.get("clock_hash", "")) == EXPECTED_CLOCK_HASH, "frozen clock hash exact")
	var clock_from_int_interval := EcologyClock.create_clock(region, 1)
	_check(String(clock_from_int_interval.get("clock_hash", "")) == EXPECTED_CLOCK_HASH, "integer and float interval normalize to same clock identity")

	var before_first := EcologyClock.due_plan(region, 43.49, clock)
	_check(bool(before_first.get("success", false)) and int(before_first.get("due_steps", -1)) == 0, "time before first boundary has zero due steps")
	var first_boundary := EcologyClock.due_plan(region, 43.5, clock)
	_check(bool(first_boundary.get("success", false)) and int(first_boundary.get("due_steps", -1)) == 1, "exact first boundary has one due step")
	var fractional_after := EcologyClock.due_plan(region, 47.9, clock)
	_check(bool(fractional_after.get("success", false)), "fractional target produces plan")
	_check(int(fractional_after.get("due_steps", -1)) == 5 and int(fractional_after.get("target_generation", -1)) == 5, "world time maps to completed generation deterministically")
	_check(is_equal_approx(float(fractional_after.get("processed_boundary_world_time", NAN)), 47.5), "plan records last completed boundary only")
	_check(is_equal_approx(float(fractional_after.get("observed_target_world_time", NAN)), 47.9), "plan retains observation separately")

	var unchanged := EcologyClock.advance_to(region, 43.49, clock)
	_check(unchanged == region, "zero-due advance preserves exact region state")
	var direct := EcologyClock.advance_to(region, 47.9, clock)
	_check(bool(RegionState.validate_region_state(direct).get("success", false)), "direct clock advance yields valid region")
	_check(bool(EcologyClock.validate_bound_region(direct, clock).get("success", false)), "direct result remains clock-bound")
	_check(int(direct.get("ecology_generation", -1)) == 5, "direct target advances five generations")
	_check(is_equal_approx(float(direct.get("last_simulated_world_time", NAN)), 47.5), "region stores processed boundary rather than arbitrary target")
	_check(String(direct.get("region_state_hash", "")) == EXPECTED_GENERATION_5_REGION_HASH, "frozen generation-five region identity exact")

	var partition_a := EcologyClock.advance_to(region, 44.6, clock)
	_check(int(partition_a.get("ecology_generation", -1)) == 2, "partition first leg reaches generation two")
	var partition_b := EcologyClock.advance_to(partition_a, 47.9, clock)
	_check(int(partition_b.get("ecology_generation", -1)) == 5, "partition second leg reaches generation five")
	_check(String(partition_b.get("p3_state_hash", "")) == String(direct.get("p3_state_hash", "")), "partitioned advance converges to direct P3 state")
	_check(String(partition_b.get("region_state_hash", "")) == String(direct.get("region_state_hash", "")), "partitioned advance converges to direct region identity")

	var noisy_partition := region.duplicate(true)
	for target in [42.6, 43.1, 43.6, 44.49, 44.51, 45.9, 47.9]:
		noisy_partition = EcologyClock.advance_to(noisy_partition, target, clock)
		_check(not noisy_partition.is_empty(), "arbitrary observation partition stays valid")
	_check(String(noisy_partition.get("region_state_hash", "")) == String(direct.get("region_state_hash", "")), "observation cadence does not affect final state")

	var decimal_region := RegionState.create_region_state("decimal-region", 10.0, p3_initial)
	var decimal_clock := EcologyClock.create_clock(decimal_region, 0.1)
	_check(bool(EcologyClock.validate_clock(decimal_clock).get("success", false)), "decimal interval clock validates")
	var decimal_target := EcologyClock.boundary_time_for_generation(100, decimal_clock)
	_check(not is_nan(decimal_target), "generation-100 decimal boundary representable")
	var decimal_direct := EcologyClock.advance_to(decimal_region, decimal_target, decimal_clock)
	_check(int(decimal_direct.get("ecology_generation", -1)) == 100, "decimal direct reaches generation 100")
	var decimal_cut_target := EcologyClock.boundary_time_for_generation(37, decimal_clock)
	var decimal_cut := EcologyClock.advance_to(decimal_region, decimal_cut_target, decimal_clock)
	var decimal_resumed := EcologyClock.advance_to(decimal_cut, decimal_target, decimal_clock)
	_check(String(decimal_resumed.get("region_state_hash", "")) == String(decimal_direct.get("region_state_hash", "")), "decimal interval partition is drift-free")
	_check(float(decimal_direct.get("last_simulated_world_time", NAN)) == decimal_target, "stored decimal boundary uses direct origin plus generation multiplication")
	_check(String(decimal_direct.get("region_state_hash", "")) == EXPECTED_DECIMAL_GENERATION_100_REGION_HASH, "frozen decimal generation-100 identity exact")

	var future_from_original := EcologyClock.advance_to(direct, 50.1, clock)
	var rebased_clock := EcologyClock.create_clock(direct, 1.0)
	var future_from_rebase := EcologyClock.advance_to(direct, 50.1, rebased_clock)
	_check(not future_from_original.is_empty() and not future_from_rebase.is_empty(), "original and rebased clocks both advance future state")
	_check(String(future_from_original.get("region_state_hash", "")) == String(future_from_rebase.get("region_state_hash", "")), "clock rebasing at a canonical boundary preserves future result")

	var large_plan := EcologyClock.due_plan(region, 42.5 + float(Persistence.MAX_ADVANCE_STEPS + 1), clock)
	_check(bool(large_plan.get("success", false)) and int(large_plan.get("due_steps", -1)) == Persistence.MAX_ADVANCE_STEPS + 1, "clock can describe backlog beyond one P3.8 advance call")
	_check(EcologyClock.advance_to(region, 42.5 + float(Persistence.MAX_ADVANCE_STEPS + 1), clock).is_empty(), "P4.2 refuses oversized backlog; P4.3 owns catch-up policy")

	_check(not bool(EcologyClock.due_plan(region, 42.0, clock).get("success", false)), "world-time rewind rejected")
	_check(not bool(EcologyClock.due_plan(region, NAN, clock).get("success", false)), "NaN target rejected")
	_check(not bool(EcologyClock.due_plan(region, INF, clock).get("success", false)), "infinite target rejected")
	_check(not bool(EcologyClock.due_plan(region, "44.0", clock).get("success", false)), "non-numeric target rejected")
	_check(not bool(EcologyClock.due_plan(region, 1.0e30, clock).get("success", false)), "target generation beyond exact range rejected")
	_check(EcologyClock.create_clock(region, 0.0).is_empty(), "zero interval rejected")
	_check(EcologyClock.create_clock(region, -1.0).is_empty(), "negative interval rejected")
	_check(EcologyClock.create_clock(region, NAN).is_empty(), "NaN interval rejected")
	_check(EcologyClock.create_clock(region, INF).is_empty(), "infinite interval rejected")

	var tampered_clock := clock.duplicate(true)
	tampered_clock["clock_hash"] = "0".repeat(64)
	_check(not bool(EcologyClock.validate_clock(tampered_clock).get("success", false)), "tampered clock hash rejected")
	tampered_clock = clock.duplicate(true)
	tampered_clock["parent_p4_1_accepted_aggregate"] = "0".repeat(64)
	_check(not bool(EcologyClock.validate_clock(tampered_clock).get("success", false)), "wrong P4.1 parent rejected")
	tampered_clock = clock.duplicate(true)
	tampered_clock["step_interval_world_time"] = 1
	_check(not bool(EcologyClock.validate_clock(tampered_clock).get("success", false)), "stored interval requires canonical float")
	tampered_clock = clock.duplicate(true)
	tampered_clock["unexpected"] = true
	_check(not bool(EcologyClock.validate_clock(tampered_clock).get("success", false)), "extra clock field rejected")

	var misbound := RegionState.create_region_state("planet-01:region_0007", 42.75, p3_initial)
	_check(not bool(EcologyClock.validate_bound_region(misbound, clock).get("success", false)), "region off clock boundary rejected")
	_check(EcologyClock.advance_to(misbound, 44.0, clock).is_empty(), "misbound region cannot advance")
	var microscopic_misbound := RegionState.create_region_state("planet-01:region_0007", 42.50000000001, p3_initial)
	_check(not bool(EcologyClock.validate_bound_region(microscopic_misbound, clock).get("success", false)), "persisted region time must equal exact clock boundary, not merely epsilon-close")

	var reordered_clock := {}
	for key in ["clock_hash", "step_interval_world_time", "origin_world_time", "origin_generation", "parent_p4_1_accepted_aggregate", "version", "schema"]:
		reordered_clock[key] = clock[key]
	_check(bool(EcologyClock.validate_clock(reordered_clock).get("success", false)), "clock dictionary insertion order irrelevant")
	_check(String(EcologyClock.compute_clock_hash(reordered_clock)) == String(clock["clock_hash"]), "clock hash insertion-order independent")

	seed(86420)
	var rng_before := [randi(), randi(), randi()]
	seed(86420)
	var rng_clock := EcologyClock.create_clock(region, 1.0)
	EcologyClock.due_plan(region, 47.9, rng_clock)
	EcologyClock.advance_to(region, 44.6, rng_clock)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "P4.2 clock consumes no global RNG")

	var aggregate_hash := (String(clock.get("clock_hash", "")) + "\n" + String(direct.get("region_state_hash", "")) + "\n" + String(decimal_direct.get("region_state_hash", "")) + "\n" + EcologyClock.PARENT_P4_1_ACCEPTED_AGGREGATE).sha256_text()
	_check(aggregate_hash == EXPECTED_AGGREGATE, "frozen P4.2 aggregate exact")

	if failed:
		quit(1)
		return
	print("ECO.P4.2 Deterministic Ecology Clock: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("clock_hash=" + String(clock.get("clock_hash", "")))
	print("generation_5_region_hash=" + String(direct.get("region_state_hash", "")))
	print("decimal_generation_100_region_hash=" + String(decimal_direct.get("region_state_hash", "")))
	print("parent_p4_1=" + EcologyClock.PARENT_P4_1_ACCEPTED_AGGREGATE)
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
	push_error("ECO.P4.2 FAIL: " + message)
