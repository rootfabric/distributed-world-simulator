extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")
const ProfileScript = preload("res://scripts/construction/behavior/construction_behavior_profile.gd")

const PORT_FIELDS: Array[String] = ["port_id", "part_id", "port_kind", "local_position_m", "metadata"]

const ACTION_PLACE_ITEM: String = "PLACE_ITEM"
const ACTION_USE_WORK_SURFACE: String = "USE_WORK_SURFACE"
const ACTION_MOUNT_ITEM: String = "MOUNT_ITEM"
const ACTION_OPEN_CONTAINER: String = "OPEN_CONTAINER"
const ACTION_STORE_ITEM: String = "STORE_ITEM"
const ACTION_TAKE_ITEM: String = "TAKE_ITEM"
const ACTION_SIT: String = "SIT"
const ACTION_CLIMB: String = "CLIMB"
const ACTION_USE_WORKSTATION: String = "USE_WORKSTATION"


static func compile(snapshot: Dictionary) -> Dictionary:
	var snapshot_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return snapshot_validation
	var operational: bool = String(snapshot["build_state"]) == "OPERATIONAL"
	var facets: Dictionary = snapshot["compiled_facets"]
	if facets.has("operational") and typeof(facets["operational"]) == TYPE_BOOL:
		operational = operational and bool(facets["operational"])
	var part_map: Dictionary = {}
	for part in snapshot["parts"]:
		part_map[String(part["part_id"])] = Dictionary(part).duplicate(true)
	var source_capabilities: Dictionary = _source_capability_set(facets.get("capabilities", []))
	if not bool(source_capabilities.get("success", false)):
		return source_capabilities
	var ports_result: Dictionary = _validated_ports(facets.get("composite_exposed_ports", []), part_map)
	if not bool(ports_result.get("success", false)):
		return ports_result
	var ports: Array = ports_result["ports"]
	var capabilities_by_id: Dictionary = {}
	var affordances_by_id: Dictionary = {}
	if operational:
		var surface_targets: Array = []
		for port in ports:
			var port_kind: String = String(port["port_kind"])
			match port_kind:
				"SUPPORT_SURFACE":
					surface_targets.append(_target_from_port(port, facets))
				"MOUNT_POINT", "MOUNTING_SURFACE":
					_add_behavior(
						capabilities_by_id,
						affordances_by_id,
						"MOUNTING_SURFACE",
						ACTION_MOUNT_ITEM,
						_target_from_port(port, facets),
						["INSTALL_COMPONENT"],
						220
					)
				"CONTAINER_ACCESS":
					var container_target: Dictionary = _target_from_port(port, facets)
					_add_behavior(capabilities_by_id, affordances_by_id, "CONTAINER", ACTION_OPEN_CONTAINER, container_target, ["INTERACT"], 220)
					_add_affordance_for_existing(capabilities_by_id, affordances_by_id, "CONTAINER", ACTION_STORE_ITEM, container_target, ["MANIPULATE_ITEM"], 210)
					_add_affordance_for_existing(capabilities_by_id, affordances_by_id, "CONTAINER", ACTION_TAKE_ITEM, container_target, ["MANIPULATE_ITEM"], 210)
				"SEAT":
					_add_behavior(capabilities_by_id, affordances_by_id, "SEAT", ACTION_SIT, _target_from_port(port, facets), ["LOCOMOTION"], 200)
				"CLIMB_POINT", "CLIMBABLE":
					_add_behavior(capabilities_by_id, affordances_by_id, "CLIMBABLE", ACTION_CLIMB, _target_from_port(port, facets), ["LOCOMOTION_CLIMB"], 200)
				"WORKSTATION":
					_add_behavior(capabilities_by_id, affordances_by_id, "WORKSTATION", ACTION_USE_WORKSTATION, _target_from_port(port, facets), ["OPERATE_WORKSTATION"], 230)
				_:
					pass
		if surface_targets.is_empty():
			for part in snapshot["parts"]:
				if String(part["role"]) == "surface":
					surface_targets.append(_target_from_part(part, facets))
		if source_capabilities["set"].has("SUPPORT_SURFACE") or not surface_targets.is_empty():
			for target in surface_targets:
				_add_capability_only(capabilities_by_id, "SUPPORT_SURFACE", target)
		if source_capabilities["set"].has("PLACE_ITEMS"):
			for target in surface_targets:
				_add_behavior(capabilities_by_id, affordances_by_id, "PLACE_ITEMS", ACTION_PLACE_ITEM, target, ["MANIPULATE_ITEM"], 240)
		if source_capabilities["set"].has("WORK_SURFACE"):
			for target in surface_targets:
				_add_behavior(capabilities_by_id, affordances_by_id, "WORK_SURFACE", ACTION_USE_WORK_SURFACE, target, ["MANIPULATE_ITEM"], 230)
	var capabilities: Array = _sorted_values(capabilities_by_id, "capability_id")
	var affordances: Array = _sorted_values(affordances_by_id, "affordance_id")
	var diagnostics: Dictionary = {
		"source_capability_kinds": source_capabilities["kinds"],
		"part_count": snapshot["parts"].size(),
		"exposed_port_count": ports.size(),
		"compiled_capability_count": capabilities.size(),
		"compiled_affordance_count": affordances.size(),
		"rebuildable_projection": true,
	}
	var profile: Dictionary = ProfileScript.create(snapshot, operational, capabilities, affordances, diagnostics)
	var profile_validation: Dictionary = ProfileScript.validate(profile)
	if not bool(profile_validation.get("success", false)):
		return profile_validation
	return _success({"profile": profile})


static func _source_capability_set(value) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_SOURCE_CAPABILITIES")
	var set: Dictionary = {}
	var kinds: Array = []
	for raw in value:
		if typeof(raw) != TYPE_STRING:
			return _failure("INVALID_CONSTRUCTION_SOURCE_CAPABILITY")
		var kind: String = String(raw)
		if not _is_upper_kind(kind) or set.has(kind):
			return _failure("INVALID_CONSTRUCTION_SOURCE_CAPABILITY")
		set[kind] = true
		kinds.append(kind)
	kinds.sort()
	return _success({"set": set, "kinds": kinds})


static func _validated_ports(value, part_map: Dictionary) -> Dictionary:
	if value == null:
		return _success({"ports": []})
	if typeof(value) != TYPE_ARRAY:
		return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORTS")
	var ports: Array = []
	var seen: Dictionary = {}
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY:
			return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT")
		var port: Dictionary = raw
		var exact: Dictionary = UtilsScript.validate_exact_fields(port, PORT_FIELDS)
		if not bool(exact.get("success", false)):
			return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT_FIELDS", {"cause": exact})
		var port_id: String = String(port.get("port_id", ""))
		var part_id: String = String(port.get("part_id", ""))
		if not _is_path_id(port_id, "port/") or seen.has(port_id):
			return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT_ID")
		if not part_map.has(part_id):
			return _failure("CONSTRUCTION_COMPILED_EXPOSED_PORT_PART_MISSING")
		if not _is_upper_kind(String(port.get("port_kind", ""))):
			return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT_KIND")
		if typeof(port.get("local_position_m")) != TYPE_ARRAY or port["local_position_m"].size() != 3:
			return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT_POSITION")
		for component in port["local_position_m"]:
			if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(component)):
				return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT_POSITION")
		if typeof(port.get("metadata")) != TYPE_DICTIONARY or not bool(UtilsScript.canonicalize(port["metadata"]).get("success", false)):
			return _failure("INVALID_CONSTRUCTION_COMPILED_EXPOSED_PORT_METADATA")
		seen[port_id] = true
		ports.append(Dictionary(port).duplicate(true))
	ports.sort_custom(func(left, right): return String(left["port_id"]) < String(right["port_id"]))
	return _success({"ports": ports})


static func _target_from_port(port: Dictionary, facets: Dictionary) -> Dictionary:
	return {
		"target_key": String(port["port_id"]),
		"part_id": String(port["part_id"]),
		"port_id": String(port["port_id"]),
		"properties": _target_properties(
			"PORT",
			String(port["port_kind"]),
			Array(port["local_position_m"]),
			Dictionary(port["metadata"]),
			facets
		),
	}


static func _target_from_part(part: Dictionary, facets: Dictionary) -> Dictionary:
	return {
		"target_key": String(part["part_id"]),
		"part_id": String(part["part_id"]),
		"port_id": "",
		"properties": _target_properties(
			"PART",
			String(part["role"]).to_upper(),
			Array(part["local_position_m"]),
			Dictionary(part["metadata"]),
			facets
		),
	}


static func _target_properties(
	source_kind: String,
	source_semantic_kind: String,
	local_position_m: Array,
	metadata: Dictionary,
	facets: Dictionary
) -> Dictionary:
	var properties: Dictionary = {
		"source_kind": source_kind,
		"source_semantic_kind": source_semantic_kind,
		"local_position_m": local_position_m.duplicate(true),
		"metadata": metadata.duplicate(true),
	}
	var parameters = facets.get("composite_parameters", {})
	if typeof(parameters) == TYPE_DICTIONARY:
		var parameter_values: Dictionary = parameters
		if parameter_values.has("parameter/load-rating-kg"):
			properties["load_rating_kg"] = parameter_values["parameter/load-rating-kg"]
		if parameter_values.has("parameter/finish"):
			properties["finish"] = parameter_values["parameter/finish"]
	return properties


static func _add_behavior(
	capabilities_by_id: Dictionary,
	affordances_by_id: Dictionary,
	capability_kind: String,
	action_kind: String,
	target: Dictionary,
	actor_requirements: Array,
	priority: int
) -> void:
	var capability: Dictionary = _add_capability_only(capabilities_by_id, capability_kind, target)
	var target_key: String = String(target["target_key"])
	var affordance_id: String = "affordance/%s/%s" % [action_kind.to_lower().replace("_", "-"), target_key]
	if affordances_by_id.has(affordance_id):
		return
	affordances_by_id[affordance_id] = AffordanceScript.create(
		affordance_id,
		action_kind,
		String(capability["capability_id"]),
		String(target["part_id"]),
		String(target["port_id"]),
		actor_requirements,
		Dictionary(target["properties"]),
		priority
	)


static func _add_affordance_for_existing(
	capabilities_by_id: Dictionary,
	affordances_by_id: Dictionary,
	capability_kind: String,
	action_kind: String,
	target: Dictionary,
	actor_requirements: Array,
	priority: int
) -> void:
	_add_behavior(capabilities_by_id, affordances_by_id, capability_kind, action_kind, target, actor_requirements, priority)


static func _add_capability_only(
	capabilities_by_id: Dictionary,
	capability_kind: String,
	target: Dictionary
) -> Dictionary:
	var target_key: String = String(target["target_key"])
	var capability_id: String = "capability/%s/%s" % [capability_kind.to_lower().replace("_", "-"), target_key]
	if not capabilities_by_id.has(capability_id):
		var ports: Array = [] if String(target["port_id"]).is_empty() else [String(target["port_id"])]
		capabilities_by_id[capability_id] = CapabilityScript.create(
			capability_id,
			capability_kind,
			[String(target["part_id"])],
			ports,
			Dictionary(target["properties"])
		)
	return capabilities_by_id[capability_id]


static func _sorted_values(values: Dictionary, id_field: String) -> Array:
	var result: Array = values.values()
	result.sort_custom(func(left, right): return String(left.get(id_field, "")) < String(right.get(id_field, "")))
	return result


static func _is_path_id(value: String, prefix: String) -> bool:
	if not value.begins_with(prefix) or value.length() <= prefix.length() or value != value.to_lower() or value.contains("//"):
		return false
	for segment in value.split("/", true):
		if segment.is_empty():
			return false
		for character in segment:
			if not String(character) in "abcdefghijklmnopqrstuvwxyz0123456789-_":
				return false
	return true


static func _is_upper_kind(value: String) -> bool:
	if value.is_empty() or value != value.to_upper():
		return false
	for character in value:
		if not String(character) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_":
			return false
	return true


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
