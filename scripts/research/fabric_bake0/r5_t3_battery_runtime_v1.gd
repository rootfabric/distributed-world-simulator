extends RefCounted
## Prepared T3 battery runtime. State is caller-owned and explicit.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/battery_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/battery_pack_descriptor_v1.gd")
const CellPhysics = preload("res://scripts/research/fabric_bake0/battery_cell_physics_v1.gd")

var _ready := false
var _capsule_id := ""
var _frontier_hash := ""
var _authority_checksum := ""
var _dependency_hash := ""
var _graph_hash := ""
var _material_catalog_hash := ""
var _interface_hash := ""
var _series_count := 0
var _capacity := PackedFloat64Array()
var _resistance_ref := PackedFloat64Array()
var _empty_v := PackedFloat64Array()
var _full_v := PackedFloat64Array()
var _max_current := PackedFloat64Array()
var _alpha := PackedFloat64Array()
var _reference_t := PackedFloat64Array()
var _thermal_capacity := 0.0
var _thermal_conductance := 0.0
var _min_temperature := 0.0
var _max_temperature := 0.0
var _pack_max_current := 0.0

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
	if String(capsule.executable_artifact_kind) != "BATTERY_PACK" or String(capsule.executable_artifact_checksum) != String(artifact.checksum):
		return U.failure("BATTERY_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash) != String(descriptor.checksum):
		return U.failure("BATTERY_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute) != 0:
		return U.failure("BATTERY_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
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
	_series_count = int(descriptor.series_group_count)
	_capacity = _packed(descriptor.group_capacity_c)
	_resistance_ref = _packed(descriptor.group_resistance_ref_ohm)
	_empty_v = _packed(descriptor.group_empty_voltage_v)
	_full_v = _packed(descriptor.group_full_voltage_v)
	_max_current = _packed(descriptor.group_max_current_a)
	_alpha = _packed(descriptor.group_resistance_temp_coefficient_per_k)
	_reference_t = _packed(descriptor.group_reference_temperature_k)
	_thermal_capacity = float(descriptor.thermal_capacity_j_k)
	_thermal_conductance = float(descriptor.thermal_conductance_w_k)
	_min_temperature = float(descriptor.min_temperature_k)
	_max_temperature = float(descriptor.max_temperature_k)
	_pack_max_current = float(descriptor.max_continuous_current_a)
	_ready = true
	return U.success({
		"capsule_id": _capsule_id,
		"series_group_count": _series_count,
		"state_scalar_count": _series_count + 1,
		"runtime_source_cell_traversals": 0,
	})

func initial_state(soc: float, temperature_k: float) -> Dictionary:
	if not _ready or soc < 0.0 or soc > 1.0 or temperature_k < _min_temperature or temperature_k > _max_temperature:
		return {}
	var charges: Array = []
	for index in range(_series_count):
		charges.append(float(_capacity[index]) * soc)
	return {"group_charge_c": charges, "temperature_k": temperature_k}

func execute(live: Dictionary, state: Dictionary, current_a: float, dt_s: float, ambient_temperature_k: float) -> Dictionary:
	if not _ready:
		return U.failure("BATTERY_RUNTIME_NOT_READY")
	var checked := _fast_live_gate(live)
	if not checked.success:
		return checked
	if not is_finite(current_a) or absf(current_a) > _pack_max_current:
		return U.failure("BATTERY_RUNTIME_CURRENT_LIMIT", {"current_a": current_a, "limit_a": _pack_max_current})
	if not U.is_positive_number(dt_s) or not U.is_positive_number(ambient_temperature_k):
		return U.failure("BATTERY_RUNTIME_STEP_INVALID")
	if typeof(state.get("group_charge_c")) != TYPE_ARRAY or state.group_charge_c.size() != _series_count or not U.is_positive_number(state.get("temperature_k")):
		return U.failure("BATTERY_RUNTIME_STATE_INVALID")
	var temperature := float(state.temperature_k)
	if temperature < _min_temperature or temperature > _max_temperature:
		return U.failure("BATTERY_RUNTIME_TEMPERATURE_OUT_OF_DOMAIN")
	var next_charges: Array = []
	var terminal_voltage := 0.0
	var heat_j := 0.0
	var chemical_delta_j := 0.0
	for index in range(_series_count):
		var capacity := float(_capacity[index])
		var old_charge := float(state.group_charge_c[index])
		var next_charge := old_charge - current_a * dt_s
		if old_charge < -1.0e-9 or old_charge > capacity + 1.0e-9 or next_charge < -1.0e-9 or next_charge > capacity + 1.0e-9:
			return U.failure("BATTERY_RUNTIME_CHARGE_OUT_OF_DOMAIN", {"series_index": index, "old_charge_c": old_charge, "next_charge_c": next_charge, "capacity_c": capacity})
		var midpoint_charge := 0.5 * (old_charge + next_charge)
		var soc_mid := midpoint_charge / capacity
		var ocv := float(_empty_v[index]) + (float(_full_v[index]) - float(_empty_v[index])) * clampf(soc_mid, 0.0, 1.0)
		var factor := 1.0 + float(_alpha[index]) * (temperature - float(_reference_t[index]))
		var resistance := float(_resistance_ref[index]) * maxf(factor, 0.05)
		terminal_voltage += ocv - current_a * resistance
		heat_j += current_a * current_a * resistance * dt_s
		chemical_delta_j += CellPhysics.chemical_energy_j(capacity, old_charge, float(_empty_v[index]), float(_full_v[index]))
		chemical_delta_j -= CellPhysics.chemical_energy_j(capacity, next_charge, float(_empty_v[index]), float(_full_v[index]))
		next_charges.append(clampf(next_charge, 0.0, capacity))
	var electrical_energy_j := terminal_voltage * current_a * dt_s
	var passive_heat_removed_j := _thermal_conductance * (temperature - ambient_temperature_k) * dt_s
	var next_temperature := temperature + (heat_j - passive_heat_removed_j) / _thermal_capacity
	if next_temperature < _min_temperature or next_temperature > _max_temperature:
		return U.failure("BATTERY_RUNTIME_NEXT_TEMPERATURE_OUT_OF_DOMAIN", {"temperature_k": next_temperature})
	return U.success({
		"capsule_id": _capsule_id,
		"terminal_voltage_v": terminal_voltage,
		"heat_generated_j": heat_j,
		"passive_heat_removed_j": passive_heat_removed_j,
		"electrical_energy_j": electrical_energy_j,
		"chemical_energy_delta_j": chemical_delta_j,
		"energy_residual_j": chemical_delta_j - electrical_energy_j - heat_j,
		"next_state": {"group_charge_c": next_charges, "temperature_k": next_temperature},
		"runtime_source_cell_traversals": 0,
		"compiled_group_traversals": _series_count,
	})

func _packed(values: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(values.size())
	for index in range(values.size()):
		out[index] = float(values[index])
	return out

func _full_live_gate(artifact: Dictionary, live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("BATTERY_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("BATTERY_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != String(artifact.canonical_source_frontier.frontier_hash):
		return U.failure("BATTERY_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != String(artifact.authority_envelope.checksum):
		return U.failure("BATTERY_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != String(artifact.dependency_set.dependency_hash):
		return U.failure("BATTERY_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != String(artifact.graph_hash):
		return U.failure("BATTERY_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != String(artifact.material_catalog_hash):
		return U.failure("BATTERY_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != String(artifact.interface_contract.interface_hash):
		return U.failure("BATTERY_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live: Dictionary) -> Dictionary:
	if String(live.get("artifact_state", "")) != "READY":
		return U.failure("BATTERY_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations")) != TYPE_ARRAY or not live.invalidations.is_empty():
		return U.failure("BATTERY_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier")) != TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash", "")) != _frontier_hash:
		return U.failure("BATTERY_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope")) != TYPE_DICTIONARY or String(live.authority_envelope.get("checksum", "")) != _authority_checksum:
		return U.failure("BATTERY_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set")) != TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash", "")) != _dependency_hash:
		return U.failure("BATTERY_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash", "")) != _graph_hash:
		return U.failure("BATTERY_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("material_catalog_hash", "")) != _material_catalog_hash:
		return U.failure("BATTERY_RUNTIME_MATERIAL_MISMATCH")
	if String(live.get("interface_hash", "")) != _interface_hash:
		return U.failure("BATTERY_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
