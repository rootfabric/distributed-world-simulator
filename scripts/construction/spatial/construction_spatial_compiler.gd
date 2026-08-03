extends RefCounted

const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const SectionDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_section_definition.gd")
const OpeningDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_opening_definition.gd")
const SpaceDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_space_definition.gd")
const UtilityDefinitionScript = preload("res://scripts/construction/spatial/construction_spatial_utility_definition.gd")
const SectionStateScript = preload("res://scripts/construction/spatial/construction_spatial_section_state.gd")
const OpeningStateScript = preload("res://scripts/construction/spatial/construction_spatial_opening_state.gd")
const SpaceStateScript = preload("res://scripts/construction/spatial/construction_spatial_space_state.gd")
const UtilityStateScript = preload("res://scripts/construction/spatial/construction_spatial_utility_state.gd")
const ProfileScript = preload("res://scripts/construction/spatial/construction_spatial_profile.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")

const PART_CONDITIONS: Array[String] = ["INTACT", "DEGRADED", "DESTROYED"]

static func compile(snapshot: Dictionary) -> Dictionary:
	var snapshot_validation := SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	var facets: Dictionary = snapshot["compiled_facets"]
	for field in ["spatial_sections", "spatial_openings", "spatial_spaces", "spatial_utilities"]:
		if typeof(facets.get(field)) != TYPE_ARRAY:
			return _failure("CONSTRUCTION_SPATIAL_DEFINITIONS_REQUIRED", {"field": field})
	var definitions := _validate_definitions(snapshot, facets)
	if not bool(definitions.get("success", false)):
		return definitions
	var parts_by_id: Dictionary = definitions["parts_by_id"]
	var bonds_by_id: Dictionary = definitions["bonds_by_id"]
	var section_definitions: Dictionary = definitions["section_definitions"]
	var opening_definitions: Dictionary = definitions["opening_definitions"]
	var space_definitions: Dictionary = definitions["space_definitions"]
	var utility_definitions: Dictionary = definitions["utility_definitions"]
	var active_build_state := ["OPERATIONAL", "DAMAGED"].has(String(snapshot["build_state"]))
	var section_states: Array = []
	var section_states_by_id: Dictionary = {}
	var section_ids: Array = section_definitions.keys()
	section_ids.sort()
	for raw_id in section_ids:
		var state_result := _evaluate_section(section_definitions[raw_id], parts_by_id, bonds_by_id, active_build_state)
		if not bool(state_result.get("success", false)):
			return state_result
		var state: Dictionary = state_result["state"]
		section_states.append(state)
		section_states_by_id[String(raw_id)] = state
	var utility_cache: Dictionary = {}
	var utility_states: Array = []
	var utility_ids: Array = utility_definitions.keys()
	utility_ids.sort()
	for raw_id in utility_ids:
		var state_result := _evaluate_utility(String(raw_id), utility_definitions, parts_by_id, bonds_by_id, utility_cache, {}, active_build_state)
		if not bool(state_result.get("success", false)):
			return state_result
		utility_states.append(Dictionary(state_result["state"]).duplicate(true))
	var opening_states: Array = []
	var opening_states_by_id: Dictionary = {}
	var opening_ids: Array = opening_definitions.keys()
	opening_ids.sort()
	for raw_id in opening_ids:
		var state_result := _evaluate_opening(opening_definitions[raw_id], section_states_by_id, parts_by_id, bonds_by_id, active_build_state)
		if not bool(state_result.get("success", false)):
			return state_result
		var state: Dictionary = state_result["state"]
		opening_states.append(state)
		opening_states_by_id[String(raw_id)] = state
	var space_states: Array = []
	var space_ids: Array = space_definitions.keys()
	space_ids.sort()
	for raw_id in space_ids:
		var state_result := _evaluate_space(space_definitions[raw_id], section_states_by_id, opening_states_by_id, utility_cache, active_build_state)
		if not bool(state_result.get("success", false)):
			return state_result
		space_states.append(Dictionary(state_result["state"]).duplicate(true))
	var building_state := _building_state(space_states, active_build_state)
	var activation_level := _activation_level(building_state, active_build_state)
	var capabilities: Array = []
	var affordances: Array = []
	if building_state != "INACTIVE":
		_compile_behavior(space_states, opening_states, utility_states, section_states_by_id, capabilities, affordances)
	var profile := ProfileScript.create(
		snapshot,
		building_state,
		activation_level,
		section_states,
		opening_states,
		space_states,
		utility_states,
		capabilities,
		affordances,
		{
			"active_build_state": active_build_state,
			"section_count": section_states.size(),
			"opening_count": opening_states.size(),
			"space_count": space_states.size(),
			"utility_count": utility_states.size(),
			"habitable_space_count": _count_status(space_states, "HABITABLE"),
			"degraded_space_count": _count_status(space_states, "DEGRADED"),
			"exposed_space_count": _count_status(space_states, "EXPOSED"),
			"compiled_capability_count": capabilities.size(),
			"compiled_affordance_count": affordances.size(),
		}
	)
	var profile_validation := ProfileScript.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return profile_validation
	return _success({"profile": profile})

static func _validate_definitions(snapshot: Dictionary, facets: Dictionary) -> Dictionary:
	var parts_by_id: Dictionary = {}
	for raw in snapshot["parts"]:
		parts_by_id[String(raw["part_id"])] = Dictionary(raw).duplicate(true)
	var bonds_by_id: Dictionary = {}
	for raw in snapshot["bonds"]:
		bonds_by_id[String(raw["bond_id"])] = Dictionary(raw).duplicate(true)
	var section_definitions := _collect_definitions(Array(facets["spatial_sections"]), SectionDefinitionScript, "section_id", "SECTION")
	if not bool(section_definitions.get("success", false)):
		return section_definitions
	var opening_definitions := _collect_definitions(Array(facets["spatial_openings"]), OpeningDefinitionScript, "opening_id", "OPENING")
	if not bool(opening_definitions.get("success", false)):
		return opening_definitions
	var space_definitions := _collect_definitions(Array(facets["spatial_spaces"]), SpaceDefinitionScript, "space_id", "SPACE")
	if not bool(space_definitions.get("success", false)):
		return space_definitions
	var utility_definitions := _collect_definitions(Array(facets["spatial_utilities"]), UtilityDefinitionScript, "utility_id", "UTILITY")
	if not bool(utility_definitions.get("success", false)):
		return utility_definitions
	var sections: Dictionary = section_definitions["definitions"]
	var openings: Dictionary = opening_definitions["definitions"]
	var spaces: Dictionary = space_definitions["definitions"]
	var utilities: Dictionary = utility_definitions["definitions"]
	if sections.is_empty() or spaces.is_empty():
		return _failure("CONSTRUCTION_SPATIAL_SECTION_AND_SPACE_REQUIRED")
	for section in sections.values():
		for raw_part_id in section["provider_part_ids"]:
			if not parts_by_id.has(String(raw_part_id)):
				return _failure("CONSTRUCTION_SPATIAL_SECTION_PROVIDER_PART_MISSING")
		for raw_bond_id in section["required_bond_ids"]:
			if not bonds_by_id.has(String(raw_bond_id)):
				return _failure("CONSTRUCTION_SPATIAL_SECTION_REQUIRED_BOND_MISSING")
	for utility in utilities.values():
		for raw_part_id in utility["provider_part_ids"]:
			if not parts_by_id.has(String(raw_part_id)):
				return _failure("CONSTRUCTION_SPATIAL_UTILITY_PROVIDER_PART_MISSING")
		for raw_bond_id in utility["required_bond_ids"]:
			if not bonds_by_id.has(String(raw_bond_id)):
				return _failure("CONSTRUCTION_SPATIAL_UTILITY_REQUIRED_BOND_MISSING")
		for raw_dependency_id in utility["dependency_utility_ids"]:
			if not utilities.has(String(raw_dependency_id)):
				return _failure("CONSTRUCTION_SPATIAL_UTILITY_DEPENDENCY_MISSING")
	for opening in openings.values():
		if not sections.has(String(opening["frame_section_id"])):
			return _failure("CONSTRUCTION_SPATIAL_OPENING_FRAME_SECTION_MISSING")
		var closure_part_id := String(opening["closure_part_id"])
		if not closure_part_id.is_empty() and not parts_by_id.has(closure_part_id):
			return _failure("CONSTRUCTION_SPATIAL_OPENING_CLOSURE_PART_MISSING")
		for raw_bond_id in opening["required_bond_ids"]:
			if not bonds_by_id.has(String(raw_bond_id)):
				return _failure("CONSTRUCTION_SPATIAL_OPENING_REQUIRED_BOND_MISSING")
		for field in ["from_space_id", "to_space_id"]:
			var space_id := String(opening[field])
			if space_id != "space/exterior" and not spaces.has(space_id):
				return _failure("CONSTRUCTION_SPATIAL_OPENING_SPACE_MISSING")
	for space in spaces.values():
		for raw_section_id in space["section_ids"]:
			if not sections.has(String(raw_section_id)):
				return _failure("CONSTRUCTION_SPATIAL_SPACE_SECTION_MISSING")
		for raw_opening_id in space["opening_ids"]:
			var opening_id := String(raw_opening_id)
			if not openings.has(opening_id):
				return _failure("CONSTRUCTION_SPATIAL_SPACE_OPENING_MISSING")
			var opening: Dictionary = openings[opening_id]
			if String(opening["from_space_id"]) != String(space["space_id"]) and String(opening["to_space_id"]) != String(space["space_id"]):
				return _failure("CONSTRUCTION_SPATIAL_SPACE_OPENING_TOPOLOGY_MISMATCH")
		for raw_utility_id in space["required_utility_ids"]:
			if not utilities.has(String(raw_utility_id)):
				return _failure("CONSTRUCTION_SPATIAL_SPACE_UTILITY_MISSING")
	return _success({
		"parts_by_id": parts_by_id,
		"bonds_by_id": bonds_by_id,
		"section_definitions": sections,
		"opening_definitions": openings,
		"space_definitions": spaces,
		"utility_definitions": utilities,
	})

static func _collect_definitions(values: Array, script, id_field: String, label: String) -> Dictionary:
	var definitions: Dictionary = {}
	var previous := ""
	for raw in values:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_SPATIAL_%s_DEFINITION" % label)
		var checked: Dictionary = script.validate(raw)
		if not bool(checked.get("success", false)):
			return checked
		var identifier := String(raw[id_field])
		if definitions.has(identifier):
			return _failure("DUPLICATE_CONSTRUCTION_SPATIAL_%s_DEFINITION" % label)
		if not previous.is_empty() and identifier < previous:
			return _failure("CONSTRUCTION_SPATIAL_%s_DEFINITIONS_NOT_SORTED" % label)
		definitions[identifier] = Dictionary(raw).duplicate(true)
		previous = identifier
	return _success({"definitions": definitions})

static func _evaluate_section(definition: Dictionary, parts_by_id: Dictionary, bonds_by_id: Dictionary, active_build_state: bool) -> Dictionary:
	var partition := _partition_providers(definition["provider_part_ids"], parts_by_id)
	if not bool(partition.get("success", false)):
		return partition
	var status := "ONLINE"
	var required_bond_states: Dictionary = {}
	for raw_bond_id in definition["required_bond_ids"]:
		var bond_id := String(raw_bond_id)
		var bond_state := String(bonds_by_id[bond_id]["state"])
		required_bond_states[bond_id] = bond_state
		if bond_state == "BROKEN":
			status = "OFFLINE"
		elif bond_state == "DEGRADED" and status == "ONLINE":
			status = "DEGRADED"
	if Array(partition["online"]).size() + Array(partition["degraded"]).size() < int(definition["minimum_intact_providers"]):
		status = "OFFLINE"
	elif (not Array(partition["degraded"]).is_empty() or not Array(partition["offline"]).is_empty()) and status == "ONLINE":
		status = "DEGRADED"
	if not active_build_state:
		status = "OFFLINE"
	var properties: Dictionary = Dictionary(definition["properties"]).duplicate(true)
	properties["status"] = status
	properties["health_ratio"] = float(partition["health_score"]) / float(Array(definition["provider_part_ids"]).size())
	var state := SectionStateScript.create(definition, status, partition["online"], partition["degraded"], partition["offline"], properties, {"required_bond_states": required_bond_states})
	var checked := SectionStateScript.validate(state)
	return _success({"state": state}) if bool(checked.get("success", false)) else checked

static func _evaluate_utility(utility_id: String, definitions: Dictionary, parts_by_id: Dictionary, bonds_by_id: Dictionary, cache: Dictionary, visiting: Dictionary, active_build_state: bool) -> Dictionary:
	if cache.has(utility_id):
		return _success({"state": Dictionary(cache[utility_id]).duplicate(true)})
	if visiting.has(utility_id):
		return _failure("CONSTRUCTION_SPATIAL_UTILITY_DEPENDENCY_CYCLE")
	var next_visiting := visiting.duplicate()
	next_visiting[utility_id] = true
	var definition: Dictionary = definitions[utility_id]
	var partition := _partition_providers(definition["provider_part_ids"], parts_by_id)
	if not bool(partition.get("success", false)):
		return partition
	var status := "ONLINE"
	var required_bond_states: Dictionary = {}
	for raw_bond_id in definition["required_bond_ids"]:
		var bond_id := String(raw_bond_id)
		var bond_state := String(bonds_by_id[bond_id]["state"])
		required_bond_states[bond_id] = bond_state
		if bond_state == "BROKEN":
			status = "OFFLINE"
		elif bond_state == "DEGRADED" and status == "ONLINE":
			status = "DEGRADED"
	if Array(partition["online"]).size() + Array(partition["degraded"]).size() < int(definition["minimum_online_providers"]):
		status = "OFFLINE"
	elif (not Array(partition["degraded"]).is_empty() or not Array(partition["offline"]).is_empty()) and status == "ONLINE":
		status = "DEGRADED"
	var dependency_statuses: Dictionary = {}
	for raw_dependency_id in definition["dependency_utility_ids"]:
		var dependency_id := String(raw_dependency_id)
		var dependency_result := _evaluate_utility(dependency_id, definitions, parts_by_id, bonds_by_id, cache, next_visiting, active_build_state)
		if not bool(dependency_result.get("success", false)):
			return dependency_result
		var dependency_status := String(dependency_result["state"]["status"])
		dependency_statuses[dependency_id] = dependency_status
		if dependency_status == "OFFLINE":
			status = "OFFLINE"
		elif dependency_status == "DEGRADED" and status == "ONLINE":
			status = "DEGRADED"
	if not active_build_state:
		status = "OFFLINE"
	var properties: Dictionary = Dictionary(definition["properties"]).duplicate(true)
	properties["status"] = status
	properties["health_ratio"] = float(partition["health_score"]) / float(Array(definition["provider_part_ids"]).size())
	var state := UtilityStateScript.create(definition, status, partition["online"], partition["degraded"], partition["offline"], properties, {"required_bond_states": required_bond_states, "dependency_statuses": dependency_statuses})
	var checked := UtilityStateScript.validate(state)
	if not bool(checked.get("success", false)):
		return checked
	cache[utility_id] = Dictionary(state).duplicate(true)
	return _success({"state": state})

static func _evaluate_opening(definition: Dictionary, section_states: Dictionary, parts_by_id: Dictionary, bonds_by_id: Dictionary, active_build_state: bool) -> Dictionary:
	var frame_state: Dictionary = section_states[String(definition["frame_section_id"])]
	var status := "INACTIVE"
	var closure_condition := "NONE"
	var access_state := "OPEN"
	var bond_states: Dictionary = {}
	if active_build_state:
		status = "OPEN" if String(definition["opening_kind"]) == "PASSAGE" else "CLOSED"
		var closure_part_id := String(definition["closure_part_id"])
		if not closure_part_id.is_empty():
			var closure_part: Dictionary = parts_by_id[closure_part_id]
			closure_condition = String(Dictionary(closure_part["metadata"]).get("condition", "INTACT"))
			access_state = String(Dictionary(closure_part["metadata"]).get("access_state", "CLOSED"))
			if not PART_CONDITIONS.has(closure_condition):
				return _failure("INVALID_CONSTRUCTION_SPATIAL_CLOSURE_CONDITION")
			if closure_condition == "DESTROYED":
				status = "BREACHED"
			elif access_state == "OPEN":
				status = "OPEN"
			elif String(definition["opening_kind"]) in ["WINDOW", "VENT"]:
				status = "SEALED"
			else:
				status = "CLOSED"
		if String(frame_state["status"]) == "OFFLINE":
			status = "BREACHED"
		elif String(frame_state["status"]) == "DEGRADED" and status in ["CLOSED", "SEALED"]:
			status = "BREACHED"
		for raw_bond_id in definition["required_bond_ids"]:
			var bond_id := String(raw_bond_id)
			var bond_state := String(bonds_by_id[bond_id]["state"])
			bond_states[bond_id] = bond_state
			if bond_state == "BROKEN":
				status = "BREACHED"
	var properties: Dictionary = Dictionary(definition["properties"]).duplicate(true)
	properties["normally_closed"] = bool(definition["normally_closed"])
	properties["status"] = status
	var state := OpeningStateScript.create(definition, status, properties, {"frame_status": String(frame_state["status"]), "closure_condition": closure_condition, "access_state": access_state, "required_bond_states": bond_states})
	var checked := OpeningStateScript.validate(state)
	return _success({"state": state}) if bool(checked.get("success", false)) else checked

static func _evaluate_space(definition: Dictionary, sections: Dictionary, openings: Dictionary, utilities: Dictionary, active_build_state: bool) -> Dictionary:
	var boundary_failures: Array = []
	var degraded_boundary_count := 0
	var active_boundary_count := 0
	for raw_section_id in definition["section_ids"]:
		var section_id := String(raw_section_id)
		var status := String(sections[section_id]["status"])
		if status == "OFFLINE":
			boundary_failures.append(section_id)
		else:
			active_boundary_count += 1
			if status == "DEGRADED":
				degraded_boundary_count += 1
	var open_exterior_openings: Array = []
	var breached_exterior_openings: Array = []
	for raw_opening_id in definition["opening_ids"]:
		var opening_id := String(raw_opening_id)
		var opening: Dictionary = openings[opening_id]
		var exterior := String(opening["from_space_id"]) == "space/exterior" or String(opening["to_space_id"]) == "space/exterior"
		if exterior and String(opening["status"]) == "OPEN" and bool(opening["properties"].get("normally_closed", true)):
			open_exterior_openings.append(opening_id)
		if exterior and String(opening["status"]) == "BREACHED":
			breached_exterior_openings.append(opening_id)
	var available_utilities: Array = []
	var degraded_utility_count := 0
	for raw_utility_id in definition["required_utility_ids"]:
		var utility_id := String(raw_utility_id)
		var status := String(utilities[utility_id]["status"])
		if status != "OFFLINE":
			available_utilities.append(utility_id)
		if status != "ONLINE":
			degraded_utility_count += 1
	var status := "INACTIVE"
	if active_build_state:
		if active_boundary_count < int(definition["minimum_enclosure_sections"]) or not boundary_failures.is_empty() or not breached_exterior_openings.is_empty():
			status = "EXPOSED"
		elif degraded_boundary_count > 0 or not open_exterior_openings.is_empty() or degraded_utility_count > 0:
			status = "DEGRADED"
		else:
			status = "HABITABLE"
	var properties: Dictionary = Dictionary(definition["properties"]).duplicate(true)
	properties["status"] = status
	properties["enclosure_ratio"] = float(active_boundary_count) / float(Array(definition["section_ids"]).size())
	properties["required_utility_count"] = Array(definition["required_utility_ids"]).size()
	properties["available_utility_count"] = available_utilities.size()
	var combined_failures := boundary_failures.duplicate()
	for opening_id in breached_exterior_openings:
		properties["breached_opening_id"] = String(opening_id)
	var state := SpaceStateScript.create(definition, status, combined_failures, open_exterior_openings, available_utilities, properties, {"breached_exterior_opening_ids": breached_exterior_openings, "degraded_boundary_count": degraded_boundary_count, "degraded_utility_count": degraded_utility_count})
	var checked := SpaceStateScript.validate(state)
	return _success({"state": state}) if bool(checked.get("success", false)) else checked

static func _partition_providers(provider_part_ids: Array, parts_by_id: Dictionary) -> Dictionary:
	var online: Array = []
	var degraded: Array = []
	var offline: Array = []
	var health_score := 0.0
	for raw_part_id in provider_part_ids:
		var part_id := String(raw_part_id)
		var condition := String(Dictionary(parts_by_id[part_id]["metadata"]).get("condition", "INTACT"))
		if not PART_CONDITIONS.has(condition):
			return _failure("INVALID_CONSTRUCTION_SPATIAL_PROVIDER_CONDITION")
		match condition:
			"INTACT":
				online.append(part_id)
				health_score += 1.0
			"DEGRADED":
				degraded.append(part_id)
				health_score += 0.5
			"DESTROYED":
				offline.append(part_id)
	online.sort()
	degraded.sort()
	offline.sort()
	return _success({"online": online, "degraded": degraded, "offline": offline, "health_score": health_score})

static func _building_state(space_states: Array, active_build_state: bool) -> String:
	if not active_build_state:
		return "INACTIVE"
	var usable := false
	var degraded := false
	for state in space_states:
		match String(state["status"]):
			"HABITABLE": usable = true
			"DEGRADED":
				usable = true
				degraded = true
			"EXPOSED": degraded = true
	return "INACTIVE" if not usable else ("DEGRADED" if degraded else "ACTIVE")

static func _activation_level(building_state: String, active_build_state: bool) -> String:
	if building_state in ["ACTIVE", "DEGRADED"]:
		return "FUNCTIONAL"
	return "SUMMARY" if active_build_state else "DORMANT"

static func _compile_behavior(space_states: Array, opening_states: Array, utility_states: Array, section_states: Dictionary, capabilities: Array, affordances: Array) -> void:
	for space in space_states:
		if not String(space["status"]) in ["HABITABLE", "DEGRADED"]:
			continue
		var provider_parts: Array = []
		for section_id in space["section_ids"]:
			var section_state: Dictionary = section_states[String(section_id)]
			var section_provider_parts: Array = Array(section_state["online_provider_part_ids"]).duplicate(true)
			section_provider_parts.append_array(Array(section_state["degraded_provider_part_ids"]))
			for part_id in section_provider_parts:
				if not provider_parts.has(String(part_id)):
					provider_parts.append(String(part_id))
		provider_parts.sort()
		if provider_parts.is_empty():
			continue
		var properties: Dictionary = Dictionary(space["properties"]).duplicate(true)
		properties["space_id"] = String(space["space_id"])
		properties["space_status"] = String(space["status"])
		var enclosed := _add_capability(capabilities, "capability/spatial/enclosed/%s" % _id_tail(String(space["space_id"])), "ENCLOSED_SPACE", provider_parts, properties)
		var shelter := _add_capability(capabilities, "capability/spatial/shelter/%s" % _id_tail(String(space["space_id"])), "SHELTER", provider_parts, properties)
		_add_affordance(affordances, "affordance/spatial/inspect/%s" % _id_tail(String(space["space_id"])), "INSPECT_SPACE", enclosed, String(provider_parts[0]), ["INSPECT_CONSTRUCT"], properties, 170)
		_add_affordance(affordances, "affordance/spatial/occupy/%s" % _id_tail(String(space["space_id"])), "OCCUPY_SPACE", shelter, String(provider_parts[0]), [], properties, 180)
	for opening in opening_states:
		if String(opening["opening_kind"]) != "DOOR" or not String(opening["status"]) in ["OPEN", "CLOSED"]:
			continue
		var closure_part_id := String(opening["closure_part_id"])
		if closure_part_id.is_empty():
			continue
		var properties: Dictionary = Dictionary(opening["properties"]).duplicate(true)
		properties["opening_id"] = String(opening["opening_id"])
		properties["from_space_id"] = String(opening["from_space_id"])
		properties["to_space_id"] = String(opening["to_space_id"])
		var access := _add_capability(capabilities, "capability/spatial/access/%s" % _id_tail(String(opening["opening_id"])), "ACCESS_CONTROL", [closure_part_id], properties)
		var action := "CLOSE_DOOR" if String(opening["status"]) == "OPEN" else "OPEN_DOOR"
		_add_affordance(affordances, "affordance/spatial/%s/%s" % [action.to_lower().replace("_", "-"), _id_tail(String(opening["opening_id"]))], action, access, closure_part_id, ["OPERATE_DOOR"], properties, 250)
		_add_affordance(affordances, "affordance/spatial/traverse/%s" % _id_tail(String(opening["opening_id"])), "TRAVERSE_OPENING", access, closure_part_id, [], properties, 220)
	for utility in utility_states:
		if String(utility["status"]) == "OFFLINE" or Array(utility["online_provider_part_ids"]).is_empty():
			continue
		var provider_parts: Array = Array(utility["online_provider_part_ids"]).duplicate(true)
		provider_parts.append_array(Array(utility["degraded_provider_part_ids"]))
		provider_parts.sort()
		var kind := String(utility["utility_kind"])
		var properties: Dictionary = Dictionary(utility["properties"]).duplicate(true)
		properties["utility_id"] = String(utility["utility_id"])
		properties["utility_status"] = String(utility["status"])
		var capability_kind := "%s_DISTRIBUTION" % kind
		var capability := _add_capability(capabilities, "capability/spatial/utility/%s" % kind.to_lower(), capability_kind, provider_parts, properties)
		_add_affordance(affordances, "affordance/spatial/use-utility/%s" % kind.to_lower(), "USE_UTILITY", capability, String(provider_parts[0]), ["OPERATE_UTILITY"], properties, 160)
		if kind == "POWER" and bool(properties.get("lighting", false)):
			_add_affordance(affordances, "affordance/spatial/toggle-lighting", "TOGGLE_LIGHTING", capability, String(provider_parts[0]), [], properties, 190)

static func _add_capability(capabilities: Array, capability_id: String, capability_kind: String, provider_parts: Array, properties: Dictionary) -> Dictionary:
	var capability := CapabilityScript.create(capability_id, capability_kind, provider_parts, [], properties)
	capabilities.append(capability)
	return capability

static func _add_affordance(affordances: Array, affordance_id: String, action_kind: String, capability: Dictionary, target_part_id: String, actor_requirements: Array, parameters: Dictionary, priority: int) -> void:
	affordances.append(AffordanceScript.create(affordance_id, action_kind, String(capability["capability_id"]), target_part_id, "", actor_requirements, parameters, priority))

static func _count_status(states: Array, status: String) -> int:
	var count := 0
	for state in states:
		if String(state["status"]) == status:
			count += 1
	return count

static func _id_tail(value: String) -> String:
	return value.replace("/", "-")

static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
