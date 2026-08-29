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
	var graph := Kernel.new_graph()
	Kernel.add_element(graph, Kernel.source("pump", "flow", 2.0))
	Kernel.add_element(graph, Kernel.gate("valve", "flow"))
	Kernel.add_element(graph, Kernel.integrator("tank", "flow", "level", 0.0, 0.0, 10.0))
	Kernel.add_element(graph, Kernel.threshold("level_switch", "level", 7.999, "lte"))
	assert(Kernel.link(graph, "pump_valve", "pump", "out", "valve", "in"))
	assert(Kernel.link(graph, "level_switch_signal", "level_switch", "out", "valve", "control"))
	assert(Kernel.link(graph, "valve_tank", "valve", "out", "tank", "flow"))
	assert(Kernel.link(graph, "tank_sensor", "tank", "value", "level_switch", "in"))
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
		tank_history.append(float(Kernel.read_state(tank, "tank", "value")))

	return {
		"lamp_off": lamp_off,
		"lamp_on": lamp_on,
		"converted_power": converted_power,
		"breaker_active": Kernel.is_bond_active(breaker, "weak_bond"),
		"breaker_events": breaker["events"].duplicate(true),
		"components_before": components_before,
		"components_after": components_after,
		"tank_level": float(Kernel.read_state(tank, "tank", "value")),
		"tank_history": tank_history,
		"tank_hash": Kernel.state_hash(tank),
	}
