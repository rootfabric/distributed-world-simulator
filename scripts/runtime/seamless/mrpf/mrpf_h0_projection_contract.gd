extends RefCounted

const SCHEMA := "distributed_world_simulator.mrpf_h0_projection.v1"
const LEVELS := {
	"SPACE": 0,
	"EARTH": 1,
	"SURFACE": 2,
	"BASE": 3,
}
const ALLOWED_KEYS := [
	"schema",
	"representation_id",
	"canonical_subject_id",
	"source_domain_id",
	"source_authority_id",
	"publisher_id",
	"source_revision",
	"representation_class",
	"lod_level",
	"coverage_scope",
	"reference_frame_id",
	"content_hash",
	"valid_from_revision",
	"replacement_group_id",
	"domain_level",
	"presentation_only",
	"canonical_write_allowed",
	"checksum",
]
const STRING_KEYS := [
	"schema",
	"representation_id",
	"canonical_subject_id",
	"source_domain_id",
	"source_authority_id",
	"publisher_id",
	"representation_class",
	"coverage_scope",
	"reference_frame_id",
	"content_hash",
	"replacement_group_id",
	"domain_level",
	"checksum",
]
const INT_KEYS := ["source_revision", "lod_level", "valid_from_revision"]
const BOOL_KEYS := ["presentation_only", "canonical_write_allowed"]

static func create_representation(
	representation_id: String,
	canonical_subject_id: String,
	source_domain_id: String,
	source_authority_id: String,
	publisher_id: String,
	source_revision: int,
	representation_class: String,
	lod_level: int,
	coverage_scope: String,
	reference_frame_id: String,
	content_hash: String,
	valid_from_revision: int,
	replacement_group_id: String,
	domain_level: String
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"representation_id": representation_id.strip_edges(),
		"canonical_subject_id": canonical_subject_id.strip_edges(),
		"source_domain_id": source_domain_id.strip_edges(),
		"source_authority_id": source_authority_id.strip_edges(),
		"publisher_id": publisher_id.strip_edges(),
		"source_revision": source_revision,
		"representation_class": representation_class.strip_edges(),
		"lod_level": lod_level,
		"coverage_scope": coverage_scope.strip_edges(),
		"reference_frame_id": reference_frame_id.strip_edges(),
		"content_hash": content_hash.strip_edges(),
		"valid_from_revision": valid_from_revision,
		"replacement_group_id": replacement_group_id.strip_edges(),
		"domain_level": domain_level.strip_edges(),
		"presentation_only": true,
		"canonical_write_allowed": false,
	}
	value["checksum"] = checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	for raw_key in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return _failure("MRPF_H0_FIELD_UNKNOWN", {"field": str(raw_key)})
		var key := String(raw_key)
		if not ALLOWED_KEYS.has(key):
			return _failure("MRPF_H0_FIELD_UNKNOWN", {"field": key})
	for key in ALLOWED_KEYS:
		if not value.has(key):
			return _failure("MRPF_H0_FIELD_REQUIRED", {"field": key})
	for key in STRING_KEYS:
		if typeof(value[key]) != TYPE_STRING:
			return _failure("MRPF_H0_FIELD_TYPE_INVALID", {"field": key})
	for key in INT_KEYS:
		if typeof(value[key]) != TYPE_INT:
			return _failure("MRPF_H0_FIELD_TYPE_INVALID", {"field": key})
	for key in BOOL_KEYS:
		if typeof(value[key]) != TYPE_BOOL:
			return _failure("MRPF_H0_FIELD_TYPE_INVALID", {"field": key})
	if String(value["schema"]) != SCHEMA:
		return _failure("MRPF_H0_SCHEMA_INVALID")
	for key in [
		"representation_id", "canonical_subject_id", "source_domain_id",
		"source_authority_id", "publisher_id", "representation_class",
		"coverage_scope", "reference_frame_id", "content_hash",
		"replacement_group_id", "domain_level"
	]:
		if String(value[key]).strip_edges().is_empty():
			return _failure("MRPF_H0_FIELD_REQUIRED", {"field": key})
	if int(value["source_revision"]) < 1:
		return _failure("MRPF_H0_SOURCE_REVISION_INVALID")
	if int(value["valid_from_revision"]) < 0:
		return _failure("MRPF_H0_VALID_FROM_REVISION_INVALID")
	if int(value["lod_level"]) < 0:
		return _failure("MRPF_H0_LOD_INVALID")
	var level := String(value["domain_level"])
	if not LEVELS.has(level):
		return _failure("MRPF_H0_DOMAIN_LEVEL_INVALID")
	if value["presentation_only"] != true or value["canonical_write_allowed"] != false:
		return _failure("MRPF_H0_PRESENTATION_FLAGS_INVALID")
	if String(value["checksum"]) != checksum(value):
		return _failure("MRPF_H0_CHECKSUM_MISMATCH")
	return _success()

static func specificity(value: Dictionary) -> int:
	return int(LEVELS.get(String(value.get("domain_level", "")), -1))

static func checksum(value: Dictionary) -> String:
	return canonical_semantic_payload(value).sha256_text()

static func canonical_semantic_payload(value: Dictionary) -> String:
	var parts: Array[String] = []
	parts.append(_encode_string(String(value.get("schema", ""))))
	parts.append(_encode_string(String(value.get("representation_id", ""))))
	parts.append(_encode_string(String(value.get("canonical_subject_id", ""))))
	parts.append(_encode_string(String(value.get("source_domain_id", ""))))
	parts.append(_encode_string(String(value.get("source_authority_id", ""))))
	parts.append(_encode_string(String(value.get("publisher_id", ""))))
	parts.append(_encode_int(int(value.get("source_revision", 0))))
	parts.append(_encode_string(String(value.get("representation_class", ""))))
	parts.append(_encode_int(int(value.get("lod_level", -1))))
	parts.append(_encode_string(String(value.get("coverage_scope", ""))))
	parts.append(_encode_string(String(value.get("reference_frame_id", ""))))
	parts.append(_encode_string(String(value.get("content_hash", ""))))
	parts.append(_encode_int(int(value.get("valid_from_revision", 0))))
	parts.append(_encode_string(String(value.get("replacement_group_id", ""))))
	parts.append(_encode_string(String(value.get("domain_level", ""))))
	parts.append(_encode_bool(bool(value.get("presentation_only", false))))
	parts.append(_encode_bool(bool(value.get("canonical_write_allowed", true))))
	return "".join(parts)

static func canonical_string_sequence_payload(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(_encode_string(String(value)))
	return "".join(parts)

static func _encode_string(value: String) -> String:
	return "S%d:%s" % [value.to_utf8_buffer().size(), value]

static func _encode_int(value: int) -> String:
	return "I%d;" % value

static func _encode_bool(value: bool) -> String:
	return "B1;" if value else "B0;"

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
