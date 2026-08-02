extends RefCounted

const C = preload("res://scripts/construction/proxies/construction_proxy_contract_utils.gd")
const Interest = preload("res://scripts/construction/proxies/construction_proxy_interest_request.gd")
const Plan = preload("res://scripts/construction/proxies/construction_proxy_stream_plan.gd")

static func compile(manifest: Dictionary, topology: Dictionary, interest: Dictionary, cache) -> Dictionary:
	var checked := Interest.validate(interest)
	if not bool(checked.get("success", false)): return checked
	if String(interest["construct_id"]) != String(manifest["construct_id"]): return C.failure("CONSTRUCTION_PROXY_INTEREST_CONSTRUCT_MISMATCH")
	if int(interest["authority_epoch"]) != int(manifest["authority_epoch"]): return C.failure("CONSTRUCTION_PROXY_INTEREST_AUTHORITY_EPOCH_MISMATCH")
	var distance := float(interest["distance_m"])
	var mode := Plan.DISTANT_SHELL
	var artifact_ids: Array = []
	var section_ids: Array = []
	var interior_cell_ids: Array = []
	var interactive_part_ids: Array = []
	var estimated_bytes := 0
	if distance >= float(manifest["shell_distance_m"]):
		artifact_ids = [String(manifest["shell_artifact_id"])]
	else:
		var entered_cell := String(interest["entered_cell_id"])
		if not entered_cell.is_empty():
			mode = Plan.INTERIOR_CELL
			var interior_ref := _interior_ref(manifest, entered_cell)
			if interior_ref.is_empty(): return C.failure("CONSTRUCTION_PROXY_INTEREST_UNKNOWN_INTERIOR_CELL")
			artifact_ids.append(String(interior_ref["artifact_id"])); interior_cell_ids.append(entered_cell)
			var cell_part_ids := _cell_part_ids(topology, entered_cell)
			for part_id in cell_part_ids:
				if interactive_part_ids.size() >= int(interest["max_interactive_parts"]): break
				interactive_part_ids.append(part_id)
			var local_sections := _nearest_sections(manifest, interest["focus_local_m"], int(interest["max_section_artifacts"]), interest["visible_section_ids"])
			for ref in local_sections:
				artifact_ids.append(String(ref["artifact_id"])); section_ids.append(String(ref["section_id"]))
		elif distance >= float(manifest["section_distance_m"]):
			mode = Plan.SECTION_HLOD
			for ref in _nearest_sections(manifest, interest["focus_local_m"], int(interest["max_section_artifacts"]), interest["visible_section_ids"]):
				artifact_ids.append(String(ref["artifact_id"])); section_ids.append(String(ref["section_id"]))
		else:
			mode = Plan.LOCAL_EXTERIOR
			var local_sections := _nearest_sections(manifest, interest["focus_local_m"], int(interest["max_section_artifacts"]), interest["visible_section_ids"])
			for ref in local_sections:
				artifact_ids.append(String(ref["artifact_id"])); section_ids.append(String(ref["section_id"]))
			if distance < float(manifest["local_distance_m"]):
				interactive_part_ids = _interactive_parts(topology, section_ids, int(interest["max_interactive_parts"]))
	artifact_ids = _unique_sorted(artifact_ids); section_ids = _unique_sorted(section_ids); interactive_part_ids = _unique_sorted(interactive_part_ids); interior_cell_ids = _unique_sorted(interior_cell_ids)
	for artifact_id in artifact_ids:
		var artifact: Dictionary = cache.get_artifact(artifact_id)
		if artifact.is_empty(): return C.failure("CONSTRUCTION_PROXY_CACHE_MISS", {"artifact_id": artifact_id})
		estimated_bytes += int(artifact["estimated_bytes"])
	estimated_bytes += interactive_part_ids.size() * 256
	if estimated_bytes > int(interest["bandwidth_budget_bytes"]): return C.failure("CONSTRUCTION_PROXY_BANDWIDTH_BUDGET_EXCEEDED", {"estimated_bytes": estimated_bytes})
	var plan := Plan.create(manifest, interest, mode, artifact_ids, section_ids, interior_cell_ids, interactive_part_ids, estimated_bytes)
	checked = Plan.validate(plan)
	return C.success({"plan": plan}) if bool(checked.get("success", false)) else checked

static func _nearest_sections(manifest: Dictionary, focus: Array, limit: int, visible_section_ids: Array) -> Array:
	var candidates: Array = []
	var visible := {}
	for section_id in visible_section_ids: visible[section_id] = true
	for ref in manifest["section_artifacts"]:
		if not visible.is_empty() and not visible.has(String(ref["section_id"])): continue
		var center := _center(ref["bounds_min_m"], ref["bounds_max_m"])
		var dx := float(center[0]) - float(focus[0]); var dy := float(center[1]) - float(focus[1]); var dz := float(center[2]) - float(focus[2])
		var copy: Dictionary = ref.duplicate(true); copy["distance_sq"] = dx * dx + dy * dy + dz * dz; candidates.append(copy)
	candidates.sort_custom(func(a, b): return float(a["distance_sq"]) < float(b["distance_sq"]) or (float(a["distance_sq"]) == float(b["distance_sq"]) and String(a["section_id"]) < String(b["section_id"])))
	return candidates.slice(0, mini(limit, candidates.size()))

static func _interactive_parts(topology: Dictionary, section_ids: Array, limit: int) -> Array:
	var selected := {}; for section_id in section_ids: selected[section_id] = true
	var result: Array = []
	for section in topology["sections"]:
		if not selected.has(String(section["section_id"])): continue
		for part_id in section["interactive_part_ids"]:
			if result.size() >= limit: return result
			result.append(part_id)
	return result

static func _cell_part_ids(topology: Dictionary, cell_id: String) -> Array:
	var result: Array = []
	for section in topology["sections"]:
		if Array(section["interior_cell_ids"]).has(cell_id): result.append_array(section["interactive_part_ids"])
	return _unique_sorted(result)
static func _interior_ref(manifest: Dictionary, cell_id: String) -> Dictionary:
	for ref in manifest["interior_artifacts"]:
		if String(ref["cell_id"]) == cell_id: return ref
	return {}
static func _center(min_v: Array, max_v: Array) -> Array: return [(float(min_v[0]) + float(max_v[0])) * 0.5, (float(min_v[1]) + float(max_v[1])) * 0.5, (float(min_v[2]) + float(max_v[2])) * 0.5]
static func _unique_sorted(values: Array) -> Array:
	var seen := {}; for value in values: seen[String(value)] = true
	var result: Array = seen.keys(); result.sort(); return result
