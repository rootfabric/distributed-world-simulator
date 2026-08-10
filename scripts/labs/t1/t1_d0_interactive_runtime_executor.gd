extends RefCounted

const T1A4Script = preload("res://scripts/labs/t1/t1_d0_interactive_fixture_binder.gd")
const RuntimeSubjectScript = preload("res://scripts/construction/behavior/construction_runtime_subject_state.gd")
const RuntimeStoreScript = preload("res://scripts/construction/behavior/construction_runtime_state_store.gd")
const RuntimeExecutorScript = preload("res://scripts/construction/behavior/construction_affordance_runtime_executor.gd")
const UtilityNodeScript = preload("res://scripts/construction/utilities/construction_utility_node_definition.gd")
const UtilityNetworkScript = preload("res://scripts/construction/utilities/construction_utility_network_definition.gd")
const UtilitySimulatorScript = preload("res://scripts/construction/utilities/construction_utility_simulator.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const SCHEMA: String = "planet_simulator.t1a5_d0_interactive_runtime_executor.v1"
const CONSTRUCT_ID: String = "construct/t1/lunar-outpost/d0"

const RUNTIME_IDS: Dictionary = {
	"DOOR": "runtime/t1a5/d0/door",
	"GENERATOR": "runtime/t1a5/d0/generator",
	"LAMP": "runtime/t1a5/d0/lamp",
	"CONSOLE": "runtime/t1a5/d0/console",
}

const ACTIONS_BY_KIND: Dictionary = {
	"DOOR": ["CLOSE_DOOR", "OPEN_DOOR"],
	"GENERATOR": ["START_GENERATOR", "STOP_GENERATOR"],
	"LAMP": ["TOGGLE_LIGHT"],
	"CONSOLE": ["USE_WORKSTATION"],
}

var _bound: Dictionary = {}
var _profile: Dictionary = {}
var _runtime_store
var _runtime_executor
var _base_power_network: Dictionary = {}
var _power_storage: Dictionary = {}
var _power_execution_profile: Dictionary = {}
var _data_execution_profile: Dictionary = {}
var _power_tick: int = 0
var _configured: bool = false


func setup(m0_root: String) -> Dictionary:
	if m0_root.strip_edges().is_empty():
		return _failure("T1A5_M0_ROOT_REQUIRED")
	_bound = T1A4Script.materialize_bound(m0_root)
	if not bool(_bound.get("success", false)):
		return _failure("T1A5_T1A4_BOOTSTRAP_FAILED", {"cause": _bound})
	_profile = Dictionary(_bound["binding_profile"]).duplicate(true)
	var profile_validation: Dictionary = T1A4Script.validate_binding_profile(_profile)
	if not bool(profile_validation.get("success", false)):
		return _failure("T1A5_T1A4_BINDING_PROFILE_INVALID", {"cause": profile_validation})

	_runtime_store = RuntimeStoreScript.new()
	var store_setup: Dictionary = _runtime_store.setup()
	if not bool(store_setup.get("success", false)):
		return store_setup
	for kind in ["DOOR", "GENERATOR", "LAMP", "CONSOLE"]:
		var binding: Dictionary = _binding(kind)
		if binding.is_empty():
			return _failure("T1A5_BINDING_MISSING", {"kind": kind})
		var subject: Dictionary = RuntimeSubjectScript.create(
			String(RUNTIME_IDS[kind]),
			CONSTRUCT_ID,
			String(binding["item_id"]),
			String(binding["capability_id"]),
			0,
			_initial_state(kind)
		)
		var registered: Dictionary = _runtime_store.register_subject(subject)
		if not bool(registered.get("success", false)):
			return _failure("T1A5_RUNTIME_SUBJECT_REGISTRATION_FAILED", {"kind": kind, "cause": registered})

	_runtime_executor = RuntimeExecutorScript.new()
	var executor_setup: Dictionary = _runtime_executor.setup(
		_runtime_store,
		_bound["domain"].operations,
		Callable(self, "_handle_runtime_command")
	)
	if not bool(executor_setup.get("success", false)):
		return _failure("T1A5_RUNTIME_EXECUTOR_SETUP_FAILED", {"cause": executor_setup})

	_base_power_network = Dictionary(_profile["power_network"]).duplicate(true)
	_power_storage = Dictionary(_profile["power_storage"]).duplicate(true)
	_data_execution_profile = Dictionary(_profile["data_execution_profile"]).duplicate(true)
	_power_tick = int(_power_storage.get("tick", 0))
	var power_bootstrap: Dictionary = _recompute_power()
	if not bool(power_bootstrap.get("success", false)):
		return _failure("T1A5_POWER_RUNTIME_BOOTSTRAP_FAILED", {"cause": power_bootstrap})
	_configured = true
	return _success({"report": get_report()})


func execute(
	kind: String,
	action_kind: String,
	operation_id: String,
	expected_revision: int,
	payload: Dictionary = {}
) -> Dictionary:
	if not _configured:
		return _failure("T1A5_RUNTIME_NOT_CONFIGURED")
	var normalized_kind := kind.to_upper()
	if not RUNTIME_IDS.has(normalized_kind):
		return _failure("T1A5_UNSUPPORTED_RUNTIME_KIND", {"kind": kind})
	var command: Dictionary = RuntimeExecutorScript.create_command(
		operation_id,
		action_kind.to_upper(),
		String(RUNTIME_IDS[normalized_kind]),
		expected_revision,
		payload
	)
	return _runtime_executor.execute(command)


func get_subject(kind: String) -> Dictionary:
	var normalized := kind.to_upper()
	if not RUNTIME_IDS.has(normalized) or _runtime_store == null:
		return {}
	return _runtime_store.get_subject(String(RUNTIME_IDS[normalized]))


func get_report() -> Dictionary:
	if _runtime_store == null:
		return {}
	return {
		"schema": SCHEMA,
		"construct_id": CONSTRUCT_ID,
		"construct_checksum": String(_profile.get("construct_checksum", "")),
		"runtime_state": _runtime_store.to_dict(),
		"power_tick": _power_tick,
		"power_storage": _power_storage.duplicate(true),
		"power_execution_profile": _power_execution_profile.duplicate(true),
		"data_execution_profile": _data_execution_profile.duplicate(true),
		"operation_count": int(_bound["domain"].operations.size()) if not _bound.is_empty() else 0,
	}


func get_bound_composition() -> Dictionary:
	return _bound


func _handle_runtime_command(command: Dictionary, subject: Dictionary) -> Dictionary:
	var action := String(command.get("action_kind", ""))
	var runtime_id := String(command.get("runtime_id", ""))
	var kind := String(Dictionary(subject.get("state", {})).get("kind", ""))
	if not ACTIONS_BY_KIND.has(kind) or not Array(ACTIONS_BY_KIND[kind]).has(action):
		return _reject("T1A5_ACTION_NOT_SUPPORTED_BY_RUNTIME", {"kind": kind, "action_kind": action})
	if not _binding_exposes_action(kind, action):
		return _reject("T1A5_ACTION_NOT_EXPOSED_BY_BINDING", {"kind": kind, "action_kind": action})

	var state: Dictionary = Dictionary(subject["state"]).duplicate(true)
	var next_state: Dictionary = state.duplicate(true)
	var mutates := false
	match action:
		"OPEN_DOOR":
			if not _power_allocation_full("door") or not _data_allocation_full("door"):
				return _reject("T1A5_DOOR_UTILITY_UNAVAILABLE")
			if String(state.get("position", "")) != "OPEN":
				next_state["position"] = "OPEN"
				mutates = true
		"CLOSE_DOOR":
			if not _power_allocation_full("door") or not _data_allocation_full("door"):
				return _reject("T1A5_DOOR_UTILITY_UNAVAILABLE")
			if String(state.get("position", "")) != "CLOSED":
				next_state["position"] = "CLOSED"
				mutates = true
		"START_GENERATOR":
			if not bool(state.get("running", false)):
				next_state["running"] = true
				mutates = true
		"STOP_GENERATOR":
			if bool(state.get("running", false)):
				next_state["running"] = false
				mutates = true
		"TOGGLE_LIGHT":
			var turning_on := not bool(state.get("on", false))
			if turning_on and not _power_source_available():
				return _reject("T1A5_LIGHT_POWER_UNAVAILABLE")
			next_state["on"] = turning_on
			mutates = true
		"USE_WORKSTATION":
			if not _power_source_available() or String(_data_execution_profile.get("status", "")) == "OFFLINE":
				return _reject("T1A5_WORKSTATION_UTILITY_UNAVAILABLE")
			next_state["active"] = true
			next_state["use_count"] = int(state.get("use_count", 0)) + 1
			mutates = true
		_:
			return _reject("T1A5_UNHANDLED_ACTION")

	if mutates and kind in ["GENERATOR", "LAMP", "CONSOLE"]:
		var projected: Dictionary = _recompute_power(runtime_id, next_state)
		if not bool(projected.get("success", false)):
			return _reject("T1A5_POWER_RUNTIME_UPDATE_FAILED", {"cause": projected})
	return {
		"success": true,
		"mutates": mutates,
		"next_state": next_state,
		"details": {
			"kind": kind,
			"power_status": String(_power_execution_profile.get("status", "")),
			"data_status": String(_data_execution_profile.get("status", "")),
			"power_tick": _power_tick,
		},
	}


func _recompute_power(override_runtime_id: String = "", override_state: Dictionary = {}) -> Dictionary:
	var network: Dictionary = _base_power_network.duplicate(true)
	var nodes: Array = Array(network.get("nodes", [])).duplicate(true)
	var generator_running := _runtime_bool("GENERATOR", "running", override_runtime_id, override_state, true)
	for index in range(nodes.size()):
		var node: Dictionary = Dictionary(nodes[index]).duplicate(true)
		if String(node.get("node_id", "")).ends_with("/generator"):
			var properties: Dictionary = Dictionary(node.get("properties", {})).duplicate(true)
			properties["online"] = generator_running
			node["properties"] = properties
			node["checksum"] = UtilityNodeScript.compute_checksum(node)
			nodes[index] = node
	network["nodes"] = nodes
	network["checksum"] = UtilityNetworkScript.compute_checksum(network)
	var network_validation: Dictionary = UtilityNetworkScript.validate(network)
	if not bool(network_validation.get("success", false)):
		return network_validation

	var lamp_on := _runtime_bool("LAMP", "on", override_runtime_id, override_state, false)
	var console_active := _runtime_bool("CONSOLE", "active", override_runtime_id, override_state, false)
	var demands: Array = []
	for demand_value in _profile.get("power_demands", []):
		var demand: Dictionary = Dictionary(demand_value).duplicate(true)
		var demand_id := String(demand.get("demand_id", ""))
		if demand_id.ends_with("/lamp") and not lamp_on:
			continue
		if demand_id.ends_with("/console") and not console_active:
			continue
		demands.append(demand)
	var next_tick := _power_tick + 1
	var stepped: Dictionary = UtilitySimulatorScript.step(network, demands, [_power_storage], next_tick)
	if not bool(stepped.get("success", false)):
		return stepped
	_power_tick = next_tick
	_power_execution_profile = Dictionary(stepped["profile"]).duplicate(true)
	var storage_rows: Array = Array(_power_execution_profile.get("storage_states", []))
	if storage_rows.size() != 1 or not storage_rows[0] is Dictionary:
		return _failure("T1A5_POWER_STORAGE_RUNTIME_STATE_MISSING")
	_power_storage = Dictionary(storage_rows[0]).duplicate(true)
	return _success({"profile": _power_execution_profile.duplicate(true), "storage": _power_storage.duplicate(true)})


func _runtime_bool(
	kind: String,
	field: String,
	override_runtime_id: String,
	override_state: Dictionary,
	fallback: bool
) -> bool:
	var runtime_id := String(RUNTIME_IDS[kind])
	if runtime_id == override_runtime_id:
		return bool(override_state.get(field, fallback))
	var subject: Dictionary = _runtime_store.get_subject(runtime_id)
	if subject.is_empty():
		return fallback
	return bool(Dictionary(subject.get("state", {})).get(field, fallback))


func _power_allocation_full(name: String) -> bool:
	for allocation_value in _power_execution_profile.get("allocations", []):
		var allocation: Dictionary = Dictionary(allocation_value)
		if String(allocation.get("demand_id", "")).ends_with("/%s" % name):
			return String(allocation.get("status", "")) == "FULL"
	return false


func _data_allocation_full(name: String) -> bool:
	for allocation_value in _data_execution_profile.get("allocations", []):
		var allocation: Dictionary = Dictionary(allocation_value)
		if String(allocation.get("demand_id", "")).ends_with("/%s" % name):
			return String(allocation.get("status", "")) == "FULL"
	return false


func _power_source_available() -> bool:
	return String(_power_execution_profile.get("status", "")) != "OFFLINE"


func _binding_exposes_action(kind: String, action: String) -> bool:
	var binding: Dictionary = _binding(kind)
	if binding.is_empty():
		return false
	for affordance_value in _profile.get("behavior_affordances", []):
		var affordance: Dictionary = Dictionary(affordance_value)
		if String(affordance.get("capability_id", "")) == String(binding.get("capability_id", "")) and String(affordance.get("action_kind", "")) == action:
			return true
	return false


func _binding(kind: String) -> Dictionary:
	for binding_value in _profile.get("bindings", []):
		var binding: Dictionary = Dictionary(binding_value)
		if String(binding.get("kind", "")) == kind:
			return binding.duplicate(true)
	return {}


static func _initial_state(kind: String) -> Dictionary:
	match kind:
		"DOOR": return {"kind": kind, "position": "CLOSED"}
		"GENERATOR": return {"kind": kind, "running": true}
		"LAMP": return {"kind": kind, "on": false}
		"CONSOLE": return {"kind": kind, "active": false, "use_count": 0}
	return {"kind": kind}


static func _reject(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "mutates": false, "details": details.duplicate(true)}


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code}
	for key in details:
		result[key] = details[key]
	return result
