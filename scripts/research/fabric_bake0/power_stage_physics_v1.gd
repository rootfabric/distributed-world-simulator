extends RefCounted
## Per-die electrical derivation for T6.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const Graph = preload("res://scripts/research/fabric_bake0/power_stage_graph_v1.gd")

static func derive_die(graph: Dictionary, die: Dictionary) -> Dictionary:
	var profile := Graph.profile_by_id(graph, String(die.profile_id))
	if profile.is_empty():
		return U.failure("POWER_STAGE_DIE_PROFILE_NOT_FOUND")
	var material := MatterCatalog.material_by_id(graph.material_catalog, String(profile.semiconductor_material_id))
	if material.is_empty():
		return U.failure("POWER_STAGE_DIE_MATERIAL_NOT_FOUND")
	var quality := float(die.quality_ratio)
	var resistance_ref := float(profile.effective_on_resistivity_ohm_m) * float(die.current_path_length_m) / float(die.active_area_m2) / quality
	var conductance_ref := 1.0 / resistance_ref
	var max_current := float(profile.max_current_density_a_m2) * float(die.active_area_m2) * quality
	var transition_time := float(profile.transition_time_s) / quality
	var mass := float(material.density_kg_m3) * float(die.current_path_length_m) * float(die.active_area_m2)
	var row := {
		"die_id": String(die.die_id),
		"bank_index": int(die.bank_index),
		"profile_id": String(die.profile_id),
		"enabled": bool(die.enabled),
		"quality_ratio": quality,
		"resistance_ref_ohm": resistance_ref,
		"conductance_ref_s": conductance_ref,
		"max_abs_current_a": max_current,
		"transition_time_s": transition_time,
		"resistance_temp_coefficient_per_k": float(profile.resistance_temp_coefficient_per_k),
		"reference_temperature_k": float(profile.reference_temperature_k),
		"min_temperature_k": float(profile.min_temperature_k),
		"max_temperature_k": float(profile.max_temperature_k),
		"max_bus_voltage_v": float(profile.max_bus_voltage_v),
		"mass_kg": mass,
		"current_limit_per_conductance": max_current / conductance_ref,
	}
	for field in ["resistance_ref_ohm", "conductance_ref_s", "max_abs_current_a", "transition_time_s", "mass_kg", "current_limit_per_conductance"]:
		if not U.is_positive_number(row[field]):
			return U.failure("POWER_STAGE_DIE_DERIVATION_NONPOSITIVE", {"field": field})
	return U.success({"die": row})

static func resistance_at_temperature(row: Dictionary, temperature_k: float) -> float:
	var factor := 1.0 + float(row.resistance_temp_coefficient_per_k) * (temperature_k - float(row.reference_temperature_k))
	return float(row.resistance_ref_ohm) * maxf(factor, 0.05)
