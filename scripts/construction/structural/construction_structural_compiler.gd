extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SnapshotScript = preload("res://scripts/construction/contracts/construct_snapshot.gd")
const LoadCaseScript = preload("res://scripts/construction/structural/construction_structural_load_case.gd")
const LoadPathScript = preload("res://scripts/construction/structural/construction_structural_load_path.gd")
const PartStateScript = preload("res://scripts/construction/structural/construction_structural_part_state.gd")
const BondStateScript = preload("res://scripts/construction/structural/construction_structural_bond_state.gd")
const ProfileScript = preload("res://scripts/construction/structural/construction_structural_profile.gd")

static func compile(snapshot: Dictionary, load_case: Dictionary) -> Dictionary:
	var snapshot_validation := SnapshotScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)): return snapshot_validation
	var load_validation := LoadCaseScript.validate(load_case)
	if not bool(load_validation.get("success", false)): return load_validation
	if String(snapshot["construct_id"]) != String(load_case["construct_id"]): return _failure("CONSTRUCTION_STRUCTURAL_LOAD_CASE_CONSTRUCT_MISMATCH")
	if String(snapshot["checksum"]) != String(load_case["source_snapshot_checksum"]): return _failure("CONSTRUCTION_STRUCTURAL_SOURCE_CHECKSUM_MISMATCH")
	var parts := {}
	for raw in snapshot["parts"]: parts[String(raw["part_id"])] = Dictionary(raw).duplicate(true)
	var supports := {}
	for raw_id in load_case["support_part_ids"]:
		var support_id := String(raw_id)
		if not parts.has(support_id): return _failure("CONSTRUCTION_STRUCTURAL_SUPPORT_PART_NOT_FOUND", {"part_id": support_id})
		if _condition(parts[support_id]) == "DESTROYED": return _failure("CONSTRUCTION_STRUCTURAL_SUPPORT_PART_DESTROYED", {"part_id": support_id})
		supports[support_id] = true
	for part_id in load_case["external_part_loads_n"]:
		if not parts.has(String(part_id)): return _failure("CONSTRUCTION_STRUCTURAL_EXTERNAL_LOAD_PART_NOT_FOUND", {"part_id": part_id})
	var bonds := {}
	var adjacency := {}
	for part_id in parts:
		if _condition(parts[part_id]) != "DESTROYED": adjacency[part_id] = []
	for raw in snapshot["bonds"]:
		var bond: Dictionary = Dictionary(raw).duplicate(true)
		var bond_id := String(bond["bond_id"]); bonds[bond_id] = bond
		if String(bond["state"]) == "BROKEN": continue
		var a := String(bond["part_a_id"]); var b := String(bond["part_b_id"])
		if adjacency.has(a) and adjacency.has(b):
			adjacency[a].append({"part_id": b, "bond_id": bond_id})
			adjacency[b].append({"part_id": a, "bond_id": bond_id})
	for part_id in adjacency:
		adjacency[part_id].sort_custom(func(a, b):
			var ap := String(a["part_id"]); var bp := String(b["part_id"])
			return ap < bp if ap != bp else String(a["bond_id"]) < String(b["bond_id"])
		)
	var path_records: Array = []
	var part_path_ids := {}; var bond_path_ids := {}; var transmitted := {}; var reactions := {}; var bond_loads := {}
	for part_id in parts:
		part_path_ids[part_id] = []; transmitted[part_id] = 0.0; reactions[part_id] = 0.0
	for bond_id in bonds:
		bond_path_ids[bond_id] = []; bond_loads[bond_id] = 0.0
	var unsupported: Array = []
	var source_ids: Array = parts.keys(); source_ids.sort()
	var path_sequence := 0
	for source_id in source_ids:
		var source: Dictionary = parts[source_id]
		if _condition(source) == "DESTROYED" or supports.has(source_id): continue
		var applied := _part_applied_load(source, load_case)
		if applied <= 0.0: continue
		var routes := _shortest_support_routes(source_id, supports, adjacency)
		if routes.is_empty():
			unsupported.append(source_id)
			continue
		var share := applied / float(routes.size())
		for route in routes:
			path_sequence += 1
			var path_id := "load-path/%s/%04d" % [String(load_case["checksum"]).substr(0, 12), path_sequence]
			var path := LoadPathScript.create(path_id, source_id, String(route["support_part_id"]), route["part_ids"], route["bond_ids"], _rounded(share))
			path_records.append(path)
			for route_part_id in route["part_ids"]:
				part_path_ids[route_part_id].append(path_id)
				if String(route_part_id) != source_id: transmitted[route_part_id] = float(transmitted[route_part_id]) + share
			for route_bond_id in route["bond_ids"]:
				bond_path_ids[route_bond_id].append(path_id); bond_loads[route_bond_id] = float(bond_loads[route_bond_id]) + share
			reactions[String(route["support_part_id"])] = float(reactions[String(route["support_part_id"])]) + share
	var part_states: Array = []
	for part_id in source_ids:
		var part: Dictionary = parts[part_id]
		var condition := _condition(part)
		var self_weight := float(part["mass_kg"]) * float(load_case["gravity_m_s2"]) if condition != "DESTROYED" else 0.0
		var external := float(load_case["external_part_loads_n"].get(part_id, 0.0)) if condition != "DESTROYED" else 0.0
		var capacity := _part_capacity(part, load_case)
		var total_demand := self_weight + external + float(transmitted[part_id])
		var utilization := total_demand / capacity if capacity > 0.0 else 0.0
		var state := "OK"
		if condition == "DESTROYED": state = "DESTROYED"
		elif unsupported.has(part_id): state = "UNSUPPORTED"
		elif utilization > 1.0: state = "OVERLOADED"
		elif supports.has(part_id): state = "SUPPORT"
		part_states.append(PartStateScript.create(part_id, supports.has(part_id), condition, _rounded(self_weight), _rounded(external), _rounded(transmitted[part_id]), _rounded(reactions[part_id]), _rounded(capacity), _rounded(utilization), state, part_path_ids[part_id]))
	var bond_states: Array = []
	var bond_ids: Array = bonds.keys(); bond_ids.sort()
	for bond_id in bond_ids:
		var bond: Dictionary = bonds[bond_id]
		var capacity := _bond_capacity(bond, load_case)
		var demand := float(bond_loads[bond_id])
		var utilization := demand / capacity if capacity > 0.0 else 0.0
		var state := "BROKEN" if String(bond["state"]) == "BROKEN" else ("OVERLOADED" if utilization > 1.0 else "OK")
		bond_states.append(BondStateScript.create(bond_id, String(bond["state"]), _rounded(demand), _rounded(capacity), _rounded(utilization), state, bond_path_ids[bond_id]))
	var structural_state := "STABLE"
	if not unsupported.is_empty(): structural_state = "UNSUPPORTED"
	else:
		for state in part_states:
			if String(state["state"]) == "OVERLOADED": structural_state = "OVERLOADED"; break
		if structural_state == "STABLE":
			for state in bond_states:
				if String(state["state"]) == "OVERLOADED": structural_state = "OVERLOADED"; break
	var profile := ProfileScript.create(snapshot, load_case, structural_state, part_states, bond_states, path_records, {
		"algorithm": "deterministic-shortest-support-path-v1",
		"support_count": supports.size(),
		"active_part_count": adjacency.size(),
		"active_bond_count": _active_bond_count(bonds),
	})
	var profile_validation := ProfileScript.validate(profile)
	if not bool(profile_validation.get("success", false)): return profile_validation
	return _success({"profile": profile})

static func _shortest_support_routes(source_id: String, supports: Dictionary, adjacency: Dictionary) -> Array:
	if not adjacency.has(source_id): return []
	var queue: Array = [source_id]
	var distance := {source_id: 0}
	var parent_part := {}
	var parent_bond := {}
	var found_distance := -1
	var found_supports: Array = []
	while not queue.is_empty():
		var current := String(queue.pop_front())
		var current_distance := int(distance[current])
		if found_distance >= 0 and current_distance > found_distance: break
		if supports.has(current):
			found_distance = current_distance
			found_supports.append(current)
			continue
		for edge in adjacency.get(current, []):
			var neighbor := String(edge["part_id"])
			if distance.has(neighbor): continue
			distance[neighbor] = current_distance + 1
			parent_part[neighbor] = current
			parent_bond[neighbor] = String(edge["bond_id"])
			queue.append(neighbor)
	found_supports.sort()
	var routes: Array = []
	for support_id in found_supports:
		var reversed_parts: Array = [support_id]
		var reversed_bonds: Array = []
		var cursor: String = String(support_id)
		while cursor != source_id:
			reversed_bonds.append(String(parent_bond[cursor]))
			cursor = String(parent_part[cursor])
			reversed_parts.append(cursor)
		reversed_parts.reverse(); reversed_bonds.reverse()
		routes.append({"support_part_id": support_id, "part_ids": reversed_parts, "bond_ids": reversed_bonds})
	return routes

static func _part_applied_load(part: Dictionary, load_case: Dictionary) -> float:
	return float(part["mass_kg"]) * float(load_case["gravity_m_s2"]) + float(load_case["external_part_loads_n"].get(String(part["part_id"]), 0.0))
static func _part_capacity(part: Dictionary, load_case: Dictionary) -> float:
	var metadata: Dictionary = part.get("metadata", {})
	var structural: Dictionary = metadata.get("structural", {}) if metadata.get("structural", {}) is Dictionary else {}
	var base := float(structural.get("capacity_n", 1000000000000.0))
	if structural.has("buckling_capacity_n"):
		base = minf(base, float(structural["buckling_capacity_n"]))
	var factor := 1.0
	match _condition(part):
		"DEGRADED": factor = float(load_case["degraded_capacity_factor"])
		"DESTROYED": factor = 0.0
	return base * factor / float(load_case["safety_factor"])
static func _bond_capacity(bond: Dictionary, load_case: Dictionary) -> float:
	var factor := 1.0
	match String(bond["state"]):
		"DEGRADED": factor = float(load_case["degraded_capacity_factor"])
		"BROKEN": factor = 0.0
	return float(bond["strength_n"]) * factor / float(load_case["safety_factor"])
static func _condition(part: Dictionary) -> String: return String(part.get("metadata", {}).get("condition", "INTACT"))
static func _active_bond_count(bonds: Dictionary) -> int:
	var count := 0; for bond in bonds.values():
		if String(bond["state"]) != "BROKEN": count += 1
	return count
static func _rounded(value: float) -> float: return snappedf(value, 0.000000001)
static func _success(details: Dictionary = {}) -> Dictionary:
	var result := {"success": true, "error_code": "", "message": "", "details": details.duplicate(true)}; for key in details: result[key] = details[key]
	return result
static func _failure(code: String, details: Dictionary = {}) -> Dictionary: return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
