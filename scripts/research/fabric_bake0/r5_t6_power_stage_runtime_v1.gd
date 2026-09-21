extends RefCounted
## Prepared stateless T6 H-bridge runtime.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/power_stage_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/power_stage_descriptor_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _material_catalog_hash := ""
var _interface_hash := ""
var _positive_r := 0.0
var _negative_r := 0.0
var _positive_current := 0.0
var _negative_current := 0.0
var _positive_transition := 0.0
var _negative_transition := 0.0
var _alpha := 0.0
var _reference_t := 0.0
var _min_t := 0.0
var _max_t := 0.0
var _max_bus_voltage := 0.0

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
	if String(capsule.executable_artifact_kind) != "POWER_STAGE" or String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("POWER_STAGE_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("POWER_STAGE_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("POWER_STAGE_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
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
	_positive_r = float(descriptor.positive_path_resistance_ref_ohm)
	_negative_r = float(descriptor.negative_path_resistance_ref_ohm)
	_positive_current = float(descriptor.positive_path_max_abs_current_a)
	_negative_current = float(descriptor.negative_path_max_abs_current_a)
	_positive_transition = float(descriptor.positive_path_transition_time_s)
	_negative_transition = float(descriptor.negative_path_transition_time_s)
	_alpha = float(descriptor.resistance_temp_coefficient_per_k)
	_reference_t = float(descriptor.reference_temperature_k)
	_min_t = float(descriptor.min_temperature_k)
	_max_t = float(descriptor.max_temperature_k)
	_max_bus_voltage = float(descriptor.max_bus_voltage_v)
	_ready = true
	return U.success({"capsule_id": _capsule_id, "runtime_source_die_traversals": 0})

func execute(
	live: Dictionary,
	bus_voltage_v: float,
	duty_ratio: float,
	load_current_a: float,
	pwm_frequency_hz: float,
	junction_temperature_k: float,
	dt_s: float
) -> Dictionary:
	if not _ready:
		return U.failure("POWER_STAGE_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if not U.is_positive_number(bus_voltage_v) or bus_voltage_v > _max_bus_voltage:
		return U.failure("POWER_STAGE_RUNTIME_BUS_VOLTAGE_LIMIT", {"bus_voltage_v": bus_voltage_v, "limit_v": _max_bus_voltage})
	if not U.is_finite_number(duty_ratio) or absf(duty_ratio) > 1.0:
		return U.failure("POWER_STAGE_RUNTIME_DUTY_INVALID")
	if not U.is_finite_number(load_current_a) or not U.is_non_negative_number(pwm_frequency_hz) or not U.is_positive_number(dt_s):
		return U.failure("POWER_STAGE_RUNTIME_STEP_INVALID")
	if not U.is_positive_number(junction_temperature_k) or junction_temperature_k < _min_t or junction_temperature_k > _max_t:
		return U.failure("POWER_STAGE_RUNTIME_TEMPERATURE_OUT_OF_DOMAIN")
	var positive_path := duty_ratio >= 0.0
	var path_r_ref := _positive_r if positive_path else _negative_r
	var current_limit := _positive_current if positive_path else _negative_current
	var transition_time := _positive_transition if positive_path else _negative_transition
	if absf(load_current_a) > current_limit:
		return U.failure("POWER_STAGE_RUNTIME_CURRENT_LIMIT", {"current_a": load_current_a, "limit_a": current_limit})
	var factor := 1.0 + _alpha * (junction_temperature_k - _reference_t)
	var path_r := path_r_ref * maxf(factor, 0.05)
	var switching_activity := 1.0 - absf(duty_ratio)
	var load_voltage := duty_ratio * bus_voltage_v - load_current_a * path_r
	var conduction_heat := load_current_a * load_current_a * path_r * dt_s
	var switching_heat := bus_voltage_v * absf(load_current_a) * pwm_frequency_hz * transition_time * switching_activity * dt_s
	var output_energy := load_voltage * load_current_a * dt_s
	var input_energy := output_energy + conduction_heat + switching_heat
	var bus_current := input_energy / (bus_voltage_v * dt_s)
	var residual := input_energy - output_energy - conduction_heat - switching_heat
	return U.success({
		"capsule_id": _capsule_id,
		"load_voltage_v": load_voltage,
		"bus_current_a": bus_current,
		"electrical_input_energy_j": input_energy,
		"electrical_output_energy_j": output_energy,
		"conduction_heat_j": conduction_heat,
		"switching_heat_j": switching_heat,
		"energy_residual_j": residual,
		"runtime_source_die_traversals": 0,
	})

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("POWER_STAGE_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("POWER_STAGE_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("POWER_STAGE_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("POWER_STAGE_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("POWER_STAGE_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("POWER_STAGE_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != String(artifact.material_catalog_hash):
		return U.failure("POWER_STAGE_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("POWER_STAGE_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("POWER_STAGE_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("POWER_STAGE_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("POWER_STAGE_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("POWER_STAGE_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("POWER_STAGE_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("POWER_STAGE_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != _material_catalog_hash:
		return U.failure("POWER_STAGE_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("POWER_STAGE_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
