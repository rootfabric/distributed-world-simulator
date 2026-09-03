extends RefCounted

const BaseObservation = preload("res://scripts/research/fabric_bake0/cx_vis_observation_model_v1.gd")
const Complex1A = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

const SCHEMA := "planet_simulator.fabric_cx2_vis_redundant_power_observation.v1"
const PATH_A := "wire/path-a"
const PATH_B := "wire/path-b"

static func build() -> Dictionary:
	var base := BaseObservation.build(false)
	if not bool(base.get("success", false)):
		return _failure("CX2_VIS_BASE_OBSERVATION_FAILED", base)

	var support_a := String(base["break_bond_id"])
	var support_b_index := int(base["break_index"]) + 50
	if support_b_index >= int(base["scale"]):
		support_b_index = int(base["break_index"]) - 50
	if support_b_index < 1:
		return _failure("CX2_VIS_SUPPORT_B_INDEX_INVALID", {"index": support_b_index})
	var support_b := "bond/b0-2-%04d" % support_b_index
	if support_a == support_b:
		return _failure("CX2_VIS_SUPPORT_IDS_OVERLAP")

	var subject := _remap_subject(Complex1A.redundant_path(), support_a, support_b)
	if subject.is_empty():
		return _failure("CX2_VIS_REDUNDANT_SUBJECT_REMAP_FAILED")

	var intact := Complex1A.solve(subject)
	if not bool(intact.get("success", false)):
		return _failure("CX2_VIS_INTACT_SOLVE_FAILED", intact)

	var event_a := String(base["event"]["event_id"])
	var break_a := Complex1A.apply_structural_break(subject, support_a, event_a)
	if not bool(break_a.get("success", false)):
		return _failure("CX2_VIS_BREAK_A_FAILED", break_a)
	var after_a := Complex1A.solve(break_a["subject"])
	if not bool(after_a.get("success", false)):
		return _failure("CX2_VIS_AFTER_A_SOLVE_FAILED", after_a)

	var event_b := "topology-event/cx2-path-b-break"
	var break_b := Complex1A.apply_structural_break(subject, support_b, event_b)
	if not bool(break_b.get("success", false)):
		return _failure("CX2_VIS_BREAK_B_FAILED", break_b)
	var after_b := Complex1A.solve(break_b["subject"])
	if not bool(after_b.get("success", false)):
		return _failure("CX2_VIS_AFTER_B_SOLVE_FAILED", after_b)

	var break_ab := Complex1A.apply_structural_break(break_a["subject"], support_b, event_b)
	if not bool(break_ab.get("success", false)):
		return _failure("CX2_VIS_BREAK_AB_FAILED", break_ab)
	var after_ab := Complex1A.solve(break_ab["subject"])
	if not bool(after_ab.get("success", false)):
		return _failure("CX2_VIS_AFTER_AB_SOLVE_FAILED", after_ab)

	var break_ba := Complex1A.apply_structural_break(break_b["subject"], support_a, event_a)
	if not bool(break_ba.get("success", false)):
		return _failure("CX2_VIS_BREAK_BA_FAILED", break_ba)
	var after_ba := Complex1A.solve(break_ba["subject"])
	if not bool(after_ba.get("success", false)):
		return _failure("CX2_VIS_AFTER_BA_SOLVE_FAILED", after_ba)

	var unrelated := Complex1A.apply_structural_break(subject, "support/unrelated", "event/cx2-unrelated")
	if not bool(unrelated.get("success", false)):
		return _failure("CX2_VIS_UNRELATED_BREAK_FAILED", unrelated)
	var after_unrelated := Complex1A.solve(unrelated["subject"])
	if not bool(after_unrelated.get("success", false)):
		return _failure("CX2_VIS_UNRELATED_SOLVE_FAILED", after_unrelated)

	var duplicate := Complex1A.apply_structural_break(break_a["subject"], support_b, event_a)
	if bool(duplicate.get("success", false)):
		return _failure("CX2_VIS_DUPLICATE_EVENT_ACCEPTED", duplicate)

	var support_a_segment := _segment_for_bond(base, int(base["break_index"]))
	var support_b_segment := _segment_for_bond(base, support_b_index)
	if support_a_segment.is_empty() or support_b_segment.is_empty():
		return _failure("CX2_VIS_SUPPORT_SEGMENT_MISSING")

	var stages := [
		_stage("BOTH_PATHS", intact, [], []),
		_stage("BREAK_A", after_a, [event_a], [support_a]),
		_stage("BREAK_B", after_b, [event_b], [support_b]),
		_stage("BREAK_A_PLUS_B", after_ab, [event_a, event_b], [support_a, support_b]),
	]
	var observation := {
		"success": true,
		"schema": SCHEMA,
		"base_checksum": String(base["checksum"]),
		"scale": int(base["scale"]),
		"parts": Array(base["parts"]).duplicate(true),
		"bounds": Dictionary(base["bounds"]).duplicate(true),
		"support_a": support_a,
		"support_b": support_b,
		"support_a_segment": support_a_segment,
		"support_b_segment": support_b_segment,
		"event_a": event_a,
		"event_b": event_b,
		"stages": stages,
		"reverse_order": _stage("BREAK_B_PLUS_A", after_ba, [event_b, event_a], [support_b, support_a]),
		"unrelated": _stage("UNRELATED_BREAK", after_unrelated, ["event/cx2-unrelated"], ["support/unrelated"]),
		"duplicate_event_error": String(duplicate.get("error_code", "")),
	}
	observation["checksum"] = _checksum(observation)
	return observation

static func _remap_subject(subject: Dictionary, support_a: String, support_b: String) -> Dictionary:
	if subject.is_empty():
		return {}
	var next: Dictionary = subject.duplicate(true)
	var remapped_bonds: Dictionary = {}
	for raw_id in next["structural_bonds"].keys():
		var old_id := String(raw_id)
		var new_id := old_id
		if old_id == "support/path-a":
			new_id = support_a
		elif old_id == "support/path-b":
			new_id = support_b
		remapped_bonds[new_id] = bool(next["structural_bonds"][raw_id])
	next["structural_bonds"] = remapped_bonds
	for index in range(next["functional_links"].size()):
		var link: Dictionary = next["functional_links"][index]
		var supports: Array = []
		for raw_support in link["support_bond_ids"]:
			var support_id := String(raw_support)
			if support_id == "support/path-a":
				support_id = support_a
			elif support_id == "support/path-b":
				support_id = support_b
			supports.append(support_id)
		link["support_bond_ids"] = supports
		next["functional_links"][index] = link
	return next

static func _stage(name: String, solved: Dictionary, event_ids: Array, broken_supports: Array) -> Dictionary:
	var load: Dictionary = solved["loads"]["load/lamp-a"]
	return {
		"name": name,
		"event_ids": event_ids.duplicate(),
		"broken_support_bond_ids": broken_supports.duplicate(),
		"active_functional_bond_ids": Array(solved["active_functional_bond_ids"]).duplicate(),
		"network_hash": String(solved["network_hash"]),
		"lamp": {
			"on": bool(load["on"]),
			"voltage": float(load["voltage"]),
			"current": float(load["current"]),
			"absorbed_power": float(load["absorbed_power"]),
		},
		"max_balance_residual": float(solved["max_balance_residual"]),
		"max_power_residual": float(solved["max_power_residual"]),
	}

static func _segment_for_bond(base: Dictionary, bond_index: int) -> Dictionary:
	var left_id := "part/b0-2-%04d" % (bond_index - 1)
	var right_id := "part/b0-2-%04d" % bond_index
	var left: Dictionary = {}
	var right: Dictionary = {}
	for raw_part in base["parts"]:
		var part: Dictionary = raw_part
		var part_id := String(part["part_id"])
		if part_id == left_id:
			left = part
		elif part_id == right_id:
			right = part
		if not left.is_empty() and not right.is_empty():
			break
	if left.is_empty() or right.is_empty():
		return {}
	return {
		"bond_index": bond_index,
		"part_a": left_id,
		"part_b": right_id,
		"left_position": Array(left["position"]).duplicate(),
		"right_position": Array(right["position"]).duplicate(),
	}

static func _checksum(observation: Dictionary) -> String:
	var lines := PackedStringArray([
		String(observation["schema"]),
		String(observation["base_checksum"]),
		String(observation["support_a"]),
		String(observation["support_b"]),
		String(observation["event_a"]),
		String(observation["event_b"]),
	])
	for raw_stage in observation["stages"]:
		var stage: Dictionary = raw_stage
		lines.append("%s|%s|%s|%s" % [
			String(stage["name"]),
			",".join(PackedStringArray(stage["active_functional_bond_ids"])),
			str(bool(stage["lamp"]["on"])),
			String.num_scientific(float(stage["lamp"]["absorbed_power"])),
		])
	return "\n".join(lines).sha256_text()

static func _failure(error_code: String, details = null) -> Dictionary:
	var result := {"success": false, "error_code": error_code}
	if details != null:
		result["details"] = details
	return result
