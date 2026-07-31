extends RefCounted

const PartScript = preload("res://scripts/construction/contracts/construction_part_record.gd")
const BondScript = preload("res://scripts/construction/contracts/construction_bond_record.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const SubsystemScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_definition.gd")


static func rover_snapshot(
	instance_key: String = "rover-a",
	part_conditions: Dictionary = {},
	bond_states: Dictionary = {},
	revision: int = 0,
	build_state: String = ""
) -> Dictionary:
	var parts: Array = _parts(instance_key, part_conditions)
	var bonds: Array = _bonds(instance_key, bond_states)
	var resolved_build_state: String = build_state
	if resolved_build_state.is_empty():
		resolved_build_state = "DAMAGED" if _has_damage(part_conditions, bond_states) else "OPERATIONAL"
	return SnapshotScript.create(
		"construct/mobile/%s" % instance_key,
		"item/mobile/%s/root" % instance_key,
		revision,
		resolved_build_state,
		parts,
		bonds,
		{
			"operational": resolved_build_state == "OPERATIONAL",
			"capabilities": [],
			"mobile_subsystems": _subsystems(instance_key),
			"mobile_platform_kind": "WHEELED_ROVER",
		}
	)


static func one_wheel_lost(instance_key: String = "rover-a", revision: int = 1) -> Dictionary:
	return rover_snapshot(instance_key, {"wheel-fl": "DESTROYED"}, {}, revision, "DAMAGED")


static func three_wheels_lost(instance_key: String = "rover-a", revision: int = 2) -> Dictionary:
	return rover_snapshot(instance_key, {
		"wheel-fl": "DESTROYED",
		"wheel-fr": "DESTROYED",
		"wheel-rl": "DESTROYED",
	}, {}, revision, "DAMAGED")


static func sensor_lost(instance_key: String = "rover-a", revision: int = 1) -> Dictionary:
	return rover_snapshot(instance_key, {"sensor": "DESTROYED"}, {}, revision, "DAMAGED")


static func controller_lost(instance_key: String = "rover-a", revision: int = 1) -> Dictionary:
	return rover_snapshot(instance_key, {"controller": "DESTROYED"}, {}, revision, "DAMAGED")


static func power_lost(instance_key: String = "rover-a", revision: int = 1) -> Dictionary:
	return rover_snapshot(instance_key, {"battery": "DESTROYED"}, {}, revision, "DAMAGED")


static func repaired(instance_key: String = "rover-a", revision: int = 3) -> Dictionary:
	return rover_snapshot(instance_key, {}, {}, revision, "OPERATIONAL")


static func partial(instance_key: String = "rover-a", revision: int = 0) -> Dictionary:
	return rover_snapshot(instance_key, {}, {}, revision, "PARTIAL")


static func _parts(instance_key: String, conditions: Dictionary) -> Array:
	var specs: Array = [
		["battery", "POWER_STORAGE", "power", 18.0, [0.0, 0.35, -0.25]],
		["chassis", "FRAME", "chassis", 80.0, [0.0, 0.5, 0.0]],
		["controller", "CONTROL_UNIT", "control", 4.0, [0.0, 0.75, 0.0]],
		["sensor", "SENSOR_ARRAY", "sensor", 3.0, [0.0, 1.15, 0.15]],
		["wheel-fl", "WHEEL", "drive", 9.0, [-0.7, 0.2, 0.65]],
		["wheel-fr", "WHEEL", "drive", 9.0, [0.7, 0.2, 0.65]],
		["wheel-rl", "WHEEL", "drive", 9.0, [-0.7, 0.2, -0.65]],
		["wheel-rr", "WHEEL", "drive", 9.0, [0.7, 0.2, -0.65]],
	]
	var result: Array = []
	for spec in specs:
		var key: String = String(spec[0])
		result.append(PartScript.create(
			"part/mobile/%s/%s" % [instance_key, key],
			"item/mobile/%s/%s" % [instance_key, key],
			String(spec[1]),
			String(spec[2]),
			float(spec[3]),
			Array(spec[4]),
			{
				"condition": String(conditions.get(key, "INTACT")),
				"mobile_component": true,
			}
		))
	return result


static func _bonds(instance_key: String, states: Dictionary) -> Array:
	var component_keys: Array = ["battery", "controller", "sensor", "wheel-fl", "wheel-fr", "wheel-rl", "wheel-rr"]
	var result: Array = []
	for key in component_keys:
		result.append(BondScript.create(
			"bond/mobile/%s/%s" % [instance_key, key],
			"part/mobile/%s/chassis" % instance_key,
			"part/mobile/%s/%s" % [instance_key, key],
			"MECHANICAL",
			12000.0,
			String(states.get(key, "INTACT")),
			{"mobile_component": key}
		))
	return result


static func _subsystems(instance_key: String) -> Array:
	var prefix: String = "part/mobile/%s/" % instance_key
	var bond_prefix: String = "bond/mobile/%s/" % instance_key
	return [
		SubsystemScript.create(
			"mobile-subsystem/control/main",
			"CONTROL",
			[prefix + "controller"],
			[bond_prefix + "controller"],
			["mobile-subsystem/power/main"],
			1,
			{"control_mode": "AUTONOMOUS", "command_rate_hz": 20.0}
		),
		SubsystemScript.create(
			"mobile-subsystem/drive/wheels",
			"DRIVE",
			[prefix + "wheel-fl", prefix + "wheel-fr", prefix + "wheel-rl", prefix + "wheel-rr"],
			[],
			["mobile-subsystem/control/main", "mobile-subsystem/power/main"],
			2,
			{"max_speed_mps": 8.0, "turn_rate_rps": 1.2, "tractive_force_n": 2400.0}
		),
		SubsystemScript.create(
			"mobile-subsystem/power/main",
			"POWER",
			[prefix + "battery"],
			[bond_prefix + "battery"],
			[],
			1,
			{"capacity_kwh": 12.0, "continuous_power_kw": 20.0}
		),
		SubsystemScript.create(
			"mobile-subsystem/sensor/main",
			"SENSOR",
			[prefix + "sensor"],
			[bond_prefix + "sensor"],
			["mobile-subsystem/control/main", "mobile-subsystem/power/main"],
			1,
			{"range_m": 60.0, "field_of_view_deg": 120.0}
		),
	]


static func _has_damage(part_conditions: Dictionary, bond_states: Dictionary) -> bool:
	for value in part_conditions.values():
		if String(value) != "INTACT":
			return true
	for value in bond_states.values():
		if String(value) != "INTACT":
			return true
	return false
