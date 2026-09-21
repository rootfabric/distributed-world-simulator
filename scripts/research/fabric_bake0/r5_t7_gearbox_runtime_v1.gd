extends RefCounted
## Prepared T7 rigid gearbox runtime.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/gearbox_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/gearbox_descriptor_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _material_catalog_hash := ""
var _interface_hash := ""
var _ratio := 0.0
var _max_input_torque := 0.0
var _max_input_omega := 0.0
var _equivalent_input_inertia := 0.0

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
	if String(capsule.executable_artifact_kind) != "GEARBOX" or String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("GEARBOX_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("GEARBOX_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("GEARBOX_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
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
	_ratio = float(descriptor.total_speed_ratio)
	_max_input_torque = float(descriptor.max_abs_input_torque_nm)
	_max_input_omega = float(descriptor.max_abs_input_omega_rad_s)
	_equivalent_input_inertia = float(descriptor.equivalent_input_inertia_kg_m2)
	_ready = true
	return U.success({"capsule_id": _capsule_id, "runtime_source_component_traversals": 0})

func execute(live: Dictionary, input_omega_rad_s: float, input_torque_nm: float, dt_s: float) -> Dictionary:
	if not _ready:
		return U.failure("GEARBOX_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if not U.is_finite_number(input_omega_rad_s) or not U.is_finite_number(input_torque_nm) or not U.is_positive_number(dt_s):
		return U.failure("GEARBOX_RUNTIME_STEP_INVALID")
	if absf(input_omega_rad_s) > _max_input_omega:
		return U.failure("GEARBOX_RUNTIME_SPEED_LIMIT", {"omega_rad_s": input_omega_rad_s, "limit": _max_input_omega})
	if absf(input_torque_nm) > _max_input_torque:
		return U.failure("GEARBOX_RUNTIME_TORQUE_LIMIT", {"torque_nm": input_torque_nm, "limit": _max_input_torque})
	var output_omega := input_omega_rad_s * _ratio
	var output_torque := input_torque_nm / _ratio
	var input_energy := input_torque_nm * input_omega_rad_s * dt_s
	var output_energy := output_torque * output_omega * dt_s
	return U.success({
		"capsule_id": _capsule_id,
		"output_angular_velocity_rad_s": output_omega,
		"output_torque_nm": output_torque,
		"input_mechanical_energy_j": input_energy,
		"output_mechanical_energy_j": output_energy,
		"energy_residual_j": input_energy - output_energy,
		"equivalent_input_inertia_kg_m2": _equivalent_input_inertia,
		"runtime_source_component_traversals": 0,
	})

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("GEARBOX_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("GEARBOX_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("GEARBOX_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("GEARBOX_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("GEARBOX_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("GEARBOX_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != String(artifact.material_catalog_hash):
		return U.failure("GEARBOX_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("GEARBOX_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("GEARBOX_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("GEARBOX_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("GEARBOX_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("GEARBOX_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("GEARBOX_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("GEARBOX_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != _material_catalog_hash:
		return U.failure("GEARBOX_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("GEARBOX_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
