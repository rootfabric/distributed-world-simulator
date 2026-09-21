extends RefCounted
## Characterized electromechanical primitives used by T5 compiler/reference.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/motor_generator_graph_v1.gd")
const Profile = preload("res://scripts/research/fabric_bake0/motor_electromagnetic_profile_v1.gd")

static func derive_winding(graph: Dictionary, winding: Dictionary) -> Dictionary:
	var profile := Graph.profile_by_id(graph, String(winding.profile_id))
	if profile.is_empty():
		return U.failure("MOTOR_WINDING_PROFILE_NOT_FOUND")
	var conductor := MatterCatalog.material_by_id(graph.material_catalog, String(profile.conductor_material_id))
	var magnet := MatterCatalog.material_by_id(graph.material_catalog, String(profile.magnet_material_id))
	if conductor.is_empty() or magnet.is_empty():
		return U.failure("MOTOR_WINDING_MATERIAL_NOT_FOUND")
	var checked := Profile.validate_against_materials(profile, conductor, magnet)
	if not checked.success:
		return checked
	var q := float(winding.quality_ratio)
	var resistance := float(profile.conductor_resistivity_ohm_m) * float(winding.wire_length_m) / float(winding.wire_area_m2) / q
	var coupling := 2.0 * float(int(winding.turns)) * float(profile.flux_density_t) * float(winding.active_length_m) * float(winding.lever_arm_m) * q
	var max_current := float(profile.max_current_density_a_m2) * float(winding.wire_area_m2) * q
	var wire_volume := float(winding.wire_length_m) * float(winding.wire_area_m2)
	var wire_mass := float(conductor.density_kg_m3) * wire_volume
	for number in [resistance, coupling, max_current, wire_mass]:
		if not U.is_positive_number(number):
			return U.failure("MOTOR_WINDING_DERIVATION_INVALID")
	return U.success({"winding": {
		"winding_id": String(winding.winding_id),
		"enabled": bool(winding.enabled),
		"resistance_ohm": resistance,
		"torque_constant_nm_a": coupling,
		"back_emf_constant_v_s_rad": coupling,
		"max_current_a": max_current,
		"wire_mass_kg": wire_mass,
	}})

static func derive_rotor_sector(graph: Dictionary, sector: Dictionary) -> Dictionary:
	var material := MatterCatalog.material_by_id(graph.material_catalog, String(sector.material_id))
	if material.is_empty():
		return U.failure("MOTOR_ROTOR_MATERIAL_NOT_FOUND")
	var density := float(material.density_kg_m3)
	var mass := density * float(sector.volume_m3)
	var radius := float(sector.radius_m)
	var inertia := mass * radius * radius
	var allowable_tensile := float(material.tensile_strength_pa) * float(sector.quality_ratio)
	var max_omega := sqrt(allowable_tensile / density) / radius
	for number in [mass, inertia, max_omega]:
		if not U.is_positive_number(number):
			return U.failure("MOTOR_ROTOR_DERIVATION_INVALID")
	return U.success({"sector": {
		"sector_id": String(sector.sector_id),
		"enabled": bool(sector.enabled),
		"mass_kg": mass,
		"inertia_kg_m2": inertia,
		"max_abs_angular_velocity_rad_s": max_omega,
	}})
