extends RefCounted
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const DefinitionScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_definition.gd")
const ProfileScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_profile.gd")
const BehaviorProfileScript = preload("res://scripts/construction/behavior/construction_behavior_profile.gd")
const SpatialProfileScript = preload("res://scripts/construction/spatial/construction_spatial_profile.gd")
const CapabilityScript = preload("res://scripts/construction/behavior/construction_capability_descriptor.gd")
const AffordanceScript = preload("res://scripts/construction/behavior/construction_affordance_descriptor.gd")
static func compile(snapshot: Dictionary, definition: Dictionary, behavior_profile: Dictionary, spatial_profile: Dictionary = {}) -> Dictionary:
	var checked := SnapshotScript.validate(snapshot); if not bool(checked.get("success", false)): return checked
	checked = DefinitionScript.validate(definition); if not bool(checked.get("success", false)): return checked
	checked = BehaviorProfileScript.validate(behavior_profile); if not bool(checked.get("success", false)): return checked
	if String(behavior_profile["construct_id"]) != String(snapshot["construct_id"]) or String(behavior_profile["construct_checksum"]) != String(snapshot["checksum"]): return _failure("CONSTRUCTION_FABRICATION_BEHAVIOR_PROFILE_MISMATCH")
	if not spatial_profile.is_empty():
		checked = SpatialProfileScript.validate(spatial_profile); if not bool(checked.get("success", false)): return checked
	var parts: Dictionary = {}; for part in snapshot["parts"]: parts[String(part["part_id"])] = part
	var bonds: Dictionary = {}; for bond in snapshot["bonds"]: bonds[String(bond["bond_id"])] = bond
	var providers: Array = []; var intact := 0; var degraded := 0
	for part_id in definition["provider_part_ids"]:
		if not parts.has(String(part_id)): return _failure("CONSTRUCTION_FABRICATION_MACHINE_PROVIDER_MISSING")
		var condition := String(Dictionary(parts[String(part_id)].get("metadata", {})).get("condition", "INTACT"))
		providers.append({"part_id": String(part_id), "condition": condition})
		if condition == "INTACT": intact += 1
		elif condition == "DEGRADED": degraded += 1
	var bond_degraded := false; var bond_offline := false
	for bond_id in definition["required_bond_ids"]:
		if not bonds.has(String(bond_id)): return _failure("CONSTRUCTION_FABRICATION_MACHINE_BOND_MISSING")
		var state := String(bonds[String(bond_id)]["state"])
		if state == "BROKEN": bond_offline = true
		elif state == "DEGRADED": bond_degraded = true
	var behavior_kinds: Dictionary = {}; for capability in behavior_profile["capabilities"]: behavior_kinds[String(capability["capability_kind"])] = true
	var behavior_ok := bool(behavior_profile["operational"])
	for kind in definition["required_behavior_capability_kinds"]: behavior_ok = behavior_ok and behavior_kinds.has(String(kind))
	var utility_rows: Array = []; var utility_offline := false; var utility_degraded := false
	var utilities: Dictionary = {}
	if not spatial_profile.is_empty():
		for utility in spatial_profile["utility_states"]: utilities[String(utility["utility_id"])] = utility
	for utility_id in definition["required_utility_ids"]:
		if not utilities.has(String(utility_id)): utility_offline = true; utility_rows.append({"utility_id": String(utility_id), "status": "MISSING"}); continue
		var status := String(utilities[String(utility_id)]["status"]); utility_rows.append({"utility_id": String(utility_id), "status": status})
		if status == "OFFLINE": utility_offline = true
		elif status == "DEGRADED": utility_degraded = true
	var active := ["OPERATIONAL", "DAMAGED"].has(String(snapshot["build_state"]))
	var status := "ONLINE"
	if not active or not behavior_ok or bond_offline or utility_offline or intact + degraded < int(definition["minimum_intact_providers"]): status = "OFFLINE"
	elif degraded > 0 or bond_degraded or utility_degraded or intact < Array(definition["provider_part_ids"]).size(): status = "DEGRADED"
	var capabilities: Array = []; var affordances: Array = []
	if status != "OFFLINE":
		var part_id := String(definition["provider_part_ids"][0])
		for kind in ["FABRICATION_CELL", "MATERIAL_INPUT", "PRODUCT_OUTPUT"]:
			capabilities.append(CapabilityScript.create("capability/%s/%s" % [String(kind).to_lower().replace("_", "-"), String(snapshot["construct_id"])], kind, [part_id], [], {"machine_status": status, "machine_definition_id": String(definition["machine_definition_id"])}))
		var actions := [["QUEUE_FABRICATION_JOB", "FABRICATION_CELL", 250], ["START_FABRICATION_JOB", "MATERIAL_INPUT", 240], ["ADVANCE_FABRICATION_JOB", "FABRICATION_CELL", 230], ["COMPLETE_FABRICATION_JOB", "PRODUCT_OUTPUT", 240], ["CANCEL_FABRICATION_JOB", "MATERIAL_INPUT", 220]]
		for row in actions:
			var kind := String(row[1]); var cap_id := "capability/%s/%s" % [kind.to_lower().replace("_", "-"), String(snapshot["construct_id"])]
			affordances.append(AffordanceScript.create("affordance/%s/%s" % [String(row[0]).to_lower().replace("_", "-"), String(snapshot["construct_id"])], String(row[0]), cap_id, part_id, "", ["OPERATE_FABRICATION_CELL"], {"input_container_id": String(definition["input_container_id"]), "output_container_id": String(definition["output_container_id"])}, int(row[2])))
	var profile := ProfileScript.create(snapshot, definition, status, providers, utility_rows, capabilities, affordances, {"behavior_ok": behavior_ok, "intact_provider_count": intact, "degraded_provider_count": degraded})
	checked = ProfileScript.validate(profile); return _success({"profile": profile}) if bool(checked.get("success", false)) else checked
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result
static func _failure(code: String) -> Dictionary: return {"success": false, "error_code": code, "message": code}
