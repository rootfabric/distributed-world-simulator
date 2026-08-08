extends RefCounted

const SCHEMA := "planet_simulator.t1_part_visual_profile.v1"
const REPRESENTATION_CLASSES := ["STRUCTURAL_CELL", "STATIC_COMPLEX_MESH", "INSTANCED_MESH", "INTERACTIVE_FIXTURE"]
const SOURCE_KINDS := ["NONE", "BUILTIN_PRIMITIVE", "RESOURCE_PATH", "COMPILED_PROXY"]
const COLLISION_PROFILES := ["INHERIT_RUNTIME_DESCRIPTOR", "NONE", "BOX", "MESH"]
const BATCHING_POLICIES := ["SECTION_COMPILE", "STATIC_MERGE", "INSTANCE_BATCH", "SEPARATE_INTERACTIVE"]
const DETAIL_KEYS := ["near", "mid", "far"]
const FIELDS := [
	"schema", "visual_profile_id", "representation_class", "material_family",
	"bounds_m", "pivot_m", "grid_footprint", "collision_profile", "batching_policy",
	"near", "mid", "far", "checksum",
]

static func validate(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, FIELDS): return _failure("T1A1_VISUAL_PROFILE_FIELDS_MISMATCH")
	if String(value.get("schema", "")) != SCHEMA: return _failure("T1A1_VISUAL_PROFILE_SCHEMA_MISMATCH")
	if not _path_id(String(value.get("visual_profile_id", "")), "visual-profile/t1/"): return _failure("T1A1_VISUAL_PROFILE_ID_INVALID")
	if not REPRESENTATION_CLASSES.has(String(value.get("representation_class", ""))): return _failure("T1A1_REPRESENTATION_CLASS_INVALID")
	if typeof(value.get("material_family")) != TYPE_STRING or String(value["material_family"]).is_empty(): return _failure("T1A1_MATERIAL_FAMILY_INVALID")
	if not _positive_vector(value.get("bounds_m"), 3): return _failure("T1A1_BOUNDS_INVALID")
	if not _finite_vector(value.get("pivot_m"), 3): return _failure("T1A1_PIVOT_INVALID")
	if not _positive_int_vector(value.get("grid_footprint"), 3): return _failure("T1A1_GRID_FOOTPRINT_INVALID")
	if not COLLISION_PROFILES.has(String(value.get("collision_profile", ""))): return _failure("T1A1_COLLISION_PROFILE_INVALID")
	if not BATCHING_POLICIES.has(String(value.get("batching_policy", ""))): return _failure("T1A1_BATCHING_POLICY_INVALID")
	for key in DETAIL_KEYS:
		var detail = value.get(key)
		if typeof(detail) != TYPE_DICTIONARY: return _failure("T1A1_DETAIL_DESCRIPTOR_INVALID")
		var result := _validate_detail(Dictionary(detail))
		if not bool(result.get("success", false)): return result
	if String(value.get("checksum", "")) != compute_checksum(value): return _failure("T1A1_VISUAL_PROFILE_CHECKSUM_MISMATCH")
	return {"success": true}

static func compute_checksum(value: Dictionary) -> String:
	var lines := PackedStringArray()
	for field in FIELDS:
		if field == "checksum": continue
		if DETAIL_KEYS.has(field):
			var detail: Dictionary = value.get(field, {})
			lines.append("%s=%s|%s" % [field, String(detail.get("source_kind", "")), String(detail.get("source_ref", ""))])
		elif field == "grid_footprint":
			lines.append("%s=%s" % [field, _joined_int(Array(value.get(field, [])))])
		elif field in ["bounds_m", "pivot_m"]:
			lines.append("%s=%s" % [field, _joined(Array(value.get(field, [])))])
		else:
			lines.append("%s=%s" % [field, String(value.get(field, ""))])
	return "\n".join(lines).sha256_text()

static func detail_for(value: Dictionary, detail_mode: String) -> Dictionary:
	var key := detail_mode.to_lower()
	if not DETAIL_KEYS.has(key): return _failure("T1A1_DETAIL_MODE_INVALID")
	var validation := validate(value)
	if not bool(validation.get("success", false)): return validation
	return {"success": true, "detail": Dictionary(value[key]).duplicate(true)}

static func _validate_detail(value: Dictionary) -> Dictionary:
	if not _has_exact_fields(value, ["source_kind", "source_ref"]): return _failure("T1A1_DETAIL_FIELDS_MISMATCH")
	var kind := String(value.get("source_kind", ""))
	var ref := String(value.get("source_ref", ""))
	if not SOURCE_KINDS.has(kind): return _failure("T1A1_SOURCE_KIND_INVALID")
	match kind:
		"NONE":
			if not ref.is_empty(): return _failure("T1A1_NONE_SOURCE_REF_MUST_BE_EMPTY")
		"BUILTIN_PRIMITIVE":
			if not ref.begins_with("primitive://"): return _failure("T1A1_PRIMITIVE_SOURCE_REF_INVALID")
		"RESOURCE_PATH":
			if not ref.begins_with("res://"): return _failure("T1A1_RESOURCE_SOURCE_REF_INVALID")
		"COMPILED_PROXY":
			if not ref.begins_with("proxy://"): return _failure("T1A1_PROXY_SOURCE_REF_INVALID")
	return {"success": true}

static func _has_exact_fields(value: Dictionary, fields: Array) -> bool:
	if value.size() != fields.size(): return false
	for field in fields:
		if not value.has(field): return false
	return true

static func _finite_vector(value, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != size: return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT] or is_nan(float(component)) or is_inf(float(component)): return false
	return true

static func _positive_vector(value, size: int) -> bool:
	if not _finite_vector(value, size): return false
	for component in value:
		if float(component) <= 0.0: return false
	return true

static func _positive_int_vector(value, size: int) -> bool:
	if typeof(value) != TYPE_ARRAY or Array(value).size() != size: return false
	for component in value:
		if typeof(component) not in [TYPE_INT, TYPE_FLOAT]: return false
		var numeric := float(component)
		if is_nan(numeric) or is_inf(numeric) or numeric < 1.0 or absf(numeric - float(int(numeric))) > 0.000001: return false
	return true

static func _path_id(value: String, prefix: String) -> bool:
	return value.begins_with(prefix) and value.length() > prefix.length() and value == value.to_lower() and not value.contains("//")

static func _joined(values: Array) -> String:
	var result := PackedStringArray()
	for value in values: result.append(str(value))
	return ",".join(result)

static func _joined_int(values: Array) -> String:
	var result := PackedStringArray()
	for value in values: result.append(str(int(value)))
	return ",".join(result)

static func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code}
