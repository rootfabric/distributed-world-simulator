extends RefCounted
## Prepared T9 laser-emitter runtime.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/laser_emitter_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/laser_emitter_descriptor_v1.gd")
const Physics = preload("res://scripts/research/fabric_bake0/laser_emitter_physics_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _material_catalog_hash := ""
var _interface_hash := ""
var _active_count := 0
var _row := {}
var _total_max_current := 0.0
var _wavelength := 0.0
var _divergence := 0.0

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
	if String(capsule.executable_artifact_kind) != "LASER_EMITTER" or String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("LASER_EMITTER_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("LASER_EMITTER_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("LASER_EMITTER_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
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
	_active_count = int(descriptor.active_cell_count)
	_total_max_current = float(descriptor.total_max_current_a)
	_wavelength = float(descriptor.wavelength_m)
	_divergence = float(descriptor.beam_divergence_half_angle_rad)
	_row = {
		"resistance_ref_ohm": float(descriptor.per_cell_resistance_ref_ohm),
		"threshold_current_a": float(descriptor.per_cell_threshold_current_a),
		"max_current_a": float(descriptor.per_cell_max_current_a),
		"forward_voltage_v": float(descriptor.forward_voltage_v),
		"reference_optical_efficiency_ratio": float(descriptor.reference_optical_efficiency_ratio),
		"efficiency_temp_coefficient_per_k": float(descriptor.efficiency_temp_coefficient_per_k),
		"reference_temperature_k": float(descriptor.reference_temperature_k),
		"min_temperature_k": float(descriptor.min_temperature_k),
		"max_temperature_k": float(descriptor.max_temperature_k),
		"wavelength_m": float(descriptor.wavelength_m),
	}
	_ready = true
	return U.success({"capsule_id": _capsule_id, "runtime_source_cell_traversals": 0})

func execute(live: Dictionary, current_a: float, junction_temperature_k: float, dt_s: float) -> Dictionary:
	if not _ready:
		return U.failure("LASER_EMITTER_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if not U.is_non_negative_number(current_a) or not U.is_positive_number(junction_temperature_k) or not U.is_positive_number(dt_s):
		return U.failure("LASER_EMITTER_RUNTIME_STEP_INVALID")
	if current_a > _total_max_current:
		return U.failure("LASER_EMITTER_RUNTIME_CURRENT_LIMIT", {"current_a": current_a, "limit_a": _total_max_current})
	var per_cell_current := current_a / float(_active_count)
	var one := Physics.evaluate_cell(_row, per_cell_current, junction_temperature_k, dt_s)
	if not one.success:
		return one
	var electrical_energy := float(one.details.electrical_energy_j) * float(_active_count)
	var optical_energy := float(one.details.optical_energy_j) * float(_active_count)
	var heat_energy := float(one.details.waste_heat_j) * float(_active_count)
	var photon_count := float(one.details.photon_count) * float(_active_count)
	return U.success({
		"capsule_id": _capsule_id,
		"terminal_voltage_v": float(one.details.terminal_voltage_v),
		"electrical_energy_j": electrical_energy,
		"optical_energy_j": optical_energy,
		"waste_heat_j": heat_energy,
		"photon_count": photon_count,
		"wavelength_m": _wavelength,
		"beam_divergence_half_angle_rad": _divergence,
		"energy_residual_j": electrical_energy - optical_energy - heat_energy,
		"runtime_source_cell_traversals": 0,
	})

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("LASER_EMITTER_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("LASER_EMITTER_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("LASER_EMITTER_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("LASER_EMITTER_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("LASER_EMITTER_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("LASER_EMITTER_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != String(artifact.material_catalog_hash):
		return U.failure("LASER_EMITTER_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("LASER_EMITTER_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("LASER_EMITTER_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("LASER_EMITTER_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("LASER_EMITTER_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("LASER_EMITTER_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("LASER_EMITTER_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("LASER_EMITTER_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != _material_catalog_hash:
		return U.failure("LASER_EMITTER_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("LASER_EMITTER_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
