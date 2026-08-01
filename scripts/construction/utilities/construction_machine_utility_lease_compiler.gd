extends RefCounted

const ContractUtils = preload("res://scripts/construction/utilities/construction_utility_contract_utils.gd")
const LeaseScript = preload("res://scripts/construction/utilities/construction_machine_utility_lease.gd")
const ExecutionProfileScript = preload("res://scripts/construction/utilities/construction_utility_execution_profile.gd")
const MachineProfileScript = preload("res://scripts/construction/fabrication/construction_fabrication_machine_profile.gd")
const RecipeScript = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")

static func compile(lease_id: String, machine_profile: Dictionary, job_id: String, recipe: Dictionary, requirements: Array, execution_profiles: Array, tick: int) -> Dictionary:
	var checked := MachineProfileScript.validate(machine_profile); if not bool(checked.get("success", false)): return checked
	checked = RecipeScript.validate(recipe); if not bool(checked.get("success", false)): return checked
	var profiles := {}; for profile in execution_profiles:
		if typeof(profile) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_EXECUTION_PROFILE")
		checked = ExecutionProfileScript.validate(profile); if not bool(checked.get("success", false)): return checked
		var network_id := String(profile["network_id"]); if profiles.has(network_id): return ContractUtils.failure("DUPLICATE_CONSTRUCTION_MACHINE_UTILITY_EXECUTION_PROFILE")
		profiles[network_id] = profile
	var required_kinds: Array = recipe["required_utility_kinds"].duplicate(); required_kinds.sort()
	if requirements.size() != required_kinds.size(): return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_REQUIREMENTS_MISMATCH")
	var rows: Array = []; var seen_kinds := {}; var profile_checksums := {}; var allocation_checksums := {}; var max_work := 2147483647; var degraded := false; var offline := String(machine_profile["status"]) == "OFFLINE"
	for raw in requirements:
		if typeof(raw) != TYPE_DICTIONARY: return ContractUtils.failure("INVALID_CONSTRUCTION_MACHINE_UTILITY_REQUIREMENT")
		var exact := preload("res://scripts/network/contracts/network_contract_utils.gd").validate_exact_fields(raw, LeaseScript.REQUIREMENT_FIELDS); if not bool(exact.get("success", false)): return exact
		var row: Dictionary = raw.duplicate(true); var kind := String(row.get("utility_kind", "")); var network_id := String(row.get("network_id", "")); var demand_id := String(row.get("demand_id", ""))
		if not required_kinds.has(kind) or seen_kinds.has(kind) or not profiles.has(network_id): return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_REQUIREMENT_NOT_SATISFIED")
		var profile: Dictionary = profiles[network_id]
		if String(profile["utility_kind"]) != kind or int(profile["tick"]) != tick: return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_PROFILE_MISMATCH")
		var allocation := _find_allocation(profile, demand_id); if allocation.is_empty(): return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_ALLOCATION_NOT_FOUND")
		var ratio := float(allocation["delivered_per_tick"]) / float(allocation["requested_per_tick"])
		var units := int(floor(float(allocation["delivered_per_tick"]) / float(row["units_per_work_unit"])))
		if String(allocation["status"]) == "SHED" or ratio + 0.000001 < float(row["minimum_ratio"]) or units < 1: offline = true
		elif String(allocation["status"]) == "PARTIAL": degraded = true
		max_work = mini(max_work, units); profile_checksums[network_id] = String(profile["checksum"]); allocation_checksums[demand_id] = String(allocation["checksum"]); seen_kinds[kind] = true; rows.append(row)
	for kind in required_kinds:
		if not seen_kinds.has(String(kind)): return ContractUtils.failure("CONSTRUCTION_MACHINE_UTILITY_KIND_NOT_BOUND")
	if max_work == 2147483647: max_work = 0
	var status := "OFFLINE" if offline else ("DEGRADED" if degraded or String(machine_profile["status"]) == "DEGRADED" else "ONLINE")
	if status == "OFFLINE": max_work = 0
	var lease := LeaseScript.create(lease_id, String(machine_profile["construct_id"]), job_id, String(machine_profile["checksum"]), String(recipe["checksum"]), tick, status, max_work, rows, profile_checksums, allocation_checksums)
	checked = LeaseScript.validate(lease); return ContractUtils.success({"lease": lease}) if bool(checked.get("success", false)) else checked

static func _find_allocation(profile: Dictionary, demand_id: String) -> Dictionary:
	for allocation in profile["allocations"]:
		if String(allocation["demand_id"]) == demand_id: return allocation
	return {}
