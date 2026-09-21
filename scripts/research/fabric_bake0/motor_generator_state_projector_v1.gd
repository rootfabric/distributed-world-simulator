extends RefCounted
## Conservative T5 state reconstruction across derived-coefficient mutations.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/motor_generator_descriptor_v1.gd")

const REL_TOL := 1.0e-12

static func project(old_descriptor: Dictionary, new_descriptor: Dictionary, old_state: Dictionary) -> Dictionary:
	var checked := Descriptor.validate(old_descriptor)
	if not checked.success:
		return checked
	checked = Descriptor.validate(new_descriptor)
	if not checked.success:
		return checked
	if not U.is_finite_number(old_state.get("angular_velocity_rad_s")):
		return U.failure("MOTOR_STATE_PROJECTOR_STATE_INVALID")
	var omega := float(old_state.angular_velocity_rad_s)
	if absf(omega) > float(old_descriptor.max_abs_angular_velocity_rad_s):
		return U.failure("MOTOR_STATE_PROJECTOR_OLD_SPEED_OUT_OF_DOMAIN")
	var old_inertia := float(old_descriptor.rotor_inertia_kg_m2)
	var new_inertia := float(new_descriptor.rotor_inertia_kg_m2)
	var scale := maxf(1.0e-18, maxf(absf(old_inertia), absf(new_inertia)))
	if absf(old_inertia - new_inertia) > REL_TOL * scale:
		return U.failure("MOTOR_STATE_RECONSTRUCTION_INERTIA_CHANGE_UNSUPPORTED", {
			"old_inertia_kg_m2": old_inertia,
			"new_inertia_kg_m2": new_inertia,
		})
	if absf(omega) > float(new_descriptor.max_abs_angular_velocity_rad_s):
		return U.failure("MOTOR_STATE_PROJECTOR_NEW_SPEED_OUT_OF_DOMAIN")
	return U.success({
		"projection_kind": "COEFFICIENT_CHANGE_SAME_ROTOR_INERTIA",
		"next_state": {"angular_velocity_rad_s": omega},
		"angular_momentum_before_kg_m2_rad_s": old_inertia * omega,
		"angular_momentum_after_kg_m2_rad_s": new_inertia * omega,
		"kinetic_energy_before_j": 0.5 * old_inertia * omega * omega,
		"kinetic_energy_after_j": 0.5 * new_inertia * omega * omega,
	})
