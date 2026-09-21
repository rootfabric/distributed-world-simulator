extends RefCounted
## One-lane thermal/hydraulic derivation for T8.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")

static func derive_lane(graph: Dictionary, lane: Dictionary) -> Dictionary:
	if not bool(lane.enabled):
		return U.failure("COOLING_LANE_DISABLED", {"lane_id": lane.lane_id})
	var plate := MatterCatalog.material_by_id(graph.material_catalog, String(lane.plate_material_id))
	var radiator := MatterCatalog.material_by_id(graph.material_catalog, String(lane.radiator_material_id))
	var coolant := MatterCatalog.material_by_id(graph.material_catalog, String(lane.coolant_material_id))
	if plate.is_empty() or radiator.is_empty() or coolant.is_empty():
		return U.failure("COOLING_LANE_MATERIAL_MISSING", {"lane_id": lane.lane_id})
	var profile: Dictionary = graph.coolant_profile
	var q := float(lane.quality_ratio)
	var plate_mass := float(plate.density_kg_m3) * float(lane.plate_volume_m3)
	var radiator_mass := float(radiator.density_kg_m3) * float(lane.radiator_volume_m3)
	var hot_mass := float(coolant.density_kg_m3) * float(lane.hot_coolant_volume_m3)
	var cold_mass := float(coolant.density_kg_m3) * float(lane.cold_coolant_volume_m3)
	var plate_capacity := plate_mass * float(plate.heat_capacity_j_kg_k)
	var hot_capacity := hot_mass * float(coolant.heat_capacity_j_kg_k)
	var cold_capacity := cold_mass * float(coolant.heat_capacity_j_kg_k)
	var radiator_capacity := radiator_mass * float(radiator.heat_capacity_j_kg_k)
	var plate_g := float(plate.thermal_conductivity_w_m_k) * float(lane.plate_contact_area_m2) / float(lane.plate_wall_thickness_m) * q
	var radiator_g := float(radiator.thermal_conductivity_w_m_k) * float(lane.radiator_contact_area_m2) / float(lane.radiator_wall_thickness_m) * q
	var ambient_g := float(profile.ambient_heat_transfer_coefficient_w_m2_k) * float(lane.radiator_ambient_area_m2) * q
	var mu := float(profile.dynamic_viscosity_pa_s)
	var max_lane_mass_flow := float(profile.laminar_reynolds_limit) * mu * float(lane.channel_flow_area_m2) / float(lane.channel_hydraulic_diameter_m)
	var min_temperature := float(coolant.melting_temperature_k) + 1.0
	var max_temperature := minf(float(coolant.vaporization_temperature_k) - 1.0, minf(float(plate.melting_temperature_k), float(radiator.melting_temperature_k)))
	var row := {
		"lane_id": String(lane.lane_id),
		"plate_capacity_j_k": plate_capacity,
		"hot_coolant_capacity_j_k": hot_capacity,
		"radiator_capacity_j_k": radiator_capacity,
		"cold_coolant_capacity_j_k": cold_capacity,
		"plate_to_hot_conductance_w_k": plate_g,
		"cold_to_radiator_conductance_w_k": radiator_g,
		"radiator_to_ambient_conductance_w_k": ambient_g,
		"coolant_heat_capacity_j_kg_k": float(coolant.heat_capacity_j_kg_k),
		"coolant_density_kg_m3": float(coolant.density_kg_m3),
		"dynamic_viscosity_pa_s": mu,
		"laminar_reynolds_limit": float(profile.laminar_reynolds_limit),
		"channel_flow_area_m2": float(lane.channel_flow_area_m2),
		"channel_hydraulic_diameter_m": float(lane.channel_hydraulic_diameter_m),
		"channel_flow_length_m": float(lane.channel_flow_length_m),
		"max_lane_mass_flow_kg_s": max_lane_mass_flow,
		"total_mass_kg": plate_mass + radiator_mass + hot_mass + cold_mass,
		"min_temperature_k": min_temperature,
		"max_temperature_k": max_temperature,
	}
	for field in [
		"plate_capacity_j_k", "hot_coolant_capacity_j_k", "radiator_capacity_j_k", "cold_coolant_capacity_j_k",
		"plate_to_hot_conductance_w_k", "cold_to_radiator_conductance_w_k", "radiator_to_ambient_conductance_w_k",
		"coolant_heat_capacity_j_kg_k", "coolant_density_kg_m3", "dynamic_viscosity_pa_s",
		"channel_flow_area_m2", "channel_hydraulic_diameter_m", "channel_flow_length_m",
		"max_lane_mass_flow_kg_s", "total_mass_kg", "min_temperature_k", "max_temperature_k"
	]:
		if not U.is_positive_number(row[field]):
			return U.failure("COOLING_LANE_DERIVATION_NONPOSITIVE", {"lane_id": lane.lane_id, "field": field})
	if min_temperature >= max_temperature:
		return U.failure("COOLING_LANE_TEMPERATURE_DOMAIN_EMPTY", {"lane_id": lane.lane_id})
	return U.success({"lane": row})

static func reynolds_number(row: Dictionary, lane_mass_flow_kg_s: float) -> float:
	if lane_mass_flow_kg_s <= 0.0:
		return 0.0
	return lane_mass_flow_kg_s * float(row.channel_hydraulic_diameter_m) / (float(row.dynamic_viscosity_pa_s) * float(row.channel_flow_area_m2))

static func hydraulic_power_w(row: Dictionary, lane_mass_flow_kg_s: float) -> float:
	if lane_mass_flow_kg_s <= 0.0:
		return 0.0
	var volumetric_flow := lane_mass_flow_kg_s / float(row.coolant_density_kg_m3)
	var velocity := volumetric_flow / float(row.channel_flow_area_m2)
	var pressure_drop := 32.0 * float(row.dynamic_viscosity_pa_s) * float(row.channel_flow_length_m) * velocity / pow(float(row.channel_hydraulic_diameter_m), 2.0)
	return pressure_drop * volumetric_flow
