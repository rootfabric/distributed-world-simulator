extends RefCounted
## T12 shared battery bus. All nonlinear trials read the same caller-owned snapshot.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
const Battery = preload("res://scripts/research/fabric_bake0/r5_t3_battery_runtime_v1.gd")
const Bank = preload("res://scripts/research/fabric_bake0/r5_t12_bank_runtime_v1.gd")
const BUS_TOL_J := 1.0e-9
const ENERGY_TOL_J := 1.0e-7
const MAX_EVALUATIONS := 48
var battery = Battery.new()
var bank = Bank.new()
var bd: Dictionary
var bl: Dictionary
var anchors: Dictionary = {}
var checksum := ""
var ready := false

func prepare(bundle: Dictionary, trusted_capsule_checksum: String) -> Dictionary:
	ready = false
	var checked := C.verify(bundle, trusted_capsule_checksum)
	if not checked.success: return checked
	if bundle.capsule.executable_kind != "T12_SHIP": return U.failure("T12_NOT_SHIP")
	var b: Dictionary = bundle.children.battery
	bl = C.own_live(b); bd = b.descriptor.duplicate(true)
	checked = battery.prepare(b.capsule, b.artifact, b.descriptor, bl)
	if not checked.success: return checked
	checked = bank.prepare(bundle.children.bank)
	if not checked.success: return checked
	anchors = C.live_tree(bundle)
	checksum = trusted_capsule_checksum
	ready = true
	return U.success({"instance_count":bank.order.size(), "state_scalars":int(bd.series_group_count) + 1 + 6 * bank.order.size()})

func initial_state(soc: float = 0.8, temperature_k: float = 300.0) -> Dictionary:
	if not ready or not U.is_finite_number(soc) or not U.is_finite_number(temperature_k): return {}
	var value := {"battery":battery.initial_state(soc, temperature_k), "bank":bank.initial_state(temperature_k)}
	return value if state_valid(value) else {}

func state_valid(s: Dictionary) -> bool:
	if not ready or s.size() != 2 or typeof(s.get("battery")) != TYPE_DICTIONARY or typeof(s.get("bank")) != TYPE_DICTIONARY: return false
	var b: Dictionary = s.battery
	if b.size() != 2 or typeof(b.get("group_charge_c")) != TYPE_ARRAY or b.group_charge_c.size() != int(bd.series_group_count): return false
	if not U.is_finite_number(b.get("temperature_k")) or float(b.temperature_k) < float(bd.min_temperature_k) or float(b.temperature_k) > float(bd.max_temperature_k): return false
	for i in range(b.group_charge_c.size()):
		if not U.is_finite_number(b.group_charge_c[i]) or float(b.group_charge_c[i]) < 0.0 or float(b.group_charge_c[i]) > float(bd.group_capacity_c[i]): return false
	return bank.state_valid(s.bank)

func state_signature() -> String:
	return U.canonical_hash({"battery_descriptor":bd.checksum, "bank":bank.state_signature()})

func rebind_state(previous: RefCounted, state: Dictionary) -> Dictionary:
	if not previous.state_valid(state) or not state_valid(state): return U.failure("T12_REBIND_STATE_INVALID")
	if previous.state_signature() != state_signature(): return U.failure("T12_CANONICAL_STATE_PROJECTOR_REQUIRED")
	return U.success({"next_state":state.duplicate(true), "projection":"IDENTITY_SAME_STORAGE_LAWS"})

func _scalars(state: Dictionary) -> Array:
	var values: Array = state.battery.group_charge_c.duplicate()
	values.append(state.battery.temperature_k)
	for slot in bank.order:
		for field in bank.modules[slot].TEMPS: values.append(state.bank[slot].cannon[field])
		values.append(state.bank[slot].servo.output_position_rad)
		values.append(state.bank[slot].servo.motor_angular_velocity_rad_s)
	return values

func snapshot(state: Dictionary) -> Dictionary:
	if not state_valid(state): return U.failure("T12_SNAPSHOT_STATE_INVALID")
	# Decimal JSON parsing need not preserve every IEEE-754 bit. Encode the fixed,
	# validated scalar layout as raw doubles; JSON contains strings only.
	var values := _scalars(state)
	var bytes := PackedByteArray(); bytes.resize(values.size() * 8)
	for i in range(values.size()): bytes.encode_double(i * 8, float(values[i]))
	var text := JSON.stringify({"schema":"t12.snapshot.v1", "capsule_checksum":checksum,
		"state_base64":Marshalls.raw_to_base64(bytes)}, "", true)
	return U.success({"text":text, "sha256":text.sha256_text()})

func restore(text: String, trusted_hash: String) -> Dictionary:
	if text.length() > 4096 or not U.is_lower_hex_64(trusted_hash) or text.sha256_text() != trusted_hash:
		return U.failure("T12_SNAPSHOT_ANCHOR_MISMATCH")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or parsed.size() != 3 or parsed.get("schema") != "t12.snapshot.v1" or parsed.get("capsule_checksum") != checksum:
		return U.failure("T12_SNAPSHOT_CAPSULE_MISMATCH")
	if typeof(parsed.get("state_base64")) != TYPE_STRING: return U.failure("T12_SNAPSHOT_STATE_INVALID")
	var encoded: String = parsed.state_base64
	var count: int = int(bd.series_group_count) + 1 + 6 * bank.order.size()
	if encoded.length() != 4 * int(ceil(float(count * 8) / 3.0)): return U.failure("T12_SNAPSHOT_STATE_INVALID")
	for ch in encoded:
		if not ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=": return U.failure("T12_SNAPSHOT_STATE_INVALID")
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.size() != count * 8 or Marshalls.raw_to_base64(bytes) != encoded: return U.failure("T12_SNAPSHOT_STATE_INVALID")
	var state := initial_state(0.0)
	var offset := 0
	for i in range(int(bd.series_group_count)):
		state.battery.group_charge_c[i] = bytes.decode_double(offset); offset += 8
	state.battery.temperature_k = bytes.decode_double(offset); offset += 8
	for slot in bank.order:
		for field in bank.modules[slot].TEMPS:
			state.bank[slot].cannon[field] = bytes.decode_double(offset); offset += 8
		state.bank[slot].servo.output_position_rad = bytes.decode_double(offset); offset += 8
		state.bank[slot].servo.motor_angular_velocity_rad_s = bytes.decode_double(offset); offset += 8
	if not state_valid(state): return U.failure("T12_SNAPSHOT_STATE_INVALID")
	return U.success({"next_state":state})

func execute(live: Dictionary, state: Dictionary, commands: Dictionary, ambient: float, dt: float, bisection: bool = false) -> Dictionary:
	if not ready: return U.failure("T12_SHIP_NOT_READY")
	var checked := C.gate(live, anchors)
	if not checked.success: return checked
	if not state_valid(state) or not U.is_positive_number(ambient) or not U.is_positive_number(dt): return U.failure("T12_SHIP_INPUT_INVALID")
	# T3's midpoint port law is affine in current at a fixed snapshot. Derive only
	# from the compact group descriptor; no source-cell traversal or recompile.
	var e := 0.0; var r := 0.0
	var discharge := float(bd.max_continuous_current_a)
	var charge := discharge
	for i in range(int(bd.series_group_count)):
		var q := float(state.battery.group_charge_c[i])
		var cap := float(bd.group_capacity_c[i])
		var slope := (float(bd.group_full_voltage_v[i]) - float(bd.group_empty_voltage_v[i])) / cap
		e += float(bd.group_empty_voltage_v[i]) + slope * q
		var factor := maxf(0.05, 1.0 + float(bd.group_resistance_temp_coefficient_per_k[i]) * (float(state.battery.temperature_k) - float(bd.group_reference_temperature_k[i])))
		r += float(bd.group_resistance_ref_ohm[i]) * factor + 0.5 * dt * slope
		discharge = minf(discharge, q / dt)
		charge = minf(charge, (cap - q) / dt)
	if not U.is_positive_number(e) or not U.is_positive_number(r): return U.failure("T12_BATTERY_PORT_INVALID")
	var stats := {"evaluations":0, "boundary_calls":0, "leaf_traversals":0, "compiled_group_visits":0}
	var zero := _trial(state, commands, 0.0, ambient, dt, stats)
	if not zero.success: return zero
	if absf(float(zero.details.residual_j)) <= BUS_TOL_J: return _finish(state, zero.details, stats)
	var load: Dictionary = zero.details.bank
	var upper := minf(discharge * (1.0 - 1.0e-12), minf((e - maxf(1.0e-6, float(load.headroom_v))) / r, e / (2.0 * r)))
	var lower := maxf(-charge * (1.0 - 1.0e-12), (e - float(load.max_bus_v)) / r)
	# Only the high-voltage / stable branch of the battery power curve is admitted.
	if lower > 0.0 or upper < 0.0: return U.failure("T12_NO_ADMISSIBLE_BUS_INTERVAL")
	var lo := 0.0; var hi := 0.0
	var f_lo := float(zero.details.residual_j); var f_hi := f_lo
	if f_lo < 0.0:
		hi = upper
		if hi <= 0.0: return U.failure("T12_BATTERY_DEPLETED")
		var end := _trial(state, commands, hi, ambient, dt, stats)
		if not end.success: return end
		f_hi = float(end.details.residual_j)
	else:
		lo = lower
		if lo >= 0.0: return U.failure("T12_CHARGE_ACCEPTANCE_EXHAUSTED")
		var end := _trial(state, commands, lo, ambient, dt, stats)
		if not end.success: return end
		f_lo = float(end.details.residual_j)
	if f_lo > 0.0 or f_hi < 0.0: return U.failure("T12_SHARED_POWER_LIMIT")
	for iteration in range(MAX_EVALUATIONS - 2):
		var current := 0.5 * (lo + hi)
		if not bisection and iteration % 6 != 5 and f_hi != f_lo:
			current = clampf((lo * f_hi - hi * f_lo) / (f_hi - f_lo), lo + (hi - lo) * 1.0e-8, hi - (hi - lo) * 1.0e-8)
		var trial := _trial(state, commands, current, ambient, dt, stats)
		if not trial.success: return trial
		var f := float(trial.details.residual_j)
		if absf(f) <= BUS_TOL_J:
			if absf(float(trial.details.battery.terminal_voltage_v) - (e - r * current)) > 1.0e-9: return U.failure("T12_BATTERY_PORT_PARITY_FAILED")
			return _finish(state, trial.details, stats)
		if f < 0.0: lo = current; f_lo = f
		else: hi = current; f_hi = f
	return U.failure("T12_BUS_SOLVER_DID_NOT_CONVERGE", stats)

func _trial(state: Dictionary, commands: Dictionary, current: float, ambient: float, dt: float, stats: Dictionary) -> Dictionary:
	stats.evaluations += 1
	var b: Dictionary = battery.execute(bl, state.battery, current, dt, ambient)
	if not b.success: return U.failure(b.error_code, {"refine_path":"root/battery", "cause":b.details})
	var voltage := float(b.details.terminal_voltage_v)
	if not U.is_positive_number(voltage): return U.failure("T12_BUS_VOLTAGE_NONPOSITIVE")
	var k: Dictionary = bank.evaluate(state.bank, voltage, commands, ambient, dt)
	if not k.success: return k
	stats.boundary_calls += 1 + int(k.details.boundary_calls)
	stats.leaf_traversals += int(b.details.runtime_source_cell_traversals) + int(k.details.leaf_traversals)
	stats.compiled_group_visits += int(b.details.compiled_group_traversals)
	var residual := float(b.details.electrical_energy_j) - float(k.details.bus_energy_j)
	if not is_finite(residual): return U.failure("T12_BUS_NONFINITE")
	return U.success({"battery":b.details, "bank":k.details, "current_a":current, "residual_j":residual})

func _finish(state: Dictionary, trial: Dictionary, stats: Dictionary) -> Dictionary:
	var b: Dictionary = trial.battery; var k: Dictionary = trial.bank
	var thermal_battery := float(bd.thermal_capacity_j_k) * (float(b.next_state.temperature_k) - float(state.battery.temperature_k))
	var stored := thermal_battery + float(k.thermal_delta_j) + float(k.kinetic_delta_j)
	var heat_out := float(b.passive_heat_removed_j) + float(k.ambient_j) + float(k.exported_heat_j)
	var residual := float(b.chemical_energy_delta_j) + float(k.external_work_j) - float(k.muzzle_j) - stored - heat_out
	if not is_finite(residual) or absf(residual) > ENERGY_TOL_J: return U.failure("T12_WHOLE_ENERGY_AUDIT_FAILED", {"residual_j":residual})
	return U.success({"next_state":{"battery":b.next_state, "bank":k.next_state},
		"battery_current_a":trial.current_a, "bus_voltage_v":b.terminal_voltage_v,
		"battery_electrical_j":b.electrical_energy_j, "chemical_delta_j":b.chemical_energy_delta_j,
		"load_electrical_j":k.bus_energy_j, "muzzle_j":k.muzzle_j, "pump_j":k.pump_j,
		"external_work_j":k.external_work_j, "stored_delta_j":stored, "heat_out_j":heat_out,
		"energy_residual_j":residual, "bus_residual_j":trial.residual_j,
		"modules":k.modules, "metrics":stats})
