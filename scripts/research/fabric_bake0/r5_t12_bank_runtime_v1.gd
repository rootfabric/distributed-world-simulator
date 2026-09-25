extends RefCounted
## T12 bank boundary executes prepared modules; never unfolds their source graphs.
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Module = preload("res://scripts/research/fabric_bake0/r5_t12_turret_runtime_v1.gd")
const TOTALS := ["bus_energy_j", "muzzle_j", "pump_j", "thermal_delta_j", "ambient_j", "exported_heat_j", "kinetic_delta_j", "external_work_j", "drive_bus_energy_j", "leaf_traversals", "boundary_calls"]
var modules: Dictionary = {}
var order: Array = []

func prepare(bundle: Dictionary) -> Dictionary:
	modules.clear(); order = bundle.children.keys(); order.sort()
	for slot in order:
		var runtime = Module.new()
		var checked: Dictionary = runtime.prepare(bundle.children[slot])
		if not checked.success: return checked
		modules[slot] = runtime
	return U.success()

func initial_state(t: float) -> Dictionary:
	var state := {}
	for slot in order: state[slot] = modules[slot].initial_state(t)
	return state

func state_valid(state: Dictionary) -> bool:
	if state.size() != modules.size(): return false
	for slot in order:
		if typeof(state.get(slot)) != TYPE_DICTIONARY or not modules[slot].state_valid(state[slot]): return false
	return true

func state_signature() -> Dictionary:
	var value := {}
	for slot in order: value[slot] = modules[slot].state_signature()
	return value

func evaluate(state: Dictionary, voltage: float, commands: Dictionary, ambient: float, dt: float) -> Dictionary:
	if not state_valid(state) or commands.size() != order.size(): return U.failure("T12_BANK_INPUT_INVALID")
	var result := {"headroom_v":0.0, "max_bus_v":INF, "next_state":{}, "modules":{}}
	for k in TOTALS: result[k] = 0.0
	for slot in order:
		if typeof(commands.get(slot)) != TYPE_DICTIONARY: return U.failure("T12_COMMAND_SLOT_MISSING")
		var step: Dictionary = modules[slot].evaluate(state[slot], voltage, commands[slot], ambient, dt)
		if not step.success: return U.failure(step.error_code, {"refine_path":"root/bank/" + slot, "cause":step.details})
		for k in TOTALS: result[k] += step.details[k]
		result.headroom_v = maxf(float(result.headroom_v), float(step.details.headroom_v))
		result.max_bus_v = minf(float(result.max_bus_v), float(step.details.max_bus_v))
		result.next_state[slot] = step.details.next_state
		result.modules[slot] = step.details
	return U.success(result)
