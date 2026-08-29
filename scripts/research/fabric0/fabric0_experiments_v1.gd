class_name Fabric0ExperimentsV1
extends RefCounted

const Kernel = preload("res://scripts/research/fabric0/fabric0_kernel_v1.gd")

static func build_switchable_lamp() -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("battery", "power", 12.0))
	Kernel.add_element(graph, Kernel.source("switch", "signal", 0.0))
	Kernel.add_element(graph, Kernel.gate("power_gate", "power"))
	Kernel.add_element(graph, Kernel.sink("indicator", "power"))
	assert(Kernel.link(graph, "battery_gate", "battery", "out", "power_gate", "in"))
	assert(Kernel.link(graph, "switch_gate", "switch", "out", "power_gate", "control"))
	assert(Kernel.link(graph, "gate_indicator", "power_gate", "out", "indicator", "in"))
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
	return build_regulated_accumulator("flow", "level", 0.0, 2.0, 7.999, 10.0)

static func build_regulated_heater() -> Dictionary:
	return build_regulated_accumulator("temperature_rate", "temperature", 18.0, 1.0, 21.999, 30.0)

static func build_regulated_accumulator(
	flow_domain: String,
	value_domain: String,
	initial_value: float,
	rate: float,
	target: float,
	maximum: float
) -> Dictionary:
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("source", flow_domain, rate))
	Kernel.add_element(graph, Kernel.gate("gate", flow_domain))
	Kernel.add_element(graph, Kernel.integrator("store", flow_domain, value_domain, initial_value, -INF, maximum))
	Kernel.add_element(graph, Kernel.threshold("controller", value_domain, target, "lte"))
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

static func run_all() -> Dictionary:
	var lamp := build_switchable_lamp()
	Kernel.settle(lamp)
	var lamp_off := Kernel.read_input(lamp, "indicator")
	Kernel.set_source_value(lamp, "switch", 1.0)
	Kernel.settle(lamp)
	var lamp_on := Kernel.read_input(lamp, "indicator")

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

	return {
		"lamp_off": lamp_off,
		"lamp_on": lamp_on,
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
	}
