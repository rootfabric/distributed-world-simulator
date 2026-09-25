extends RefCounted
## T12 nested module adapter. No leaf graph is retained by this runtime.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const C = preload("res://scripts/research/fabric_bake0/ship_matryoshka_contract_v1.gd")
const Cannon = preload("res://scripts/research/fabric_bake0/r5_t10_laser_cannon_runtime_v1.gd")
const Servo = preload("res://scripts/research/fabric_bake0/r5_t11_smart_servo_runtime_v1.gd")
const Drive = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_runtime_v1.gd")
const TEMPS := ["plate_temperature_k", "hot_coolant_temperature_k", "radiator_temperature_k", "cold_coolant_temperature_k"]
const COMMANDS := ["target_position_rad", "target_velocity_rad_s", "external_torque_nm", "laser_current_a", "pwm_hz", "mass_flow_kg_s", "range_m"]
var cannon = Cannon.new()
var servo = Servo.new()
var drive = Drive.new()
var cl: Dictionary
var sl: Dictionary
var dl: Dictionary
var pd: Dictionary
var sd: Dictionary
var cd: Dictionary
var capacities: Array = []
var max_voltage := 0.0
var prepared := false

func prepare(b: Dictionary) -> Dictionary:
	prepared = false
	var checked := C.verify(b, String(b.capsule.checksum))
	if not checked.success: return checked
	var ch: Dictionary = b.children
	cl = C.own_live(ch.cannon); sl = C.own_live(ch.servo); dl = C.own_live(ch.drive)
	var nested: Dictionary = ch.cannon.children
	checked = cannon.prepare(ch.cannon.capsule, ch.cannon.artifact, ch.cannon.descriptor, cl,
		child_bundle(nested.power), child_bundle(nested.emitter), child_bundle(nested.cooling))
	if not checked.success: return checked
	checked = servo.prepare(ch.servo.capsule, ch.servo.artifact, ch.servo.descriptor, sl)
	if not checked.success: return checked
	checked = drive.prepare(ch.drive.capsule, ch.drive.artifact, ch.drive.descriptor, dl)
	if not checked.success: return checked
	pd = ch.drive.descriptor.duplicate(true); sd = ch.servo.descriptor.duplicate(true)
	cd = nested.cooling.descriptor.duplicate(true)
	max_voltage = minf(float(pd.max_bus_voltage_v), float(nested.power.descriptor.max_bus_voltage_v))
	capacities = [cd.plate_capacity_j_k, cd.hot_coolant_capacity_j_k, cd.radiator_capacity_j_k, cd.cold_coolant_capacity_j_k]
	prepared = true
	return U.success()

static func child_bundle(b: Dictionary) -> Dictionary:
	return {"capsule":b.capsule, "artifact":b.artifact, "descriptor":b.descriptor, "live":C.own_live(b)}

func initial_state(t: float) -> Dictionary:
	return {"cannon":cannon.initial_state(t), "servo":servo.initial_state()} if prepared else {}

func state_valid(s: Dictionary) -> bool:
	if s.size() != 2 or typeof(s.get("cannon")) != TYPE_DICTIONARY or typeof(s.get("servo")) != TYPE_DICTIONARY: return false
	if s.cannon.size() != 4 or s.servo.size() != 2: return false
	for k in TEMPS:
		if not U.is_finite_number(s.cannon.get(k)) or float(s.cannon[k]) < float(cd.min_temperature_k) or float(s.cannon[k]) > float(cd.max_temperature_k): return false
	return U.is_finite_number(s.servo.get("output_position_rad")) and U.is_finite_number(s.servo.get("motor_angular_velocity_rad_s")) and absf(float(s.servo.motor_angular_velocity_rad_s)) <= float(sd.max_abs_motor_omega_rad_s)

func state_signature() -> Dictionary:
	return {"capacities":capacities, "inertia":sd.combined_input_inertia_kg_m2, "ratio":sd.gear_ratio}

func evaluate(s: Dictionary, voltage: float, command: Dictionary, ambient: float, dt: float) -> Dictionary:
	if not prepared: return U.failure("T12_TURRET_NOT_READY")
	if not state_valid(s) or command.size() != COMMANDS.size(): return U.failure("T12_TURRET_INPUT_INVALID")
	for k in COMMANDS:
		if not U.is_finite_number(command.get(k)): return U.failure("T12_COMMAND_INVALID", {"field":k})
	var serv: Dictionary = servo.execute(sl, s.servo, command.target_position_rad, command.target_velocity_rad_s, command.external_torque_nm, dt)
	if not serv.success: return serv
	var current := float(serv.details.current_command_a)
	var junction := float(s.cannon.plate_temperature_k)
	var factor := maxf(0.05, 1.0 + float(pd.resistance_temp_coefficient_per_k) * (junction - float(pd.reference_temperature_k)))
	var duty := 2.0
	for sign_positive in [true, false]:
		var r := float(pd.positive_path_resistance_ref_ohm if sign_positive else pd.negative_path_resistance_ref_ohm) * factor
		var trial := (float(serv.details.terminal_voltage_v) + current * r) / voltage
		if (trial >= 0.0) == sign_positive:
			duty = trial
			break
	if absf(duty) > 1.0: return U.failure("T12_DRIVE_HEADROOM")
	var stage: Dictionary = drive.execute(dl, voltage, duty, current, command.pwm_hz, junction, dt)
	if not stage.success: return stage
	if absf(float(stage.details.electrical_output_energy_j) - float(serv.details.electrical_energy_j)) > 1.0e-9:
		return U.failure("T12_SERVO_DRIVE_ENERGY_MISMATCH")
	var shot: Dictionary = cannon.execute(cl, s.cannon, voltage, command.laser_current_a, command.pwm_hz, command.mass_flow_kg_s, ambient, command.range_m, dt)
	if not shot.success: return shot
	var thermal_delta := 0.0
	for i in range(TEMPS.size()):
		thermal_delta += float(capacities[i]) * (float(shot.details.next_state[TEMPS[i]]) - float(s.cannon[TEMPS[i]]))
	var pump := float(shot.details.cooling_pump_hydraulic_energy_j)
	var ambient_j := float(shot.details.total_internal_heat_j) + pump - thermal_delta
	var exported_heat := float(serv.details.resistive_heat_j) + float(stage.details.conduction_heat_j) + float(stage.details.switching_heat_j)
	# Explicit ideal pump conversion: battery pays hydraulic work, not a free source.
	var bus_energy := float(shot.details.bus_input_energy_j) + float(stage.details.electrical_input_energy_j) + pump
	var traversals := int(serv.details.runtime_source_component_traversals) + int(stage.details.runtime_source_die_traversals) + int(shot.details.runtime_source_component_traversals)
	for n in shot.details.subsystem_runtime_source_traversals.values(): traversals += int(n)
	return U.success({"bus_energy_j":bus_energy, "muzzle_j":shot.details.muzzle_optical_energy_j,
		"pump_j":pump, "thermal_delta_j":thermal_delta, "ambient_j":ambient_j,
		"exported_heat_j":exported_heat, "kinetic_delta_j":serv.details.kinetic_energy_delta_j,
		"external_work_j":serv.details.output_boundary_energy_j, "drive_bus_energy_j":stage.details.electrical_input_energy_j,
		"headroom_v":maxf(absf(duty) * voltage, float(shot.details.duty_ratio) * voltage),
		"max_bus_v":max_voltage, "leaf_traversals":traversals, "boundary_calls":6,
		"next_state":{"cannon":shot.details.next_state, "servo":serv.details.next_state}})
