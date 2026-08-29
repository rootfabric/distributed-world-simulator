class_name Fabric0ExperimentsV1
extends RefCounted

const Kernel = preload("res://scripts/research/fabric0/fabric0_kernel_v1.gd")

static func build_switchable_lamp() -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("battery", "power", 12.0))
	Kernel.add_element(graph, Kernel.switch("wall_switch", "power", false))
	Kernel.add_element(graph, Kernel.threshold("lamp", "power", 1.0, "gt"))
	assert(Kernel.link(graph, "battery_switch", "battery", "out", "wall_switch", "in"))
	assert(Kernel.link(graph, "switch_lamp", "wall_switch", "out", "lamp", "in"))
	return graph

static func build_energy_converter() -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("battery", "electric_power", 100.0))
	Kernel.add_element(graph, Kernel.transducer("converter", "electric_power", "rotational_power", 0.80))
	Kernel.add_element(graph, Kernel.gain("gear_loss", "rotational_power", 0.90))
	Kernel.add_element(graph, Kernel.sink("shaft_load", "rotational_power"))
	assert(Kernel.link(graph, "battery_converter", "battery", "out", "converter", "in"))
	assert(Kernel.link(graph, "converter_gear", "converter", "out", "gear_loss", "in"))
	assert(Kernel.link(graph, "gear_load", "gear_loss", "out", "shaft_load", "in"))
	return graph

static func build_breakable_link(source_value: float = 10.0, capacity: float = 5.0) -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("source", "load", source_value))
	Kernel.add_element(graph, Kernel.sink("receiver", "load"))
	assert(Kernel.link(graph, "weak_bond", "source", "out", "receiver", "in", capacity))
	return graph

static func build_auto_fill_tank() -> Dictionary:
	return build_regulated_accumulator("flow", "level", 0.0, 2.0, 8.0, 0.0, 10.0)

static func build_regulated_heater() -> Dictionary:
	return build_regulated_accumulator("temperature_rate", "temperature", 18.0, 1.0, 22.0, -273.15, 30.0)

static func build_regulated_accumulator(
	flow_domain: String,
	value_domain: String,
	initial_value: float,
	rate: float,
	target: float,
	minimum: float,
	maximum: float
) -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("source", flow_domain, rate))
	Kernel.add_element(graph, Kernel.gate("gate", flow_domain))
	Kernel.add_element(graph, Kernel.integrator("store", flow_domain, value_domain, initial_value, minimum, maximum))
	Kernel.add_element(graph, Kernel.threshold("controller", value_domain, target, "lt"))
	assert(Kernel.link(graph, "source_gate", "source", "out", "gate", "in"))
	assert(Kernel.link(graph, "controller_gate", "controller", "out", "gate", "control"))
	assert(Kernel.link(graph, "gate_store", "gate", "out", "store", "flow"))
	assert(Kernel.link(graph, "store_controller", "store", "value", "controller", "in"))
	return graph

static func build_proximity_door() -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("proximity", "signal", 0.0))
	Kernel.add_element(graph, Kernel.source("drive_rate", "position_rate", 1.0))
	Kernel.add_element(graph, Kernel.gate("drive", "position_rate"))
	Kernel.add_element(graph, Kernel.integrator("position", "position_rate", "position", 0.0, 0.0, 3.0))
	assert(Kernel.link(graph, "rate_drive", "drive_rate", "out", "drive", "in"))
	assert(Kernel.link(graph, "proximity_drive", "proximity", "out", "drive", "control"))
	assert(Kernel.link(graph, "drive_position", "drive", "out", "position", "flow"))
	return graph

static func build_rotational_drive() -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("motor", "torque", 4.0))
	Kernel.add_element(graph, Kernel.switch("motor_switch", "torque", true))
	Kernel.add_element(graph, Kernel.rotational_inertia("flywheel", 2.0))
	Kernel.add_element(graph, Kernel.viscous_load("load", 1.0))
	assert(Kernel.link(graph, "motor_switch_in", "motor", "out", "motor_switch", "in"))
	assert(Kernel.link(graph, "drive_torque", "motor_switch", "out", "flywheel", "torque"))
	assert(Kernel.link(graph, "flywheel_speed", "flywheel", "speed", "load", "speed"))
	assert(Kernel.link(graph, "load_reaction", "load", "reaction_torque", "flywheel", "torque"))
	return graph

static func run_all() -> Dictionary:
	var lamp := build_switchable_lamp()
	Kernel.settle(lamp)
	var lamp_open_power := Kernel.read_input(lamp, "lamp")
	var lamp_open_signal := Kernel.read_output(lamp, "lamp")
	Kernel.set_switch_state(lamp, "wall_switch", true)
	Kernel.settle(lamp)
	var lamp_closed_power := Kernel.read_input(lamp, "lamp")
	var lamp_closed_signal := Kernel.read_output(lamp, "lamp")

	var converter := build_energy_converter()
	Kernel.settle(converter)
	var converted_power := Kernel.read_input(converter, "shaft_load")

	var breaker := build_breakable_link()
	var components_before := Kernel.connected_components(breaker).size()
	Kernel.step(breaker)
	var components_after := Kernel.connected_components(breaker).size()

	var tank := build_auto_fill_tank()
	var tank_history: Array = []
	for _tick in range(8):
		Kernel.step(tank)
		tank_history.append(float(Kernel.read_state(tank, "store", "value")))

	var heater := build_regulated_heater()
	var heater_history: Array = []
	for _tick in range(8):
		Kernel.step(heater)
		heater_history.append(float(Kernel.read_state(heater, "store", "value")))

	var door := build_proximity_door()
	Kernel.step(door)
	var door_closed := float(Kernel.read_state(door, "position", "value"))
	Kernel.set_source_value(door, "proximity", 1.0)
	Kernel.step(door)
	Kernel.step(door)
	var door_opening := float(Kernel.read_state(door, "position", "value"))

	var rotation := build_rotational_drive()
	var speed_history: Array = []
	for _tick in range(8):
		Kernel.step(rotation)
		speed_history.append(float(Kernel.read_state(rotation, "flywheel", "speed")))
	var loaded_speed := float(Kernel.read_state(rotation, "flywheel", "speed"))
	var reaction_torque := Kernel.read_output(rotation, "load", "reaction_torque")
	Kernel.set_switch_state(rotation, "motor_switch", false)
	Kernel.step(rotation)
	var coast_speed := float(Kernel.read_state(rotation, "flywheel", "speed"))

	return {
		"lamp_open_power": lamp_open_power,
		"lamp_open_signal": lamp_open_signal,
		"lamp_closed_power": lamp_closed_power,
		"lamp_closed_signal": lamp_closed_signal,
		"converted_power": converted_power,
		"breaker_active": Kernel.is_bond_active(breaker, "weak_bond"),
		"breaker_events": breaker["events"].duplicate(true),
		"components_before": components_before,
		"components_after": components_after,
		"tank_level": float(Kernel.read_state(tank, "store", "value")),
		"tank_history": tank_history,
		"tank_hash": Kernel.state_hash(tank),
		"heater_temperature": float(Kernel.read_state(heater, "store", "value")),
		"heater_history": heater_history,
		"door_closed": door_closed,
		"door_opening": door_opening,
		"rotation_speed_history": speed_history,
		"rotation_loaded_speed": loaded_speed,
		"rotation_reaction_torque": reaction_torque,
		"rotation_coast_speed": coast_speed,
		"rotation_hash": Kernel.state_hash(rotation),
	}
