extends RefCounted
## Detailed T5 reference. Traverses every winding and rotor source row per execute.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/motor_generator_graph_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/motor_generator_physics_v1.gd")

static func prepare(graph: Dictionary) -> Dictionary:
	var checked := Graph.validate(graph)
	if not checked.success:
		return checked
	var windings: Array = []
	var rotors: Array = []
	var max_current := INF
	var max_omega := INF
	for winding in graph.winding_segments:
		if not bool(winding.enabled):
			return U.failure("MOTOR_WINDING_OPEN", {"winding_id": winding.winding_id})
		var derived := Physics.derive_winding(graph, winding)
		if not derived.success:
			return derived
		windings.append(derived.details.winding)
		max_current = minf(max_current, float(derived.details.winding.max_current_a))
	for sector in graph.rotor_sectors:
		if not bool(sector.enabled):
			return U.failure("MOTOR_ROTOR_INCOMPLETE", {"sector_id": sector.sector_id})
		var derived := Physics.derive_rotor_sector(graph, sector)
		if not derived.success:
			return derived
		rotors.append(derived.details.sector)
		max_omega = minf(max_omega, float(derived.details.sector.max_abs_angular_velocity_rad_s))
	return U.success({
		"graph_hash": graph.graph_hash,
		"winding_rows": windings,
		"rotor_rows": rotors,
		"max_abs_current_a": max_current,
		"max_abs_angular_velocity_rad_s": max_omega,
	})

static func initial_state(plan: Dictionary, angular_velocity_rad_s: float) -> Dictionary:
	if not U.is_finite_number(angular_velocity_rad_s) or absf(angular_velocity_rad_s) > float(plan.max_abs_angular_velocity_rad_s):
		return {}
	return {"angular_velocity_rad_s": angular_velocity_rad_s}

static func execute(plan: Dictionary, state: Dictionary, current_a: float, external_shaft_torque_nm: float, dt_s: float) -> Dictionary:
	if not U.is_finite_number(current_a) or absf(current_a) > float(plan.max_abs_current_a):
		return U.failure("MOTOR_REFERENCE_CURRENT_LIMIT")
	if not U.is_finite_number(external_shaft_torque_nm) or not U.is_positive_number(dt_s):
		return U.failure("MOTOR_REFERENCE_STEP_INVALID")
	if not U.is_finite_number(state.get("angular_velocity_rad_s")):
		return U.failure("MOTOR_REFERENCE_STATE_INVALID")
	var omega := float(state.angular_velocity_rad_s)
	if absf(omega) > float(plan.max_abs_angular_velocity_rad_s):
		return U.failure("MOTOR_REFERENCE_SPEED_OUT_OF_DOMAIN")

	var total_resistance := 0.0
	var total_k := 0.0
	var winding_traversals := 0
	for row in plan.winding_rows:
		total_resistance += float(row.resistance_ohm)
		total_k += float(row.torque_constant_nm_a)
		winding_traversals += 1
	var inertia := 0.0
	var rotor_traversals := 0
	for row in plan.rotor_rows:
		inertia += float(row.inertia_kg_m2)
		rotor_traversals += 1

	var electromagnetic_torque := total_k * current_a
	var net_torque := electromagnetic_torque + external_shaft_torque_nm
	var next_omega := omega + net_torque * dt_s / inertia
	if not is_finite(next_omega) or absf(next_omega) > float(plan.max_abs_angular_velocity_rad_s):
		return U.failure("MOTOR_REFERENCE_NEXT_SPEED_OUT_OF_DOMAIN")
	var midpoint_omega := 0.5 * (omega + next_omega)
	var terminal_voltage := current_a * total_resistance + total_k * midpoint_omega
	var electrical_energy := terminal_voltage * current_a * dt_s
	var resistive_heat := current_a * current_a * total_resistance * dt_s
	var electromagnetic_mechanical_energy := electromagnetic_torque * midpoint_omega * dt_s
	var shaft_boundary_energy := external_shaft_torque_nm * midpoint_omega * dt_s
	var kinetic_energy_delta := 0.5 * inertia * (next_omega * next_omega - omega * omega)
	return U.success({
		"terminal_voltage_v": terminal_voltage,
		"electromagnetic_torque_nm": electromagnetic_torque,
		"electrical_energy_j": electrical_energy,
		"resistive_heat_j": resistive_heat,
		"electromagnetic_mechanical_energy_j": electromagnetic_mechanical_energy,
		"shaft_boundary_energy_j": shaft_boundary_energy,
		"kinetic_energy_delta_j": kinetic_energy_delta,
		"electrical_energy_residual_j": electrical_energy - resistive_heat - electromagnetic_mechanical_energy,
		"total_energy_residual_j": electrical_energy + shaft_boundary_energy - resistive_heat - kinetic_energy_delta,
		"next_state": {"angular_velocity_rad_s": next_omega},
		"source_component_traversals": winding_traversals + rotor_traversals,
	})
