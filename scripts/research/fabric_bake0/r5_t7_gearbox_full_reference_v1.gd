extends RefCounted
## Detailed T7 reference: re-derives all gears/teeth on every execute.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/gearbox_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/gearbox_physics_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	return U.success({"graph": graph.duplicate(true), "source_component_count": int(graph.gears.size() + graph.teeth.size())})

static func execute(plan: Dictionary, input_omega_rad_s: float, input_torque_nm: float, dt_s: float) -> Dictionary:
	if not U.is_finite_number(input_omega_rad_s) or not U.is_finite_number(input_torque_nm) or not U.is_positive_number(dt_s):
		return U.failure("GEARBOX_REFERENCE_STEP_INVALID")
	var graph: Dictionary = plan.graph
	var stages: int = Graph.stage_count(graph)
	var total_ratio := 1.0
	var max_input_torque := INF
	var max_input_omega := INF
	var equivalent_input_inertia := 0.0
	var driver_omega_ratio := 1.0
	for stage in range(stages):
		var driver := Graph.gear_by_stage_role(graph, stage, "DRIVER")
		var driven := Graph.gear_by_stage_role(graph, stage, "DRIVEN")
		if absf(float(driver.module_m) - float(driven.module_m)) > 1.0e-15:
			return U.failure("GEARBOX_REFERENCE_MESH_MODULE_MISMATCH", {"stage": stage})
		var ra := Physics.derive_gear(graph, driver, Graph.teeth_for_gear(graph, String(driver.gear_id)))
		if not ra.success:
			return ra
		var rb := Physics.derive_gear(graph, driven, Graph.teeth_for_gear(graph, String(driven.gear_id)))
		if not rb.success:
			return rb
		var a: Dictionary = ra.details.gear
		var b: Dictionary = rb.details.gear
		var stage_ratio := -float(a.tooth_count) / float(b.tooth_count)
		var driven_omega_ratio := driver_omega_ratio * stage_ratio
		total_ratio *= stage_ratio
		equivalent_input_inertia += float(a.inertia_kg_m2) * driver_omega_ratio * driver_omega_ratio
		equivalent_input_inertia += float(b.inertia_kg_m2) * driven_omega_ratio * driven_omega_ratio
		max_input_omega = minf(max_input_omega, float(a.max_abs_omega_rad_s) / absf(driver_omega_ratio))
		max_input_omega = minf(max_input_omega, float(b.max_abs_omega_rad_s) / absf(driven_omega_ratio))
		var mesh_force_limit := minf(float(a.tangential_force_limit_n), float(b.tangential_force_limit_n))
		max_input_torque = minf(max_input_torque, mesh_force_limit * absf(driver_omega_ratio) * float(a.pitch_radius_m))
		driver_omega_ratio = driven_omega_ratio
	if absf(input_omega_rad_s) > max_input_omega:
		return U.failure("GEARBOX_REFERENCE_SPEED_LIMIT")
	if absf(input_torque_nm) > max_input_torque:
		return U.failure("GEARBOX_REFERENCE_TORQUE_LIMIT")
	var output_omega := input_omega_rad_s * total_ratio
	var output_torque := input_torque_nm / total_ratio
	var input_energy := input_torque_nm * input_omega_rad_s * dt_s
	var output_energy := output_torque * output_omega * dt_s
	return U.success({
		"output_angular_velocity_rad_s": output_omega,
		"output_torque_nm": output_torque,
		"input_mechanical_energy_j": input_energy,
		"output_mechanical_energy_j": output_energy,
		"energy_residual_j": input_energy - output_energy,
		"equivalent_input_inertia_kg_m2": equivalent_input_inertia,
		"source_component_traversals": int(plan.source_component_count),
	})
