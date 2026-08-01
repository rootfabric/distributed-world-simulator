extends RefCounted

const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const LoadCaseScript = preload("res://scripts/construction/structural/construction_structural_load_case.gd")
const CompilerScript = preload("res://scripts/construction/structural/construction_structural_compiler.gd")
const CascadePlanScript = preload("res://scripts/construction/structural/construction_structural_cascade_plan.gd")
const DamageRequestScript = preload("res://scripts/construction/damage/construction_damage_request.gd")
const SalvagePolicyScript = preload("res://scripts/construction/damage/construction_salvage_policy.gd")

static func build(cascade_id: String, snapshot: Dictionary, load_case: Dictionary) -> Dictionary:
	var snapshot_validation := SnapshotScript.validate(snapshot); if not bool(snapshot_validation.get("success", false)): return snapshot_validation
	var load_validation := LoadCaseScript.validate(load_case); if not bool(load_validation.get("success", false)): return load_validation
	if not cascade_id.begins_with("cascade/"): return _failure("INVALID_CONSTRUCTION_STRUCTURAL_CASCADE_ID")
	if String(snapshot["checksum"]) != String(load_case["source_snapshot_checksum"]): return _failure("CONSTRUCTION_STRUCTURAL_SOURCE_CHECKSUM_MISMATCH")
	var current := snapshot.duplicate(true)
	var failed_bonds: Array = []
	var part_conditions := {}
	var profiles: Array = []
	var maximum_steps := int(load_case["maximum_cascade_steps"])
	for step in range(maximum_steps + 1):
		var step_case := load_case.duplicate(true)
		step_case["source_snapshot_checksum"] = String(current["checksum"])
		step_case["checksum"] = LoadCaseScript.compute_checksum(step_case)
		var compiled := CompilerScript.compile(current, step_case)
		if not bool(compiled.get("success", false)): return compiled
		var profile: Dictionary = compiled["profile"]; profiles.append(profile)
		var failure := _next_failure(profile, float(load_case["collapse_utilization"]))
		if failure.is_empty(): break
		if step >= maximum_steps: return _failure("CONSTRUCTION_STRUCTURAL_CASCADE_LIMIT_EXCEEDED")
		if String(failure["kind"]) == "BOND":
			var bond_id := String(failure["id"])
			if not failed_bonds.has(bond_id): failed_bonds.append(bond_id)
		else:
			var part_id := String(failure["id"]); var condition := String(failure["condition"])
			part_conditions[part_id] = condition
			if condition == "DESTROYED":
				for bond in current["bonds"]:
					if String(bond["part_a_id"]) == part_id or String(bond["part_b_id"]) == part_id:
						var adjacent := String(bond["bond_id"]); if not failed_bonds.has(adjacent): failed_bonds.append(adjacent)
		current = _apply_failures(snapshot, failed_bonds, part_conditions, step + 1)
	failed_bonds.sort()
	var damage_request := {}
	if not failed_bonds.is_empty() or not part_conditions.is_empty():
		var retained_part_id := String(load_case["support_part_ids"][0])
		var split_targets := _split_targets(snapshot, failed_bonds, part_conditions, retained_part_id, int(load_case["minimum_split_parts"]), String(load_case["checksum"]))
		var policy := SalvagePolicyScript.create(int(load_case["minimum_split_parts"]), load_case["salvage_relation"], false)
		damage_request = DamageRequestScript.create(
			"damage/structural/%s" % String(load_case["checksum"]).substr(0, 20), String(snapshot["construct_id"]), String(snapshot["checksum"]), retained_part_id,
			failed_bonds, [], part_conditions, split_targets, policy
		)
	var stable := failed_bonds.is_empty() and part_conditions.is_empty() and String(profiles[-1]["structural_state"]) == "STABLE"
	var plan := CascadePlanScript.create(cascade_id, String(snapshot["construct_id"]), String(snapshot["checksum"]), String(load_case["checksum"]), profiles, failed_bonds, part_conditions, damage_request, stable)
	var plan_validation := CascadePlanScript.validate(plan); if not bool(plan_validation.get("success", false)): return plan_validation
	return _success({"plan": plan, "final_profile": profiles[-1], "damage_request": damage_request})

static func _next_failure(profile: Dictionary, collapse_utilization: float) -> Dictionary:
	var part_candidates: Array = []
	for state in profile["part_states"]:
		if String(state["state"]) == "OVERLOADED": part_candidates.append(state)
	part_candidates.sort_custom(func(a, b):
		var au := float(a["utilization"]); var bu := float(b["utilization"])
		return au > bu if absf(au - bu) > 0.000000001 else String(a["part_id"]) < String(b["part_id"])
	)
	if not part_candidates.is_empty():
		var top: Dictionary = part_candidates[0]
		return {"kind": "PART", "id": String(top["part_id"]), "condition": "DESTROYED" if float(top["utilization"]) >= collapse_utilization else "DEGRADED"}
	var bond_candidates: Array = []
	for state in profile["bond_states"]:
		if String(state["state"]) == "OVERLOADED": bond_candidates.append(state)
	bond_candidates.sort_custom(func(a, b):
		var au := float(a["utilization"]); var bu := float(b["utilization"])
		return au > bu if absf(au - bu) > 0.000000001 else String(a["bond_id"]) < String(b["bond_id"])
	)
	if not bond_candidates.is_empty(): return {"kind": "BOND", "id": String(bond_candidates[0]["bond_id"])}
	return {}

static func _apply_failures(source: Dictionary, failed_bonds: Array, part_conditions: Dictionary, step: int) -> Dictionary:
	var parts: Array = []
	for raw in source["parts"]:
		var part: Dictionary = raw.duplicate(true); var part_id := String(part["part_id"])
		if part_conditions.has(part_id):
			var metadata: Dictionary = part["metadata"].duplicate(true); metadata["condition"] = String(part_conditions[part_id]); part["metadata"] = metadata
		parts.append(part)
	var bonds: Array = []
	for raw in source["bonds"]:
		var bond: Dictionary = raw.duplicate(true)
		if failed_bonds.has(String(bond["bond_id"])): bond["state"] = "BROKEN"
		bonds.append(bond)
	var facets: Dictionary = source["compiled_facets"].duplicate(true); facets["structural_cascade_preview_step"] = step
	return SnapshotScript.create(String(source["construct_id"]), String(source["root_item_instance_id"]), int(source["state_revision"]) + step, "DAMAGED", parts, bonds, facets)

static func _split_targets(source: Dictionary, failed_bonds: Array, part_conditions: Dictionary, retained_part_id: String, minimum_split_parts: int, seed: String) -> Array:
	var active := {}; for part in source["parts"]:
		var part_id := String(part["part_id"]); var condition := String(part_conditions.get(part_id, part.get("metadata", {}).get("condition", "INTACT")))
		if condition != "DESTROYED": active[part_id] = true
	var adjacency := {}; for part_id in active: adjacency[part_id] = []
	for bond in source["bonds"]:
		if failed_bonds.has(String(bond["bond_id"])) or String(bond["state"]) == "BROKEN": continue
		var a := String(bond["part_a_id"]); var b := String(bond["part_b_id"])
		if active.has(a) and active.has(b): adjacency[a].append(b); adjacency[b].append(a)
	var components: Array = []; var visited := {}; var ids: Array = active.keys(); ids.sort()
	for start in ids:
		if visited.has(start): continue
		var stack: Array = [start]; var component: Array = []; visited[start] = true
		while not stack.is_empty():
			var current = stack.pop_back(); component.append(current)
			var neighbors: Array = adjacency[current].duplicate(); neighbors.sort()
			for neighbor in neighbors:
				if not visited.has(neighbor): visited[neighbor] = true; stack.append(neighbor)
		component.sort(); components.append(component)
	components.sort_custom(func(a, b): return String(a[0]) < String(b[0]))
	var targets: Array = []; var index := 0
	for component in components:
		if component.has(retained_part_id) or component.size() < minimum_split_parts: continue
		index += 1
		targets.append(DamageRequestScript.split_target(
			"%s/structural-split-%02d" % [String(source["construct_id"]), index],
			"item/structural-split/%s/%02d" % [seed.substr(0, 16), index]
		))
	return targets

static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}; for key in details: result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
