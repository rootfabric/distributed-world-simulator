extends RefCounted
## Prepared T4 thermal filter runtime. Persistent state is caller-owned.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/thermal_filter_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/thermal_filter_descriptor_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _material_catalog_hash := ""
var _interface_hash := ""
var _layer_count := 0
var _capacity := PackedFloat64Array()
var _links := PackedFloat64Array()
var _ambient_conductance := 0.0
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
	if String(capsule.executable_artifact_kind) != "THERMAL_FILTER" or String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("THERMAL_FILTER_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("THERMAL_FILTER_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("THERMAL_FILTER_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
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
	_layer_count = int(descriptor.layer_count)
	_capacity = _packed(descriptor.layer_capacity_j_k)
	_links = _packed(descriptor.layer_link_conductance_w_k)
	_ambient_conductance = float(descriptor.ambient_conductance_w_k)
	_min_temperature = float(descriptor.min_temperature_k)
	_max_temperature = float(descriptor.max_temperature_k)
	_ready = true
	return U.success({
		"capsule_id": _capsule_id,
		"layer_count": _layer_count,
		"state_scalar_count": _layer_count,
		"runtime_source_cell_traversals": 0,
	})

func initial_state(temperature_k: float) -> Dictionary:
	if not _ready or temperature_k < _min_temperature or temperature_k > _max_temperature:
		return {}
	var values: Array = []
	for _index in range(_layer_count):
		values.append(temperature_k)
	return {"layer_temperature_k": values}

func execute(live: Dictionary, state: Dictionary, heat_input_w: float, dt_s: float, ambient_temperature_k: float) -> Dictionary:
	if not _ready:
		return U.failure("THERMAL_FILTER_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if not U.is_non_negative_number(heat_input_w) or not U.is_positive_number(dt_s) or not U.is_positive_number(ambient_temperature_k):
		return U.failure("THERMAL_FILTER_RUNTIME_STEP_INVALID")
	if typeof(state.get("layer_temperature_k")) != TYPE_ARRAY or state.layer_temperature_k.size() != _layer_count:
		return U.failure("THERMAL_FILTER_RUNTIME_STATE_INVALID")
	var temperatures: Array = []
	for raw in state.layer_temperature_k:
		if not U.is_positive_number(raw):
			return U.failure("THERMAL_FILTER_RUNTIME_STATE_INVALID")
		var t := float(raw)
		if t < _min_temperature or t > _max_temperature:
			return U.failure("THERMAL_FILTER_RUNTIME_TEMPERATURE_OUT_OF_DOMAIN")
		temperatures.append(t)
	var net_power: Array = []
	net_power.resize(_layer_count)
	for i in range(_layer_count):
		net_power[i] = 0.0
	net_power[0] = float(net_power[0]) + heat_input_w
	for i in range(_layer_count - 1):
		var flow := float(_links[i]) * (float(temperatures[i]) - float(temperatures[i + 1]))
		net_power[i] = float(net_power[i]) - flow
		net_power[i + 1] = float(net_power[i + 1]) + flow
	var ambient_exchange_w := _ambient_conductance * (float(temperatures[_layer_count - 1]) - ambient_temperature_k)
	net_power[_layer_count - 1] = float(net_power[_layer_count - 1]) - ambient_exchange_w

	var next_temperatures: Array = []
	var state_energy_delta := 0.0
	for i in range(_layer_count):
		var next_t := float(temperatures[i]) + float(net_power[i]) * dt_s / float(_capacity[i])
		if next_t < _min_temperature or next_t > _max_temperature:
			return U.failure("THERMAL_FILTER_RUNTIME_NEXT_TEMPERATURE_OUT_OF_DOMAIN", {"layer": i, "temperature_k": next_t})
		next_temperatures.append(next_t)
		state_energy_delta += float(_capacity[i]) * (next_t - float(temperatures[i]))
	var input_energy := heat_input_w * dt_s
	var ambient_exchange_j := ambient_exchange_w * dt_s
	var residual := state_energy_delta - input_energy + ambient_exchange_j
	return U.success({
		"capsule_id": _capsule_id,
		"output_temperature_k": float(next_temperatures[_layer_count - 1]),
		"ambient_exchange_j": ambient_exchange_j,
		"state_energy_delta_j": state_energy_delta,
		"energy_residual_j": residual,
		"next_state": {"layer_temperature_k": next_temperatures},
		"runtime_source_cell_traversals": 0,
		"compiled_layer_traversals": _layer_count,
	})

func _packed(values: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(values.size())
	for index in range(values.size()):
		out[index] = float(values[index])
	return out

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("THERMAL_FILTER_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("THERMAL_FILTER_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("THERMAL_FILTER_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("THERMAL_FILTER_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("THERMAL_FILTER_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("THERMAL_FILTER_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != String(artifact.material_catalog_hash):
		return U.failure("THERMAL_FILTER_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("THERMAL_FILTER_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("THERMAL_FILTER_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("THERMAL_FILTER_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("THERMAL_FILTER_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("THERMAL_FILTER_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("THERMAL_FILTER_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("THERMAL_FILTER_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != _material_catalog_hash:
		return U.failure("THERMAL_FILTER_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("THERMAL_FILTER_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
