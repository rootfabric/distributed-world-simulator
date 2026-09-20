extends RefCounted
## Conservative state projector for T3 rebake after capacity-losing topology changes.
## It relies only on the exact parallel-group SOC synchrony contract already
## required by the T3 compiler.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/battery_pack_descriptor_v1.gd")
const CellPhysics = preload("res://scripts/research/fabric_bake0/battery_cell_physics_v1.gd")

static func project_capacity_loss(old_descriptor: Dictionary, new_descriptor: Dictionary, old_state: Dictionary) -> Dictionary:
	var checked := Descriptor.validate(old_descriptor)
	if not checked.success:
		return checked
	checked = Descriptor.validate(new_descriptor)
	if not checked.success:
		return checked
	var n := int(old_descriptor.series_group_count)
	if int(new_descriptor.series_group_count) != n:
		return U.failure("BATTERY_STATE_PROJECTION_SERIES_COUNT_MISMATCH")
	if typeof(old_state.get("group_charge_c")) != TYPE_ARRAY or old_state.group_charge_c.size() != n:
		return U.failure("BATTERY_STATE_PROJECTION_STATE_INVALID")
	if not U.is_positive_number(old_state.get("temperature_k")):
		return U.failure("BATTERY_STATE_PROJECTION_TEMPERATURE_INVALID")
	var next_charges: Array = []
	var detached_charge: Array = []
	var detached_energy_j: Array = []
	var total_detached_energy_j := 0.0
	for index in range(n):
		if String(old_descriptor.group_profile_ids[index]) != String(new_descriptor.group_profile_ids[index]):
			return U.failure("BATTERY_STATE_PROJECTION_PROFILE_MISMATCH", {"series_index": index})
		var old_capacity := float(old_descriptor.group_capacity_c[index])
		var new_capacity := float(new_descriptor.group_capacity_c[index])
		if new_capacity > old_capacity + 1.0e-9:
			return U.failure("BATTERY_STATE_PROJECTION_CAPACITY_GAIN_UNSUPPORTED", {
				"series_index": index,
				"old_capacity_c": old_capacity,
				"new_capacity_c": new_capacity,
			})
		var old_charge := float(old_state.group_charge_c[index])
		if old_charge < -1.0e-9 or old_charge > old_capacity + 1.0e-9:
			return U.failure("BATTERY_STATE_PROJECTION_CHARGE_OUT_OF_DOMAIN", {"series_index": index})
		var soc := clampf(old_charge / old_capacity, 0.0, 1.0)
		var next_charge := new_capacity * soc
		var removed_charge := maxf(0.0, old_charge - next_charge)
		var old_energy := CellPhysics.chemical_energy_j(
			old_capacity,
			old_charge,
			float(old_descriptor.group_empty_voltage_v[index]),
			float(old_descriptor.group_full_voltage_v[index])
		)
		var new_energy := CellPhysics.chemical_energy_j(
			new_capacity,
			next_charge,
			float(new_descriptor.group_empty_voltage_v[index]),
			float(new_descriptor.group_full_voltage_v[index])
		)
		var removed_energy := maxf(0.0, old_energy - new_energy)
		next_charges.append(next_charge)
		detached_charge.append(removed_charge)
		detached_energy_j.append(removed_energy)
		total_detached_energy_j += removed_energy
	return U.success({
		"next_state": {
			"group_charge_c": next_charges,
			"temperature_k": float(old_state.temperature_k),
		},
		"detached_charge_c_by_group": detached_charge,
		"detached_chemical_energy_j_by_group": detached_energy_j,
		"total_detached_chemical_energy_j": total_detached_energy_j,
		"projection_kind": "CAPACITY_LOSS_SAME_SOC",
	})

static func soc_by_group(descriptor: Dictionary, state: Dictionary) -> Dictionary:
	var checked := Descriptor.validate(descriptor)
	if not checked.success:
		return checked
	if typeof(state.get("group_charge_c")) != TYPE_ARRAY or state.group_charge_c.size() != int(descriptor.series_group_count):
		return U.failure("BATTERY_STATE_SOC_STATE_INVALID")
	var values: Array = []
	for index in range(int(descriptor.series_group_count)):
		values.append(float(state.group_charge_c[index]) / float(descriptor.group_capacity_c[index]))
	return U.success({"soc": values})
