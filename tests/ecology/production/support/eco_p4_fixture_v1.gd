extends RefCounted

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

static func completed_catchup(region_id: String = "planet-01:region_0007", origin_world_time: float = 42.5, observed_target_world_time: float = 47.9) -> Dictionary:
	var p3_initial := Persistence.initialize(initial_p3_7_result())
	var region := RegionState.create_region_state(region_id, origin_world_time, p3_initial)
	var clock := EcologyClock.create_clock(region, 1.0)
	var catchup := OfflineCatchup.create(region, observed_target_world_time, clock)
	return OfflineCatchup.advance_batch(catchup, 10)

static func initial_p3_7_result() -> Dictionary:
	var parent := disturbance_result()
	var niches := niches()
	var community := Coexistence.community_from_parent(parent, niches)
	var skewed := skew_community(community, 0.05, 0.95)
	return Coexistence.step(parent, skewed, niches, {"stabilization_fraction": 0.5})

static func niches() -> Array:
	return [{"id":"alpha","temperature_optimum_c":10.0,"temperature_breadth_c":12.0,"moisture_optimum":0.8,"moisture_breadth":0.5,"light_optimum":0.5,"light_breadth":0.5,"nutrients_optimum":0.9,"nutrients_breadth":0.7},{"id":"beta","temperature_optimum_c":15.0,"temperature_breadth_c":12.0,"moisture_optimum":0.65,"moisture_breadth":0.5,"light_optimum":0.85,"light_breadth":0.5,"nutrients_optimum":0.4,"nutrients_breadth":0.7}]

static func skew_community(base: Array, alpha_share: float, beta_share: float) -> Array:
	var out := []
	for patch_value in base:
		var patch: Dictionary = patch_value
		var total := 0.0
		for plant_value in patch["plants"]:
			total += float(plant_value["biomass_kg"])
		out.append({"id":String(patch["id"]),"plant_order":PackedStringArray(["alpha","beta"]),"plants":[{"id":"alpha","biomass_kg":total*alpha_share},{"id":"beta","biomass_kg":total*beta_share}]})
	return out

static func disturbance_result() -> Dictionary:
	return Disturbance.apply(seasonal(0.0), disturbance(0.8, 1.0, 0.0, 0.0), traits(), 2.0)

static func traits() -> Array:
	return [{"id":"alpha","heat_resistance":0.9,"flood_resistance":0.2,"drought_resistance":0.2,"recovery_rate":0.4,"pioneer_capacity":0.2},{"id":"beta","heat_resistance":0.2,"flood_resistance":0.8,"drought_resistance":0.8,"recovery_rate":0.9,"pioneer_capacity":0.9}]

static func disturbance(severity: float, heat: float, flood: float, drought: float) -> Dictionary:
	return {"severity":severity,"heat_pressure":heat,"flood_pressure":flood,"drought_pressure":drought,"recovery_time_scale_years":2.0}

static func seasonal(time_years: float) -> Dictionary:
	return Seasonal.evaluate(environment(), time_years, season_config())

static func season_config() -> Dictionary:
	return {"cycle":{"period_years":1.0,"epoch_year":0.0,"phase_x_slope":0.0,"phase_y_slope":0.125,"phase_altitude_slope":0.0},"temperature_c":{"amplitude":10.0,"phase_offset":0.0},"moisture":{"amplitude":0.2,"phase_offset":0.25},"light":{"amplitude":0.1,"phase_offset":0.5},"nutrients":{"amplitude":0.15,"phase_offset":0.75}}

static func environment() -> Dictionary:
	return EnvGradient.apply(spatial(0.2), [{"id":"C","x":4.0,"y":2.0,"altitude":200.0},{"id":"A","x":0.0,"y":0.0,"altitude":0.0},{"id":"B","x":2.0,"y":0.0,"altitude":100.0}], environment_config())

static func environment_config() -> Dictionary:
	return {"origin":{"x":0.0,"y":0.0,"altitude":0.0},"temperature_c":channel(20.0,-1.0,0.5,-0.01,-50.0,50.0),"moisture":channel(0.8,-0.05,0.025,-0.001,0.0,1.0),"light":channel(0.4,0.05,0.025,0.001,0.0,1.0),"nutrients":channel(0.9,-0.05,-0.025,-0.0005,0.0,1.0)}

static func channel(base: float, x: float, y: float, z: float, minimum: float, maximum: float) -> Dictionary:
	return {"base":base,"x_slope":x,"y_slope":y,"altitude_slope":z,"min":minimum,"max":maximum}

static func spatial(fraction: float) -> Dictionary:
	var a := density([{"id":"alpha","biomass_kg":6.0},{"id":"beta","biomass_kg":4.0}],10.0)
	var b := density([{"id":"beta","biomass_kg":2.0}],2.0)
	var c := density([],10.0)
	return Dispersal.disperse([{"id":"C","density_result":c,"boundary_export_fraction":0.0},{"id":"A","density_result":a,"boundary_export_fraction":0.25},{"id":"B","density_result":b,"boundary_export_fraction":0.0}],[{"from":"A","to":"C","weight":1.0},{"from":"A","to":"B","weight":3.0}],{"dispersal_fraction":fraction})

static func density(plants: Array, capacity: float) -> Dictionary:
	var competitors := []
	for plant in plants:
		competitors.append({"id":String(plant["id"]),"demand":resources(1.0),"capture_efficiency":resources(1.0)})
	return Density.step(Competition.compete(resources(100.0), competitors), {"area_m2":capacity,"reference_capacity_kg_m2":1.0,"minimum_capacity_fraction":0.25,"max_recovery_fraction":0.25,"max_decline_fraction":0.6}, plants)

static func resources(value: float) -> Dictionary:
	return {"light":value,"water":value,"nutrients":value}
