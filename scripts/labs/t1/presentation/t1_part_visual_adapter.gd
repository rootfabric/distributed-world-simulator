extends RefCounted

const VisualProfile = preload("res://scripts/labs/t1/presentation/t1_part_visual_profile.gd")
const PLAN_SCHEMA := "planet_simulator.t1_fixture_presentation_plan.v1"
const PART_SCHEMA := "planet_simulator.t1_part_presentation_descriptor.v1"
const DETAIL_MODES := ["NEAR", "MID", "FAR"]

static func build_fixture_plan(fixture: Dictionary, catalog, detail_mode: String = "NEAR") -> Dictionary:
	if not DETAIL_MODES.has(detail_mode): return _failure("T1A1_DETAIL_MODE_INVALID")
	if typeof(fixture.get("profile_id")) != TYPE_STRING or typeof(fixture.get("part_ids")) != TYPE_ARRAY: return _failure("T1A1_FIXTURE_DESCRIPTOR_INVALID")
	var rules_result: Dictionary = catalog.fixture_rules(String(fixture["profile_id"]))
	if not bool(rules_result.get("success", false)): return rules_result
	var part_ids: Array = fixture["part_ids"]
	var semantics := _expand_rules(Array(rules_result["rules"]), part_ids.size())
	if not bool(semantics.get("success", false)): return semantics
	var descriptors: Array = []
	for index in range(part_ids.size()):
		var semantic_class := String(semantics["semantic_classes"][index])
		var profile_result: Dictionary = catalog.resolve_semantic(semantic_class)
		if not bool(profile_result.get("success", false)): return profile_result
		var profile: Dictionary = profile_result["profile"]
		var detail_result := VisualProfile.detail_for(profile, detail_mode)
		if not bool(detail_result.get("success", false)): return detail_result
		var detail: Dictionary = detail_result["detail"]
		descriptors.append({
			"schema": PART_SCHEMA,
			"part_id": String(part_ids[index]),
			"semantic_class": semantic_class,
			"visual_profile_id": String(profile["visual_profile_id"]),
			"representation_class": String(profile["representation_class"]),
			"detail_mode": detail_mode,
			"source_kind": String(detail["source_kind"]),
			"source_ref": String(detail["source_ref"]),
			"material_family": String(profile["material_family"]),
			"bounds_m": Array(profile["bounds_m"]).duplicate(true),
			"pivot_m": Array(profile["pivot_m"]).duplicate(true),
			"grid_footprint": Array(profile["grid_footprint"]).duplicate(true),
			"collision_profile": String(profile["collision_profile"]),
			"batching_policy": String(profile["batching_policy"]),
		})
	var plan := {
		"schema": PLAN_SCHEMA,
		"fixture_profile_id": String(fixture["profile_id"]),
		"fixture_checksum": String(fixture.get("fixture_checksum", "")),
		"catalog_manifest_hash": catalog.manifest_hash(),
		"detail_mode": detail_mode,
		"part_count": descriptors.size(),
		"parts": descriptors,
		"checksum": "",
	}
	plan["checksum"] = compute_plan_checksum(plan)
	return {"success": true, "plan": plan}

static func compute_plan_checksum(plan: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append(String(plan.get("schema", "")))
	lines.append(String(plan.get("fixture_profile_id", "")))
	lines.append(String(plan.get("fixture_checksum", "")))
	lines.append(String(plan.get("catalog_manifest_hash", "")))
	lines.append(String(plan.get("detail_mode", "")))
	lines.append(str(int(plan.get("part_count", -1))))
	for raw_part in Array(plan.get("parts", [])):
		var part: Dictionary = raw_part
		lines.append("|".join(PackedStringArray([
			String(part.get("part_id", "")), String(part.get("semantic_class", "")), String(part.get("visual_profile_id", "")),
			String(part.get("representation_class", "")), String(part.get("detail_mode", "")), String(part.get("source_kind", "")),
			String(part.get("source_ref", "")), String(part.get("material_family", "")), String(part.get("collision_profile", "")),
			String(part.get("batching_policy", ""))
		])))
	return "\n".join(lines).sha256_text()

static func _expand_rules(rules: Array, part_count: int) -> Dictionary:
	var semantics: Array = []
	semantics.resize(part_count)
	for raw_rule in rules:
		var rule: Dictionary = raw_rule
		var start := int(rule["start"]); var end := int(rule["end"])
		if start < 0 or end >= part_count or end < start: return _failure("T1A1_FIXTURE_RULE_OUT_OF_RANGE")
		for index in range(start, end + 1):
			if semantics[index] != null: return _failure("T1A1_FIXTURE_RULE_OVERLAP")
			semantics[index] = String(rule["semantic_class"])
	for index in range(part_count):
		if semantics[index] == null: return _failure("T1A1_FIXTURE_RULE_GAP")
	return {"success": true, "semantic_classes": semantics}

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code}
