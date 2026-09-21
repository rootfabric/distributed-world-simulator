extends RefCounted
## Prepared T5 motor/generator runtime. Angular velocity is caller-owned state.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/motor_generator_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/motor_generator_descriptor_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _material_catalog_hash := ""
var _interface_hash := ""
var _resistance := 0.0
var _k := 0.0
var _max_current := 0.0
var _inertia := 0.0
var _max_omega := 0.0

func prepare(capsule: Dictionary, artifact: Dictionary, descriptor: Dictionary, live: Dictionary) -> Dictionary:
	_ready = false
	var checked := Capsule.validate(capsule)
	if not checked.success:
		return checked
	checked = Artifact.verify_descriptor(artifact, descriptor)
	if not checked.success:
		return checked
	checked = Descriptor.validate(descriptor)
	if not checked.success:
		return checked
	if String(capsule.executable_artifact_kind) != "MOTOR_GENERATOR" or String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("MOTOR_GENERATOR_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("MOTOR_GENERATOR_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("MOTOR_GENERATOR_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
	checked = _full_live_gate(artifact, live)
	if not checked.success:
		return checked
	_capsule_id = String(capsule.capsule_id)
	_frontier_hash = String(artifact.canonical_source_frontier.frontier_hash)
	_authority_checksum = String(artifact.authority_envelope.checksum)
	_dependency_hash = String(artifact.dependency_set.dependency_hash)
	_graph_hash = String(artifact.graph_hash)
	_material_catalog_hash = String(artifact.material_catalog_hash)
	_interface_hash = String(artifact.interface_contract.interface_hash)
	_resistance = float(descriptor.total_resistance_ohm)
	_k = float(descriptor.torque_constant_nm_a)
	_max_current = float(descriptor.max_abs_current_a)
	_inertia = float(descriptor.rotor_inertia_kg_m2)
	_max_omega = float(descriptor.max_abs_angular_velocity_rad_s)
	_ready = true
	return U.success({
		"capsule_id": _capsule_id,
		"state_scalar_count": 1,
		"runtime_source_component_traversals": 0,
	})

func initial_state(angular_velocity_rad_s: float) -> Dictionary:
	if not _ready or not U.is_finite_number(angular_velocity_rad_s) or absf(angular_velocity_rad_s) > _max_omega:
		return {}
	return {"angular_velocity_rad_s": angular_velocity_rad_s}

func execute(live: Dictionary, state: Dictionary, current_a: float, external_shaft_torque_nm: float, dt_s: float) -> Dictionary:
	if not _ready:
		return U.failure("MOTOR_GENERATOR_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if not U.is_finite_number(current_a) or absf(current_a) > _max_current:
		return U.failure("MOTOR_GENERATOR_RUNTIME_CURRENT_LIMIT", {"current_a": current_a, "limit_a": _max_current})
	if not U.is_finite_number(external_shaft_torque_nm) or not U.is_positive_number(dt_s):
		return U.failure("MOTOR_GENERATOR_RUNTIME_STEP_INVALID")
	if not U.is_finite_number(state.get("angular_velocity_rad_s")):
		return U.failure("MOTOR_GENERATOR_RUNTIME_STATE_INVALID")
	var omega := float(state.angular_velocity_rad_s)
	if absf(omega) > _max_omega:
		return U.failure("MOTOR_GENERATOR_RUNTIME_SPEED_OUT_OF_DOMAIN")
	var electromagnetic_torque := _k * current_a
	var net_torque := electromagnetic_torque + external_shaft_torque_nm
	var next_omega := omega + net_torque * dt_s / _inertia
	if not is_finite(next_omega) or absf(next_omega) > _max_omega:
		return U.failure("MOTOR_GENERATOR_RUNTIME_NEXT_SPEED_OUT_OF_DOMAIN", {"angular_velocity_rad_s": next_omega})
	var midpoint_omega := 0.5 * (omega + next_omega)
	var terminal_voltage := current_a * _resistance + _k * midpoint_omega
	var electrical_energy := terminal_voltage * current_a * dt_s
	var resistive_heat := current_a * current_a * _resistance * dt_s
	var electromagnetic_mechanical_energy := electromagnetic_torque * midpoint_omega * dt_s
	var shaft_boundary_energy := external_shaft_torque_nm * midpoint_omega * dt_s
	var kinetic_energy_delta := 0.5 * _inertia * (next_omega * next_omega - omega * omega)
	var electrical_residual := electrical_energy - resistive_heat - electromagnetic_mechanical_energy
	var total_residual := electrical_energy + shaft_boundary_energy - resistive_heat - kinetic_energy_delta
	return U.success({
		"capsule_id": _capsule_id,
		"terminal_voltage_v": terminal_voltage,
		"electromagnetic_torque_nm": electromagnetic_torque,
		"electrical_energy_j": electrical_energy,
		"resistive_heat_j": resistive_heat,
		"electromagnetic_mechanical_energy_j": electromagnetic_mechanical_energy,
		"shaft_boundary_energy_j": shaft_boundary_energy,
		"kinetic_energy_delta_j": kinetic_energy_delta,
		"electrical_energy_residual_j": electrical_residual,
		"total_energy_residual_j": total_residual,
		"next_state": {"angular_velocity_rad_s": next_omega},
		"runtime_source_component_traversals": 0,
	})

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("MOTOR_GENERATOR_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("MOTOR_GENERATOR_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("MOTOR_GENERATOR_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("MOTOR_GENERATOR_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("MOTOR_GENERATOR_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("MOTOR_GENERATOR_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != String(artifact.material_catalog_hash):
		return U.failure("MOTOR_GENERATOR_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("MOTOR_GENERATOR_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("MOTOR_GENERATOR_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("MOTOR_GENERATOR_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("MOTOR_GENERATOR_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("MOTOR_GENERATOR_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("MOTOR_GENERATOR_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("MOTOR_GENERATOR_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != _material_catalog_hash:
		return U.failure("MOTOR_GENERATOR_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("MOTOR_GENERATOR_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
