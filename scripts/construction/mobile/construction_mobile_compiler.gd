extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const DefinitionScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_definition.gd")
const StateScript = preload("res://scripts/construction/mobile/construction_mobile_subsystem_state.gd")
const ProfileScript = preload("res://scripts/construction/mobile/construction_mobile_profile.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")

const PART_CONDITIONS: Array[String] = ["INTACT", "DEGRADED", "DESTROYED"]


static func compile(snapshot: Dictionary) -> Dictionary:
	var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	var facets: Dictionary = snapshot["compiled_facets"]
	if typeof(facets.get("mobile_subsystems")) != TYPE_ARRAY:
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITIONS_REQUIRED")
	var definitions_result: Dictionary = _validate_definitions(Array(facets["mobile_subsystems"]), snapshot)
	if not bool(definitions_result.get("success", false)):
		return definitions_result
	var definitions_by_id: Dictionary = definitions_result["definitions_by_id"]
	var parts_by_id: Dictionary = definitions_result["parts_by_id"]
	var bonds_by_id: Dictionary = definitions_result["bonds_by_id"]
	var cache: Dictionary = {}
	var states: Array = []
	var subsystem_ids: Array = definitions_by_id.keys()
	subsystem_ids.sort()
	for raw_id in subsystem_ids:
		var evaluated: Dictionary = _evaluate_subsystem(
			String(raw_id),
			definitions_by_id,
			parts_by_id,
			bonds_by_id,
			cache,
			{}
		)
		if not bool(evaluated.get("success", false)):
			return evaluated
		states.append(Dictionary(evaluated["state"]).duplicate(true))
	var active_build_state: bool = ["OPERATIONAL", "DAMAGED"].has(String(snapshot["build_state"]))
	var capabilities: Array = []
	var affordances: Array = []
	var state_by_kind: Dictionary = {}
	for state in states:
		state_by_kind[String(state["subsystem_kind"])] = state
	var mobility_state: String = _mobility_state(state_by_kind, active_build_state)
	if active_build_state:
		_compile_behavior(states, mobility_state, capabilities, affordances)
	var online_count: int = 0
	var degraded_count: int = 0
	var offline_count: int = 0
	for state in states:
		match String(state["status"]):
			"ONLINE": online_count += 1
			"DEGRADED": degraded_count += 1
			"OFFLINE": offline_count += 1
	var profile: Dictionary = ProfileScript.create(
		snapshot,
		mobility_state,
		states,
		capabilities,
		affordances,
		{
			"active_build_state": active_build_state,
			"subsystem_count": states.size(),
			"online_subsystem_count": online_count,
			"degraded_subsystem_count": degraded_count,
			"offline_subsystem_count": offline_count,
			"compiled_capability_count": capabilities.size(),
			"compiled_affordance_count": affordances.size(),
		}
	)
	var profile_validation: Dictionary = ProfileScript.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return profile_validation
	return _success({"profile": profile})


static func _validate_definitions(definitions: Array, snapshot: Dictionary) -> Dictionary:
	if definitions.is_empty():
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITIONS_REQUIRED")
	var parts_by_id: Dictionary = {}
	for raw in snapshot["parts"]:
		parts_by_id[String(raw["part_id"])] = Dictionary(raw).duplicate(true)
	var bonds_by_id: Dictionary = {}
	for raw in snapshot["bonds"]:
		bonds_by_id[String(raw["bond_id"])] = Dictionary(raw).duplicate(true)
	var definitions_by_id: Dictionary = {}
	var previous_id: String = ""
	for raw in definitions:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITION")
		var definition: Dictionary = raw
		var validation: Dictionary = DefinitionScript.validate(definition)
		if not bool(validation.get("success", false)):
			return validation
		var subsystem_id: String = String(definition["subsystem_id"])
		if definitions_by_id.has(subsystem_id):
			return _failure("DUPLICATE_CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITION")
		if not previous_id.is_empty() and subsystem_id < previous_id:
			return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_DEFINITIONS_NOT_SORTED")
		for part_id in definition["provider_part_ids"]:
			if not parts_by_id.has(String(part_id)):
				return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_PROVIDER_PART_MISSING", {"subsystem_id": subsystem_id, "part_id": part_id})
		for bond_id in definition["required_bond_ids"]:
			if not bonds_by_id.has(String(bond_id)):
				return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_REQUIRED_BOND_MISSING", {"subsystem_id": subsystem_id, "bond_id": bond_id})
		definitions_by_id[subsystem_id] = Dictionary(definition).duplicate(true)
		previous_id = subsystem_id
	for subsystem_id in definitions_by_id.keys():
		for dependency_id in definitions_by_id[subsystem_id]["dependency_subsystem_ids"]:
			if not definitions_by_id.has(String(dependency_id)):
				return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_DEPENDENCY_MISSING", {"subsystem_id": subsystem_id, "dependency_id": dependency_id})
	return _success({
		"definitions_by_id": definitions_by_id,
		"parts_by_id": parts_by_id,
		"bonds_by_id": bonds_by_id,
	})


static func _evaluate_subsystem(
	subsystem_id: String,
	definitions_by_id: Dictionary,
	parts_by_id: Dictionary,
	bonds_by_id: Dictionary,
	cache: Dictionary,
	visiting: Dictionary
) -> Dictionary:
	if cache.has(subsystem_id):
		return _success({"state": Dictionary(cache[subsystem_id]).duplicate(true)})
	if visiting.has(subsystem_id):
		return _failure("CONSTRUCTION_MOBILE_SUBSYSTEM_DEPENDENCY_CYCLE", {"subsystem_id": subsystem_id})
	var next_visiting: Dictionary = visiting.duplicate()
	next_visiting[subsystem_id] = true
	var definition: Dictionary = definitions_by_id[subsystem_id]
	var online_parts: Array = []
	var degraded_parts: Array = []
	var offline_parts: Array = []
	var health_score: float = 0.0
	for raw_part_id in definition["provider_part_ids"]:
		var part_id: String = String(raw_part_id)
		var part: Dictionary = parts_by_id[part_id]
		var condition: String = String(Dictionary(part.get("metadata", {})).get("condition", "INTACT"))
		if not PART_CONDITIONS.has(condition):
			return _failure("INVALID_CONSTRUCTION_MOBILE_PROVIDER_CONDITION", {"part_id": part_id, "condition": condition})
		match condition:
			"INTACT":
				online_parts.append(part_id)
				health_score += 1.0
			"DEGRADED":
				online_parts.append(part_id)
				degraded_parts.append(part_id)
				health_score += 0.5
			"DESTROYED":
				offline_parts.append(part_id)
	var status: String = "ONLINE"
	var required_bond_states: Dictionary = {}
	for raw_bond_id in definition["required_bond_ids"]:
		var bond_id: String = String(raw_bond_id)
		var bond_state: String = String(bonds_by_id[bond_id]["state"])
		required_bond_states[bond_id] = bond_state
		if bond_state == "BROKEN":
			status = "OFFLINE"
		elif bond_state == "DEGRADED" and status == "ONLINE":
			status = "DEGRADED"
	if online_parts.size() < int(definition["minimum_online_providers"]):
		status = "OFFLINE"
	elif (not degraded_parts.is_empty() or not offline_parts.is_empty()) and status == "ONLINE":
		status = "DEGRADED"
	var dependency_statuses: Dictionary = {}
	for raw_dependency_id in definition["dependency_subsystem_ids"]:
		var dependency_id: String = String(raw_dependency_id)
		var dependency_result: Dictionary = _evaluate_subsystem(
			dependency_id,
			definitions_by_id,
			parts_by_id,
			bonds_by_id,
			cache,
			next_visiting
		)
		if not bool(dependency_result.get("success", false)):
			return dependency_result
		var dependency_state: Dictionary = dependency_result["state"]
		dependency_statuses[dependency_id] = String(dependency_state["status"])
		if String(dependency_state["status"]) == "OFFLINE":
			status = "OFFLINE"
		elif String(dependency_state["status"]) == "DEGRADED" and status == "ONLINE":
			status = "DEGRADED"
	var total_provider_count: int = Array(definition["provider_part_ids"]).size()
	var health_ratio: float = health_score / float(total_provider_count)
	var properties: Dictionary = Dictionary(definition["properties"]).duplicate(true)
	properties["health_ratio"] = health_ratio
	properties["online_provider_count"] = online_parts.size()
	properties["total_provider_count"] = total_provider_count
	properties["minimum_online_providers"] = int(definition["minimum_online_providers"])
	properties["status"] = status
	if String(definition["subsystem_kind"]) == "DRIVE":
		for numeric_key in ["max_speed_mps", "turn_rate_rps", "tractive_force_n"]:
			if properties.has(numeric_key) and typeof(properties[numeric_key]) in [TYPE_INT, TYPE_FLOAT]:
				properties["effective_%s" % numeric_key] = 0.0 if status == "OFFLINE" else float(properties[numeric_key]) * health_ratio
	var state: Dictionary = StateScript.create(
		definition,
		status,
		online_parts,
		degraded_parts,
		offline_parts,
		properties,
		{
			"required_bond_states": required_bond_states,
			"dependency_statuses": dependency_statuses,
		}
	)
	var state_validation: Dictionary = StateScript.validate(state)
	if not bool(state_validation.get("success", false)):
		return state_validation
	cache[subsystem_id] = Dictionary(state).duplicate(true)
	return _success({"state": state})


static func _mobility_state(state_by_kind: Dictionary, active_build_state: bool) -> String:
	if not active_build_state:
		return "IMMOBILE"
	for required_kind in ["POWER", "CONTROL", "DRIVE"]:
		if not state_by_kind.has(required_kind) or String(state_by_kind[required_kind]["status"]) == "OFFLINE":
			return "IMMOBILE"
	for required_kind in ["POWER", "CONTROL", "DRIVE"]:
		if String(state_by_kind[required_kind]["status"]) == "DEGRADED":
			return "DEGRADED"
	return "MOBILE"


static func _compile_behavior(states: Array, mobility_state: String, capabilities: Array, affordances: Array) -> void:
	for state in states:
		var status: String = String(state["status"])
		if status == "OFFLINE":
			continue
		var provider_parts: Array = Array(state["online_provider_part_ids"]).duplicate(true)
		if provider_parts.is_empty():
			continue
		var kind: String = String(state["subsystem_kind"])
		var target_part_id: String = String(provider_parts[0])
		var properties: Dictionary = Dictionary(state["properties"]).duplicate(true)
		properties["subsystem_id"] = String(state["subsystem_id"])
		properties["subsystem_status"] = status
		match kind:
			"POWER":
				_add_capability(capabilities, "POWERED", provider_parts, properties)
			"CONTROL":
				_add_capability(capabilities, "MOBILE_CONTROL", provider_parts, properties)
			"DRIVE":
				if mobility_state != "IMMOBILE":
					var locomotion: Dictionary = _add_capability(capabilities, "LOCOMOTION_GROUND", provider_parts, properties)
					var steering: Dictionary = _add_capability(capabilities, "STEERING", provider_parts, properties)
					_add_affordance(affordances, "DRIVE_TO", locomotion, target_part_id, ["OPERATE_MOBILE_CONSTRUCT"], properties, 300)
					_add_affordance(affordances, "ROTATE", steering, target_part_id, ["OPERATE_MOBILE_CONSTRUCT"], properties, 290)
					_add_affordance(affordances, "STOP", locomotion, target_part_id, ["OPERATE_MOBILE_CONSTRUCT"], properties, 310)
			"SENSOR":
				var perception: Dictionary = _add_capability(capabilities, "PERCEPTION", provider_parts, properties)
				_add_affordance(affordances, "SCAN_ENVIRONMENT", perception, target_part_id, ["OPERATE_SENSOR"], properties, 250)
			"COMMUNICATION":
				var link: Dictionary = _add_capability(capabilities, "REMOTE_LINK", provider_parts, properties)
				_add_affordance(affordances, "ISSUE_REMOTE_COMMAND", link, target_part_id, ["OPERATE_REMOTE_LINK"], properties, 240)


static func _add_capability(capabilities: Array, kind: String, provider_parts: Array, properties: Dictionary) -> Dictionary:
	var capability: Dictionary = CapabilityScript.create(
		"capability/mobile/%s" % kind.to_lower().replace("_", "-"),
		kind,
		provider_parts,
		[],
		properties
	)
	capabilities.append(capability)
	return capability


static func _add_affordance(
	affordances: Array,
	action_kind: String,
	capability: Dictionary,
	target_part_id: String,
	actor_requirements: Array,
	parameters: Dictionary,
	priority: int
) -> void:
	affordances.append(AffordanceScript.create(
		"affordance/mobile/%s" % action_kind.to_lower().replace("_", "-"),
		action_kind,
		String(capability["capability_id"]),
		target_part_id,
		"",
		actor_requirements,
		parameters,
		priority
	))


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
