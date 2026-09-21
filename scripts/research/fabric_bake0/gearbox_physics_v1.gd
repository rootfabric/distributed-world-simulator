extends RefCounted
## Physical derivation for one gear body + its explicit teeth.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")

static func derive_gear(graph: Dictionary, gear: Dictionary, teeth: Array) -> Dictionary:
	if not bool(gear.enabled):
		return U.failure("GEARBOX_GEAR_DISABLED", {"gear_id": gear.gear_id})
	if teeth.size() != int(gear.tooth_count):
		return U.failure("GEARBOX_TOOTH_COVERAGE_MISMATCH", {"gear_id": gear.gear_id})
	var min_tooth_quality := 1.0
	for tooth in teeth:
		if not bool(tooth.enabled):
			return U.failure("GEARBOX_TOOTH_DISABLED", {"tooth_id": tooth.tooth_id, "gear_id": gear.gear_id})
		min_tooth_quality = minf(min_tooth_quality, float(tooth.quality_ratio))
	var material := MatterCatalog.material_by_id(graph.material_catalog, String(gear.material_id))
	if material.is_empty():
		return U.failure("GEARBOX_GEAR_MATERIAL_MISSING", {"gear_id": gear.gear_id})
	var pitch_radius := 0.5 * float(gear.module_m) * float(gear.tooth_count)
	var body_volume := PI * pitch_radius * pitch_radius * float(gear.body_thickness_m)
	var mass := float(material.density_kg_m3) * body_volume
	var inertia := 0.5 * mass * pitch_radius * pitch_radius
	var effective_quality := float(gear.quality_ratio) * min_tooth_quality
	var strength_pa := minf(float(material.tensile_strength_pa), float(material.compressive_strength_pa))
	var tooth_root_area := float(gear.face_width_m) * float(gear.module_m) * 0.45
	var tangential_force_limit := strength_pa * tooth_root_area * effective_quality
	var torque_limit := tangential_force_limit * pitch_radius
	var rim_speed_limit := sqrt(maxf(0.0, float(material.tensile_strength_pa) / float(material.density_kg_m3))) * sqrt(effective_quality)
	var omega_limit := rim_speed_limit / pitch_radius
	var row := {
		"gear_id": String(gear.gear_id),
		"stage_index": int(gear.stage_index),
		"role": String(gear.role),
		"material_id": String(gear.material_id),
		"tooth_count": int(gear.tooth_count),
		"module_m": float(gear.module_m),
		"pitch_radius_m": pitch_radius,
		"mass_kg": mass,
		"inertia_kg_m2": inertia,
		"min_tooth_quality": min_tooth_quality,
		"effective_quality": effective_quality,
		"tangential_force_limit_n": tangential_force_limit,
		"torque_limit_nm": torque_limit,
		"max_abs_omega_rad_s": omega_limit,
	}
	for field in ["pitch_radius_m", "mass_kg", "inertia_kg_m2", "effective_quality", "tangential_force_limit_n", "torque_limit_nm", "max_abs_omega_rad_s"]:
		if not U.is_positive_number(row[field]):
			return U.failure("GEARBOX_GEAR_DERIVATION_NONPOSITIVE", {"gear_id": gear.gear_id, "field": field})
	return U.success({"gear": row})
