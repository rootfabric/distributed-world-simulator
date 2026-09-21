extends RefCounted
## Prepared T8 active cooling-loop runtime. Four thermal states are caller-owned.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/cooling_loop_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/cooling_loop_descriptor_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _material_catalog_hash := ""
var _interface_hash := ""
var _lane_count := 0
var _plate_capacity := 0.0
var _hot_capacity := 0.0
var _radiator_capacity := 0.0
var _cold_capacity := 0.0
var _plate_g := 0.0
var _radiator_g := 0.0
var _ambient_g := 0.0
var _coolant_cp := 0.0
var _coolant_density := 0.0
var _mu := 0.0
var _re_limit := 0.0
var _flow_area := 0.0
var _hydraulic_diameter := 0.0
var _flow_length := 0.0
var _max_total_flow := 0.0
var _min_temperature := 0.0
var _max_temperature := 0.0

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
	if String(capsule.executable_artifact_kind) != "COOLING_LOOP" or String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("COOLING_LOOP_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("COOLING_LOOP_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("COOLING_LOOP_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
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
	_lane_count = int(descriptor.lane_count)
	_plate_capacity = float(descriptor.plate_capacity_j_k)
	_hot_capacity = float(descriptor.hot_coolant_capacity_j_k)
	_radiator_capacity = float(descriptor.radiator_capacity_j_k)
	_cold_capacity = float(descriptor.cold_coolant_capacity_j_k)
	_plate_g = float(descriptor.plate_to_hot_conductance_w_k)
	_radiator_g = float(descriptor.cold_to_radiator_conductance_w_k)
	_ambient_g = float(descriptor.radiator_to_ambient_conductance_w_k)
	_coolant_cp = float(descriptor.coolant_heat_capacity_j_kg_k)
	_coolant_density = float(descriptor.coolant_density_kg_m3)
	_mu = float(descriptor.dynamic_viscosity_pa_s)
	_re_limit = float(descriptor.laminar_reynolds_limit)
	_flow_area = float(descriptor.channel_flow_area_m2)
	_hydraulic_diameter = float(descriptor.channel_hydraulic_diameter_m)
	_flow_length = float(descriptor.channel_flow_length_m)
	_max_total_flow = float(descriptor.max_total_mass_flow_kg_s)
	_min_temperature = float(descriptor.min_temperature_k)
	_max_temperature = float(descriptor.max_temperature_k)
	_ready = true
	return U.success({
		"capsule_id": _capsule_id,
		"state_scalar_count": 4,
		"runtime_source_thermal_node_traversals": 0,
	})

func initial_state(temperature_k: float) -> Dictionary:
	if not _ready or not U.is_positive_number(temperature_k) or temperature_k < _min_temperature or temperature_k > _max_temperature:
		return {}
	return {
		"plate_temperature_k": temperature_k,
		"hot_coolant_temperature_k": temperature_k,
		"radiator_temperature_k": temperature_k,
		"cold_coolant_temperature_k": temperature_k,
	}

func execute(
	live: Dictionary,
	state: Dictionary,
	heat_input_w: float,
	mass_flow_kg_s: float,
	ambient_temperature_k: float,
	dt_s: float
) -> Dictionary:
	if not _ready:
		return U.failure("COOLING_LOOP_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if not U.is_non_negative_number(heat_input_w) or not U.is_non_negative_number(mass_flow_kg_s) or not U.is_positive_number(ambient_temperature_k) or not U.is_positive_number(dt_s):
		return U.failure("COOLING_LOOP_RUNTIME_STEP_INVALID")
	if mass_flow_kg_s > _max_total_flow:
		return U.failure("COOLING_LOOP_RUNTIME_FLOW_LIMIT", {"mass_flow_kg_s": mass_flow_kg_s, "limit_kg_s": _max_total_flow})
	var state_check := _state_values(state)
	if not state_check.success:
		return state_check
	var p := float(state.plate_temperature_k)
	var h := float(state.hot_coolant_temperature_k)
	var r := float(state.radiator_temperature_k)
	var c := float(state.cold_coolant_temperature_k)
	var lane_flow := mass_flow_kg_s / float(_lane_count)
	var reynolds := _reynolds(lane_flow)
	if reynolds > _re_limit * (1.0 + 1.0e-12):
		return U.failure("COOLING_LOOP_RUNTIME_FLOW_REGIME_UNSUPPORTED", {"reynolds": reynolds, "limit": _re_limit})
	var pump_power := _hydraulic_power_total(lane_flow)
	var flow_g := mass_flow_kg_s * _coolant_cp
	var q_plate_hot := _plate_g * (p - h)
	var q_hot_cold := flow_g * (h - c)
	var q_cold_radiator := _radiator_g * (c - r)
	var q_ambient := _ambient_g * (r - ambient_temperature_k)
	var net_p := heat_input_w - q_plate_hot
	var net_h := q_plate_hot - q_hot_cold + 0.5 * pump_power
	var net_c := q_hot_cold - q_cold_radiator + 0.5 * pump_power
	var net_r := q_cold_radiator - q_ambient
	var next_p := p + net_p * dt_s / _plate_capacity
	var next_h := h + net_h * dt_s / _hot_capacity
	var next_c := c + net_c * dt_s / _cold_capacity
	var next_r := r + net_r * dt_s / _radiator_capacity
	for pair in [
		["plate", next_p], ["hot_coolant", next_h], ["cold_coolant", next_c], ["radiator", next_r]
	]:
		var t := float(pair[1])
		if not is_finite(t) or t < _min_temperature or t > _max_temperature:
			return U.failure("COOLING_LOOP_RUNTIME_NEXT_TEMPERATURE_OUT_OF_DOMAIN", {"node": String(pair[0]), "temperature_k": t})
	var state_delta := (
		_plate_capacity * (next_p - p)
		+ _hot_capacity * (next_h - h)
		+ _cold_capacity * (next_c - c)
		+ _radiator_capacity * (next_r - r)
	)
	var ambient_exchange_j := q_ambient * dt_s
	var pump_energy_j := pump_power * dt_s
	var residual := state_delta - heat_input_w * dt_s - pump_energy_j + ambient_exchange_j
	return U.success({
		"capsule_id": _capsule_id,
		"plate_temperature_k": next_p,
		"hot_coolant_temperature_k": next_h,
		"cold_coolant_temperature_k": next_c,
		"radiator_temperature_k": next_r,
		"ambient_exchange_j": ambient_exchange_j,
		"pump_hydraulic_energy_j": pump_energy_j,
		"state_energy_delta_j": state_delta,
		"energy_residual_j": residual,
		"reynolds_number": reynolds,
		"next_state": {
			"plate_temperature_k": next_p,
			"hot_coolant_temperature_k": next_h,
			"radiator_temperature_k": next_r,
			"cold_coolant_temperature_k": next_c,
		},
		"runtime_source_thermal_node_traversals": 0,
	})

func _state_values(state: Dictionary) -> Dictionary:
	for field in ["plate_temperature_k", "hot_coolant_temperature_k", "radiator_temperature_k", "cold_coolant_temperature_k"]:
		if not U.is_positive_number(state.get(field)):
			return U.failure("COOLING_LOOP_RUNTIME_STATE_INVALID", {"field": field})
		var t := float(state[field])
		if t < _min_temperature or t > _max_temperature:
			return U.failure("COOLING_LOOP_RUNTIME_TEMPERATURE_OUT_OF_DOMAIN", {"field": field})
	return U.success()

func _reynolds(lane_mass_flow: float) -> float:
	if lane_mass_flow <= 0.0:
		return 0.0
	return lane_mass_flow * _hydraulic_diameter / (_mu * _flow_area)

func _hydraulic_power_total(lane_mass_flow: float) -> float:
	if lane_mass_flow <= 0.0:
		return 0.0
	var q := lane_mass_flow / _coolant_density
	var velocity := q / _flow_area
	var dp := 32.0 * _mu * _flow_length * velocity / pow(_hydraulic_diameter, 2.0)
	return dp * q * float(_lane_count)

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("COOLING_LOOP_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("COOLING_LOOP_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("COOLING_LOOP_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("COOLING_LOOP_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("COOLING_LOOP_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("COOLING_LOOP_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != String(artifact.material_catalog_hash):
		return U.failure("COOLING_LOOP_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("COOLING_LOOP_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("COOLING_LOOP_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("COOLING_LOOP_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("COOLING_LOOP_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("COOLING_LOOP_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("COOLING_LOOP_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("COOLING_LOOP_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != _material_catalog_hash:
		return U.failure("COOLING_LOOP_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("COOLING_LOOP_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
