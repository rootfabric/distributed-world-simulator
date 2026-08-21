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
const OfflineCatchup = preload("res://scripts/ecology/production/ecology_offline_catchup_v1.gd")

const EXPECTED_P3_8_INITIAL_STATE := "6070494e77828f4e25a00eed9695de9e87fdf94e472f5018d660a7c20b15d7fb"
const EXPECTED_CLOCK_HASH := "f62815a7be67d7db2aeaa809915924ba2eb0437521ef6c908239642ba6909899"
const EXPECTED_GENERATION_5_REGION_HASH := "fbc2072e388b2c9b02ff5755815821391bcf23b97cab35a5a8b1452bc4e5999c"
const EXPECTED_CATCHUP_HASH := "cc2a4815e1eae75b879ea52d8ba404880c69344928f953e8aaa38bd062b1ce3a"
const EXPECTED_AGGREGATE := "4bdfd994a27ef15ff4010643e35f4652a0a2f3fdb2d3fcfa6b86b816b14cca62"

var assertions := 0
var failed := false

func _init() -> void:
	var p3_initial := Persistence.initialize(_initial_p3_7_result())
	_check(bool(Persistence.validate_state(p3_initial).get("success", false)), "P3.8 initial fixture validates")
	_check(String(p3_initial.get("state_hash", "")) == EXPECTED_P3_8_INITIAL_STATE, "P3.8 initial identity exact")
	var region := RegionState.create_region_state("planet-01:region_0007", 42.5, p3_initial)
	_check(bool(RegionState.validate_region_state(region).get("success", false)), "accepted P4.1 region fixture validates")
	var clock := EcologyClock.create_clock(region, 1.0)
	_check(bool(EcologyClock.validate_clock(clock).get("success", false)), "accepted P4.2 clock validates")
	_check(String(clock.get("clock_hash", "")) == EXPECTED_CLOCK_HASH, "accepted P4.2 clock identity exact")
	_check(OfflineCatchup.PARENT_P4_2_ACCEPTED_AGGREGATE == "607884ed9ce2d398fb225928f03f423f4fd2ae4198c12d066aa74c6ce421a42e", "accepted P4.2 aggregate pinned")

	var initial := OfflineCatchup.create(region, 47.9, clock)
	_check(bool(OfflineCatchup.validate_state(initial).get("success", false)), "offline catch-up ticket validates")
	_check(int(initial.get("remaining_due_steps", -1)) == 5, "five completed generations due")
	_check(not bool(initial.get("fully_caught_up", true)), "initial ticket reports pending backlog")
	_check(float(initial.get("observed_target_world_time", NAN)) == 47.9, "observed offline horizon retained exactly")
	_check(String(Dictionary(initial.get("region_state", {})).get("region_state_hash", "")) == String(region.get("region_state_hash", "")), "ticket creation is read-only for region")

	var from_elapsed := OfflineCatchup.create_from_elapsed(region, 5.4, clock)
	_check(bool(OfflineCatchup.validate_state(from_elapsed).get("success", false)), "elapsed constructor validates")
	_check(float(from_elapsed.get("observed_target_world_time", NAN)) == 47.9, "elapsed converts to same observed horizon")
	_check(int(from_elapsed.get("remaining_due_steps", -1)) == 5, "elapsed constructor derives same backlog")

	var staged := OfflineCatchup.advance_batch(initial, 2)
	_check(not staged.is_empty(), "first bounded batch succeeds")
	_check(int(Dictionary(staged["region_state"])["ecology_generation"]) == 2, "first batch advances exactly two generations")
	_check(int(staged["remaining_due_steps"]) == 3, "first batch retains remaining backlog")
	_check(float(staged["observed_target_world_time"]) == 47.9, "first batch preserves offline horizon")
	staged = OfflineCatchup.advance_batch(staged, 2)
	_check(int(Dictionary(staged["region_state"])["ecology_generation"]) == 4, "second batch advances to generation four")
	_check(int(staged["remaining_due_steps"]) == 1, "one generation remains after second batch")
	var completed := OfflineCatchup.advance_batch(staged, 2)
	_check(bool(OfflineCatchup.validate_state(completed).get("success", false)), "completed catch-up validates")
	_check(bool(completed["fully_caught_up"]), "catch-up marks completion")
	_check(int(completed["remaining_due_steps"]) == 0, "whole-step backlog exhausted")
	_check(int(Dictionary(completed["region_state"])["ecology_generation"]) == 5, "completed catch-up reaches generation five")
	_check(float(Dictionary(completed["region_state"])["last_simulated_world_time"]) == 47.5, "region stores last exact completed boundary")
	_check(float(completed["observed_target_world_time"]) == 47.9, "fractional 0.4 world-time remainder retained after catch-up")
	_check(String(Dictionary(completed["region_state"])["region_state_hash"]) == EXPECTED_GENERATION_5_REGION_HASH, "accepted generation-five region identity preserved")
	_check(String(completed["catchup_hash"]) == EXPECTED_CATCHUP_HASH, "frozen P4.3 catch-up identity exact")

	var direct := OfflineCatchup.advance_batch(initial, 5)
	_check(bool(direct.get("fully_caught_up", false)), "single allowed batch completes same backlog")
	_check(String(direct["catchup_hash"]) == String(completed["catchup_hash"]), "batch partition converges to same catch-up identity")
	_check(String(Dictionary(direct["region_state"])["region_state_hash"]) == String(Dictionary(completed["region_state"])["region_state_hash"]), "batch partition converges to same canonical region")

	var exact_partition := OfflineCatchup.create_from_elapsed(region, 2.0, clock)
	exact_partition = OfflineCatchup.advance_batch(exact_partition, 10)
	exact_partition = OfflineCatchup.extend_elapsed(exact_partition, 3.0)
	exact_partition = OfflineCatchup.advance_batch(exact_partition, 10)
	var exact_direct := OfflineCatchup.create_from_elapsed(region, 5.0, clock)
	exact_direct = OfflineCatchup.advance_batch(exact_direct, 10)
	_check(String(exact_partition["catchup_hash"]) == String(exact_direct["catchup_hash"]), "elapsed-time partition converges for same exact horizon")

	var fractional := OfflineCatchup.create_from_elapsed(region, 0.4, clock)
	_check(bool(fractional["fully_caught_up"]) and int(fractional["remaining_due_steps"]) == 0, "sub-step offline time does not fake a generation")
	_check(float(fractional["observed_target_world_time"]) == 42.9, "sub-step remainder is retained")
	var fractional_extended := OfflineCatchup.extend_elapsed(fractional, 0.7)
	_check(int(fractional_extended["remaining_due_steps"]) == 1, "retained fraction contributes to later due generation")
	_check(float(fractional_extended["observed_target_world_time"]) == 43.6, "extended observed horizon retained")
	fractional_extended = OfflineCatchup.advance_batch(fractional_extended, 1)
	_check(int(Dictionary(fractional_extended["region_state"])["ecology_generation"]) == 1, "fractional accumulation advances exactly one completed generation")
	_check(float(Dictionary(fractional_extended["region_state"])["last_simulated_world_time"]) == 43.5, "fractional accumulation remains on exact clock boundary")
	_check(float(fractional_extended["observed_target_world_time"]) == 43.6, "post-advance sub-step remainder survives")

	var large := OfflineCatchup.create_from_elapsed(region, float(Persistence.MAX_ADVANCE_STEPS + 1) + 0.25, clock)
	_check(not large.is_empty(), "P4.3 can represent backlog larger than one P3.8 advance call")
	_check(int(large["remaining_due_steps"]) == Persistence.MAX_ADVANCE_STEPS + 1, "large backlog count exact")
	var large_one := OfflineCatchup.advance_batch(large, 1)
	_check(not large_one.is_empty(), "large backlog can make bounded progress")
	_check(int(large_one["remaining_due_steps"]) == Persistence.MAX_ADVANCE_STEPS, "large backlog debt is explicit after bounded progress")
	_check(float(large_one["observed_target_world_time"]) == float(large["observed_target_world_time"]), "large backlog never silently drops offline horizon")

	var no_due := OfflineCatchup.create_from_elapsed(region, 0.0, clock)
	var no_due_after := OfflineCatchup.advance_batch(no_due, 1)
	_check(String(no_due_after["catchup_hash"]) == String(no_due["catchup_hash"]), "zero-backlog batch is exact no-op")
	_check(String(Dictionary(no_due_after["region_state"])["region_state_hash"]) == String(region["region_state_hash"]), "zero-backlog batch preserves region")

	var observed_forward := OfflineCatchup.observe_target(no_due, 44.6)
	_check(int(observed_forward.get("remaining_due_steps", -1)) == 2, "absolute observed target can extend catch-up horizon")
	_check(OfflineCatchup.observe_target(observed_forward, 44.0).is_empty(), "observed target rewind rejected")
	_check(OfflineCatchup.create(region, 42.0, clock).is_empty(), "target before canonical region boundary rejected")
	_check(OfflineCatchup.create_from_elapsed(region, -1.0, clock).is_empty(), "negative offline elapsed rejected")
	_check(OfflineCatchup.create_from_elapsed(region, NAN, clock).is_empty(), "NaN offline elapsed rejected")
	_check(OfflineCatchup.create_from_elapsed(region, INF, clock).is_empty(), "infinite offline elapsed rejected")
	_check(OfflineCatchup.extend_elapsed(initial, -0.1).is_empty(), "negative elapsed extension rejected")
	_check(OfflineCatchup.extend_elapsed(initial, INF).is_empty(), "infinite elapsed extension rejected")
	_check(OfflineCatchup.advance_batch(initial, 0).is_empty(), "zero batch budget rejected")
	_check(OfflineCatchup.advance_batch(initial, -1).is_empty(), "negative batch budget rejected")
	_check(OfflineCatchup.advance_batch(initial, 1.0).is_empty(), "non-integer batch budget rejected")
	_check(OfflineCatchup.advance_batch(initial, Persistence.MAX_ADVANCE_STEPS + 1).is_empty(), "batch above P3.8 safe maximum rejected")

	var tampered := initial.duplicate(true)
	tampered["remaining_due_steps"] = 4
	_check(not bool(OfflineCatchup.validate_state(tampered).get("success", false)), "derived backlog tamper rejected")
	tampered = initial.duplicate(true)
	tampered["fully_caught_up"] = true
	_check(not bool(OfflineCatchup.validate_state(tampered).get("success", false)), "derived completion flag tamper rejected")
	tampered = initial.duplicate(true)
	tampered["catchup_hash"] = "0".repeat(64)
	_check(not bool(OfflineCatchup.validate_state(tampered).get("success", false)), "catch-up hash tamper rejected")
	tampered = initial.duplicate(true)
	tampered["parent_p4_2_accepted_aggregate"] = "0".repeat(64)
	_check(not bool(OfflineCatchup.validate_state(tampered).get("success", false)), "wrong P4.2 parent rejected")
	tampered = initial.duplicate(true)
	Dictionary(tampered["clock"])["clock_hash"] = "0".repeat(64)
	_check(not bool(OfflineCatchup.validate_state(tampered).get("success", false)), "tampered P4.2 clock rejected")
	tampered = initial.duplicate(true)
	Dictionary(tampered["region_state"])["region_state_hash"] = "0".repeat(64)
	_check(not bool(OfflineCatchup.validate_state(tampered).get("success", false)), "tampered P4.1 region rejected")
	tampered = initial.duplicate(true)
	tampered["unexpected"] = true
	_check(not bool(OfflineCatchup.validate_state(tampered).get("success", false)), "extra catch-up field rejected")

	seed(97531)
	var rng_before := [randi(), randi(), randi()]
	seed(97531)
	var rng_state := OfflineCatchup.create_from_elapsed(region, 3.5, clock)
	rng_state = OfflineCatchup.advance_batch(rng_state, 2)
	OfflineCatchup.extend_elapsed(rng_state, 0.25)
	var rng_after := [randi(), randi(), randi()]
	_check(rng_before == rng_after, "P4.3 consumes no global RNG")

	var aggregate_hash := (String(completed["catchup_hash"]) + "\n" + String(Dictionary(completed["region_state"])["region_state_hash"]) + "\n" + OfflineCatchup.PARENT_P4_2_ACCEPTED_AGGREGATE).sha256_text()
	_check(aggregate_hash == EXPECTED_AGGREGATE, "frozen P4.3 aggregate exact")

	if failed:
		quit(1)
		return
	print("ECO.P4.3 Offline Catch-up: PASS (%d assertions)" % assertions)
	print("aggregate_hash=" + aggregate_hash)
	print("catchup_hash=" + String(completed["catchup_hash"]))
	print("generation_5_region_hash=" + String(Dictionary(completed["region_state"])["region_state_hash"]))
	print("parent_p4_2=" + OfflineCatchup.PARENT_P4_2_ACCEPTED_AGGREGATE)
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
	push_error("ECO.P4.3 FAIL: " + message)
